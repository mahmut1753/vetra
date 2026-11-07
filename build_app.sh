#!/bin/zsh
set -e

APP_NAME="Vetra"
BUNDLE_ID="com.vetra.windowmanager"
APP_DIR="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🎨 ${APP_NAME} uygulama ikonları (AppIcon.icns & logo.png) üretiliyor..."
swift scripts/generate_icons.swift
iconutil -c icns "Assets/AppIcon.iconset" -o "Assets/AppIcon.icns"
rm -rf "Assets/AppIcon.iconset"

echo "🔨 ${APP_NAME} derleniyor (Release)..."
swift build -c release

rm -rf "Tessera.app" "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/Tessera" "$MACOS_DIR/${APP_NAME}"
cp "Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
chmod +x "$MACOS_DIR/${APP_NAME}"

# Ad-hoc imzalama
codesign --force --deep --entitlements "Tessera.entitlements" --sign - "$APP_DIR"

# Yeniden derlenen ad-hoc binary'nin eski CDHash kaydının takılı kalmaması için TCC kaydını sıfırla
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true

echo "💿 ${DMG_NAME} kurulum paketi hazırlanıyor..."
STAGING_DIR=".dmg_staging"
rm -rf "$STAGING_DIR" "$DMG_NAME"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp "Assets/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
SetFile -a C "$STAGING_DIR" 2>/dev/null || true

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_NAME" >/dev/null

rm -rf "$STAGING_DIR"

echo "✅ ${APP_DIR} ve ${DMG_NAME} başarıyla oluşturuldu!"
