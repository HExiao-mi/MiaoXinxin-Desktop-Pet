#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_root/dist}"
build_dir="$(mktemp -d)"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir" "$staging_dir"' EXIT
mkdir -p "$output_dir"

xcodebuild \
  -project "$project_root/DockCatApp/DockCat.xcodeproj" \
  -scheme DockCat \
  -configuration Release \
  -derivedDataPath "$build_dir" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  build

app="$build_dir/Build/Products/Release/DockCat.app"
if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$app"
fi

ditto -c -k --sequesterRsrc --keepParent "$app" "$output_dir/MiaoXinxin-macOS-universal.zip"
ditto "$app" "$staging_dir/MiaoXinxin.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "MiaoXinxin" -srcfolder "$staging_dir" -ov -format UDZO "$output_dir/MiaoXinxin-macOS-universal.dmg"
