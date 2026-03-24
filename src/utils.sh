
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
    If omitted or '.', the current directory ($PWD) is used.
    Relative paths are resolved from $PWD.
    The work dir must contain a mirror/ bare clone (created by 'gitscan mirror').
    Contains: mirror/ findings.tsv extracted/ report.txt cleanup.sh

EXAMPLES:
    gitscan run https://github.com/user/repo
    gitscan mirror https://github.com/user/repo ./workspace
    gitscan scan ./workspace
    gitscan report ./workspace
    gitscan clean ./workspace
EOF
}

# Resolve a work-dir argument to an absolute path.
# No argument or '.' → $PWD; relative paths → $PWD/<path>; absolute → unchanged.
gitscan_utils_resolve_workdir() {
    local arg resolved
    arg="${1:-}"

    if [ -z "$arg" ] || [ "$arg" = "." ]; then
        echo "$PWD"
        return 0
    fi

    case "$arg" in
        /*)  resolved="$arg" ;;
        *)   resolved="${PWD}/${arg}" ;;
    esac

    echo "$resolved"
}

# Verify that <work_dir>/mirror is a real bare mirror clone.
# Prints an actionable error and returns 1 if it is not.
gitscan_utils_verify_mirror() {
    local work_dir mirror_dir
    work_dir="$1"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"

    if [ ! -d "$mirror_dir" ]; then
        gitscan_utils_error "No mirror found at '$mirror_dir'"
        echo "" >&2
        echo "  Create a mirror with:" >&2
        echo "    gitscan mirror <repo-url> $work_dir" >&2
        echo "" >&2
        echo "  Or clone manually:" >&2
        echo "    git clone --mirror <repo-url> $mirror_dir" >&2
        return 1
    fi

    if ! git --git-dir="$mirror_dir" rev-parse --git-dir >/dev/null 2>&1; then
        gitscan_utils_error "'$mirror_dir' exists but is not a valid bare git repository"
        echo "" >&2
        echo "  Remove it and recreate the mirror:" >&2
        echo "    rm -rf $mirror_dir" >&2
        echo "    gitscan mirror <repo-url> $work_dir" >&2
        return 1
    fi

    if ! git --git-dir="$mirror_dir" config --get remote.origin.mirror >/dev/null 2>&1; then
        gitscan_utils_warn "'$mirror_dir' is a bare repo but does not appear to be a mirror clone"
        gitscan_utils_warn "For full history coverage use: gitscan mirror <repo-url> $work_dir"
    fi

    return 0
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
