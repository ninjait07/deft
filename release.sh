#!/bin/bash
# แพ็กรุ่นแจกฟรี: build → .dmg → notarize กับ Apple → staple → appcast.json
#
#   ./release.sh 1.0 1        (เลขรุ่นที่โชว์  เลข build ที่ต้องเพิ่มทุกครั้ง — Updater ใช้เทียบ)
#
# ครั้งแรกต้องเก็บ credential สำหรับ notarize ไว้ใน keychain ก่อน (ทำครั้งเดียว):
#   xcrun notarytool store-credentials deft-notary \
#       --apple-id you@example.com --team-id 9FT88D47SP --password <app-specific password>
#   (สร้าง app-specific password ที่ appleid.apple.com → Sign-In and Security → App-Specific Passwords)
#
# ผลลัพธ์อยู่ใน dist/Deft-<version>.dmg และ dist/appcast.json
# วิธีแจกผ่าน GitHub Releases:
#   1) สร้าง release ใหม่ tag = v<version> ที่ github.com/ninjait07/deft
#   2) แนบไฟล์ Deft-<version>.dmg และ appcast.json เข้าไปใน release นั้น
#   Updater อ่าน appcast.json จาก .../releases/latest/download/appcast.json อัตโนมัติ

set -euo pipefail
VERSION="${1:?usage: ./release.sh <version> <build>}"
BUILD="${2:?usage: ./release.sh <version> <build>}"
PROFILE="${DEFT_NOTARY_PROFILE:-deft-notary}"
REPO="ninjait07/deft"

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST="$SRC_DIR/dist"
STAGE="$DIST/stage"
APP="$STAGE/Deft.app"
DMG="$DIST/Deft-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

echo "==> [1/5] build $VERSION ($BUILD) แบบ release (ชื่อ Deft / bundle id com.nonbannawat.deft)"
KNACK_APP="$APP" KNACK_NAME="Deft" KNACK_BUNDLE_ID="com.nonbannawat.deft" \
  KNACK_VERSION="$VERSION" KNACK_BUILD="$BUILD" KNACK_RELEASE=1 "$SRC_DIR/build.sh" --no-launch

echo "==> [2/5] สร้าง dmg"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Deft" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "==> [3/5] ส่ง notarize (รอผลจาก Apple ปกติ 1–5 นาที)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> [4/5] staple"
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 | sed 's/^/    /' || true

echo "==> [5/5] appcast"
cat > "$DIST/appcast.json" <<JSON
{
  "version": "$VERSION",
  "build": $BUILD,
  "url": "https://github.com/$REPO/releases/download/v$VERSION/Deft-$VERSION.dmg",
  "notes": "What's new in $VERSION"
}
JSON

rm -rf "$STAGE"
echo "==> เสร็จ: $DMG"
echo "    อัปโหลด Deft-$VERSION.dmg + appcast.json ไปที่ GitHub release tag v$VERSION"
