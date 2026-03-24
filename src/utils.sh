
GITSCAN_VERSION="0.1.0"
GITSCAN_BACKUP_DONE=0
GITSCAN_NO_BACKUP=0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

gitscan_utils_log() {
    local level msg
    level="$1"
    msg="$2"
    echo "[$(date '+%H:%M:%S')] [$level] $msg" >&2
}

gitscan_utils_info()  { gitscan_utils_log "INFO" "$1"; }
gitscan_utils_warn()  { gitscan_utils_log "WARN" "$1"; }
gitscan_utils_error() { gitscan_utils_log "ERROR" "$1"; }

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

gitscan_utils_check_deps() {
    local dep
    for dep in git; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            gitscan_utils_error "Required dependency not found: $dep"
            exit 1
        fi
    done
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

gitscan_utils_usage() {
    cat <<EOF
gitscan v${GITSCAN_VERSION} - Git history scanner for sensitive data

USAGE:
    gitscan [--no-backup] <command> [options]

COMMANDS:
    mirror <url> [work-dir]    Clone repository as local mirror
    scan [work-dir]            Scan history for sensitive data
    extract [work-dir]         Extract suspicious file contents
    report [work-dir]          Generate findings report
    clean [work-dir]           Generate git-filter-repo cleanup script
    run <url> [work-dir]       Run all steps in sequence

GLOBAL FLAGS:
    --no-backup                Skip safety backup (use with care)
    --help, -h                 Show this help

WORK DIR:
    If omitted or '.', \$PWD is used.
    Relative paths are resolved from \$PWD.
    The work dir can be:
      a) A bare git repo itself   → gitscan uses it directly as the mirror
      b) A directory containing a mirror/ bare repo (standard layout)
      c) Any directory with a bare repo subdir (non-standard mirror name)
    Outputs (findings.tsv, report.txt, ...) are placed in the work dir.

BACKUP:
    Before every action gitscan creates a safety backup in:
      ~/.gitscan/backups/<repo>_<timestamp>/
    If a valid backup already exists for that repo it is reused — no
    redundant clones. Use --no-backup to skip.

EXAMPLES:
    gitscan run https://github.com/user/repo
    gitscan mirror https://github.com/user/repo ./workspace
    cd ./workspace/mirror && gitscan scan
    gitscan scan .                       # from inside the bare mirror dir
    gitscan --no-backup scan ./workspace
EOF
}

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

# Resolve a work-dir CLI argument to an absolute path.
# Empty or '.' → $PWD; relative → $PWD/<arg>; absolute → unchanged.
gitscan_utils_resolve_workdir() {
    local arg path
    arg="${1:-}"

    if [ -z "$arg" ] || [ "$arg" = "." ]; then
        path="$PWD"
    else
        case "$arg" in
            /*) path="$arg" ;;
            *)  path="${PWD}/${arg}" ;;
        esac
    fi

    echo "$path"
}

# Locate the mirror bare repo given a work dir. Resolution order:
#   1. work_dir itself is a bare git repo  → use it directly
#   2. work_dir/mirror is a bare git repo  → standard layout
#   3. any immediate subdir is a bare repo → non-standard mirror name
#   4. fallback: work_dir/mirror           → used for error messages / first clone
gitscan_utils_mirror_dir() {
    local work_dir candidate subdir
    work_dir="$1"

    # 1. work_dir IS the mirror
    if git --git-dir="$work_dir" rev-parse --git-dir >/dev/null 2>&1; then
        echo "$work_dir"
        return 0
    fi

    # 2. Standard: work_dir/mirror
    candidate="${work_dir}/mirror"
    if [ -d "$candidate" ] && \
       git --git-dir="$candidate" rev-parse --git-dir >/dev/null 2>&1; then
        echo "$candidate"
        return 0
    fi

    # 3. Any bare repo subdir (non-standard mirror name)
    if [ -d "$work_dir" ]; then
        for subdir in "${work_dir}"/*/; do
            subdir="${subdir%/}"
            [ -d "$subdir" ] || continue
            if git --git-dir="$subdir" rev-parse --git-dir >/dev/null 2>&1; then
                echo "$subdir"
                return 0
            fi
        done
    fi

    # 4. Fallback
    echo "${work_dir}/mirror"
}

# ---------------------------------------------------------------------------
# Mirror validation
# ---------------------------------------------------------------------------

