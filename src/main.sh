
module utils
module mirror
module scan
module extract
module report
module clean

inject file patterns.txt

main() {
    local cmd
    cmd="${1:-help}"
    shift 2>/dev/null || true

    gitscan_utils_check_deps

    case "$cmd" in
        mirror)  gitscan_mirror_run "$@" ;;
        scan)    gitscan_scan_run "$@" ;;
        extract) gitscan_extract_run "$@" ;;
        report)  gitscan_report_run "$@" ;;
        clean)   gitscan_clean_run "$@" ;;
        run)     gitscan_run_all "$@" ;;
        --help|-h|help) gitscan_utils_usage ;;
        *)
            gitscan_utils_error "Unknown command: $cmd"
            gitscan_utils_usage
            exit 1
            ;;
    esac
}

gitscan_run_all() {
    local url work_dir
    url="$1"
    work_dir="${2:-.gitscan}"

    [ -z "$url" ] && {
        gitscan_utils_error "Usage: gitscan run <url> [work-dir]"
        exit 1
    }

    gitscan_mirror_run "$url" "$work_dir"
    gitscan_scan_run "$work_dir"
    gitscan_extract_run "$work_dir"
    gitscan_report_run "$work_dir"
    gitscan_clean_run "$work_dir"
}
