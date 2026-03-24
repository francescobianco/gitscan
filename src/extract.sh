
gitscan_extract_run() {
    local work_dir mirror_dir findings_file extracted_dir
    work_dir="$(gitscan_utils_resolve_workdir "${1:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"
    findings_file="$(gitscan_utils_findings_file "$work_dir")"
    extracted_dir="$(gitscan_utils_extracted_dir "$work_dir")"

    gitscan_utils_verify_mirror "$work_dir" || exit 1

    [ ! -f "$findings_file" ] && {
        gitscan_utils_error "Findings not found at $findings_file. Run 'gitscan scan' first."
        exit 1
    }

    mkdir -p "$extracted_dir"

    local extracted count
    extracted=0
    count=0

    local hash author date file type pattern
    while IFS=$'\t' read -r hash author date file type pattern; do
        # skip TSV header
        [ "$hash" = "hash" ] && continue

        count=$((count + 1))

        local out_file out_dir short_hash
        short_hash="${hash:0:12}"
        out_dir="${extracted_dir}/${short_hash}/$(dirname "$file")"
        out_file="${extracted_dir}/${short_hash}/${file}"

        mkdir -p "$out_dir"

        if git --git-dir="$mirror_dir" show "${hash}:${file}" \
            > "$out_file" 2>/dev/null; then
            extracted=$((extracted + 1))
            gitscan_utils_info "  Extracted ${short_hash}:${file}"
        else
            gitscan_utils_warn "  Could not extract ${short_hash}:${file} (may have been deleted)"
        fi
    done < "$findings_file"

    gitscan_utils_info "Extracted $extracted/$count file(s) to $extracted_dir"
}
