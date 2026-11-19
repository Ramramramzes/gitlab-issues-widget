#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$(pwd)/GitLab Issues.app"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" /tmp/gitlab-widget-swift-cache
cp -R Resources/en.lproj "$app/Contents/Resources/"
sources=(main.swift)
while IFS= read -r -d '' source; do
  sources+=("$source")
done < <(find Sources -type f -name '*.swift' -print0)

for architecture in arm64 x86_64; do
  xcrun swiftc "${sources[@]}" -o "$build_dir/GitLabWidget-$architecture" \
    -target "$architecture-apple-macos13.0" -module-cache-path /tmp/gitlab-widget-swift-cache -O \
    -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Security
done
xcrun lipo -create "$build_dir/GitLabWidget-arm64" "$build_dir/GitLabWidget-x86_64" \
  -output "$app/Contents/MacOS/GitLabWidget"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>GitLabWidget</string>
  <key>CFBundleIdentifier</key><string>app.gitlab-issues-desktop.beta</string>
  <key>CFBundleName</key><string>GitLab Issues</string>
  <key>CFBundleDisplayName</key><string>GitLab Issues</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>3.1.2</string>
  <key>CFBundleVersion</key><string>12</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