gitscan_utils_verify_mirror() {
    local work_dir mirror_dir
    work_dir="$1"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"

    if ! git --git-dir="$mirror_dir" rev-parse --git-dir >/dev/null 2>&1; then
        gitscan_utils_error "No valid git mirror found in '$work_dir'"
        echo "" >&2
        echo "  Tip: to create a mirror run:" >&2
        echo "    gitscan mirror <repo-url> $work_dir" >&2
        echo "" >&2
        echo "  Or clone manually and then enter the directory:" >&2
        echo "    git clone --mirror <repo-url> ${work_dir}/mirror" >&2
        echo "    cd ${work_dir}/mirror && gitscan scan" >&2
        return 1
    fi

    if ! git --git-dir="$mirror_dir" config --get remote.origin.mirror >/dev/null 2>&1; then
        gitscan_utils_warn "'$mirror_dir' is a bare repo but not a proper mirror clone"
        gitscan_utils_warn "For full history coverage use: gitscan mirror <repo-url> $work_dir"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

# Create a safety backup in ~/.gitscan/backups/ unless:
#   a) --no-backup flag  (GITSCAN_NO_BACKUP=1)
#   b) a valid, integrity-verified backup already exists for this repo
#   c) a backup was already created in this process (GITSCAN_BACKUP_DONE=1)
gitscan_utils_backup_if_needed() {
    local mirror_dir
    mirror_dir="$1"

    if [ "${GITSCAN_NO_BACKUP:-0}" = "1" ]; then
        gitscan_utils_info "Backup skipped (--no-backup)"
        return 0
    fi

    # Fast path: already done in this session
    [ "${GITSCAN_BACKUP_DONE:-0}" = "1" ] && return 0

    local remote_url slug
    remote_url="$(git --git-dir="$mirror_dir" \
        config --get remote.origin.url 2>/dev/null || true)"

    if [ -z "$remote_url" ]; then
        gitscan_utils_warn "Cannot determine remote URL — backup skipped"
        return 0
    fi

    # Slug is based on the mirror's absolute path, not the URL,
    # so two clones of the same repo get independent backups.
    slug="$(gitscan_utils_path_slug "$mirror_dir")"

    # Persistent check: reuse any existing valid backup for this mirror path
    local backup_base existing
    backup_base="${HOME}/.gitscan/backups"
    if [ -d "$backup_base" ]; then
        for existing in "${backup_base}/${slug}_"*/; do
            existing="${existing%/}"
            [ -d "$existing" ] || continue
            if git --git-dir="$existing" rev-parse --git-dir >/dev/null 2>&1; then
                gitscan_utils_info "Backup verified at $existing — skipping new backup"
                GITSCAN_BACKUP_DONE=1
                return 0
            fi
        done
    fi

    # No valid backup found: create one now
    gitscan_utils_backup "$mirror_dir" "$remote_url" "$slug"
    GITSCAN_BACKUP_DONE=1
}

gitscan_utils_backup() {
    local mirror_dir remote_url slug timestamp backup_dir
    mirror_dir="$1"
    remote_url="$2"
    slug="$3"
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    backup_dir="${HOME}/.gitscan/backups/${slug}_${timestamp}"

    gitscan_utils_info "Creating safety backup at $backup_dir ..."
    mkdir -p "${HOME}/.gitscan/backups"
    git clone --mirror "$remote_url" "$backup_dir"
    gitscan_utils_info "Backup ready: $backup_dir"
}

# ---------------------------------------------------------------------------
# Path slug: /home/pippo/dev/proj → home-pippo-dev-proj
# ---------------------------------------------------------------------------

gitscan_utils_path_slug() {
    local path
    path="$1"
    echo "$path" | sed 's|^/||; s|/|-|g'
}

# ---------------------------------------------------------------------------
# Output path helpers
# ---------------------------------------------------------------------------

# findings.tsv and report.txt live in ~/.gitscan/reports/, named after the
# mirror's absolute path so different repos never collide.
# Pass mirror_dir as argument.

gitscan_utils_findings_file() {
    local mirror_dir slug
    mirror_dir="$1"
    slug="$(gitscan_utils_path_slug "$mirror_dir")"
    echo "${HOME}/.gitscan/reports/${slug}.tsv"
}

gitscan_utils_report_file() {
    local mirror_dir slug
    mirror_dir="$1"
    slug="$(gitscan_utils_path_slug "$mirror_dir")"
    echo "${HOME}/.gitscan/reports/${slug}.txt"
}

# extracted/ and cleanup.sh stay in the work dir (local, potentially large).

gitscan_utils_extracted_dir() {
    local work_dir
    work_dir="$1"
    echo "${work_dir}/extracted"
}

gitscan_utils_cleanup_script() {
    local work_dir
    work_dir="$1"
    echo "${work_dir}/cleanup.sh"
}
