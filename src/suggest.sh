
# ---------------------------------------------------------------------------
# suggest — reads findings and prints actionable remediation commands
# ---------------------------------------------------------------------------

gitscan_suggest_run() {
    local work_dir mirror_dir findings_file
    work_dir="$(gitscan_utils_resolve_workdir "${1:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"
    findings_file="$(gitscan_utils_findings_file "$mirror_dir")"

    gitscan_utils_verify_mirror "$work_dir" || exit 1

    [ ! -f "$findings_file" ] && {
        gitscan_utils_error "No findings file at $findings_file. Run 'gitscan scan' first."
        exit 1
    }

    local total
    total="$(tail -n +2 "$findings_file" | wc -l | tr -d ' ')"

    if [ "$total" -eq 0 ]; then
        echo "No findings — nothing to suggest."
        return 0
    fi

    echo "======================================================"
    echo "  GITSCAN — SUGGESTIONS"
    echo "======================================================"
    echo ""
    echo "  Mirror: $mirror_dir"
    echo "  Run commands from inside the mirror directory."
    echo ""

    # ── FILES TO REMOVE (path + content findings) ──────────────────────────

    local file_count
    file_count="$(tail -n +2 "$findings_file" | \
        awk -F'\t' '$5=="path" || $5=="content"' | \
        cut -f4 | sort -u | wc -l | tr -d ' ')"

    if [ "$file_count" -gt 0 ]; then
        echo "── FILES TO REMOVE ($file_count unique file(s)) ──────────────────"
        echo "   These files must be purged from the full git history."
        echo ""

        # For each unique file: collect all distinct reasons
        tail -n +2 "$findings_file" | \
            awk -F'\t' '$5=="path" || $5=="content" {print $4 "\t" $5 "\t" $6}' | \
            sort -u | \
            awk -F'\t' '
                {
                    if ($1 != prev) {
                        if (prev != "") print "---"
                        print "FILE\t" $1
                        prev = $1
                    }
                    print "REASON\t" $2 ": " $3
                }
                END { if (prev != "") print "---" }
            ' | \
            while IFS=$'\t' read -r tag value; do
                case "$tag" in
                    FILE)
                        echo "  gitscan remove-file \"$value\""
                        ;;
                    REASON)
                        echo "    ↳ $value"
                        ;;
                    ---)
                        echo ""
                        ;;
                esac
            done
    fi

    # ── IP ADDRESSES TO MASK ───────────────────────────────────────────────

    local ip_count
    ip_count="$(tail -n +2 "$findings_file" | \
        awk -F'\t' '$5=="ip"' | cut -f6 | sort -u | wc -l | tr -d ' ')"

    if [ "$ip_count" -gt 0 ]; then
        echo "── IP ADDRESSES TO MASK ($ip_count unique IP(s)) ──────────────────"
        echo "   These IPs will be replaced with X.X.X.X across ALL history."
        echo ""

        local ip
        while IFS= read -r ip; do
            echo "  gitscan mask-ip \"$ip\""

            # List files where this IP appears (deduplicated)
            local files
            files="$(tail -n +2 "$findings_file" | \
                awk -F'\t' -v ip="$ip" '$5=="ip" && $6==ip {print $4}' | \
                sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
            echo "    ↳ found in: $files"
            echo ""
        done < <(tail -n +2 "$findings_file" | \
            awk -F'\t' '$5=="ip"' | cut -f6 | sort -u)
    fi

    echo "NOTE: All these commands rewrite git history."
    echo "      After running, force-push and ask collaborators to re-clone."
}

# ---------------------------------------------------------------------------
# remove-file — purge a file from all git history via git-filter-repo
# ---------------------------------------------------------------------------

gitscan_remove_file_run() {
    local file work_dir mirror_dir
    file="${1:-}"
    work_dir="$(gitscan_utils_resolve_workdir "${2:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"

    [ -z "$file" ] && {
        gitscan_utils_error "Usage: gitscan remove-file <file-path> [work-dir]"
        exit 1
    }

    gitscan_utils_verify_mirror "$work_dir" || exit 1

    if ! command -v git-filter-repo >/dev/null 2>&1; then
        gitscan_utils_error "git-filter-repo is required but not installed"
        gitscan_utils_install_hint "git-filter-repo" >&2
        exit 1
    fi

    gitscan_utils_backup_if_needed "$mirror_dir"

    gitscan_utils_warn "Removing '$file' from the full git history — IRREVERSIBLE"
    gitscan_utils_info "Running git-filter-repo..."

    (cd "$mirror_dir" && \
        git-filter-repo --path "$file" --invert-paths --force 2>&1)

    gitscan_utils_info "File removed from history."
    echo ""
    echo "  Next step: push the rewritten history to remote:"
    echo "    gitscan push $work_dir"
}

# ---------------------------------------------------------------------------
# mask-ip — replace an IP address with X.X.X.X across all git history
# ---------------------------------------------------------------------------

gitscan_mask_ip_run() {
    local ip work_dir mirror_dir
    ip="${1:-}"
    work_dir="$(gitscan_utils_resolve_workdir "${2:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"

    [ -z "$ip" ] && {
        gitscan_utils_error "Usage: gitscan mask-ip <ip-address> [work-dir]"
        exit 1
    }

    gitscan_utils_verify_mirror "$work_dir" || exit 1

    if ! command -v git-filter-repo >/dev/null 2>&1; then
        gitscan_utils_error "git-filter-repo is required but not installed"
        gitscan_utils_install_hint "git-filter-repo" >&2
        exit 1
    fi

    gitscan_utils_backup_if_needed "$mirror_dir"

    # Build the replacements file for git-filter-repo
    local tmp_replacements
    tmp_replacements="$(mktemp)"
    printf "literal:%s==>X.X.X.X\n" "$ip" > "$tmp_replacements"

    gitscan_utils_warn "Replacing '$ip' with 'X.X.X.X' in ALL files across full history — IRREVERSIBLE"
    gitscan_utils_info "Running git-filter-repo..."

    (cd "$mirror_dir" && \
        git-filter-repo --replace-text "$tmp_replacements" --force 2>&1)

    rm -f "$tmp_replacements"

    gitscan_utils_info "IP address masked."
    echo ""
    echo "  Next step: push the rewritten history to remote:"
    echo "    gitscan push $work_dir"
}

# ---------------------------------------------------------------------------
# push — force-push all branches and tags to remote
# ---------------------------------------------------------------------------

gitscan_push_run() {
    local work_dir mirror_dir
    work_dir="$(gitscan_utils_resolve_workdir "${1:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"

    gitscan_utils_verify_mirror "$work_dir" || exit 1

    gitscan_utils_warn "Force-pushing all refs to remote — IRREVERSIBLE"

    # Push only writable refs: branches and tags.
    # --mirror and --all are avoided because they also push read-only
    # host-managed refs (refs/pull/*, refs/merge-requests/*, etc.) that
    # the remote rejects with "deny updating a hidden ref".
    gitscan_utils_info "Pushing branches..."
    (cd "$mirror_dir" && \
        git push --force origin 'refs/heads/*:refs/heads/*' 2>&1)

    gitscan_utils_info "Pushing tags..."
    (cd "$mirror_dir" && \
        git push --force origin 'refs/tags/*:refs/tags/*' 2>&1)

    gitscan_utils_info "Push complete."
    echo ""
    echo "  IMPORTANT: All collaborators must re-clone the repository:"
    echo "    git clone <repo-url>"
}
