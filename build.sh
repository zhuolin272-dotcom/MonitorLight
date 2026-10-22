#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${MONITORLIGHT_BUILD_DIR:-$(mktemp -d /tmp/monitorlight-build.XXXXXX)}"
app_dir="$build_dir/MonitorLight.app"
delivery_dir="${MONITORLIGHT_OUTPUT_DIR:-$project_dir/dist}"

cd "$project_dir"
swift test --scratch-path "$build_dir/swift" --build-system native
swift build --scratch-path "$build_dir/swift" --build-system native -c release
make -C "$project_dir/Vendor/m1ddc"
binary_dir="$(swift build --scratch-path "$build_dir/swift" --build-system native -c release --show-bin-path)"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources"
cp "$binary_dir/MonitorLight" "$app_dir/Contents/MacOS/MonitorLight"
cp "$project_dir/Vendor/m1ddc/m1ddc" "$app_dir/Contents/Helpers/m1ddc"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Vendor/m1ddc/LICENSE" "$app_dir/Contents/Resources/m1ddc-LICENSE.txt"
swift "$project_dir/Resources/make-icon.swift" "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir/Contents/Helpers/m1ddc"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
mkdir -p "$delivery_dir"
ditto -c -k --norsrc --noextattr --keepParent "$app_dir" "$delivery_dir/MonitorLight.zip"
ditto --norsrc --noextattr "$app_dir" "$delivery_dir/MonitorLight.app"
printf 'Application: %s\nArchive: %s\n' "$delivery_dir/MonitorLight.app" "$delivery_dir/MonitorLight.zip"
