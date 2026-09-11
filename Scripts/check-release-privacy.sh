#!/bin/bash
set -euo pipefail

if [[ $# != 1 ]]; then
    echo "Usage: bash Scripts/check-release-privacy.sh <LectureCaption.app|zip|dmg>" >&2
    exit 64
fi
asset="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/lecturecaption-privacy.XXXXXX")"
mounted=false
cleanup() {
    if $mounted; then
        if ! hdiutil detach "$scratch/mount" >/dev/null; then
            echo "Unable to detach test image: $scratch/mount; retained temporary directory." >&2
            return 1
        fi
    fi
    rm -rf "$scratch"
}
trap cleanup EXIT
fail() { echo "Release privacy failed: $asset: $1" >&2; exit 1; }
case "$asset" in
    *.app) app="$asset" ;;
    *.zip)
        ditto -x -k "$asset" "$scratch/unpacked"
        app="$scratch/unpacked/LectureCaption.app"
        ;;
    *.dmg)
        mkdir "$scratch/mount"
        hdiutil attach "$asset" -readonly -nobrowse -mountpoint "$scratch/mount" >/dev/null
        mounted=true
        app="$scratch/mount/LectureCaption.app"
        [[ -L "$scratch/mount/Applications" && "$(readlink "$scratch/mount/Applications")" = /Applications ]] || fail 'missing Applications shortcut'
        ;;
    *) echo "Unsupported asset: $asset" >&2; exit 64 ;;
esac
[[ -d "$app" && ! -L "$app" ]] || fail 'missing application bundle'
executable="$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")"
[[ "$executable" = LectureCaption ]] || fail 'unexpected executable name'
binary="$app/Contents/MacOS/$executable"
[[ -f "$binary" && ! -L "$binary" ]] || fail 'missing regular executable'
xcrun lipo "$binary" -verify_arch arm64 || fail 'missing arm64 executable'
# Scan bytes directly, including short strings and NUL-separated Mach-O data.
check_pattern() {
    local label="$1"
    shift
    local result=0
    LC_ALL=C rg -a -q "$@" "$binary" || result=$?
    case "$result" in
        0) fail "$label" ;;
        1) ;;
        *) fail "scanner error ($label, exit $result)" ;;
    esac
}
check_pattern 'coverage/profile instrumentation' -e '__llvm_profile|__llvm_prf|\.profraw'
check_pattern 'developer home path' -F -e '/Users/'
check_pattern 'repository absolute path' -F -e "$root"
check_pattern 'absolute source path' -e '/[^[:space:][:cntrl:]]*/Sources/LectureCaption/'
if $mounted; then
    hdiutil detach "$scratch/mount" >/dev/null
    mounted=false
fi
echo "Release privacy passed: $asset"
