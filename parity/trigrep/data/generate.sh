#!/usr/bin/env bash
# Generates the synthetic source-code corpus the trigrep parity benchmark
# searches. Not a real codebase (nothing to check out reproducibly at a
# pinned commit that stays available), so this synthesizes one: many small
# files of code-shaped text, deterministic (no RNG seed) so the corpus and
# the pattern selectivity in ../queries/*.txt are stable across machines.
#
#   ./data/generate.sh              # small + medium + large
#   ./data/generate.sh small        # just one size
#
# Each size produces a directory tree, corpus/<size>/, of --files files
# spread across a few subdirectories, plus one file, corpus/<size>/rare.txt,
# containing a token that appears nowhere else -- the worst case for a
# trigram index (a single-hit query that still must open the index) paired
# against the best case (a token common to every file).
set -euo pipefail

# This script lives in data/; the corpus it writes belongs one level up,
# next to run.sh and queries/ -- cd there, not to this script's own dir.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# File counts per size label. Kept modest relative to sqlite-rs/column-rs's
# row counts -- a "large" source tree is tens of thousands of files, not
# millions; trigrep's own worked example (2026-09-09) was 9,016 files.
files_for() {
    case "$1" in
        small)  echo 200 ;;
        medium) echo 5000 ;;
        large)  echo 50000 ;;
        *) echo "error: unknown size '$1' (small|medium|large)" >&2; exit 1 ;;
    esac
}

# Common tokens every file gets some of (models the real-world case where a
# literal like "return" or "fn" appears near-universally, so a trigram index
# narrows nothing and the tool falls back to a full scan) and rare tokens
# unique to one in ~100 files (the case where the index earns its keep).
COMMON_WORDS=(fn let mut struct impl return match if else for while pub use)

generate_one() {
    local size="$1" idx="$2" dir="$3"
    local path="$dir/f${idx}.rs"
    {
        for j in $(seq 0 39); do
            # Deterministic pseudo-token stream: multiply-mod, same trick
            # column-rs's data generator uses for its `amount` column, so
            # the corpus is reproducible without an RNG seed.
            local common_idx=$(( (idx * 2654435761 + j * 40503) % ${#COMMON_WORDS[@]} ))
            local tok=$(( (idx * 2654435761 + j * 40503) % 1000000 ))
            printf '%s value_%x(x: i64) -> i64 { x + %d }\n' \
                "${COMMON_WORDS[$common_idx]}" "$tok" "$((j % 7))"
        done
        # Every 100th file gets a token that appears in exactly this file
        # and no other -- ../queries/rare_literal.txt searches for it.
        if [ $((idx % 100)) -eq 0 ]; then
            printf 'const NEEDLE_UNIQUE_%d: &str = "trigrep_rare_marker";\n' "$idx"
        fi
    } > "$path"
}

generate() {
    local size="$1"
    local n
    n="$(files_for "$size")"
    local out="corpus/${size}"
    rm -rf "$out"
    mkdir -p "$out"/{a,b,c,d}

    echo "==> $size: $n files"
    local sub
    for i in $(seq 1 "$n"); do
        case $(( i % 4 )) in
            0) sub=a ;; 1) sub=b ;; 2) sub=c ;; *) sub=d ;;
        esac
        generate_one "$size" "$i" "$out/$sub"
    done
    # corpus/ lives inside this benchmark repo's own git work tree but is
    # itself .gitignore'd (see ../.gitignore), so trigrep's git integration
    # -- correctly -- reports zero files for it if left as a plain
    # subdirectory: `git ls-files --others --exclude-standard` run against
    # the OUTER repo excludes everything under an ignored path. Making the
    # corpus its own nested git repo (no commit needed) sidesteps that,
    # and is also the more representative test: most real trees a grep
    # tool searches are themselves git repos.
    git -C "$out" init -q
    du -sh "$out"
}

if [ "$#" -gt 0 ]; then
    for size in "$@"; do generate "$size"; done
else
    for size in small medium large; do generate "$size"; done
fi
