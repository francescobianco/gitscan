
GITSCAN_VERSION="0.1.0"

gitscan_utils_log() {
    local level msg
    level="$1"
    msg="$2"
    echo "[$(date '+%H:%M:%S')] [$level] $msg" >&2
}

gitscan_utils_info() {
    gitscan_utils_log "INFO" "$1"
}

gitscan_utils_warn() {
    gitscan_utils_log "WARN" "$1"
}

gitscan_utils_error() {
    gitscan_utils_log "ERROR" "$1"
}

gitscan_utils_check_deps() {
    local dep
    for dep in git; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            gitscan_utils_error "Required dependency not found: $dep"
            exit 1
        fi
    done
}

gitscan_utils_usage() {
    cat <<EOF
gitscan v${GITSCAN_VERSION} - Git history scanner for sensitive data

USAGE:
    gitscan <command> [options]

COMMANDS:
    mirror <url> [work-dir]    Clone repository as local mirror
    scan [work-dir]            Scan history for sensitive data
    extract [work-dir]         Extract suspicious file contents
    report [work-dir]          Generate findings report
    clean [work-dir]           Generate git-filter-repo cleanup script
    run <url> [work-dir]       Run all steps in sequence

OPTIONS:
    --help, -h                 Show this help

WORK DIR:
    Default work directory is .gitscan in the current directory.
    Contains: mirror/ findings.tsv extracted/ report.txt cleanup.sh

EXAMPLES:
    gitscan run https://github.com/user/repo
    gitscan mirror https://github.com/user/repo ./workspace
    gitscan scan ./workspace
    gitscan report ./workspace
    gitscan clean ./workspace
EOF
}

gitscan_utils_mirror_dir() {
    local work_dir
    work_dir="$1"
    echo "${work_dir}/mirror"
}

gitscan_utils_findings_file() {
    local work_dir
    work_dir="$1"
    echo "${work_dir}/findings.tsv"
}

gitscan_utils_extracted_dir() {
    local work_dir
    work_dir="$1"
    echo "${work_dir}/extracted"
}

gitscan_utils_report_file() {
    local work_dir
    work_dir="$1"
    echo "${work_dir}/report.txt"
}

gitscan_utils_cleanup_script() {
    local work_dir
    work_dir="$1"
    echo "${work_dir}/cleanup.sh"
}
