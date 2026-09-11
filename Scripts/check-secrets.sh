#!/bin/bash
set -euo pipefail

if [[ $# != 1 ]]; then
    echo "Usage: bash Scripts/check-secrets.sh staged|worktree|history" >&2
    exit 64
fi
mode="$1"
case "$mode" in staged|worktree|history) ;; *) echo "Unknown scan mode: $mode" >&2; exit 64 ;; esac
root="$(git rev-parse --show-toplevel)"
cd "$root"
scanner="${GITLEAKS_BIN:-gitleaks}"
if ! command -v "$scanner" >/dev/null 2>&1; then
    echo "Gitleaks 8.24.2 required. See docs/LOCAL_SECURITY_CHECKS.md; set GITLEAKS_BIN to its executable path." >&2
    exit 69
fi
version="$("$scanner" version)"
if [[ "$version" != "8.24.2" ]]; then
    echo "Gitleaks 8.24.2 required; installed version: $version" >&2
    exit 69
fi
# Resolve before entering the temporary worktree snapshot.
scanner="$(command -v "$scanner")"
[[ "$scanner" = /* ]] || scanner="$root/$scanner"
snapshot="$(mktemp -d "${TMPDIR:-/tmp}/lecturecaption-secrets.XXXXXX")"
trap 'rm -rf "$snapshot"' EXIT
common=(--config "$root/.gitleaks.toml" --redact=100 --no-banner --no-color --verbose --ignore-gitleaks-allow --gitleaks-ignore-path "$snapshot/no-ignore")
case "$mode" in
    staged)
        "$scanner" git "${common[@]}" --pre-commit --staged "$root"
        ;;
    history)
        if [[ "$(git rev-parse --is-shallow-repository)" = true ]]; then
            echo "Full local Git history required; shallow clone cannot pass history checks." >&2
            exit 65
        fi
        "$scanner" git "${common[@]}" --log-opts="--all --full-history" "$root"
        ;;
    worktree)
        # Include tracked files even if now ignored, plus non-ignored untracked files.
        git ls-files --cached --others --exclude-standard -z > "$snapshot/files"
        mkdir "$snapshot/tree"
        while IFS= read -r -d '' path; do
            if [[ -L "$path" ]]; then
                echo "Cannot scan symlink as source: $path" >&2
                exit 65
            fi
            [[ -e "$path" ]] || continue # Tracked file removed in working tree.
            if [[ ! -f "$path" ]]; then
                echo "Unsupported source entry: $path" >&2
                exit 65
            fi
            mkdir -p "$snapshot/tree/$(dirname "$path")"
            cp "$path" "$snapshot/tree/$path"
        done < "$snapshot/files"
        "$scanner" dir "${common[@]}" "$snapshot/tree"
        ;;
esac
echo "Secret check passed: $mode (Gitleaks $version)"
