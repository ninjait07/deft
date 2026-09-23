#!/bin/bash
# สร้างแอปจาก Deft.swift ไฟล์เดียว
#
#   ./build.sh               คอมไพล์ + เซ็น + เปิดแอปใหม่
#   ./build.sh --reset       ล้างสิทธิ์ Accessibility ของ Knack ด้วย (ใช้ตอนเปลี่ยน cert)
#   ./build.sh --no-launch   คอมไพล์อย่างเดียว ไม่เปิดแอป (release.sh ใช้)
#
#   ตัวแปรสภาพแวดล้อม:
#     KNACK_VERSION=4.1 KNACK_BUILD=5   เลขรุ่นที่ใส่ใน Info.plist (ค่าเริ่มต้น 1.0 / 1)
#     KNACK_RELEASE=1                    เซ็นแบบส่ง notarize: hardened runtime + timestamp
#     KNACK_APP=/path/Knack.app          ตำแหน่งแอปที่จะสร้าง (ค่าเริ่มต้น ~/Applications/Knack.app)
#
# หมายเหตุเรื่องสิทธิ์: macOS ผูกสิทธิ์ Accessibility ไว้กับ code signature requirement
# ถ้าเซ็นแบบ ad-hoc requirement จะเป็น cdhash ซึ่งเปลี่ยนทุกครั้งที่ compile
# → ติ๊กค้างในลิสต์แต่ใช้ไม่ได้จริง ต้องถอด/ใส่ใหม่ทุกรอบ
# สคริปต์นี้จึงเซ็นด้วย Developer ID / Apple Development cert ที่มีอยู่ในเครื่อง
# requirement จะกลายเป็น Team ID + bundle id ซึ่งคงที่ → rebuild กี่รอบสิทธิ์ก็ไม่หลุด

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${KNACK_APP:-$HOME/Applications/Deft.app}"
NAME="${KNACK_NAME:-Deft}"
BUNDLE_ID="${KNACK_BUNDLE_ID:-com.nonbannawat.deft}"
VERSION="${KNACK_VERSION:-1.2}"
BUILD="${KNACK_BUILD:-3}"

# ---- เลือก signing identity -------------------------------------------------
pick_identity() {
    local list
    list="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    # เรียงความสำคัญ: Developer ID > Apple Development > อะไรก็ได้
    for pattern in "Developer ID Application" "Apple Development" ""; do
        local line
        line="$(echo "$list" | grep -F "$pattern" | grep -v CSSMERR | head -1 || true)"
        if [ -n "$line" ]; then
            echo "$line" | sed -E 's/.*"(.*)".*/\1/'
            return
        fi
    done
    echo "-"   # ไม่เจอเลย → ad-hoc
}

IDENTITY="${KNACK_IDENTITY:-$(pick_identity)}"

echo "==> หยุดตัวเดิมถ้าเปิดอยู่"
pkill -x "$NAME" 2>/dev/null || true

echo "==> คอมไพล์"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
    -target arm64-apple-macos13.0 \
    -o "$APP/Contents/MacOS/$NAME" \
    "$SRC_DIR/Deft.swift" \
    -framework Cocoa -framework Carbon -framework ApplicationServices -framework ScreenCaptureKit

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Deft</string>
    <key>CFBundleDisplayName</key><string>Deft</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>NSHumanReadableCopyright</key><string>© Non Bannawat</string>
    <key>NSInputMonitoringUsageDescription</key><string>Auto Keyboard Detect uses this to tell a Windows keyboard from a Mac one.</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconFile</key><string>$NAME</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> สร้างไอคอนจากโค้ดในแอปเอง"
ICONSET="$SRC_DIR/build/Knack.iconset"
rm -rf "$SRC_DIR/build"
mkdir -p "$SRC_DIR/build"
"$APP/Contents/MacOS/$NAME" --export-icon "$ICONSET"
if [ -d "$ICONSET" ]; then
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$NAME.icns"
    cp "$SRC_DIR/build/knack-logo.png" "$SRC_DIR/knack-logo.png" 2>/dev/null || true
    rm -rf "$SRC_DIR/build"
    echo "    เสร็จ: $(du -h "$APP/Contents/Resources/$NAME.icns" | cut -f1)"
else
    echo "    สร้างไอคอนไม่สำเร็จ (แอปยังใช้ได้ปกติ)"
fi

if [ "$IDENTITY" = "-" ]; then
    echo "==> เซ็นแบบ ad-hoc (ไม่เจอ certificate — สิทธิ์จะหลุดทุก build)"
else
    echo "==> เซ็นด้วย: $IDENTITY"
fi
if [ "${KNACK_RELEASE:-0}" = "1" ]; then
    # notarize ต้องมี hardened runtime + secure timestamp
    codesign --force --identifier "$BUNDLE_ID" --sign "$IDENTITY" --options runtime --timestamp "$APP"
else
    codesign --force --identifier "$BUNDLE_ID" --sign "$IDENTITY" --timestamp=none "$APP"
fi
codesign --verify --strict "$APP"

echo "==> designated requirement:"
codesign -d -r- "$APP" 2>&1 | grep "designated" | sed 's/^/    /'

if [ "${1:-}" = "--reset" ]; then
    echo "==> ล้างสิทธิ์ Accessibility ของ $BUNDLE_ID"
    tccutil reset Accessibility "$BUNDLE_ID" || echo "    (ล้างไม่สำเร็จ — ถอด/ใส่เองใน System Settings)"
fi

if [ "${1:-}" = "--no-launch" ]; then
    echo "==> เสร็จ (ไม่เปิดแอป): $APP"
    exit 0
fi
echo "==> เปิดแอป"
open -a "$APP"
echo "==> เสร็จ: $APP"
