#!/bin/bash
# TokenMac.app 번들 조립 + /Applications 설치
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
APP_NAME="TokenMac"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

echo "==> $APP 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.chattymin.tokenmac</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> codesign"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-TokenMac Local}"
# 안정적 Keychain ACL 을 위해서는 인증서 존재가 아니라 유효한 codesigning identity 가 필요하다.
if security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    # 안정적 자체 서명 신원 → 재빌드해도 Keychain "항상 허용" 유지
    codesign --force -s "$SIGN_IDENTITY" "$APP"
else
    # 인증서 없음 → ad-hoc (빌드마다 Keychain 재프롬프트 가능, scripts/create-signing-cert.sh 로 해결)
    echo "   ('$SIGN_IDENTITY' 유효 codesigning identity 없음 → ad-hoc 서명)"
    echo "   반복 Keychain 허용 프롬프트를 줄이려면 ./scripts/create-signing-cert.sh 실행 후 다시 빌드하세요."
    codesign --force -s - "$APP"
fi

echo "==> 기존 인스턴스 종료 + /Applications 설치"
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP" /Applications/

echo "완료: open /Applications/$APP_NAME.app"
