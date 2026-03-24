
# ---------------------------------------------------------------------------
# Default path patterns (glob-style, matched against filename and full path)
# ---------------------------------------------------------------------------
GITSCAN_PATH_PATTERNS=(
    "*.pem" "*.key" "*.p12" "*.pfx" "*.pkcs12"
    "*.jks" "*.keystore" "*.ppk" "*.cert" "*.crt"
    "id_rsa" "id_dsa" "id_ecdsa" "id_ed25519"
    ".env" ".env.local" ".env.production" ".env.development" ".env.staging"
    "credentials" "credentials.json" "credentials.csv"
    "secrets.json" "secrets.yaml" "secrets.yml" "secrets.xml"
    ".netrc" ".pgpass" "htpasswd" ".htpasswd" "shadow"
)

# ---------------------------------------------------------------------------
# Default content patterns (ERE, used with git log -G and grep -E)
# ---------------------------------------------------------------------------
GITSCAN_CONTENT_PATTERNS=(
    "-----BEGIN RSA PRIVATE KEY-----"
    "-----BEGIN DSA PRIVATE KEY-----"
    "-----BEGIN EC PRIVATE KEY-----"
    "-----BEGIN OPENSSH PRIVATE KEY-----"
    "-----BEGIN PRIVATE KEY-----"
    "AKIA[0-9A-Z]{16}"
    "(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}"
    "github_pat_[0-9A-Za-z_]{82}"
    "xox[baprs]-[0-9a-zA-Z-]{10,48}"
    "AIza[0-9A-Za-z_-]{35}"
    "AWS_SECRET_ACCESS_KEY[[:space:]]*=[[:space:]]*[A-Za-z0-9/+]{40}"
    "SG\\.[0-9A-Za-z_-]{22}\\.[0-9A-Za-z_-]{43}"
)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

gitscan_scan_run() {
    local work_dir mirror_dir findings_file patterns_file
    work_dir="$(gitscan_utils_resolve_workdir "${1:-}")"
    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"
    findings_file="$(gitscan_utils_findings_file "$mirror_dir")"
    patterns_file="${work_dir}/patterns.txt"

    gitscan_utils_verify_mirror "$work_dir" || exit 1
    gitscan_utils_backup_if_needed "$mirror_dir"
    mkdir -p "${HOME}/.gitscan/reports"

    # Load custom patterns if file exists
    if [ -f "$patterns_file" ]; then
        gitscan_utils_info "Loading patterns from $patterns_file"
        gitscan_scan_load_patterns "$patterns_file"
    fi

    gitscan_utils_info "Starting scan of $mirror_dir..."

    # Write TSV header
    printf "hash\tauthor\tdate\tfile\ttype\tpattern\n" > "$findings_file"

    gitscan_utils_info "Scanning file paths..."
    gitscan_scan_paths "$mirror_dir" "$findings_file"

    gitscan_utils_info "Scanning file content..."
    gitscan_scan_content "$mirror_dir" "$findings_file"

    local count
    count=$(tail -n +2 "$findings_file" | wc -l | tr -d ' ')
    gitscan_utils_info "Scan complete — $count finding(s) saved to $findings_file"
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

gitscan_scan_load_patterns() {
    local file section line
    file="$1"
    section=""

    GITSCAN_PATH_PATTERNS=()
    GITSCAN_CONTENT_PATTERNS=()

    while IFS= read -r line || [ -n "$line" ]; do
        # skip empty lines and comments
        case "$line" in
            ""|\#*) continue ;;
        esac

        case "$line" in
            "[paths]")   section="paths";   continue ;;
            "[content]") section="content"; continue ;;
        esac

        case "$section" in
            paths)   GITSCAN_PATH_PATTERNS+=("$line") ;;
            content) GITSCAN_CONTENT_PATTERNS+=("$line") ;;
        esac
    done < "$file"
}

gitscan_scan_record() {
    local findings_file hash author date file type pattern
    findings_file="$1"
    hash="$2"
    author="$3"
    date="$4"
    file="$5"
    type="$6"
    pattern="$7"

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$hash" "$author" "$date" "$file" "$type" "$pattern" >> "$findings_file"
}

# Print the matched pattern name if the file path matches any path pattern.
# Returns 0 on match, 1 otherwise.
gitscan_scan_check_path() {
    local filepath basename ptn
    filepath="$1"
    basename="$(basename "$filepath")"

    for ptn in "${GITSCAN_PATH_PATTERNS[@]}"; do
        # shellcheck disable=SC2254
        case "$basename" in
            $ptn) echo "$ptn"; return 0 ;;
        esac
        # also test the full relative path (e.g. .env.local, secrets/credentials)
        case "$filepath" in
            $ptn) echo "$ptn"; return 0 ;;
        esac
    done

    return 1
}

# Scan git history for files matching sensitive path patterns.
gitscan_scan_paths() {
    local git_dir findings_file
    git_dir="$1"
    findings_file="$2"

    local file
    while IFS= read -r file; do
        [ -z "$file" ] && continue

        local matched_pattern
        if matched_pattern="$(gitscan_scan_check_path "$file")"; then
            # Find every commit that added this file
            local hash author date
            while IFS='|' read -r hash author date; do
                gitscan_scan_record "$findings_file" \
                    "$hash" "$author" "$date" "$file" "path" "$matched_pattern"
            done < <(git --git-dir="$git_dir" \
                log --all --diff-filter=A --format="%H|%ae|%ai" -- "$file" 2>/dev/null)
        fi
    done < <(git --git-dir="$git_dir" \
        log --all --diff-filter=A --name-only --format="" 2>/dev/null | sort -u)
}

# Scan git history for files whose content matches sensitive patterns.
gitscan_scan_content() {
    local git_dir findings_file
    git_dir="$1"
    findings_file="$2"

    local ptn
    for ptn in "${GITSCAN_CONTENT_PATTERNS[@]}"; do
        gitscan_utils_info "  pattern: ${ptn:0:50}..."

        # git log -G finds commits where a diff line matches the pattern.
        # For newly-added files every line is a diff line, so initial adds are caught.
        local hash author date
        while IFS='|' read -r hash author date; do
            # For each such commit find the specific files containing the pattern
            local file
            while IFS= read -r file; do
                [ -z "$file" ] && continue

                if git --git-dir="$git_dir" \
                    show "${hash}:${file}" 2>/dev/null | grep -qE -e "$ptn"; then

                    gitscan_scan_record "$findings_file" \
                        "$hash" "$author" "$date" "$file" "content" "$ptn"
                fi
            done < <(git --git-dir="$git_dir" \
                diff-tree --no-commit-id -r --diff-filter=AM --name-only \
                "$hash" 2>/dev/null)

        done < <(git --git-dir="$git_dir" \
            log --all --format="%H|%ae|%ai" -G "$ptn" 2>/dev/null)
    done
}
