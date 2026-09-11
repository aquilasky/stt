#!/bin/zsh
set -euo pipefail

readonly app_name="LectureCaption"
readonly repository_root="$(cd "$(dirname "$0")/.." && pwd)"
readonly output_directory="${RELEASE_OUTPUT_DIRECTORY:-$repository_root/Release}"
readonly app_path="$output_directory/$app_name.app"
readonly zip_path="$output_directory/$app_name.zip"
readonly dmg_path="$output_directory/$app_name.dmg"

replace_existing=false
if [[ $# -gt 0 ]]; then
    if [[ $# -eq 1 && "$1" == "--replace" ]]; then
        replace_existing=true
    else
        print "Usage: $0 [--replace]"
        exit 64
    fi
fi

if [[ -e "$app_path" || -e "$zip_path" || -e "$dmg_path" ]]; then
    if ! $replace_existing; then
        print "Release assets already exist. Re-run with --replace to replace only $app_name.app, $app_name.zip, and $app_name.dmg."
        exit 1
    fi
    rm -rf "$app_path"
    rm -f "$zip_path" "$dmg_path"
fi

readonly staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/${app_name}.release.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
readonly derived_data_directory="$staging_directory/DerivedData"

mkdir -p "$output_directory"
xcodebuild \
    -project "$repository_root/LectureCaption.xcodeproj" \
    -scheme "$app_name" \
    -configuration Release \
    -sdk macosx \
    -arch arm64 \
    -derivedDataPath "$derived_data_directory" \
    ENABLE_CODE_COVERAGE=NO \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    CLANG_COVERAGE_MAPPING=NO \
    GCC_GENERATE_TEST_COVERAGE_FILES=NO \
    GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO \
    build

readonly built_app="$derived_data_directory/Build/Products/Release/$app_name.app"
if [[ ! -d "$built_app" ]]; then
    print "Release build did not produce $built_app"
    exit 1
fi

bash "$repository_root/Scripts/check-release-privacy.sh" "$built_app"
ditto "$built_app" "$app_path"

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --sign "$CODE_SIGN_IDENTITY" "$app_path"
else
    codesign --force --deep --sign - "$app_path"
fi
codesign --verify --deep --strict "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

readonly disk_image_contents="$staging_directory/dmg"
mkdir -p "$disk_image_contents"
ditto "$app_path" "$disk_image_contents/$app_name.app"
ln -s /Applications "$disk_image_contents/Applications"
hdiutil create \
    -volname "$app_name" \
    -srcfolder "$disk_image_contents" \
    -format UDZO \
    -ov \
    "$dmg_path"

for asset in "$app_path" "$zip_path" "$dmg_path"; do
    bash "$repository_root/Scripts/check-release-privacy.sh" "$asset"
done

readonly version="$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")"
print "Packaged $app_name $version:"
print "  $app_path"
print "  $zip_path"
print "  $dmg_path"
