#!/bin/bash
# Source this file; the dependency is pinned and checked before extraction.
sparkle_version=2.10.0
sparkle_sha256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
sparkle_cache="$project_dir/work/sparkle"
sparkle_dir="$sparkle_cache/$sparkle_version"

ensure_sparkle() {
    local archive="$sparkle_cache/Sparkle-$sparkle_version.tar.xz"
    mkdir -p "$sparkle_cache"
    if [[ ! -f "$archive" ]]; then
        /usr/bin/curl --fail --location --retry 2 \
            "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
            -o "$archive.download"
        /bin/mv "$archive.download" "$archive"
    fi
    if [[ "$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/cut -d ' ' -f 1)" != "$sparkle_sha256" ]]; then
        printf '%s\n' 'Sparkle archive checksum mismatch.' >&2
        return 1
    fi
    if [[ ! -f "$sparkle_dir/.verified-$sparkle_sha256" ]]; then
        local staging
        staging="$(/usr/bin/mktemp -d "$sparkle_cache/.extract-XXXXXX")"
        /usr/bin/tar -xf "$archive" -C "$staging"
        /usr/bin/codesign --verify --deep --strict "$staging/Sparkle.framework"
        /usr/bin/touch "$staging/.verified-$sparkle_sha256"
        /bin/rm -rf "$sparkle_dir"
        /bin/mv "$staging" "$sparkle_dir"
    fi
}
