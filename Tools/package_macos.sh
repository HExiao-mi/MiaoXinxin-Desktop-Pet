#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_root/dist}"
mac_archs="${MACOS_ARCHS:-arm64 x86_64}"
only_active_arch="${ONLY_ACTIVE_ARCH:-NO}"
artifact_arch="universal"
if [[ "$mac_archs" != "arm64 x86_64" ]]; then
  artifact_arch="${mac_archs// /-}"
fi
build_dir="$(mktemp -d)"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir" "$staging_dir"' EXIT
mkdir -p "$output_dir"

xcodebuild \
  -project "$project_root/DockCatApp/DockCat.xcodeproj" \
  -scheme DockCat \
  -configuration Release \
  -derivedDataPath "$build_dir" \
  ARCHS="$mac_archs" \
  ONLY_ACTIVE_ARCH="$only_active_arch" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  build

app="$build_dir/Build/Products/Release/DockCat.app"
if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$app"
else
  # A complete ad-hoc signature keeps local source builds launchable even when
  # the contributor does not have an Apple Developer certificate installed.
  xattr -cr "$app"
  codesign --force --deep --sign - "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"

ditto --noextattr --norsrc "$app" "$staging_dir/MiaoXinxin.app"
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/MiaoXinxin.app" "$output_dir/MiaoXinxin-macOS-$artifact_arch.zip"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "MiaoXinxin" -srcfolder "$staging_dir" -ov -format UDZO "$output_dir/MiaoXinxin-macOS-$artifact_arch.dmg"
