#!/bin/zsh
# Builds QGuard.app next to this script (ad-hoc signed). Needs Xcode Command Line Tools.
set -euo pipefail
cd "${0:A:h}"
APP=QGuard.app
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O Sources/QGuard/main.swift Sources/QGuard/QIcon.swift -o "$APP/Contents/MacOS/QGuard"

# App icon, rendered from the same drawing code as the menu-bar icon.
swiftc -O Sources/IconTool/main.swift Sources/QGuard/QIcon.swift -o "$TMP/icontool"
"$TMP/icontool" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.qguard.QGuard</string>
  <key>CFBundleName</key><string>QGuard</string>
  <key>CFBundleExecutable</key><string>QGuard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"

# Make Finder show the new icon instead of a cached one.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $PWD/$APP"
