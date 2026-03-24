
gitscan_report_run() {
    local work_dir mirror_dir findings_file report_file
    work_dir="$(gitscan_utils_resolve_workdir "${1:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"
    findings_file="$(gitscan_utils_findings_file "$mirror_dir")"
    report_file="$(gitscan_utils_report_file "$mirror_dir")"

    gitscan_utils_verify_mirror "$work_dir" || exit 1
    gitscan_utils_backup_if_needed "$mirror_dir"
    mkdir -p "${HOME}/.gitscan/reports"

    [ ! -f "$findings_file" ] && {
        gitscan_utils_error "Findings not found at $findings_file. Run 'gitscan scan' first."
        exit 1
    }

    gitscan_report_generate "$findings_file" "$report_file"

    cat "$report_file"
    gitscan_utils_info "Report saved to $report_file"
}

gitscan_report_generate() {
    local findings_file report_file
    findings_file="$1"
    report_file="$2"

    local total unique_files unique_commits unique_authors path_count content_count
    total=$(tail -n +2 "$findings_file" | wc -l | tr -d ' ')
    unique_files=$(tail -n +2 "$findings_file" | cut -f4 | sort -u | wc -l | tr -d ' ')
    unique_commits=$(tail -n +2 "$findings_file" | cut -f1 | sort -u | wc -l | tr -d ' ')
    unique_authors=$(tail -n +2 "$findings_file" | cut -f2 | sort -u | wc -l | tr -d ' ')
    path_count=$(tail -n +2 "$findings_file" | awk -F'\t' '$5=="path"' | wc -l | tr -d ' ')
    content_count=$(tail -n +2 "$findings_file" | awk -F'\t' '$5=="content"' | wc -l | tr -d ' ')

    {
        echo "======================================================"
        echo "  GITSCAN — SECURITY REPORT"
        echo "  Generated: $(date)"
        echo "======================================================"
        echo ""
        echo "SUMMARY"
        echo "-------"
        printf "  Total findings:    %s\n" "$total"
        printf "  Unique files:      %s\n" "$unique_files"
        printf "  Commits affected:  %s\n" "$unique_commits"
        printf "  Authors involved:  %s\n" "$unique_authors"
        echo ""
        echo "FINDINGS BY TYPE"
        echo "----------------"
        printf "  Path matches:      %s\n" "$path_count"
        printf "  Content matches:   %s\n" "$content_count"
        echo ""

        echo "TOP PATTERNS"
        echo "------------"
        tail -n +2 "$findings_file" | cut -f6 | sort | uniq -c | sort -rn | head -10 | \
            while read -r cnt ptn; do
                printf "  (%s) %s\n" "$cnt" "$ptn"
            done
        echo ""

        echo "AFFECTED FILES"
        echo "--------------"
        tail -n +2 "$findings_file" | cut -f4 | sort | uniq -c | sort -rn | \
            while read -r cnt file; do
                printf "  (%s) %s\n" "$cnt" "$file"
            done
        echo ""

        echo "AFFECTED AUTHORS"
        echo "----------------"
        tail -n +2 "$findings_file" | cut -f2 | sort | uniq -c | sort -rn | \
            while read -r cnt author; do
                printf "  (%s) %s\n" "$cnt" "$author"
            done
        echo ""

        echo "DETAILED FINDINGS"
        echo "-----------------"
        local hash author date file type pattern
        while IFS=$'\t' read -r hash author date file type pattern; do
            printf "  commit:  %s\n" "${hash:0:12}"
            printf "  author:  %s\n" "$author"
            printf "  date:    %s\n" "$date"
            printf "  file:    %s\n" "$file"
            printf "  type:    %s\n" "$type"
            printf "  pattern: %s\n" "$pattern"
            echo "  ---"
        done < <(tail -n +2 "$findings_file")

    } > "$report_file"
}
