#!/bin/bash
# Собирает DockToggle.app и ставит в ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DockToggle.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O -target "arm64-apple-macos12.0" main.swift -o "$APP/Contents/MacOS/DockToggle"

# Иконка: icon/icon.png (1024x1024) -> AppIcon.icns
mkdir -p "$APP/Contents/Resources"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz icon/icon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) icon/icon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.docktoggle</string>
  <key>CFBundleName</key><string>DockToggle</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>DockToggle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

# Постоянная подпись, чтобы разрешение «Универсальный доступ» не слетало при пересборке
IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/DockToggle.app
cp -R "$APP" ~/Applications/
# DMG для передачи
STAGE=$(mktemp -d)
cp -R ~/Applications/DockToggle.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f DockToggle.dmg
hdiutil create -quiet -volname DockToggle -srcfolder "$STAGE" -ov -format UDZO DockToggle.dmg
rm -rf "$STAGE" build
echo "DMG: $(pwd)/DockToggle.dmg"
echo "Готово: ~/Applications/DockToggle.app"
