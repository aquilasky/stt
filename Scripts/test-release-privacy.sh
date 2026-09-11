#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
for configuration in A071 A073; do
    for setting in ENABLE_CODE_COVERAGE CLANG_ENABLE_CODE_COVERAGE CLANG_COVERAGE_MAPPING GCC_GENERATE_TEST_COVERAGE_FILES GCC_INSTRUMENT_PROGRAM_FLOW_ARCS; do
        value="$(plutil -extract "objects.$configuration.buildSettings.$setting" raw "$root/LectureCaption.xcodeproj/project.pbxproj")"
        if [[ "$value" != NO ]]; then
            echo "FAIL: Release $configuration $setting must be NO" >&2
            exit 1
        fi
    done
done
fixture="$(mktemp -d "${TMPDIR:-/tmp}/lecturecaption-privacy-tests.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
app="$fixture/LectureCaption.app"
mkdir -p "$app/Contents/MacOS"
plutil -create xml1 "$app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string LectureCaption "$app/Contents/Info.plist"
printf 'int main(void) { return 0; }\n' > "$fixture/main.c"
xcrun clang -arch arm64 "$fixture/main.c" -o "$fixture/clean-binary"
binary="$app/Contents/MacOS/LectureCaption"
cp "$fixture/clean-binary" "$binary"
expect() {
    local expected="$1" asset="$2" label="$3" result=0
    bash "$root/Scripts/check-release-privacy.sh" "$asset" > "$fixture/result.log" 2>&1 || result=$?
    if [[ "$result" != "$expected" ]]; then
        echo "FAIL: expected $expected, got $result ($label)" >&2
        cat "$fixture/result.log" >&2
        exit 1
    fi
    if [[ "$expected" = 1 ]]; then
        rg -F "$label" "$fixture/result.log" >/dev/null
    fi
}
expect 0 "$app" clean
for marker in '__llvm_profile' '__llvm_prf' 'default.profraw' 'other.profraw' '/Users/fixture/source.swift' "$root/source.swift" '/tmp/fixture/Sources/LectureCaption/Test.swift'; do
    cp "$fixture/clean-binary" "$binary"
    printf '\0%s\0' "$marker" >> "$binary"
    expect 1 "$app" 'Release privacy failed'
done
cp "$fixture/clean-binary" "$binary"
for state in clean contaminated; do
    expected=0
    if [[ "$state" = contaminated ]]; then
        printf '\0__llvm_profile\0' >> "$binary"
        expected=1
    fi
    ditto -c -k --keepParent "$app" "$fixture/$state.zip"
    expect "$expected" "$fixture/$state.zip" 'coverage/profile instrumentation'
    mkdir "$fixture/$state"
    ditto "$app" "$fixture/$state/LectureCaption.app"
    ln -s /Applications "$fixture/$state/Applications"
    hdiutil create -volname LectureCaptionFixture -srcfolder "$fixture/$state" -format UDZO "$fixture/$state.dmg"
    expect "$expected" "$fixture/$state.dmg" 'coverage/profile instrumentation'
done
expect 64 "$fixture/unsupported.txt" 'unsupported type'
expect 1 "$fixture/missing.app" 'missing application bundle'
printf 'not a Mach-O binary\n' > "$binary"
expect 1 "$app" 'missing arm64 executable'
echo 'Release privacy integration tests passed.'
