# Deft — เตรียมแจกฟรี + รับบริจาค

แอปแจกฟรี ไม่มีโฆษณา ไม่มี license รับบริจาคผ่าน PromptPay และ GitHub Sponsors

## ทำเสร็จแล้วในแอป

| ส่วน | อยู่ที่ | ทำงานยังไง |
|---|---|---|
| Donate | `DonateWindow` | QR PromptPay สร้างสดจาก payload ใน `Sales` + ปุ่ม Sponsor on GitHub (ninjait07) ไม่มี license/ทดลองใช้ |
| คู่มือ | `ManualWindow` | อธิบายทุกฟังก์ชัน สลับอังกฤษ/ไทยได้ เปิดจากปุ่ม Manual ท้ายเมนู |
| หน้าขอสิทธิ์ | `PermissionsWindow` | รวม Accessibility / Screen Recording / Input Monitoring หน้าเดียว สถานะอัปเดตเอง เปิดเองตอนติดตั้งครั้งแรก |
| เช็คอัปเดต | `Updater` | อ่าน appcast.json จาก GitHub Releases ตอนเปิดแอป (+10 วิ) และทุก 24 ชม. เทียบเลข build |
| สคริปต์ release | `release.sh` | build (ชื่อ Deft, bundle id com.nonbannawat.deft) → .dmg → notarize → staple → appcast.json |

## ต้องทำเองก่อนปล่อยจริง (เรียงตามลำดับ)

1. **Apple Developer Program** สมัคร (ปีละ 99 ดอลลาร์) เพื่อออก Developer ID certificate สำหรับเซ็น + notarize
2. **credential สำหรับ notarize** ทำครั้งเดียว:
   ```
   xcrun notarytool store-credentials deft-notary \
       --apple-id <Apple ID ของคุณ> --team-id 9FT88D47SP --password <app-specific password>
   ```
   สร้าง app-specific password ที่ appleid.apple.com → Sign-In and Security → App-Specific Passwords
3. **สร้าง GitHub repo** ชื่อ `ninjait07/deft` (public) ใช้ GitHub Releases เป็นที่วางไฟล์ — ฟรีและตรงกับ URL ในโค้ดแล้ว
   - ถ้าใช้ชื่อ repo อื่น ต้องแก้ 2 จุด: `Sales.updateFeed` ใน Knack.swift และ `REPO` ใน release.sh
4. **ออกรุ่น** `./release.sh 1.0 1` ได้ `dist/Deft-1.0.dmg` ที่ notarize แล้ว + `dist/appcast.json`
   - สร้าง GitHub release tag `v1.0` แล้วแนบทั้ง `Deft-1.0.dmg` และ `appcast.json`
   - เลข build ต้องเพิ่มทุกครั้งที่ออกรุ่นใหม่ (Updater ใช้เทียบ)
5. **ทดสอบบนเครื่องอื่น** ดาวน์โหลด dmg เปิดครั้งแรกต้องไม่มีคำเตือน "ไม่สามารถตรวจสอบได้" และผ่านหน้าขอสิทธิ์ครบ
6. **เช็คชื่อ + โดเมน** ยืนยันว่าไม่มีแอป/เครื่องหมายการค้าชื่อ Deft ในหมวดซอฟต์แวร์ (tmsearch.uspto.gov + กรมทรัพย์สินทางปัญญาไทย) และจองโดเมน (เช่น getdeft.app / deftapp.com เพราะ deft.app คงไม่ว่าง)
7. **นโยบายความเป็นส่วนตัว** ดู PRIVACY.md แปะขึ้นเว็บ/README

## หมายเหตุเรื่องชื่อภายใน

ตอนนี้แอป dev (ที่ `./build.sh` สร้างเข้า ~/Applications) ยังเป็น `Knack.app` / bundle id `com.nonbannawat.knack`
เพื่อไม่ให้ต้องขอสิทธิ์ใหม่ระหว่างพัฒนา ส่วนที่ผู้ใช้เห็นเป็น "Deft" หมดแล้ว

`release.sh` จะ build เป็น **Deft.app / com.nonbannawat.deft** ให้อัตโนมัติ (แยกจากแอป dev)
ผู้ใช้ปลายทางที่ติดตั้งจาก dmg จะเห็นเป็น Deft และขอสิทธิ์ในชื่อ Deft
