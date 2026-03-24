
module utils
module mirror
module scan
module extract
module report
module clean

inject file patterns.txt

main() {
    local cmd
    local args
    args=()

    # Extract global flags before command dispatch
    local arg
    for arg in "$@"; do
        case "$arg" in
            --no-backup) export GITSCAN_NO_BACKUP=1 ;;
            *)           args+=("$arg") ;;
        esac
    done

    cmd="${args[0]:-help}"
    args=("${args[@]:1}")

    gitscan_utils_check_deps

    case "$cmd" in
        mirror)  gitscan_mirror_run "${args[@]}" ;;
        scan)    gitscan_scan_run "${args[@]}" ;;
        extract) gitscan_extract_run "${args[@]}" ;;
        report)  gitscan_report_run "${args[@]}" ;;
        clean)   gitscan_clean_run "${args[@]}" ;;
        run)     gitscan_run_all "${args[@]}" ;;
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
    url="${1:-}"
    work_dir="${2:-}"

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
