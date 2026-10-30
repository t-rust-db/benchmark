#!/usr/bin/env bash
# Vendored from t-rust-db/examples lib/tool.sh: keep the two in step.
# Finds a t-rust-db tool binary for an example's run.sh, newest first.
#
#   . "$ROOT/../lib/tool.sh"
#   BIN="$(find_tool column-rs column-rs COLUMN_RS 0.32.0)"
#
# find_tool <bin> <package> <env-var> [min-version] resolves, in order:
#   1. $<env-var>                     -- an explicit path, used as given
#   2. ../../tools/target/release/<bin>, built first with
#      `cargo build --release -p <package> --bin <bin>` when the
#      t-rust-db/tools checkout sits next to this examples repo (cargo only
#      rebuilds what changed, so a fresh build costs seconds)
#   3. <bin> on $PATH                 -- an installed build
# It reports each step and the version it settles on to stderr, fails when
# that version is older than [min-version], and prints the binary's path to
# stdout.
#
# Run directly, it resolves the given tools the same way and reports each
# one; by default every tool of the t-rust-db/tools workspace (column-rs,
# column-ingest, sqlite-rs, loglume, trigrep's tg, db-studio). A tool whose
# binary is not named after its package is given as <package>:<bin>:
#
#   lib/tool.sh [column-rs] [trigrep:tg] ...

# A step of the search, on stderr.
tool_log() {
    echo "tool.sh: $*" >&2
}

# Whether version $1 is lower than version $2 (dotted numbers).
version_lt() {
    local -a a b
    local i
    IFS=. read -ra a <<<"$1"
    IFS=. read -ra b <<<"$2"
    for i in 0 1 2; do
        if [ "${a[i]:-0}" -lt "${b[i]:-0}" ]; then return 0; fi
        if [ "${a[i]:-0}" -gt "${b[i]:-0}" ]; then return 1; fi
    done
    return 1
}

find_tool() {
    local bin="$1" package="$2" env="$3" min="${4:-}"
    local tools path version branch commit start
    tools="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tools"
    if [ -n "${!env:-}" ]; then
        path="${!env}"
        tool_log "$bin: \$$env is set, using it as given: $path"
    elif [ -f "$tools/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
        tool_log "$bin: \$$env is not set"
        branch="$(git -C "$tools" branch --show-current 2>/dev/null || true)"
        commit="$(git -C "$tools" log -1 --format='%h %s' 2>/dev/null || true)"
        tool_log "$bin: tools checkout at $tools"
        tool_log "$bin:   branch ${branch:-(detached)}, commit ${commit:-(unknown)}"
        if [ -n "$(git -C "$tools" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
            tool_log "$bin:   (with uncommitted changes)"
        fi
        tool_log "$bin: cargo build --release -p $package --bin $bin ..."
        start=$SECONDS
        (cd "$tools" && cargo build --release -q -p "$package" --bin "$bin") >&2 || {
            tool_log "$bin: error: the build failed"
            return 1
        }
        tool_log "$bin: build finished in $((SECONDS - start))s"
        path="$tools/target/release/$bin"
    elif command -v "$bin" >/dev/null 2>&1; then
        tool_log "$bin: \$$env is not set and there is no tools checkout at $tools"
        path="$(command -v "$bin")"
        tool_log "$bin: using the one on PATH: $path"
    else
        tool_log "$bin: error: no $bin binary: \$$env is not set, there is no tools"
        tool_log "$bin:   checkout at $tools (it would be built), and $bin is not on PATH"
        return 1
    fi
    if [ ! -x "$path" ]; then
        tool_log "$bin: error: no $bin binary at '$path'"
        return 1
    fi
    version="$("$path" --version 2>/dev/null </dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ -n "$min" ] && [ -n "$version" ] && version_lt "$version" "$min"; then
        tool_log "$bin: error: $bin $version is older than $min, which this example needs"
        return 1
    fi
    echo "using $bin ${version:-(no version: it has no --version)} ($path)${min:+, needs $min or later}" >&2
    printf '%s\n' "$path"
}

# Run directly: report each tool.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    [ $# -gt 0 ] || set -- column-rs column-ingest sqlite-rs loglume trigrep:tg db-studio
    status=0
    for tool in "$@"; do
        package="${tool%%:*}"
        bin="${tool#*:}"
        env="$(printf '%s' "$bin" | tr 'a-z-' 'A-Z_')"
        find_tool "$bin" "$package" "$env" >/dev/null || status=1
        echo >&2
    done
    exit "$status"
fi
