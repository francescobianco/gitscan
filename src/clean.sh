
gitscan_clean_run() {
    local work_dir findings_file cleanup_script mirror_dir
    work_dir="$(gitscan_utils_resolve_workdir "${1:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"
    findings_file="$(gitscan_utils_findings_file "$mirror_dir")"
    cleanup_script="$(gitscan_utils_cleanup_script "$work_dir")"

    gitscan_utils_verify_mirror "$work_dir" || exit 1
    gitscan_utils_backup_if_needed "$mirror_dir"

    [ ! -f "$findings_file" ] && {
        gitscan_utils_error "Findings not found at $findings_file. Run 'gitscan scan' first."
        exit 1
    }

    local finding_count
    finding_count=$(tail -n +2 "$findings_file" | wc -l | tr -d ' ')

    if [ "$finding_count" -eq 0 ]; then
        gitscan_utils_info "No findings — nothing to clean up."
        return 0
    fi

    gitscan_clean_generate "$mirror_dir" "$findings_file" "$cleanup_script"

    gitscan_utils_info "Cleanup script generated at $cleanup_script"
    echo ""
    echo "  Review the script before running:"
    echo "    cat $cleanup_script"
    echo ""
    echo "  To execute (IRREVERSIBLE — rewrites git history):"
    echo "    bash $cleanup_script"
    echo ""
    echo "  After running, force-push all branches and tags:"
    echo "    git push --force --all && git push --force --tags"
    echo ""
    echo "  Notify all collaborators to re-clone the repository."
}

gitscan_clean_generate() {
    local mirror_dir findings_file cleanup_script
    mirror_dir="$1"
    findings_file="$2"
    cleanup_script="$3"

    local mirror_abs
    mirror_abs="$(cd "$mirror_dir" 2>/dev/null && pwd || echo "$mirror_dir")"

    # Collect unique file paths from findings
    local files_list
    files_list="$(tail -n +2 "$findings_file" | cut -f4 | sort -u)"

    local file_count
    file_count="$(echo "$files_list" | wc -l | tr -d ' ')"

    {
        echo "#!/usr/bin/env bash"
        echo "# ============================================================"
        echo "# GITSCAN — Cleanup Script"
        echo "# Generated: $(date)"
        echo "#"
        echo "# WARNING: This script rewrites git history using git-filter-repo."
        echo "# It is IRREVERSIBLE. Always keep a backup mirror."
        echo "# All collaborators must re-clone after running."
        echo "# ============================================================"
        echo ""
        echo "set -euo pipefail"
        echo ""
        echo "MIRROR_DIR=\"${mirror_abs}\""
        echo ""
        echo "# ---- Files to remove from history ($file_count unique path(s)) ----"
        echo "$files_list" | while IFS= read -r f; do
            echo "# $f"
        done
        echo ""
        echo "# Verify git-filter-repo is installed"
        echo "if ! command -v git-filter-repo >/dev/null 2>&1; then"
        echo "    echo 'ERROR: git-filter-repo not found. Install it and retry.' >&2"
        echo "    exit 1"
        echo "fi"
        echo ""
        echo "# Write paths to a temp file"
        echo "PATHS_FILE=\"\$(mktemp)\""
        echo "trap 'rm -f \"\$PATHS_FILE\"' EXIT"
        echo ""
        echo "cat > \"\$PATHS_FILE\" <<'PATHS_EOF'"
        echo "$files_list"
        echo "PATHS_EOF"
        echo ""
        echo "cd \"\$MIRROR_DIR\""
        echo ""
        echo "echo \"Removing sensitive files from history...\""
        echo "git-filter-repo --paths-from-file \"\$PATHS_FILE\" --invert-paths --force"
        echo ""
        echo "echo \"Running garbage collection...\""
        echo "git reflog expire --expire=now --all"
        echo "git gc --prune=now --aggressive"
        echo ""
        echo "echo \"Done. Force-push with:\""
        echo "echo \"  git push --force --all && git push --force --tags\""
        echo "echo \"All collaborators must re-clone the repository.\""
    } > "$cleanup_script"

    chmod +x "$cleanup_script"
}
