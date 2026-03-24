
gitscan_mirror_run() {
    local url work_dir mirror_dir
    url="$1"
    work_dir="${2:-.gitscan}"

    [ -z "$url" ] && {
        gitscan_utils_error "Usage: gitscan mirror <url> [work-dir]"
        exit 1
    }

    mirror_dir="$(gitscan_utils_mirror_dir "$work_dir")"

    mkdir -p "$work_dir"
    mkdir -p "$(gitscan_utils_extracted_dir "$work_dir")"

    if [ -d "$mirror_dir" ]; then
        gitscan_utils_info "Mirror already exists at $mirror_dir — updating..."
        git --git-dir="$mirror_dir" remote update --prune
    else
        gitscan_utils_info "Cloning $url as mirror to $mirror_dir..."
        git clone --mirror "$url" "$mirror_dir"
    fi

    gitscan_utils_info "Mirror ready at $mirror_dir"
}
