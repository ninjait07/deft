// =============================================================================
//  Deft.swift — Windows-style window management for macOS  (v4)
//  ไฟล์เดียวจบ
//
//  หน้าตา: เมนูบาร์ใช้สวิตช์เปิด-ปิดแทนเครื่องหมายถูก
//          คำอธิบายทุกอย่างซ่อนไว้ เอาเมาส์ชี้ค้างไว้แล้วค่อยโผล่มา
//
//  ท่าลาก (ครบตาม Windows):
//    • ลาก title bar ชนขอบซ้าย/ขวา       → ครึ่งจอ
//    • ลาก title bar ชน 4 มุม             → 1/4 จอ
//    • ลาก title bar ชนขอบบน              → เต็มจอ
//    • ลาก title bar ไปบนกลางจอ           → Snap Layouts
//    • ลากขอบบน/ล่างหน้าต่างชนขอบจอ        → Vertical maximize
//    • ดับเบิลคลิกขอบบน/ล่างหน้าต่าง        → Vertical maximize
//    • ลากหน้าต่างที่ snap อยู่ออกมา        → คืนขนาดเดิมระหว่างลาก
//    • ขอบด้านในระหว่าง 2 จอ               → มีแรงต้าน
//    • ลากเส้นแบ่งระหว่างหน้าต่างที่ snap คู่ → ปรับขนาดพร้อมกัน
//
//  หลัง snap:  Snap Assist — เลือกหน้าต่างอื่นมาเติมช่องที่เหลือ
//  ปุ่มลัด:     Win+ลูกศร (ตอนใช้รูปแบบคีย์ลัด Windows)
//              Option+Tab / Option+Shift+Tab (แทน Alt+Tab — สลับทีละหน้าต่าง)
//
//  Build:  ./build.sh
// =============================================================================

import Cocoa
import ApplicationServices
import Carbon.HIToolbox
import ScreenCaptureKit
import ServiceManagement
import IOKit
import IOKit.hidsystem
import UniformTypeIdentifiers

// MARK: - การตั้งค่าที่จำค่าไว้ข้ามการเปิดปิดแอป -----------------------------

/// เก็บลง UserDefaults อัตโนมัติ อ่านครั้งแรกได้ค่า fallback
@propertyWrapper
struct StoredBool {
    let key: String
    let fallback: Bool
    var wrappedValue: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@propertyWrapper
struct StoredNumber {
    let key: String
    let fallback: CGFloat
    var wrappedValue: CGFloat {
        get {
            guard let raw = UserDefaults.standard.object(forKey: key) as? Double else { return fallback }
            return CGFloat(raw)
        }
        nonmutating set { UserDefaults.standard.set(Double(newValue), forKey: key) }
    }
}

enum Config {
    // ---- หน้าต่าง ----------------------------------------------------------
    @StoredNumber(key: "edgeSensitivity", fallback: 6)   static var edgeSensitivity: CGFloat
    @StoredNumber(key: "cornerSize", fallback: 150)      static var cornerSize: CGFloat
    @StoredNumber(key: "gap", fallback: 0)               static var gap: CGFloat
    static let dragThreshold: CGFloat = 6
    static let borderSlop: CGFloat = 12
    @StoredNumber(key: "innerEdgeDwell", fallback: 0.28) static var innerEdgeDwellRaw: CGFloat
    static var innerEdgeDwell: TimeInterval { TimeInterval(innerEdgeDwellRaw) }

    @StoredBool(key: "bottomEdgeZone", fallback: false)    static var bottomEdgeZone: Bool
    @StoredBool(key: "portraitTopBottom", fallback: true)  static var portraitTopBottom: Bool
    @StoredBool(key: "verticalMaximize", fallback: true)   static var verticalMaximize: Bool
    @StoredBool(key: "unsnapOnDrag", fallback: true)       static var unsnapOnDrag: Bool
    @StoredBool(key: "snapLayouts", fallback: true)        static var snapLayouts: Bool
    @StoredBool(key: "snapAssist", fallback: true)         static var snapAssist: Bool
    @StoredBool(key: "dividers", fallback: true)           static var dividers: Bool
    @StoredBool(key: "altTab", fallback: true)             static var altTab: Bool
    @StoredBool(key: "windowPreviews", fallback: true)     static var windowPreviews: Bool
    @StoredBool(key: "snapEnabled", fallback: true)        static var snapEnabled: Bool
    /// จำตำแหน่งหน้าต่างต่อชุดจอ แล้วคืนให้ตอนเสียบจอกลับ
    @StoredBool(key: "layoutMemory", fallback: true)       static var layoutMemory: Bool
    /// ดับเบิลคลิก title bar = เต็มจอแบบยังเห็น menu bar (ไม่ใช่ full screen ของ Mac)
    @StoredBool(key: "trueMaximize", fallback: false)      static var trueMaximize: Bool

    // ---- เมาส์ -------------------------------------------------------------
    /// ทิศทางเลื่อนที่ "อยากได้" ของแต่ละอุปกรณ์ — ตั้งอิสระจากกัน ไม่ต้องสนว่า System Settings ตั้งไว้ยังไง
    /// Deft จะกลับทิศอีเวนต์ให้เฉพาะอุปกรณ์ที่ค่าที่อยากได้ไม่ตรงกับค่าของระบบ
    @StoredBool(key: "mouseNaturalScroll", fallback: false)    static var mouseNaturalScroll: Bool
    @StoredBool(key: "trackpadNaturalScroll", fallback: true)  static var trackpadNaturalScroll: Bool
    @StoredNumber(key: "mouseScrollSpeed", fallback: 1.0)  static var mouseScrollSpeed: CGFloat
    /// ปุ่มข้าง 4/5 ของเมาส์ = ถอยหลัง/เดินหน้า
    @StoredBool(key: "mouseSideButtons", fallback: false)  static var mouseSideButtons: Bool

    // ---- คีย์บอร์ด ---------------------------------------------------------
    /// ปุ่มเปลี่ยนภาษาแบบ Windows: 0 = ปิด, 1 = ปุ่ม ` (แบบคีย์บอร์ดไทย),
    /// 2 = Alt+Shift (แบบดั้งเดิม), 3 = Win+Space (แบบ Windows 10/11), 4 = Ctrl+Shift
    /// ทำงานเฉพาะตอนรูปแบบคีย์ลัดเป็น Windows
    @StoredNumber(key: "languageSwitchKey", fallback: 1)     static var languageSwitchKey: CGFloat
    /// ปุ่มล่าสุดที่เคยเลือก (ไม่ใช่ 0) — ใช้ตอนสับสวิตช์กลับมาเปิด
    @StoredNumber(key: "languageSwitchKeyLast", fallback: 1) static var languageSwitchKeyLast: CGFloat
    /// แก้คำที่พิมพ์ผิดแป้น (พิมพ์ไทยทั้งที่แป้นเป็นอังกฤษ หรือกลับกัน)
    @StoredBool(key: "layoutFix", fallback: false)           static var layoutFix: Bool
    /// แก้คำอัตโนมัติขณะพิมพ์ — ถ้าปิด ต้องสั่งแก้เองด้วยคีย์ยกเลิก/แก้คำ
    @StoredBool(key: "layoutFixAuto", fallback: false)        static var layoutFixAuto: Bool
    /// คีย์ยกเลิกการแก้คำ: 0 = แตะ Shift ×2, 1 = Esc, 2 = ใช้ได้ทั้งคู่
    @StoredNumber(key: "layoutFixUndoKey", fallback: 0)      static var layoutFixUndoKey: CGFloat
    /// Auto: ปรับพฤติกรรมปุ่มตามว่าปุ่มนั้นมาจากคีย์บอร์ด Windows หรือ Mac
    @StoredBool(key: "perKeyboard", fallback: false)         static var perKeyboard: Bool
    /// ตอนปิด Auto: เลือกเองว่าใช้รูปแบบ Windows (true) หรือ Mac (false)
    @StoredBool(key: "keyboardStyleWindows", fallback: true) static var keyboardStyleWindows: Bool
    /// ชี้ไอคอนใน Dock แล้วเห็นภาพหน้าต่างทั้งหมดของแอปนั้น แบบ taskbar ของ Windows
    @StoredBool(key: "dockPeek", fallback: true)             static var dockPeek: Bool
    /// ภาพย่อขยับตามของจริงระหว่างที่พาเนลเปิดอยู่ ไม่ใช่ภาพนิ่งที่จับไว้ตอนเปิด
    @StoredBool(key: "livePreviews", fallback: true)         static var livePreviews: Bool
    /// จำความละเอียด/Hz/ตำแหน่งของแต่ละจอ แล้วคืนให้ตอนเสียบชุดจอเดิมกลับมา
    @StoredBool(key: "displayMemory", fallback: true)        static var displayMemory: Bool

    // ---- Finder ------------------------------------------------------------
    /// Backspace ใน Finder: false = ลบลงถังขยะ (Windows Delete), true = ขึ้นโฟลเดอร์ (Windows Backspace)
    @StoredBool(key: "finderBackspaceGoesUp", fallback: false) static var finderBackspaceGoesUp: Bool

    // ---- ระบบ --------------------------------------------------------------
    @StoredBool(key: "launchAtLogin", fallback: false)       static var launchAtLogin: Bool
    /// ตัวเลขบนเมนูบาร์ อัปเดตทุก 2 วินาที — เลือกโชว์ทีละตัวได้
    @StoredBool(key: "monitorCPU", fallback: true)           static var monitorCPU: Bool
    @StoredBool(key: "monitorRAM", fallback: true)           static var monitorRAM: Bool
    @StoredBool(key: "monitorSSD", fallback: true)           static var monitorSSD: Bool
    static var monitorAny: Bool { monitorCPU || monitorRAM || monitorSSD }

    /// ย้ายค่าตั้งรุ่นเก่า: mouseScrollInvert (กลับทิศเทียบกับระบบ) → mouseNaturalScroll (ทิศที่อยากได้)
    static func migrate() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "mouseNaturalScroll") == nil,
           let invert = defaults.object(forKey: "mouseScrollInvert") as? Bool {
            mouseNaturalScroll = invert ? !ScrollDirection.systemNatural : ScrollDirection.systemNatural
            defaults.removeObject(forKey: "mouseScrollInvert")
        }
        // ตำแหน่งบนเมนูบาร์ที่ระบบจำไว้จากรุ่นที่ monitor อยู่ขวาไอคอน — ล้างครั้งเดียวให้เรียงใหม่
        if !defaults.bool(forKey: "monitorLayoutV2") {
            defaults.removeObject(forKey: "NSStatusItem Preferred Position DeftSystemMonitor")
            defaults.set(true, forKey: "monitorLayoutV2")
        }
        // สวิตช์ System Monitor ตัวเดียวรุ่นเก่า → สวิตช์แยกตามค่า
        if let all = defaults.object(forKey: "systemMonitor") as? Bool {
            monitorCPU = all; monitorRAM = all; monitorSSD = all
            defaults.removeObject(forKey: "systemMonitor")
        }
    }

    /// ต้องเปิด event tap แบบแก้ไขอีเวนต์ได้ไหม (แยกจาก tap ของการลากหน้าต่าง)
    static var needsInputTap: Bool {
        // รูปแบบคีย์ลัดอาจเป็น Windows ได้เมื่อไหร่ tap ก็ต้องพร้อม (Auto หรือเลือก Windows ไว้)
        ScrollDirection.mouseNeedsFlip || ScrollDirection.trackpadNeedsFlip
            || mouseScrollSpeed != 1.0 || mouseSideButtons
            || layoutFix
            || perKeyboard || keyboardStyleWindows
    }
}


// MARK: - AX helpers ---------------------------------------------------------

struct AXKey: Hashable {
    let element: AXUIElement
    static func == (a: AXKey, b: AXKey) -> Bool { CFEqual(a.element, b.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool {
        (attribute(element, name) as? Bool) ?? false
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let posRef = attribute(window, kAXPositionAttribute),
              let sizeRef = attribute(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setFrame(_ window: AXUIElement, _ rect: CGRect) {
        for _ in 0..<2 {
            var origin = rect.origin
            var size = rect.size
            if let value = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
            if let value = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            }
        }
    }

    static func setPosition(_ window: AXUIElement, _ origin: CGPoint) {
        var point = origin
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    /// ใช้ตอนลากเส้นแบ่ง — ตำแหน่ง → ขนาด → ตำแหน่ง
    /// ถ้าเซ็ตขนาดก่อนตอนหน้าต่างต้องขยายไปทางซ้าย/บน macOS จะตัดขนาดไม่ให้ล้นจอ แล้วค่อยย้าย
    /// ผลคือกว้างไม่ครบ เกิดช่องว่างตรงรอยต่อ — ย้ายก่อนแล้วค่อยขยายจึงได้ครบ ปิดท้ายด้วยตำแหน่งอีกรอบกันแอปดันกลับ
    static func setFrameFast(_ window: AXUIElement, _ rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimension = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimension)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    /// สำหรับลากเส้นแบ่ง: รู้เฟรมเดิม จึงยิงเฉพาะที่เปลี่ยน — ขนาดอย่างเดียวถ้าตำแหน่งเดิม
    /// ถ้าต้องขยายไปทางซ้าย/บน (origin ลด) ยิงตำแหน่งก่อนขนาด ไม่งั้นระบบตัดขนาดไม่ให้ล้นจอ
    static func setFrameDelta(_ window: AXUIElement, from previous: CGRect, to rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimension = AXValueCreate(.cgSize, &size) else { return }
        let originChanged = abs(previous.minX - rect.minX) > 0.5 || abs(previous.minY - rect.minY) > 0.5
        let sizeChanged = abs(previous.width - rect.width) > 0.5 || abs(previous.height - rect.height) > 0.5
        if !originChanged {
            if sizeChanged { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimension) }
            return
        }
        let growsBackward = rect.minX < previous.minX || rect.minY < previous.minY
        if growsBackward {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            if sizeChanged { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimension) }
        } else {
            if sizeChanged { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimension) }
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    static func isResizable(_ window: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
        if !settable.boolValue { return false }
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
        return settable.boolValue
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool { bool(window, "AXFullScreen") }

    static func exitFullScreen(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
    }

    static func setMinimized(_ window: AXUIElement, _ minimized: Bool) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                     minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    /// ยกหน้าต่างขึ้นหน้าสุดและโฟกัสให้ (ใช้กับ Alt+Tab / Snap Assist)
    static func raise(_ window: AXUIElement) {
        if bool(window, kAXMinimizedAttribute) { setMinimized(window, false) }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        let appElement = AXUIElementCreateApplication(pid(of: window))
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let target = pid(of: window)
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: target)?.activate()
        }
    }

    static func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<15 {
            if string(current, kAXRoleAttribute) == kAXWindowRole { return current }
            guard let parent = attribute(current, kAXParentAttribute) else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    static func windowUnderCursor(_ point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let hit = element else { return nil }
        guard pid(of: hit) != getpid() else { return nil }
        guard let window = enclosingWindow(of: hit) else { return nil }
        return acceptable(window) ? window : nil
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        guard let window = attribute(appElement, kAXFocusedWindowAttribute) else { return nil }
        let axWindow = window as! AXUIElement
        return acceptable(axWindow) ? axWindow : nil
    }

    static func acceptable(_ window: AXUIElement) -> Bool {
        if let subrole = string(window, kAXSubroleAttribute), subrole != kAXStandardWindowSubrole {
            return false
        }
        return isResizable(window)
    }
}

// MARK: - รายชื่อหน้าต่างทั้งระบบ ---------------------------------------------

struct WindowInfo {
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let icon: NSImage?
    let title: String
    let frame: CGRect          // พิกัด CG
    let isMinimized: Bool
    /// เลข window ของระบบ ใช้จับภาพหน้าต่าง (0 = จับคู่กับรายการของระบบไม่ได้)
    var windowID: CGWindowID = 0

    var key: AXKey { AXKey(element: element) }
}

// MARK: - ภาพย่อของหน้าต่างจริง ----------------------------------------------

/// จับภาพหน้าต่างด้วย ScreenCaptureKit แล้วแคชไว้
/// ภาพทยอยมาทีละใบ พอได้ใบไหนก็วาดทับไอคอนทันที ไม่ต้องรอครบ
final class Thumbnails {
    static let shared = Thumbnails()

    private var cache: [CGWindowID: NSImage] = [:]
    private var inFlight = false

    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    static var isUsable: Bool {
        guard Config.windowPreviews, isAuthorized else { return false }
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// ขอสิทธิ์ — คืนค่าว่าได้แล้วหรือยัง (ถ้ายัง ระบบจะเด้งหน้าต่างขอให้)
    @discardableResult
    static func requestAccess() -> Bool {
        if isAuthorized { return true }
        return CGRequestScreenCaptureAccess()
    }

    private var live: Timer?

    func image(for id: CGWindowID) -> NSImage? { cache[id] }

    /// จับภาพซ้ำเรื่อย ๆ ตราบใดที่พาเนลยังเปิดอยู่ — วัดแล้วจับ 6 หน้าต่างพร้อมกัน
    /// ใช้ราว 120 ms ต่อรอบ เลยตั้งจังหวะตามจำนวนหน้าต่างไม่ให้แย่งเครื่องมากเกินไป
    func startLive(for windows: [WindowInfo], onUpdate: @escaping () -> Void) {
        stopLive()
        refresh(for: windows, onUpdate: onUpdate)
        guard Self.isUsable, Config.livePreviews, !windows.isEmpty else { return }
        let interval = max(0.4, Double(min(windows.count, 14)) * 0.05)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh(for: windows, onUpdate: onUpdate)
        }
        RunLoop.main.add(timer, forMode: .common)
        live = timer
    }

    func stopLive() {
        live?.invalidate()
        live = nil
    }

    func clear() { cache.removeAll() }

    /// ย่อภาพให้กว้างไม่เกิน 520 px (ภาพจาก CGWindowList มาเต็มความละเอียด)
    private static func downscaled(_ image: CGImage, maxWidth: CGFloat = 520) -> NSImage {
        let scale = min(1.0, maxWidth / CGFloat(max(image.width, 1)))
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        guard scale < 1, let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                                 bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let small = context.makeImage() else {
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        return NSImage(cgImage: small, size: size)
    }

    /// ทางสำรองสำหรับหน้าต่างที่ ScreenCaptureKit จับไม่ได้ (ย่อไว้ / คนละ Space):
    /// window server ยังเก็บภาพสุดท้ายของหน้าต่างไว้ ดึงผ่าน CGWindowList ได้ — แบบเดียวกับที่ Windows โชว์
    /// (SDK ของ macOS 26 ถอด CGWindowListCreateImage ออกจาก Swift แล้ว แต่ตัวไลบรารียังมี symbol อยู่
    /// จึงเรียกผ่าน dlsym — ถ้ารุ่นไหนถอดจริง จะได้ nil แล้วตกไปใช้ไอคอนเหมือนเดิม ไม่ crash)
    private typealias LegacyCaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let legacyCaptureFn: LegacyCaptureFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: LegacyCaptureFn.self)
    }()

    /// ความสว่างเฉลี่ย (0–1) ของสิ่งที่อยู่ใต้หน้าต่างนี้บนจอ — ใช้ตัดสินว่าพื้นหลังขาวไหม
    /// ต้องมีสิทธิ์ Screen Recording ไม่งั้นได้ nil
    static func backdropLuminance(below window: NSWindow) -> Double? {
        guard isAuthorized, let fn = legacyCaptureFn, window.windowNumber > 0 else { return nil }
        let belowWindow: UInt32 = 1 << 4          // kCGWindowListOptionOnScreenBelowWindow
        let nominal: UInt32 = 1 << 4              // nominalResolution
        let rect = Geometry.toCG(window.frame)
        guard let image = fn(rect, belowWindow, CGWindowID(window.windowNumber), nominal)?.takeRetainedValue(),
              image.width > 1, image.height > 1 else { return nil }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
        }
        return total / Double(side * side) / 255
    }

    /// ภาพว่าง (สีเดียวทั้งแผ่น) = ระบบไม่มีเนื้อหาให้ (เช่นหน้าต่างย่อไว้บน macOS 26 ได้แผ่นเทา)
    /// ถือว่าจับไม่ได้ จะได้ไม่เอาแผ่นเทาไปทับภาพเดิมหรือไอคอน
    private static func isBlank(_ image: CGImage) -> Bool {
        let side = 6
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var low = 255, high = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
            low = min(low, v); high = max(high, v)
        }
        return high - low < 10
    }

    private static func legacyCapture(_ id: CGWindowID) -> NSImage? {
        guard let fn = legacyCaptureFn else { return nil }
        let includingWindow: UInt32 = 1 << 3          // kCGWindowListOptionIncludingWindow
        let imageOptions: UInt32 = (1 << 0) | (1 << 4) // boundsIgnoreFraming | nominalResolution
        guard let image = fn(.null, includingWindow, id, imageOptions)?.takeRetainedValue(),
              image.width > 1, image.height > 1, !isBlank(image) else { return nil }
        return downscaled(image)
    }

    func refresh(for windows: [WindowInfo], limit: Int = 14, onUpdate: @escaping () -> Void) {
        guard Self.isUsable, !inFlight else { return }
        let ids = Set(windows.prefix(limit).map(\.windowID).filter { $0 != 0 })
        guard !ids.isEmpty else { return }
        // ไม่ล้างภาพทิ้งทั้งก้อน: หน้าต่างที่ย่อไว้ต้องยังมีภาพสุดท้ายให้ดูเสมอ ตัดเฉพาะที่ไม่ได้ใช้ตอนนี้
        if cache.count > 120 {
            for key in cache.keys where !ids.contains(key) { cache[key] = nil }
        }
        inFlight = true

        if #available(macOS 14.0, *) {
            Task {
                defer { Task { @MainActor in self.inFlight = false } }
                // onScreenWindowsOnly: false = รวมหน้าต่างที่ย่อไว้และอยู่คนละ Space ด้วย
                guard let content = try? await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false) else { return }
                let targets = content.windows.filter { ids.contains($0.windowID) }
                let listed = Set(targets.map(\.windowID))
                // หน้าต่างที่ ScreenCaptureKit ไม่รู้จักเลย → ทางสำรองทันที
                for id in ids where !listed.contains(id) {
                    if let image = Self.legacyCapture(id) {
                        await MainActor.run { self.cache[id] = image; onUpdate() }
                    }
                }
                await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
                    for window in targets {
                        group.addTask {
                            let width = max(window.frame.width, 1)
                            let height = max(window.frame.height, 1)
                            let scale = min(1.0, 520 / width)
                            let config = SCStreamConfiguration()
                            config.width = max(1, Int(width * scale))
                            config.height = max(1, Int(height * scale))
                            config.showsCursor = false
                            let filter = SCContentFilter(desktopIndependentWindow: window)
                            guard let shot = try? await SCScreenshotManager.captureImage(
                                contentFilter: filter, configuration: config),
                                  shot.width > 1, shot.height > 1, !Self.isBlank(shot) else {
                                // ย่อไว้ / คนละ Space: ScreenCaptureKit จับไม่ได้ → ใช้ภาพสุดท้ายจาก window server
                                return (window.windowID, Self.legacyCapture(window.windowID))
                            }
                            return (window.windowID,
                                    NSImage(cgImage: shot,
                                            size: NSSize(width: shot.width, height: shot.height)))
                        }
                    }
                    for await (id, image) in group {
                        // จับไม่ได้รอบนี้ = เก็บภาพเดิมไว้ ไม่ให้พรีวิวหายไปเป็นไอคอน
                        guard let image else { continue }
                        await MainActor.run {
                            self.cache[id] = image
                            onUpdate()
                        }
                    }
                }
            }
        } else {
            inFlight = false
        }
    }
}

enum WindowIndex {
    /// เรียงจากหน้าสุดไปหลังสุด (= ลำดับที่ใช้ล่าสุด) ตามที่ Alt+Tab ของ Windows ใช้
    /// ลำดับ z มาจาก CGWindowList ส่วนชื่อ/ขนาดมาจาก AX (ไม่ต้องขอสิทธิ์ Screen Recording)
    static func ordered(includeMinimized: Bool = true) -> [WindowInfo] {
        var byApp: [pid_t: [WindowInfo]] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            if pid == getpid() { continue }
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.2)
            guard let windows = AX.attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            let appName = app.localizedName ?? "App"
            for window in windows {
                let subrole = AX.string(window, kAXSubroleAttribute)
                let minimized = AX.bool(window, kAXMinimizedAttribute)
                // Safari (และบางแอป) รายงานหน้าต่างที่ย่อไว้เป็น AXDialog — ถ้าย่ออยู่ให้นับเป็นหน้าต่างด้วย
                guard subrole == kAXStandardWindowSubrole
                        || (minimized && subrole == (kAXDialogSubrole as String)) else { continue }
                guard let frame = AX.frame(of: window) else { continue }
                if minimized && !includeMinimized { continue }
                let title = AX.string(window, kAXTitleAttribute) ?? ""
                byApp[pid, default: []].append(
                    WindowInfo(element: window, pid: pid, appName: appName, icon: app.icon,
                               title: title.isEmpty ? appName : title,
                               frame: frame, isMinimized: minimized))
            }
        }

        // เรียงตาม z-order จริงของระบบ
        var ordered: [WindowInfo] = []
        var taken = Set<AXKey>()
        let listOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard (entry[kCGWindowLayer as String] as? Int) == 0,
                      let ownerPid = entry[kCGWindowOwnerPID as String] as? pid_t,
                      let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                      let candidates = byApp[ownerPid] else { continue }
                let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                    width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
                guard var match = candidates.first(where: {
                    !taken.contains($0.key)
                        && abs($0.frame.minX - bounds.minX) < 6
                        && abs($0.frame.minY - bounds.minY) < 6
                        && abs($0.frame.width - bounds.width) < 6
                }) else { continue }
                match.windowID = CGWindowID(entry[kCGWindowNumber as String] as? UInt32 ?? 0)
                taken.insert(match.key)
                ordered.append(match)
            }
        }
        // ที่เหลือ (ย่อไว้ / อยู่คนละ Space) ต่อท้าย — หา window id จากรายการ "ทุกหน้าต่าง" ของระบบ
        // เพื่อให้จับภาพได้เหมือน Windows ที่เห็นพรีวิวแม้หน้าต่างย่ออยู่
        struct Offscreen { let id: CGWindowID; let pid: pid_t; let bounds: CGRect }
        var offscreen: [Offscreen] = []
        let allOptions: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(allOptions, kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard (entry[kCGWindowLayer as String] as? Int) == 0,
                      (entry[kCGWindowIsOnscreen as String] as? Bool) != true,
                      let ownerPid = entry[kCGWindowOwnerPID as String] as? pid_t,
                      let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                      let number = entry[kCGWindowNumber as String] as? UInt32 else { continue }
                let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                    width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
                guard bounds.width >= 80, bounds.height >= 60 else { continue }   // ตัด tooltip/แถบเล็ก ๆ
                offscreen.append(Offscreen(id: CGWindowID(number), pid: ownerPid, bounds: bounds))
            }
        }
        var usedOffscreen = Set<CGWindowID>()
        for (pid, windows) in byApp {
            let remaining = windows.filter { !taken.contains($0.key) }
            guard !remaining.isEmpty else { continue }
            for var window in remaining {
                taken.insert(window.key)
                // จับคู่ด้วยเฟรมก่อน (หน้าต่างย่อไว้ยังรายงานเฟรมเดิมทั้งสองฝั่ง)
                if let hit = offscreen.first(where: {
                    $0.pid == pid && !usedOffscreen.contains($0.id)
                        && abs($0.bounds.minX - window.frame.minX) < 6
                        && abs($0.bounds.minY - window.frame.minY) < 6
                        && abs($0.bounds.width - window.frame.width) < 6
                }) {
                    window.windowID = hit.id
                    usedOffscreen.insert(hit.id)
                } else {
                    // เฟรมไม่ตรง (บางแอปย้ายหน้าต่างที่ย่อไปนอกจอ) — ถ้าแอปนั้นเหลือหน้าต่างเดียวก็ใช้ตัวนั้น
                    let leftovers = offscreen.filter { $0.pid == pid && !usedOffscreen.contains($0.id) }
                    if leftovers.count == 1, remaining.count == 1 {
                        window.windowID = leftovers[0].id
                        usedOffscreen.insert(leftovers[0].id)
                    }
                }
                ordered.append(window)
            }
        }
        return ordered
    }
}

// MARK: - พิกัด: AppKit (origin ล่างซ้าย) <-> CoreGraphics/AX (origin บนซ้าย) --

enum Geometry {
    static var primaryHeight: CGFloat = 0

    /// พื้นที่ที่จัดหน้าต่างได้จริง — ไม่รวม menu bar และ Dock
    static func usableArea(of screen: NSScreen) -> NSRect {
        screen.visibleFrame
    }

    static func refresh() {
        primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
    }

    static func toCG(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func toAppKit(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func toAppKit(_ point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func toCG(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    static func screen(containing rect: CGRect) -> NSScreen? {
        screen(containing: NSPoint(x: rect.midX, y: primaryHeight - rect.midY))
    }

    enum Side { case left, right, top, bottom }

    /// ขอบด้านนี้ติดกับจออื่นไหม — ถ้าติดต้องมี "แรงต้าน" ก่อน snap
    static func isInnerEdge(_ side: Side, of screen: NSScreen) -> Bool {
        let f = screen.frame
        return NSScreen.screens.contains { other in
            guard other !== screen else { return false }
            let o = other.frame
            switch side {
            case .left:   return abs(o.maxX - f.minX) < 2 && o.maxY > f.minY && o.minY < f.maxY
            case .right:  return abs(o.minX - f.maxX) < 2 && o.maxY > f.minY && o.minY < f.maxY
            case .top:    return abs(o.minY - f.maxY) < 2 && o.maxX > f.minX && o.minX < f.maxX
            case .bottom: return abs(o.maxY - f.minY) < 2 && o.maxX > f.minX && o.minX < f.maxX
            }
        }
    }
}

// MARK: - โซน snap ------------------------------------------------------------

enum SnapZone: String {
    case left, right, top, bottom
    case topHalf                     // ครึ่งบน (top = เต็มจอ)
    case topLeft, topRight, bottomLeft, bottomRight
    case center

    var side: Geometry.Side? {
        switch self {
        case .left, .topLeft, .bottomLeft:    return .left
        case .right, .topRight, .bottomRight: return .right
        case .top, .topHalf:                  return .top
        case .bottom:                         return .bottom
        case .center:                         return nil
        }
    }

    /// โซนที่เหลือคู่กัน — ใช้เปิด Snap Assist ต่อ
    var complement: SnapZone? {
        switch self {
        case .left:        return .right
        case .right:       return .left
        case .topLeft:     return .topRight
        case .topRight:    return .topLeft
        case .bottomLeft:  return .bottomRight
        case .bottomRight: return .bottomLeft
        case .topHalf:     return .bottom
        case .bottom:      return .topHalf
        default:           return nil
        }
    }

    func rect(on screen: NSScreen) -> NSRect {
        let area = Geometry.usableArea(of: screen).insetBy(dx: Config.gap, dy: Config.gap)
        let g = Config.gap
        let halfW = (area.width - g) / 2
        let halfH = (area.height - g) / 2
        let rightX = area.minX + halfW + g
        let topY = area.minY + halfH + g

        switch self {
        case .top:         return area
        case .left:        return NSRect(x: area.minX, y: area.minY, width: halfW, height: area.height)
        case .right:       return NSRect(x: rightX,    y: area.minY, width: halfW, height: area.height)
        case .bottom:      return NSRect(x: area.minX, y: area.minY, width: area.width, height: halfH)
        case .topHalf:     return NSRect(x: area.minX, y: topY,      width: area.width, height: halfH)
        case .topLeft:     return NSRect(x: area.minX, y: topY,      width: halfW, height: halfH)
        case .topRight:    return NSRect(x: rightX,    y: topY,      width: halfW, height: halfH)
        case .bottomLeft:  return NSRect(x: area.minX, y: area.minY, width: halfW, height: halfH)
        case .bottomRight: return NSRect(x: rightX,    y: area.minY, width: halfW, height: halfH)
        case .center:
            let w = area.width * 0.6, h = area.height * 0.7
            return NSRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        }
    }

    static func detect(at point: NSPoint, on screen: NSScreen) -> SnapZone? {
        let f = screen.frame
        let edge = Config.edgeSensitivity
        let corner = Config.cornerSize

        // โซนซ้าย/ขวากว้างขึ้น จะได้ไม่ต้องดันเมาส์ชนขอบสุด — ขอบที่ติดจออื่นกว้างพิเศษ
        // เพื่อให้ snap ก่อนเคอร์เซอร์ข้ามไปจอที่สอง (ขอบพวกนี้ต้องหน่วงก่อน snap อยู่แล้ว)
        let edgeLeft  = edge + (Geometry.isInnerEdge(.left, of: screen)  ? 48 : 16)
        let edgeRight = edge + (Geometry.isInnerEdge(.right, of: screen) ? 48 : 16)

        let atLeft   = point.x <= f.minX + edgeLeft
        let atRight  = point.x >= f.maxX - edgeRight - 1
        let atTop    = point.y >= f.maxY - edge - 1
        let atBottom = point.y <= f.minY + edge

        let nearTop    = point.y >= f.maxY - corner
        let nearBottom = point.y <= f.minY + corner
        let nearLeft   = point.x <= f.minX + corner
        let nearRight  = point.x >= f.maxX - corner

        if (atLeft && nearTop) || (atTop && nearLeft)         { return .topLeft }
        if (atRight && nearTop) || (atTop && nearRight)       { return .topRight }
        if (atLeft && nearBottom) || (atBottom && nearLeft)   { return .bottomLeft }
        if (atRight && nearBottom) || (atBottom && nearRight) { return .bottomRight }

        // จอแนวตั้ง: ครึ่งบน/ครึ่งล่างมีประโยชน์กว่าครึ่งซ้าย/ขวามาก
        // เต็มจอย้ายไปอยู่ในแถบ Snap Layouts (ช่องแรก) และ Win+↑ กดซ้ำ
        let portrait = Config.portraitTopBottom && f.height > f.width

        if atLeft   { return .left }
        if atRight  { return .right }
        if atTop    { return portrait ? .topHalf : .top }
        if atBottom { return portrait || Config.bottomEdgeZone ? .bottom : nil }
        return nil
    }
}

// MARK: - Snap Layouts (แถบเลย์เอาต์แบบ Windows 11) ---------------------------

struct SnapLayout {
    let zones: [CGRect]   // unit rect ใน [0,1]² แกน y ชี้ขึ้น

    static func available(for screen: NSScreen) -> [SnapLayout] {
        let third = CGFloat(1.0 / 3.0)

        // จอแนวตั้ง = แบ่งบน-ล่าง ไม่ใช่ซ้าย-ขวา (Windows 11 ทำแบบเดียวกัน)
        if screen.frame.height > screen.frame.width {
            return [
                // เต็มจอ — เก็บท่า "ลากขึ้นบนแล้วเต็มจอ" ไว้ให้ยังใช้ได้
                SnapLayout(zones: [CGRect(x: 0, y: 0, width: 1, height: 1)]),
                // ครึ่งบน / ครึ่งล่าง
                SnapLayout(zones: [CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
                                   CGRect(x: 0, y: 0, width: 1, height: 0.5)]),
                // สามแถวซ้อน
                SnapLayout(zones: [CGRect(x: 0, y: third * 2, width: 1, height: third),
                                   CGRect(x: 0, y: third, width: 1, height: third),
                                   CGRect(x: 0, y: 0, width: 1, height: third)]),
                // บน 2/3 + ล่าง 1/3
                SnapLayout(zones: [CGRect(x: 0, y: third, width: 1, height: third * 2),
                                   CGRect(x: 0, y: 0, width: 1, height: third)]),
                // สี่ช่อง
                SnapLayout(zones: [CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                                   CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                                   CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                                   CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]),
                // บนเต็มความกว้าง + ล่างแบ่งสองคอลัมน์
                SnapLayout(zones: [CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
                                   CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                                   CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]),
            ]
        }

        var layouts: [SnapLayout] = [
            // เต็มจอ — ช่องแรกเหมือนฝั่งจอแนวตั้ง
            SnapLayout(zones: [CGRect(x: 0, y: 0, width: 1, height: 1)]),
            SnapLayout(zones: [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                               CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]),
            SnapLayout(zones: [CGRect(x: 0, y: 0, width: third, height: 1),
                               CGRect(x: third, y: 0, width: third, height: 1),
                               CGRect(x: third * 2, y: 0, width: third, height: 1)]),
            SnapLayout(zones: [CGRect(x: 0, y: 0, width: third * 2, height: 1),
                               CGRect(x: third * 2, y: 0, width: third, height: 1)]),
            SnapLayout(zones: [CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                               CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                               CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                               CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]),
            SnapLayout(zones: [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                               CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                               CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]),
        ]
        if screen.frame.width / screen.frame.height >= 1.9 {
            layouts.append(SnapLayout(zones: (0..<4).map {
                CGRect(x: CGFloat($0) * 0.25, y: 0, width: 0.25, height: 1)
            }))
        }
        return layouts
    }

    func rect(zone index: Int, on screen: NSScreen) -> NSRect {
        let area = Geometry.usableArea(of: screen).insetBy(dx: Config.gap, dy: Config.gap)
        let u = zones[index]
        let g = Config.gap / 2
        return NSRect(x: area.minX + u.minX * area.width + (u.minX > 0 ? g : 0),
                      y: area.minY + u.minY * area.height + (u.minY > 0 ? g : 0),
                      width: u.width * area.width - (u.minX > 0 ? g : 0) - (u.maxX < 1 ? g : 0),
                      height: u.height * area.height - (u.minY > 0 ? g : 0) - (u.maxY < 1 ? g : 0))
    }
}

// MARK: - เป้าหมายของการ snap -------------------------------------------------

enum SnapTarget: Equatable {
    case zone(SnapZone)
    case verticalMaximize
    case layoutZone(layout: Int, zone: Int)

    func rect(on screen: NSScreen, currentFrame: CGRect) -> NSRect {
        switch self {
        case .zone(let zone):
            return zone.rect(on: screen)
        case .verticalMaximize:
            let area = Geometry.usableArea(of: screen).insetBy(dx: Config.gap, dy: Config.gap)
            let ns = Geometry.toAppKit(currentFrame)
            return NSRect(x: ns.minX, y: area.minY, width: ns.width, height: area.height)
        case .layoutZone(let layoutIndex, let zoneIndex):
            let layouts = SnapLayout.available(for: screen)
            guard layoutIndex < layouts.count, zoneIndex < layouts[layoutIndex].zones.count else {
                return screen.visibleFrame
            }
            return layouts[layoutIndex].rect(zone: zoneIndex, on: screen)
        }
    }
}

// MARK: - Overlay พรีวิวโซน ---------------------------------------------------

final class OverlayWindow: NSWindow {
    /// หน้าต่างคลุมทั้งจอไว้เฉย ๆ แล้วขยับ "กรอบ" ที่เป็น CALayer ข้างในแทน
    /// — ย่อขยายผ่าน Core Animation ได้ลื่นกว่าการสั่งย้ายกรอบหน้าต่างทีละเฟรมมาก
    private let shape = CALayer()
    /// macOS 26 ขึ้นไปใช้ Liquid Glass ของระบบ ต่ำกว่านั้นตกไปใช้กรอบสีฟ้าทึบแบบเดิม
    private var glass: NSView?
    private var homeScreen: NSScreen?
    private var hiding = false

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none

        shape.backgroundColor = NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.98, alpha: 0.30).cgColor
        shape.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.90).cgColor
        shape.borderWidth = 2
        shape.cornerRadius = 10
        shape.cornerCurve = .continuous
        shape.opacity = 0
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = 0.25
        shape.shadowRadius = 12
        shape.shadowOffset = .zero

        let root = NSView()
        root.wantsLayer = true
        if #available(macOS 26.0, *) {
            let effect = NSGlassEffectView()
            effect.cornerRadius = 12
            effect.style = .clear
            effect.tintColor = NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.98, alpha: 0.13)
            effect.alphaValue = 0
            root.addSubview(effect)
            glass = effect
        } else {
            root.layer?.addSublayer(shape)
        }
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// rect เป็นพิกัดหน้าจอแบบ AppKit
    func present(_ rect: NSRect) {
        guard let screen = Geometry.screen(containing: NSPoint(x: rect.midX, y: rect.midY)) else { return }
        let fresh = !isVisible || hiding || homeScreen !== screen
        if homeScreen !== screen || !isVisible {
            homeScreen = screen
            setFrame(screen.frame, display: false)
        }
        hiding = false
        if !isVisible { orderFrontRegardless() }

        // แปลงเป็นพิกัดภายในหน้าต่างที่คลุมจออยู่
        let local = CGRect(x: rect.minX - screen.frame.minX, y: rect.minY - screen.frame.minY,
                           width: rect.width, height: rect.height)
        if fresh {
            // โผล่มาครั้งแรก: ผุดขึ้นจากขนาด 94% พร้อมจางเข้ามา
            shape.removeAnimation(forKey: "morph")
            place(local, animated: false)
            fade(to: 1, duration: 0.12)
            if glass == nil { pop(from: 0.94, duration: 0.20) }
        } else {
            place(local, animated: true, duration: 0.19)
        }
    }

    func dismiss() {
        guard isVisible, !hiding else { return }
        hiding = true
        fade(to: 0, duration: 0.12)
        if glass == nil { pop(from: 1.0, to: 0.97, duration: 0.12) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self, self.hiding else { return }
            self.hiding = false
            self.orderOut(nil)
        }
    }

    private func pop(from: CGFloat, to: CGFloat = 1.0, duration: CFTimeInterval) {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = from
        scale.toValue = to
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        scale.fillMode = .forwards
        shape.add(scale, forKey: "pop")
    }

    /// ยืด/หดกรอบไปยังขนาดใหม่ — เริ่มจากตำแหน่งที่ animation เดิมวิ่งค้างอยู่
    /// จะได้ไม่กระตุกเวลาลากสลับโซนเร็ว ๆ
    private func place(_ rect: CGRect, animated: Bool, duration: CFTimeInterval = 0.19) {
        if let glass {
            guard animated else { glass.frame = rect; return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                glass.animator().frame = rect
            }
            return
        }
        let position = CGPoint(x: rect.midX, y: rect.midY)
        let bounds = CGRect(origin: .zero, size: rect.size)

        if animated {
            let live = shape.presentation()
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: live?.position ?? shape.position)
            move.toValue = NSValue(point: position)
            let grow = CABasicAnimation(keyPath: "bounds")
            grow.fromValue = NSValue(rect: live?.bounds ?? shape.bounds)
            grow.toValue = NSValue(rect: bounds)
            let group = CAAnimationGroup()
            group.animations = [move, grow]
            group.duration = duration
            // ออกตัวไว แล้วค่อย ๆ เข้าที่ — ให้ความรู้สึกว่ากรอบ "ดีด" ไปติดโซน
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            shape.add(group, forKey: "morph")
        } else {
            shape.removeAnimation(forKey: "morph")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.position = position
        shape.bounds = bounds
        CATransaction.commit()
    }

    private func fade(to value: Float, duration: CFTimeInterval) {
        if let glass {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                glass.animator().alphaValue = CGFloat(value)
            }
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = shape.presentation()?.opacity ?? shape.opacity
        fade.toValue = value
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shape.add(fade, forKey: "fade")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.opacity = value
        CATransaction.commit()
    }
}

// MARK: - แถบ Snap Layouts ----------------------------------------------------

final class LayoutBarView: NSView {
    static let thumbGap: CGFloat = 12
    static let padding: CGFloat = 14

    /// รูปย่อจะเป็นแนวตั้งตามจอด้วย จะได้ดูออกว่าแบ่งบน-ล่าง
    var thumbSize = NSSize(width: 88, height: 54) { didSet { needsDisplay = true } }

    var layouts: [SnapLayout] = [] { didSet { needsDisplay = true } }
    var hovered: (layout: Int, zone: Int)? { didSet { needsDisplay = true } }
    /// true = ยังเป็นแถบเล็ก ๆ ที่รออยู่บนกลางจอ ยังไม่กางออก
    var collapsed = false { didSet { needsDisplay = true } }

    static let hintSize = NSSize(width: 116, height: 24)

    func barSize(count: Int) -> NSSize {
        NSSize(width: Self.padding * 2 + CGFloat(count) * thumbSize.width
                    + CGFloat(max(0, count - 1)) * Self.thumbGap,
               height: Self.padding * 2 + thumbSize.height)
    }

    func thumbRect(_ index: Int) -> NSRect {
        NSRect(x: Self.padding + CGFloat(index) * (thumbSize.width + Self.thumbGap),
               y: Self.padding, width: thumbSize.width, height: thumbSize.height)
    }

    func zoneRect(layout: Int, zone: Int) -> NSRect {
        let t = thumbRect(layout)
        let u = layouts[layout].zones[zone]
        return NSRect(x: t.minX + u.minX * t.width, y: t.minY + u.minY * t.height,
                      width: u.width * t.width, height: u.height * t.height).insetBy(dx: 1.5, dy: 1.5)
    }

    func zone(at point: NSPoint) -> (layout: Int, zone: Int)? {
        for layout in layouts.indices where thumbRect(layout).insetBy(dx: -5, dy: -5).contains(point) {
            for zone in layouts[layout].zones.indices
            where zoneRect(layout: layout, zone: zone).insetBy(dx: -2.5, dy: -2.5).contains(point) {
                return (layout, zone)
            }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        // พื้นหลังเป็น Liquid Glass (ครอบไว้ที่ contentView แล้ว) — ที่นี่วาดแต่เนื้อหา
        if collapsed {
            drawHint()
            return
        }

        for layout in layouts.indices {
            for zone in layouts[layout].zones.indices {
                let path = NSBezierPath(roundedRect: zoneRect(layout: layout, zone: zone), xRadius: 4, yRadius: 4)
                if let hovered, hovered.layout == layout, hovered.zone == zone {
                    NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.98, alpha: 1.0).setFill()
                } else {
                    NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
                }
                path.fill()
            }
        }
    }

    /// ใบ้ว่าข้างในมีอะไร — สามช่องเล็ก ๆ ที่แบ่งคนละแบบ
    private func drawHint() {
        let glyph = NSSize(width: 16, height: 11)
        let gap: CGFloat = 7
        let total = glyph.width * 3 + gap * 2
        var x = bounds.midX - total / 2
        let y = bounds.midY - glyph.height / 2
        for splits in [1, 2, 3] {
            let box = NSRect(x: x, y: y, width: glyph.width, height: glyph.height)
            let width = (box.width - CGFloat(splits - 1)) / CGFloat(splits)
            for part in 0..<splits {
                let cell = NSRect(x: box.minX + CGFloat(part) * (width + 1), y: box.minY,
                                  width: width, height: box.height)
                NSColor(calibratedWhite: 1, alpha: 0.55).setFill()
                NSBezierPath(roundedRect: cell, xRadius: 1.5, yRadius: 1.5).fill()
            }
            x += glyph.width + gap
        }
    }
}

final class LayoutBarWindow: NSWindow {
    let barView = LayoutBarView()
    /// กางออกเต็มแล้วหรือยัง (ต่างจาก isVisible ที่รวมสถานะแถบเล็กด้วย)
    private(set) var isExpanded = false
    /// กำลังคลี่ออก/ยุบเข้าอยู่ — ระหว่างนี้กรอบหน้าต่างยังวิ่งอยู่ อย่าเพิ่งเอาไปคิดอะไร
    private(set) var isSettling = false

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        // กระจกใสแบบเดียวกับเมนู/พรีวิว
        contentView = GlassBackdrop.wrap(barView, cornerRadius: 12, frosted: false)
    }

    override var canBecomeKey: Bool { false }

    /// แถบเล็ก ๆ ที่โผล่รอทันทีที่เริ่มลากหน้าต่าง แบบ Windows 11
    func presentHint(on screen: NSScreen) {
        let size = LayoutBarView.hintSize
        let rect = NSRect(x: screen.frame.midX - size.width / 2,
                          y: screen.visibleFrame.maxY - size.height,
                          width: size.width, height: size.height)
        if isVisible, !isExpanded, frame == rect { return }
        barView.collapsed = true
        barView.hovered = nil
        isExpanded = false
        if isVisible {
            isSettling = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.13
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(rect, display: true)
            }, completionHandler: { [weak self] in self?.isSettling = false })
        } else {
            alphaValue = 0
            setFrame(rect, display: false)
            orderFrontRegardless()
            GlassBackdrop.adaptToBackdrop(self)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                animator().alphaValue = 1
            }
        }
    }

    func present(on screen: NSScreen, layouts: [SnapLayout]) {
        barView.collapsed = false
        isExpanded = true
        barView.layouts = layouts
        barView.thumbSize = screen.frame.height > screen.frame.width
            ? NSSize(width: 58, height: 86)
            : NSSize(width: 88, height: 54)
        let size = barView.barSize(count: layouts.count)
        // เลื่อนลงมาให้พ้นเคอร์เซอร์ที่เพิ่งไปแตะแถบเล็ก ไม่งั้นแถบจะกางมาทับลูกศรพอดี
        let rect = NSRect(x: screen.frame.midX - size.width / 2,
                          y: screen.visibleFrame.maxY - size.height - 30,
                          width: size.width, height: size.height)
        if !isVisible {
            alphaValue = 0
            setFrame(rect, display: false)
            orderFrontRegardless()
            GlassBackdrop.adaptToBackdrop(self)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                animator().alphaValue = 1
            }
        } else {
            GlassBackdrop.adaptToBackdrop(self)
            // กางออกจากแถบเล็ก — ให้เห็นว่ามันคลี่ออกมา ไม่ใช่กระโดดเปลี่ยนขนาด
            isSettling = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                animator().setFrame(rect, display: true)
            }, completionHandler: { [weak self] in self?.isSettling = false })
        }
    }

    func dismiss() {
        guard isVisible else { return }
        isExpanded = false
        isSettling = false
        barView.hovered = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.09
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.orderOut(nil) })
    }
}

// MARK: - ตารางไอคอนหน้าต่าง (ใช้ร่วมกันระหว่าง Alt+Tab กับ Snap Assist) ------

final class TileGridView: NSView {
    var items: [WindowInfo] = [] { didSet { needsDisplay = true } }
    var selected: Int = 0 { didSet { needsDisplay = true } }
    var hovered: Int? { didSet { needsDisplay = true } }
    var headline: String?
    var onPick: ((Int) -> Void)?

    var tileSize = NSSize(width: 168, height: 128)
    /// ความสูงของช่องภาพหน้าต่าง — 0 = ไม่แสดงภาพ ใช้ไอคอนใหญ่แทน
    var previewHeight: CGFloat = 0
    var tileGap: CGFloat = 10
    var padding: CGFloat = 18
    var columns: Int = 5

    private var tracking: NSTrackingArea?

    static func gridSize(count: Int, columns: Int, tile: NSSize,
                         gap: CGFloat, padding: CGFloat, headline: Bool) -> NSSize {
        let cols = max(1, min(columns, count))
        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        return NSSize(width: padding * 2 + CGFloat(cols) * tile.width + CGFloat(cols - 1) * gap,
                      height: padding * 2 + CGFloat(rows) * tile.height + CGFloat(rows - 1) * gap
                            + (headline ? 26 : 0))
    }

    private var gridTop: CGFloat { bounds.height - padding - (headline == nil ? 0 : 26) }

    func tileRect(_ index: Int) -> NSRect {
        let cols = max(1, min(columns, items.count))
        let row = index / cols
        let col = index % cols
        let rowStart = row * cols
        let rowCount = min(cols, items.count - rowStart)
        let rowWidth = CGFloat(rowCount) * tileSize.width + CGFloat(rowCount - 1) * tileGap
        let x = (bounds.width - rowWidth) / 2 + CGFloat(col) * (tileSize.width + tileGap)
        let y = gridTop - CGFloat(row + 1) * tileSize.height - CGFloat(row) * tileGap
        return NSRect(x: x, y: y, width: tileSize.width, height: tileSize.height)
    }

    func index(at point: NSPoint) -> Int? {
        items.indices.first { tileRect($0).contains(point) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        selected = index
        onPick?(index)
    }

    override func draw(_ dirtyRect: NSRect) {
        // พื้นหลังเป็น Liquid Glass จาก GlassBackdrop ที่ครอบอยู่ ตรงนี้วาดแค่ตัว tile

        if let headline {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7),
                .paragraphStyle: style,
            ]
            let rect = NSRect(x: padding, y: bounds.height - padding - 18,
                              width: bounds.width - padding * 2, height: 18)
            (headline as NSString).draw(in: rect, withAttributes: attributes)
        }

        for index in items.indices { draw(item: items[index], in: tileRect(index), index: index) }
    }

    /// ย่อภาพให้พอดีกรอบโดยไม่บิดสัดส่วน
    private static func fit(_ size: NSSize, in box: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return NSRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    private func draw(item: WindowInfo, in rect: NSRect, index: Int) {
        if index == selected {
            NSColor.labelColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
        } else if index == hovered {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
        }

        let dim: CGFloat = item.isMinimized ? 0.45 : 1.0
        let shot = previewHeight > 0 && item.windowID != 0
            ? Thumbnails.shared.image(for: item.windowID) : nil

        if let shot {
            // ภาพหน้าต่างจริง + ไอคอนแอปเล็ก ๆ มุมซ้ายล่าง
            let box = NSRect(x: rect.minX + 8, y: rect.maxY - 8 - previewHeight,
                             width: rect.width - 16, height: previewHeight)
            let fitted = Self.fit(shot.size, in: box)
            let clip = NSBezierPath(roundedRect: fitted, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            shot.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: dim)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            clip.lineWidth = 1
            clip.stroke()
            if let icon = item.icon {
                let side: CGFloat = 26
                icon.draw(in: NSRect(x: fitted.minX + 5, y: fitted.minY + 5, width: side, height: side),
                          from: .zero, operation: .sourceOver, fraction: dim)
            }
        } else if let icon = item.icon {
            // ยังจับภาพไม่ได้ / ไม่ได้เปิดใช้ → ไอคอนใหญ่กลางช่องเหมือนเดิม
            let side: CGFloat = previewHeight > 0 ? 64 : 56
            let top = previewHeight > 0 ? rect.maxY - 8 - previewHeight : rect.maxY - 18 - side
            let centerY = previewHeight > 0 ? top + (previewHeight - side) / 2 : top
            icon.draw(in: NSRect(x: rect.midX - side / 2, y: centerY, width: side, height: side),
                      from: .zero, operation: .sourceOver, fraction: dim)
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail

        let nameRect = NSRect(x: rect.minX + 8, y: rect.minY + 32, width: rect.width - 16, height: 16)
        (item.appName as NSString).draw(in: nameRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ])

        let subtitle = item.isMinimized ? "· Minimized · " + item.title : item.title
        let titleRect = NSRect(x: rect.minX + 8, y: rect.minY + 12, width: rect.width - 16, height: 15)
        (subtitle as NSString).draw(in: titleRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 10.5),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(index == selected ? 0.85 : 0.55),
            .paragraphStyle: style,
        ])
    }
}

// MARK: - พื้นหลังพาเนลพรีวิว: Liquid Glass -----------------------------------------

/// ครอบ view เนื้อหาด้วยกระจกใสแบบ Liquid Glass (macOS 26) — รุ่นเก่าใช้กระจกฝ้าเข้มของระบบ
enum GlassBackdrop {
    /// เลือกสีตัวหนังสือให้เข้ากับสิ่งที่อยู่ใต้กระจก แบบเดียวกับ Control Center:
    /// พื้นหลังสว่าง → appearance สว่าง (ตัวหนังสือดำ) · มืด → ตัวหนังสือขาว
    /// ไม่มีสิทธิ์ Screen Recording → ใช้ธีมระบบ
    /// วัดพื้นหลังใต้แผ่น: ถ้าขาว (สว่างกว่าครึ่ง) ย้อมกระจกเป็นสีดำและทำให้ขุ่นขึ้น 10%
    /// พื้นมืด → ไม่แตะอะไร ใสเท่าเดิม  ·  ไม่มีสิทธิ์ Screen Recording → ถือว่ามืด
    static func adaptToBackdrop(_ window: NSWindow) {
        guard #available(macOS 26.0, *), let glass = findGlass(in: window.contentView) else { return }
        let light = (Thumbnails.backdropLuminance(below: window) ?? 0) > 0.5
        // ย้อมดำ 25% + ขุ่นเพิ่ม 10% = alpha 0.35
        glass.tintColor = light ? NSColor.black.withAlphaComponent(0.35) : nil
        window.appearance = light ? NSAppearance(named: .darkAqua) : nil   // บนพื้นย้อมดำให้ตัวหนังสือขาว
        window.contentView?.needsDisplay = true
        window.contentView?.subviews.forEach { $0.needsDisplay = true }
    }

    @available(macOS 26.0, *)
    private static func findGlass(in view: NSView?) -> NSGlassEffectView? {
        guard let view else { return nil }
        if let glass = view as? NSGlassEffectView { return glass }
        for child in view.subviews { if let glass = findGlass(in: child) { return glass } }
        return nil
    }

    /// frosted = true → กระจกฝ้า (เบลอข้างหลังจนสว่างเสมอกัน เหมาะกับเมนูที่มีตัวหนังสือเยอะ)
    /// frosted = false → กระจกใสแบบ Cmd+Tab (เห็นทะลุ มีแค่แสงหักเหตรงขอบ เหมาะกับพาเนลเล็ก ๆ)
    static func wrap(_ content: NSView, cornerRadius: CGFloat = 28, frosted: Bool = false) -> NSView {
        if #available(macOS 26.0, *) {
            // ต้องวางกระจกไว้ใน view ที่มี layer อีกชั้น (แบบเดียวกับกรอบพรีวิวโซน) ไม่งั้นไม่หักแสง
            let root = NSView()
            root.wantsLayer = true
            // ตัดทุกอย่างให้อยู่ในมุมโค้งเดียวกับกระจก — กระจกฝ้าจะวาดพื้นหลังทับมุมออกมาเป็นเหลี่ยม
            root.layer?.cornerRadius = cornerRadius
            root.layer?.masksToBounds = true
            root.layer?.backgroundColor = NSColor.clear.cgColor
            let effect = NSGlassEffectView(frame: root.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.cornerRadius = cornerRadius
            effect.style = frosted ? .regular : .clear
            effect.contentView = content
            root.addSubview(effect)
            return root
        }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}

// MARK: - Alt+Tab: ตัวสลับหน้าต่าง -------------------------------------------

final class SwitcherPanel: NSPanel {
    let grid = TileGridView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = GlassBackdrop.wrap(grid)
    }

    override var canBecomeKey: Bool { true }

    func present(items: [WindowInfo], selected: Int, on screen: NSScreen) {
        grid.items = items
        grid.selected = selected
        grid.hovered = nil
        grid.headline = nil
        if Thumbnails.isUsable {
            grid.tileSize = NSSize(width: 216, height: 172)
            grid.previewHeight = 116
        } else {
            grid.tileSize = NSSize(width: 168, height: 128)
            grid.previewHeight = 0
        }

        let columns = min(items.count, max(3, Int((screen.frame.width * 0.8) / (grid.tileSize.width + grid.tileGap))), 7)
        grid.columns = columns
        let size = TileGridView.gridSize(count: items.count, columns: columns, tile: grid.tileSize,
                                         gap: grid.tileGap, padding: grid.padding, headline: false)
        let rect = NSRect(x: screen.frame.midX - size.width / 2,
                          y: screen.frame.midY - size.height / 2,
                          width: size.width, height: size.height)
        setFrame(rect, display: true)
        orderFrontRegardless()
        makeKey()   // เป็น key window ตั้งแต่โผล่ — ไม่งั้น macOS วาดกระจกแบบ inactive (ขุ่น) จนกว่าจะคลิก
        GlassBackdrop.adaptToBackdrop(self)
        grid.needsDisplay = true
    }
}

// MARK: - Snap Assist: เลือกหน้าต่างมาเติมช่องที่เหลือ ------------------------

final class SnapAssistPanel: NSPanel {
    let grid = TileGridView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = GlassBackdrop.wrap(grid)
    }

    override var canBecomeKey: Bool { true }

    /// region = ช่องว่างที่เหลือ (พิกัด AppKit) — พาเนลจะพอดีอยู่ในนั้น
    func present(items: [WindowInfo], in region: NSRect) {
        grid.items = items
        grid.selected = -1
        grid.hovered = nil
        grid.headline = "Pick a window for this space"
        if Thumbnails.isUsable {
            grid.tileSize = NSSize(width: 186, height: 148)
            grid.previewHeight = 96
        } else {
            grid.tileSize = NSSize(width: 150, height: 118)
            grid.previewHeight = 0
        }

        let usable = region.insetBy(dx: 12, dy: 12)
        let columns = max(1, min(items.count,
                                 Int((usable.width - grid.padding * 2 + grid.tileGap)
                                     / (grid.tileSize.width + grid.tileGap))))
        grid.columns = columns
        var size = TileGridView.gridSize(count: items.count, columns: columns, tile: grid.tileSize,
                                         gap: grid.tileGap, padding: grid.padding, headline: true)
        size.width = min(size.width, usable.width)
        size.height = min(size.height, usable.height)

        setFrame(NSRect(x: region.midX - size.width / 2, y: region.midY - size.height / 2,
                        width: size.width, height: size.height), display: true)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()   // เป็น key window ตั้งแต่โผล่ — ไม่งั้น macOS วาดกระจกแบบ inactive (ขุ่น) จนกว่าจะคลิก
        GlassBackdrop.adaptToBackdrop(self)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            animator().alphaValue = 1
        }
    }
}

// MARK: - เส้นแบ่งระหว่างหน้าต่างที่ snap คู่กัน -------------------------------

final class DividerView: NSView {
    var isHorizontal = false
    var onDragBegan: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var tracking: NSTrackingArea?
    private var highlighted = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        (isHorizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
    }

    override func mouseEntered(with event: NSEvent) {
        highlighted = true
        (isHorizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
    }

    override func mouseExited(with event: NSEvent) {
        highlighted = false
        NSCursor.arrow.set()
    }

    /// หน้าต่างเส้นแบ่งไม่เคยเป็น key window — ถ้าไม่บอกว่ารับคลิกแรก คลิกจะไม่ถูกส่งมาที่ view
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onDragBegan?() }
    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
        NSCursor.arrow.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        // ต้องมีพิกเซลไม่ใสสนิทเต็มพื้นที่เสมอ — จุดที่ใส 100% macOS จะให้คลิกทะลุไปหน้าต่างข้างล่าง
        NSColor(calibratedWhite: 0, alpha: 0.02).setFill()
        bounds.fill()
        guard highlighted else { return }
        let bar = isHorizontal
            ? bounds.insetBy(dx: bounds.width * 0.25, dy: bounds.height / 2 - 1.5)
            : bounds.insetBy(dx: bounds.width / 2 - 1.5, dy: bounds.height * 0.25)
        NSColor(calibratedWhite: 1, alpha: 0.55).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

final class DividerWindow: NSPanel {
    let dividerView = DividerView()

    /// หน้าต่างที่อยู่ก่อน/หลังเส้นแบ่ง พร้อมกรอบตอนเริ่มลาก (พิกัด AppKit)
    var before: [(element: AXUIElement, rect: NSRect)] = []
    var after: [(element: AXUIElement, rect: NSRect)] = []
    var isHorizontal = false
    /// ช่องว่างระหว่างสองฝั่ง (tiling ของ macOS เว้นไว้) — ลากแล้วยังเว้นเท่าเดิม
    var gap: CGFloat = 0
    var limits: ClosedRange<CGFloat> = 0...0
    /// (รายการ (element, เฟรมเดิม, เฟรมใหม่), callback เมื่อยิงเสร็จ)
    var onApply: (([(AXUIElement, CGRect, CGRect)], @escaping () -> Void) -> Void)?
    /// เฟรมล่าสุดที่ยิงไปแล้วของแต่ละบาน — ใช้คำนวณว่าต้องยิงอะไรบ้างในรอบถัดไป
    private var lastSent: [AXKey: CGRect] = [:]
    var onFinished: (() -> Void)?

    private var applying = false
    /// กำลังลากอยู่ — SnapManager จะไม่จัดเส้นใหม่ระหว่างนี้
    private(set) var isDragging = false
    /// ตำแหน่งล่าสุดที่ยังไม่ได้ยิง (ระหว่างรอ throttle) — จะยิงให้ทันทีที่ว่าง ไม่ทิ้ง
    private var pending: NSPoint?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        contentView = dividerView

        dividerView.onDragBegan = { [weak self] in self?.isDragging = true }
        dividerView.onDrag = { [weak self] point in self?.drag(to: point) }
        dividerView.onDragEnded = { [weak self] in self?.finishDrag(at: NSEvent.mouseLocation) }
    }

    override var canBecomeKey: Bool { false }

    func configure(isHorizontal: Bool, position: CGFloat, span: ClosedRange<CGFloat>,
                   limits: ClosedRange<CGFloat>) {
        self.isHorizontal = isHorizontal
        self.limits = limits
        dividerView.isHorizontal = isHorizontal
        let thickness: CGFloat = 10
        let frame = isHorizontal
            ? NSRect(x: span.lowerBound, y: position - thickness / 2,
                     width: span.upperBound - span.lowerBound, height: thickness)
            : NSRect(x: position - thickness / 2, y: span.lowerBound,
                     width: thickness, height: span.upperBound - span.lowerBound)
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    private func drag(to point: NSPoint) {
        guard !limits.isEmpty else { return }
        // เส้นวิ่งตามเมาส์ทันทีทุกอีเวนต์ ไม่รอผลจากแอป — ให้รู้สึกติดมือ
        moveBar(to: clamped(point))
        if applying { pending = point; return }
        apply(point)
    }

    private func clamped(_ point: NSPoint) -> CGFloat {
        let raw = isHorizontal ? point.y : point.x
        return min(max(raw, limits.lowerBound), limits.upperBound)
    }

    private func moveBar(to position: CGFloat) {
        let thickness: CGFloat = 10
        if isHorizontal {
            setFrameOrigin(NSPoint(x: frame.minX, y: position - thickness / 2))
        } else {
            setFrameOrigin(NSPoint(x: position - thickness / 2, y: frame.minY))
        }
    }

    /// ปล่อยเมาส์: ยิงตำแหน่งที่ปล่อยจริงโดยไม่ throttle ให้สองฝั่งจบที่จุดเดียวกันแน่ ๆ แล้วค่อยวางเส้นใหม่
    private func finishDrag(at point: NSPoint) {
        pending = nil
        applying = false
        lastSent.removeAll()          // รอบสุดท้ายยิงเต็มเฟรม ไม่พึ่งค่าที่จำไว้ ให้จบตรงจุดแน่ ๆ
        apply(point)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.isDragging = false
            self.lastSent.removeAll()
            self.onFinished?()
        }
    }

    private func apply(_ point: NSPoint) {
        let position = clamped(point)
        var updates: [(AXUIElement, CGRect, CGRect)] = []
        let half = gap / 2
        func push(_ element: AXUIElement, _ ns: NSRect) {
            let target = Geometry.toCG(ns)
            let key = AXKey(element: element)
            let previous = lastSent[key] ?? Geometry.toCG(ns).insetBy(dx: -1, dy: -1)   // ไม่รู้ = ถือว่าต่างทุกอย่าง
            lastSent[key] = target
            updates.append((element, previous, target))
        }
        for item in before {
            let r = item.rect
            push(item.element, isHorizontal
                ? NSRect(x: r.minX, y: position + half, width: r.width, height: r.maxY - position - half)
                : NSRect(x: r.minX, y: r.minY, width: position - half - r.minX, height: r.height))
        }
        for item in after {
            let r = item.rect
            push(item.element, isHorizontal
                ? NSRect(x: r.minX, y: r.minY, width: r.width, height: position - half - r.minY)
                : NSRect(x: position + half, y: r.minY, width: r.maxX - position - half, height: r.height))
        }
        moveBar(to: position)

        applying = true
        onApply?(updates) { [weak self] in
            guard let self else { return }
            self.applying = false
            if let next = self.pending { self.pending = nil; self.apply(next) }
        }
    }
}

// MARK: - ตัวจัดการหลัก -------------------------------------------------------

final class SnapManager {
    static let shared = SnapManager()

    var isEnabled = Config.snapEnabled {
        didSet {
            Config.snapEnabled = isEnabled
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: isEnabled) }
            if !isEnabled { resetDrag(); hideAllDividers() }
        }
    }

    private let overlay = OverlayWindow()
    private let layoutBar = LayoutBarWindow()
    private let switcher = SwitcherPanel()
    private let assistPanel = SnapAssistPanel()
    private let axQueue = DispatchQueue(label: "com.knack.ax", qos: .userInteractive)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// ตัวเลขสำหรับหน้า "ตรวจสถานะ" — ไว้ไล่หาว่าติดตรงไหนเวลาลากแล้วไม่ทำงาน
    struct Diagnostics {
        var tapActive = false
        var hotKeysRegistered = false
        var mouseEvents = 0
        var dragsStarted = 0
        var windowsFound = 0
        var movesConfirmed = 0
        var resizesConfirmed = 0
        var zonesPreviewed = 0
        var snapsApplied = 0
        var lastWindow = "-"
        var lastZone = "-"
        var lastNote = "-"
    }
    private(set) var diag = Diagnostics()
    var isRunning: Bool { diag.tapActive }
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private let syntheticTag: Int64 = 0x57_4D_41_43   // 'WMAC'

    // MARK: สถานะการลาก

    private enum DragMode { case undetermined, moving, resizeTop, resizeBottom, ignored }

    private var dragMode: DragMode = .undetermined
    private var borderHint: DragMode = .ignored
    private var mouseDownAt: CGPoint = .zero
    private var draggedWindow: AXUIElement?
    private var startFrame: CGRect = .zero
    private var lastModeCheck: CFAbsoluteTime = 0
    private var didUnsnap = false

    private var activeTarget: SnapTarget?
    private var activeScreen: NSScreen?
    private var pendingTarget: SnapTarget?
    private var dwellToken = 0


    private struct SnapState {
        var target: SnapTarget
        var snappedFrame: CGRect
        var originalFrame: CGRect
    }
    private var snapStates: [AXKey: SnapState] = [:]

    // Alt+Tab
    private var switcherItems: [WindowInfo] = []
    private var switcherIndex = 0
    private var switcherTimer: Timer?
    private var switcherMonitors: [Any] = []
    private var switcherModifier: NSEvent.ModifierFlags = .option   // ปล่อยปุ่มนี้ = ยืนยัน (Option หรือ Command)

    // Snap Assist
    private struct AssistSession {
        let screen: NSScreen
        var layout: Int?
        var filled: Set<Int> = []
        var used: Set<AXKey> = []
    }
    private var assistSession: AssistSession?
    private var assistTarget: SnapTarget?
    private var assistMonitors: [Any] = []
    private var assistTimeout: Timer?

    // เส้นแบ่ง
    private var dividerPool: [DividerWindow] = []
    private var dividerTimer: Timer?

    // MARK: Event tap

    func startEventTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, _ in
            SnapManager.shared.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: callback, userInfo: nil) else { return false }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        diag.tapActive = true

        dividerTimer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.rebuildDividers()
        }
        RunLoop.main.add(dividerTimer!, forMode: .common)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: isEnabled) }
            return
        }
        guard isEnabled else { return }
        guard event.getIntegerValueField(.eventSourceUserData) != syntheticTag else { return }

        diag.mouseEvents += 1
        let location = event.location
        switch type {
        case .leftMouseDown:
            // คลิกที่ตกลงบนหน้าต่างหรือไอคอนเมนูบาร์ของ Deft เอง ต้องไม่เริ่มลาก:
            // ถ้าปล่อยให้ axQueue ยิง AXUIElementCopyElementAtPosition ใส่ตัวเอง HIServices จะตอบ
            // ในโปรเซสเดียวกันบนเธรดนั้นทันที ไปชนกับ AppKit ที่กำลังกางเมนูบน main thread
            // → heap corruption (BUG_IN_CLIENT_OF_LIBMALLOC) แล้วแอปดับ  ·  เมนูบาร์ก็ไม่มีหน้าต่างให้ลากอยู่แล้ว
            guard event.getIntegerValueField(.eventTargetUnixProcessID) != Int64(getpid()),
                  !Self.isInMenuBar(location) else { return }
            beginDrag(at: location, clickState: event.getIntegerValueField(.mouseEventClickState))
        case .leftMouseDragged:
            updateDrag(at: location)
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
    }

    // MARK: เริ่มลาก

    /// จุด (พิกัด CG) อยู่ในแถบเมนูบาร์ของจอใดจอหนึ่งไหม
    private static func isInMenuBar(_ point: CGPoint) -> Bool {
        let cocoa = Geometry.toAppKit(point)
        guard let screen = Geometry.screen(containing: cocoa) else { return false }
        // จอที่ไม่มีเมนูบาร์ (จอรองตอนปิด "แต่ละจอมี Space แยก") ห้ามกันขอบบน — ไม่งั้นหน้าต่างเต็มจอบนจอนั้น
        // จะจับ title bar ลากไม่ได้เลย
        let hasMenuBar = screen == NSScreen.screens.first || NSScreen.screensHaveSeparateSpaces
        guard hasMenuBar else { return false }
        // visibleFrame ตัดเมนูบาร์ออกแล้ว — แต่ถ้าตั้งเมนูบาร์ซ่อนอัตโนมัติจะเท่ากับ frame จึงกันด้วยความหนาปกติ
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        let barHeight = reserved > 0 ? reserved : NSStatusBar.system.thickness
        return cocoa.y >= screen.frame.maxY - barHeight
    }

    private func beginDrag(at point: CGPoint, clickState: Int64) {
        resetDrag()
        mouseDownAt = point

        diag.dragsStarted += 1
        axQueue.async {
            guard let window = AX.windowUnderCursor(point), let frame = AX.frame(of: window) else {
                DispatchQueue.main.async { self.diag.lastNote = "No window under the cursor" }
                return
            }
            let hint = Self.borderHint(cursor: point, frame: frame)
            let owner = NSRunningApplication(processIdentifier: AX.pid(of: window))?.localizedName ?? "?"
            DispatchQueue.main.async {
                self.diag.windowsFound += 1
                self.diag.lastWindow = owner
                self.draggedWindow = window
                self.startFrame = frame
                self.borderHint = hint
                if clickState == 2, Config.verticalMaximize,
                   hint == .resizeTop || hint == .resizeBottom,
                   let screen = Geometry.screen(containing: frame) {
                    self.commit(target: .verticalMaximize, window: window,
                                currentFrame: frame, screen: screen, chain: false)
                    self.dragMode = .ignored
                } else if clickState == 2, Config.trueMaximize, hint == .ignored,
                          point.y - frame.minY < 34,
                          let screen = Geometry.screen(containing: frame) {
                    // ดับเบิลคลิก title bar = เต็มจอแบบยังเห็น menu bar + Dock (ไม่ใช่ full screen)
                    // หน่วงนิดนึงให้ทำหลัง macOS จะได้ทับผลของมัน
                    self.dragMode = .ignored
                    let key = AXKey(element: window)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        if let state = self.snapStates[key], state.target == .zone(.top) {
                            let original = state.originalFrame
                            self.snapStates[key] = nil
                            self.axQueue.async { AX.setFrame(window, original) }
                        } else {
                            self.commit(target: .zone(.top), window: window,
                                        currentFrame: frame, screen: screen, chain: false)
                        }
                    }
                }
            }
        }
    }

    private static func borderHint(cursor: CGPoint, frame: CGRect) -> DragMode {
        let slop = Config.borderSlop
        guard cursor.x > frame.minX + 24, cursor.x < frame.maxX - 24 else { return .ignored }
        if abs(cursor.y - frame.minY) <= slop { return .resizeTop }
        if abs(cursor.y - frame.maxY) <= slop { return .resizeBottom }
        return .ignored
    }

    // MARK: ระหว่างลาก

    private func updateDrag(at point: CGPoint) {
        guard let window = draggedWindow else { return }
        if dragMode == .undetermined {
            classifyDrag(window: window, point: point)
            return
        }
        switch dragMode {
        case .moving:
            if Config.unsnapOnDrag { unsnapIfNeeded(window: window, point: point) }
            updateMoveTarget(at: point)
        case .resizeTop, .resizeBottom:
            updateResizeTarget(at: point)
        default:
            break
        }
    }

    private func classifyDrag(window: AXUIElement, point: CGPoint) {
        guard hypot(point.x - mouseDownAt.x, point.y - mouseDownAt.y) > Config.dragThreshold else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastModeCheck > 0.06 else { return }
        lastModeCheck = now

        let start = startFrame
        let hint = borderHint
        axQueue.async {
            guard let frame = AX.frame(of: window) else { return }
            let movedX = abs(frame.minX - start.minX) > 2
            let movedTop = abs(frame.minY - start.minY) > 2
            let movedBottom = abs(frame.maxY - start.maxY) > 2
            let sameSize = abs(frame.width - start.width) < 2 && abs(frame.height - start.height) < 2

            var mode: DragMode = .undetermined
            if (movedX || movedTop) && sameSize {
                mode = .moving
            } else if hint == .resizeTop, movedTop, !movedBottom {
                mode = .resizeTop
            } else if hint == .resizeBottom, movedBottom, !movedTop {
                mode = .resizeBottom
            }
            guard mode != .undetermined else { return }
            DispatchQueue.main.async {
                self.dragMode = mode
                if mode == .moving { self.diag.movesConfirmed += 1 }
                else { self.diag.resizesConfirmed += 1 }
                self.diag.lastNote = mode == .moving ? "Moving a window"
                                                     : "Resizing an edge"
            }
        }
    }

    private func updateMoveTarget(at point: CGPoint) {
        let appKit = Geometry.toAppKit(point)
        guard let screen = Geometry.screen(containing: appKit) else {
            clearTarget()
            return
        }

        if Config.snapLayouts {
            let layouts = SnapLayout.available(for: screen)
            // แบบ Windows 11: แถบเล็ก ๆ โผล่รออยู่บนกลางจอตั้งแต่เริ่มลาก แล้วจะคลี่ออก
            // ก็ต่อเมื่อเคอร์เซอร์เลื่อนขึ้นไป "แตะ" แถบนั้นจริง ๆ ไม่ใช่แค่เข้ามาใกล้
            let hintTarget = layoutBar.isExpanded ? layoutBar.frame
                                                  : layoutBar.frame.insetBy(dx: -10, dy: -8)
            // ระหว่างที่กรอบยังวิ่งอยู่ ขนาดหน้าต่างกับตำแหน่งช่องข้างในยังไม่ตรงกัน
            // ถ้าปล่อยให้จับ hover ตอนนั้น กรอบพรีวิวสีฟ้าจะแว้บขึ้นมาโดยที่ยังไม่ได้เลือก
            let touchingHint = layoutBar.isVisible && !layoutBar.isSettling
                && hintTarget.contains(appKit)

            if layoutBar.isExpanded {
                guard !layoutBar.isSettling else { return }
                let local = NSPoint(x: appKit.x - layoutBar.frame.minX, y: appKit.y - layoutBar.frame.minY)
                if let hit = layoutBar.barView.zone(at: local) {
                    layoutBar.barView.hovered = hit
                    setTarget(.layoutZone(layout: hit.layout, zone: hit.zone), screen: screen, immediate: true)
                    return
                }
                layoutBar.barView.hovered = nil
                // ลากออกห่างแล้วยุบกลับเป็นแถบเล็ก ไม่ใช่หายไปเลย จะได้กลับมาเลือกใหม่ได้
                if appKit.y < layoutBar.frame.minY - 56
                    || abs(appKit.x - screen.frame.midX) > layoutBar.frame.width / 2 + 90 {
                    layoutBar.presentHint(on: screen)
                    clearTarget()
                }
            } else if touchingHint {
                layoutBar.present(on: screen, layouts: layouts)
            } else {
                layoutBar.presentHint(on: screen)
            }
        }

        guard let zone = SnapZone.detect(at: appKit, on: screen) else {
            clearTarget()
            return
        }
        let isInner = zone.side.map { Geometry.isInnerEdge($0, of: screen) } ?? false
        if diag.lastZone != zone.rawValue {
            diag.lastZone = zone.rawValue
            diag.zonesPreviewed += 1
        }
        setTarget(.zone(zone), screen: screen, immediate: !isInner)
    }

    private func updateResizeTarget(at point: CGPoint) {
        guard Config.verticalMaximize else { return }
        let appKit = Geometry.toAppKit(point)
        guard let screen = Geometry.screen(containing: appKit) else {
            clearTarget()
            return
        }
        let f = screen.frame
        let hit = dragMode == .resizeTop
            ? appKit.y >= f.maxY - Config.edgeSensitivity - 1
            : appKit.y <= f.minY + Config.edgeSensitivity
        if hit {
            setTarget(.verticalMaximize, screen: screen, immediate: true)
        } else {
            if Config.unsnapOnDrag { unsnapVerticalIfNeeded(point: point) }
            clearTarget()
        }
    }

    private func setTarget(_ target: SnapTarget, screen: NSScreen, immediate: Bool) {
        if activeTarget == target && activeScreen === screen { return }
        if immediate {
            pendingTarget = nil
            dwellToken += 1
            activeTarget = target
            activeScreen = screen
            overlay.present(target.rect(on: screen, currentFrame: startFrame))
            return
        }
        guard pendingTarget != target else { return }
        pendingTarget = target
        dwellToken += 1
        let token = dwellToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.innerEdgeDwell) { [weak self] in
            guard let self, self.dwellToken == token, self.pendingTarget == target else { return }
            guard let stillOn = Geometry.screen(containing: NSEvent.mouseLocation),
                  stillOn === screen else { return }
            self.activeTarget = target
            self.activeScreen = screen
            self.overlay.present(target.rect(on: screen, currentFrame: self.startFrame))
        }
    }

    private func clearTarget() {
        activeTarget = nil
        activeScreen = nil
        pendingTarget = nil
        dwellToken += 1
        overlay.dismiss()
    }

    private func endDrag() {
        defer { resetDrag() }
        overlay.dismiss()
        layoutBar.dismiss()
        guard let target = activeTarget, let screen = activeScreen, let window = draggedWindow else { return }
        commit(target: target, window: window, currentFrame: startFrame, screen: screen, chain: true)
    }

    private func resetDrag() {
        draggedWindow = nil
        startFrame = .zero
        dragMode = .undetermined
        borderHint = .ignored
        didUnsnap = false
        activeTarget = nil
        activeScreen = nil
        pendingTarget = nil
        dwellToken += 1
        overlay.dismiss()
        layoutBar.dismiss()
    }

    // MARK: ลงมือจัดหน้าต่าง

    private func commit(target: SnapTarget, window: AXUIElement, currentFrame: CGRect,
                        screen: NSScreen, chain: Bool) {
        let rect = Geometry.toCG(target.rect(on: screen, currentFrame: currentFrame))
        let key = AXKey(element: window)
        let original = snapStates[key]?.originalFrame ?? currentFrame
        snapStates[key] = SnapState(target: target, snappedFrame: rect, originalFrame: original)
        diag.snapsApplied += 1
        if snapStates.count > 80 { snapStates.removeAll() }

        axQueue.async {
            if AX.isFullScreen(window) {
                AX.exitFullScreen(window)
                Thread.sleep(forTimeInterval: 0.45)
            }
            AX.setFrame(window, rect)

            // บางแอปไม่ยอมรับขนาดที่สั่ง เช่นโปรแกรมดูหนังที่ล็อกอัตราส่วนภาพไว้ตามวิดีโอ
            // หรือหน้าต่างที่มีขนาดต่ำสุดใหญ่กว่าโซน — ปล่อยไว้มันจะไปกองอยู่มุมโซน
            // แล้วเหลือช่องว่างข้างล่างดูเหมือนจัดไม่ติด จัดกลางโซนให้แทนจะดูตั้งใจกว่า
            if let actual = AX.frame(of: window),
               abs(actual.width - rect.width) > 8 || abs(actual.height - rect.height) > 8 {
                AX.setPosition(window, CGPoint(x: rect.midX - actual.width / 2,
                                               y: rect.midY - actual.height / 2))
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if chain { self.offerAssist(after: target, window: window, screen: screen) }
                self.rebuildDividers()
            }
        }
    }

    // MARK: ลากหน้าต่างที่ snap อยู่ออกมา

    private func unsnapIfNeeded(window: AXUIElement, point: CGPoint) {
        guard !didUnsnap else { return }
        guard hypot(point.x - mouseDownAt.x, point.y - mouseDownAt.y) > 28 else { return }
        let key = AXKey(element: window)
        didUnsnap = true   // ตัดสินครั้งเดียวต่อการลาก — ไม่ว่าจะย่อหรือไม่

        // ขนาดที่จะคืนให้: ปกติคือขนาดก่อน snap ที่จำไว้
        var original: CGRect? = nil
        if let state = snapStates[key], Self.roughlyEqual(startFrame, state.snappedFrame) {
            original = state.originalFrame
        }
        snapStates[key] = nil

        // ไม่มีข้อมูล (ขยายด้วย macOS เอง / Deft เพิ่งเปิด / แอปเปิดใหม่) หรือขนาดเดิมก็ใหญ่เต็มจออยู่แล้ว —
        // ถ้าหน้าต่างที่ลากอยู่ใหญ่เกือบเต็มจอ ให้ย่อเหลือครึ่งหนึ่งทั้งกว้างและสูง ไม่งั้นจะลากไปไหนหรือย่อต่อไม่ได้เลย
        if let screen = Geometry.screen(containing: startFrame) {
            let full = Self.isNearlyFull(startFrame, on: screen)
            if original == nil || Self.isNearlyFull(original!, on: screen) {
                guard full else { return }
                original = CGRect(x: 0, y: 0, width: (startFrame.width / 2).rounded(),
                                  height: (startFrame.height / 2).rounded())
            }
        }
        guard let original, original.width > 40, original.height > 40 else { return }
        hideAllDividers()

        let ratioX = startFrame.width > 0 ? (mouseDownAt.x - startFrame.minX) / startFrame.width : 0.5
        let offsetY = min(mouseDownAt.y - startFrame.minY, 20)
        // วางหน้าต่างใหม่ให้เคอร์เซอร์อยู่ที่ title bar ตำแหน่งสัดส่วนเดิม — ใช้ตำแหน่งเมาส์ ณ ตอนลงมือจริง
        // ไม่ใช่ตอนตัดสินใจ เพราะระหว่างนั้นมือยังเลื่อนอยู่
        restartDrag(window: window, at: point, from: startFrame, to: original.size) { size in
            CGPoint(x: size.width * ratioX, y: offsetY)
        }
    }

    private func unsnapVerticalIfNeeded(point: CGPoint) {
        guard !didUnsnap, let window = draggedWindow else { return }
        let key = AXKey(element: window)
        guard let state = snapStates[key], state.target == .verticalMaximize,
              Self.roughlyEqual(startFrame, state.snappedFrame) else { return }
        let appKit = Geometry.toAppKit(point)
        guard let screen = Geometry.screen(containing: appKit) else { return }
        let awayFromEdge = dragMode == .resizeTop
            ? appKit.y < screen.frame.maxY - 30
            : appKit.y > screen.frame.minY + 30
        guard awayFromEdge else { return }

        didUnsnap = true
        snapStates[key] = nil
        let original = state.originalFrame
        // ยืดเต็มความสูงกลับลงมา: ยึดขอบซ้ายเดิม เมาส์อยู่ที่ขอบบน/ล่างตามทิศที่ลาก
        let grabX = point.x - startFrame.minX, fromTop = dragMode == .resizeTop
        restartDrag(window: window, at: point, from: startFrame,
                    to: CGSize(width: startFrame.width, height: original.height)) { size in
            CGPoint(x: grabX, y: fromTop ? 10 : size.height - 10)
        }
    }

    /// เปลี่ยนขนาดหน้าต่าง "กลางคัน" โดยไม่ปล่อยเมาส์ — macOS ยังคงลากต่อให้และเคอร์เซอร์เกาะ title bar
    /// ตำแหน่งใหม่ (เคยใช้วิธีปล่อย+กดเมาส์ใหม่ แต่จุดที่กดใหม่มักไปโดนปุ่ม/ช่องค้นหาบน title bar ของแอป ทำให้ลากต่อไม่ได้)
    /// หน้าต่างจริงย่อครั้งเดียวแบบทันที (เหมือน macOS unzoom-on-drag) แล้ววางให้เมาส์อยู่ที่จุด anchor เดิม
    private func restartDrag(window: AXUIElement, at point: CGPoint, from start: CGRect, to size: CGSize,
                             anchor: @escaping (CGSize) -> CGPoint) {
        func cursorNow() -> CGPoint { CGEvent(source: nil)?.location ?? point }
        func place(_ cursor: CGPoint, _ s: CGSize) -> CGPoint {
            let off = anchor(s); return CGPoint(x: cursor.x - off.x, y: cursor.y - off.y)
        }
        axQueue.async {
            var target = CGRect(origin: place(cursorNow(), size), size: size)
            AX.setFrame(window, target)
            // รอให้แอปขยับจริง (สูงสุด ~0.2 วิ) — เช็คจากขนาด เพราะตำแหน่งอาจถูกแอปปัดเล็กน้อย
            var actual = AX.frame(of: window) ?? target
            for _ in 0..<12 where abs(actual.width - target.width) > 8 || abs(actual.height - target.height) > 8 {
                Thread.sleep(forTimeInterval: 0.016)
                actual = AX.frame(of: window) ?? target
            }
            // ถ้าระหว่างนั้นมือเลื่อนออกนอกแถบบนของหน้าต่างไปแล้ว ขยับหน้าต่างตามให้เคอร์เซอร์ยังอยู่บน title bar
            let cursor = cursorNow()
            let grip = CGRect(x: actual.minX + 4, y: actual.minY, width: max(actual.width - 8, 1), height: 28)
            if !grip.contains(cursor) {
                target = CGRect(origin: place(cursor, actual.size), size: actual.size)
                AX.setPosition(window, target.origin)
                actual = AX.frame(of: window) ?? target
            }
            let finalFrame = actual
            DispatchQueue.main.async {
                self.startFrame = finalFrame
                self.mouseDownAt = cursor
            }
        }
    }

    /// หาเลขหน้าต่างของระบบจาก AX element — จับคู่ด้วย pid + ขนาด/ตำแหน่งใกล้เคียง
    private static func windowID(of window: AXUIElement, near frame: CGRect) -> CGWindowID? {
        let pid = AX.pid(of: window)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for entry in list where (entry[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (entry[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let number = entry[kCGWindowNumber as String] as? UInt32 else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            // ระหว่างลาก ตำแหน่งจาก AX กับจากระบบคลาดกันได้เป็นร้อย px — จับคู่ด้วยขนาดพอ
            // (รายการเรียงหน้า→หลัง หน้าต่างที่กำลังลากอยู่หน้าสุดของแอปนั้นอยู่แล้ว)
            if abs(rect.width - frame.width) < 6, abs(rect.height - frame.height) < 6 {
                return CGWindowID(number)
            }
        }
        return nil
    }

    /// ใหญ่เกือบเต็มพื้นที่ใช้งานของจอ (ทั้งกว้างและสูง) — ถือว่า "ขยายเต็มจอ" ไม่ว่าใครเป็นคนขยาย
    fileprivate static func isNearlyFull(_ frame: CGRect, on screen: NSScreen) -> Bool {
        let visible = screen.visibleFrame
        return frame.width >= visible.width * 0.9 && frame.height >= visible.height * 0.9
    }

    fileprivate static func roughlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 12 && abs(a.minY - b.minY) < 12
            && abs(a.width - b.width) < 12 && abs(a.height - b.height) < 12
    }

    // MARK: Snap Assist — เลือกหน้าต่างอื่นมาเติมช่องที่เหลือ

    private func offerAssist(after target: SnapTarget, window: AXUIElement, screen: NSScreen) {
        guard Config.snapAssist else { return }
        let key = AXKey(element: window)

        switch target {
        case .layoutZone(let layoutIndex, let zoneIndex):
            let layouts = SnapLayout.available(for: screen)
            guard layoutIndex < layouts.count else { dismissAssist(); return }
            var session = assistSession
            if session == nil || session?.layout != layoutIndex || session?.screen !== screen {
                session = AssistSession(screen: screen, layout: layoutIndex)
            }
            session?.filled.insert(zoneIndex)
            session?.used.insert(key)
            guard let next = layouts[layoutIndex].zones.indices.first(where: {
                !(session?.filled.contains($0) ?? false)
            }) else {
                assistSession = nil
                dismissAssist()
                return
            }
            assistSession = session
            showAssist(target: .layoutZone(layout: layoutIndex, zone: next),
                       region: layouts[layoutIndex].rect(zone: next, on: screen), screen: screen)

        case .zone(let zone):
            guard let complement = zone.complement else { dismissAssist(); return }
            var session = AssistSession(screen: screen, layout: nil)
            session.used.insert(key)
            assistSession = session
            showAssist(target: .zone(complement), region: complement.rect(on: screen), screen: screen)

        case .verticalMaximize:
            dismissAssist()
        }
    }

    private func showAssist(target: SnapTarget, region: NSRect, screen: NSScreen) {
        assistTarget = target
        let used = assistSession?.used ?? []
        let regionCG = Geometry.toCG(region)
        axQueue.async {
            let candidates = WindowIndex.ordered(includeMinimized: false).filter { info in
                !used.contains(info.key) && !Self.roughlyEqual(info.frame, regionCG)
            }
            let shown = Array(candidates.prefix(12))
            DispatchQueue.main.async {
                guard !shown.isEmpty else {
                    self.assistSession = nil
                    self.dismissAssist()
                    return
                }
                self.assistPanel.grid.onPick = { [weak self] index in
                    guard let self, index < shown.count else { return }
                    self.pickAssist(shown[index], screen: screen)
                }
                self.assistPanel.present(items: shown, in: region)
                self.startAssistWatch()
                Thumbnails.shared.startLive(for: shown) { [weak self] in
                    self?.assistPanel.grid.needsDisplay = true
                }
            }
        }
    }

    private func pickAssist(_ info: WindowInfo, screen: NSScreen) {
        guard let target = assistTarget else { return }
        let isLayout: Bool
        if case .layoutZone = target { isLayout = true } else { isLayout = false }
        dismissAssist()
        assistSession?.used.insert(info.key)
        commit(target: target, window: info.element, currentFrame: info.frame,
               screen: screen, chain: isLayout)
        axQueue.async { AX.raise(info.element) }
        if !isLayout { assistSession = nil }
    }

    private func startAssistWatch() {
        stopAssistWatch()
        let escape = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if Int(event.keyCode) == kVK_Escape {
                self?.assistSession = nil
                self?.dismissAssist()
            }
        }
        // คลิกที่อื่นนอกพาเนล = ยกเลิก (คลิกในพาเนลจะไม่เข้ามอนิเตอร์ตัวนี้)
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.assistSession = nil
            self?.dismissAssist()
        }
        assistMonitors = [escape, outside].compactMap { $0 }
        assistTimeout = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
            self?.assistSession = nil
            self?.dismissAssist()
        }
        RunLoop.main.add(assistTimeout!, forMode: .common)
    }

    private func stopAssistWatch() {
        for monitor in assistMonitors { NSEvent.removeMonitor(monitor) }
        assistMonitors = []
        assistTimeout?.invalidate()
        assistTimeout = nil
    }

    private func dismissAssist() {
        stopAssistWatch()
        assistTarget = nil
        guard assistPanel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            assistPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.assistPanel.orderOut(nil) })
        Thumbnails.shared.stopLive()
    }

    // MARK: เส้นแบ่งระหว่างหน้าต่างที่ snap คู่กัน

    /// หน้าต่างจริงทุกบานที่มองเห็นบนจอ (จากรายการของระบบ ไม่ต้องใช้ AX — ถูกและเร็ว)
    private struct ScreenWindow {
        let number: CGWindowID
        let pid: pid_t
        let rect: NSRect          // พิกัด AppKit
        let order: Int            // ลำดับซ้อน 0 = หน้าสุด (ตามที่ระบบส่งมา)
    }

    private static func onScreenWindows() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var regular = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            regular.insert(app.processIdentifier)
        }
        var result: [ScreenWindow] = []
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(), regular.contains(pid),
                  let number = entry[kCGWindowNumber as String] as? UInt32,
                  let b = entry[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let cg = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard cg.width >= 200, cg.height >= 150 else { continue }   // ตัด tooltip/แถบเล็ก ๆ
            result.append(ScreenWindow(number: CGWindowID(number), pid: pid, rect: Geometry.toAppKit(cg),
                                       order: result.count))
        }
        return result
    }

    /// หา AXUIElement ของหน้าต่างเหล่านี้ (เรียกบน axQueue) จับคู่ด้วย pid + เฟรม
    private static func resolveElements(for windows: [ScreenWindow]) -> [CGWindowID: AXUIElement] {
        var result: [CGWindowID: AXUIElement] = [:]
        let byPid = Dictionary(grouping: windows, by: \.pid)
        for (pid, wanted) in byPid {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            guard let axWindows = AX.attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for axWindow in axWindows {
                guard let cg = AX.frame(of: axWindow) else { continue }
                let rect = Geometry.toAppKit(cg)
                for window in wanted where result[window.number] == nil
                    && abs(window.rect.minX - rect.minX) < 6 && abs(window.rect.minY - rect.minY) < 6
                    && abs(window.rect.width - rect.width) < 6 {
                    AXUIElementSetMessagingTimeout(axWindow, 0.15)   // ระหว่างลาก ห้ามให้แอปช้าค้างคิวนาน
                    result[window.number] = axWindow
                }
            }
        }
        return result
    }

    /// สร้างเส้นแบ่งจากหน้าต่างจริงทุกบานที่ขอบชิดกัน — ไม่ว่าจะจัดด้วย Deft, ลากเอง หรือ tiling ของ macOS
    /// (tiling ของ macOS เว้นช่องว่างระหว่างหน้าต่าง จึงยอมช่องว่างได้ถึง 14px และรักษาช่องว่างไว้ตอนลาก)
    func rebuildDividers() {
        guard Config.dividers, isEnabled else {
            hideAllDividers()
            return
        }
        // กำลังลากเส้นอยู่ = ห้ามจัดใหม่ ไม่งั้นเส้นที่จับอยู่จะถูกสลับไปคุมรอยต่ออื่นกลางคัน
        guard !dividerPool.contains(where: { $0.isDragging }) else { return }
        let windows = Self.onScreenWindows()
        let seams = Self.findSeams(windows)
        guard !seams.isEmpty else {
            hideAllDividers()
            return
        }
        let involved = Set(seams.flatMap { $0.before + $0.after })
        let subjects = windows.filter { involved.contains($0.number) }
        axQueue.async {
            let elements = Self.resolveElements(for: subjects)
            let byNumber = Dictionary(uniqueKeysWithValues: subjects.map { ($0.number, $0) })
            var specs: [DividerSpec] = []
            for seam in seams {
                let before = seam.before.compactMap { n in elements[n].map { (element: $0, rect: byNumber[n]!.rect) } }
                let after = seam.after.compactMap { n in elements[n].map { (element: $0, rect: byNumber[n]!.rect) } }
                guard !before.isEmpty, !after.isEmpty else { continue }
                specs.append(DividerSpec(isHorizontal: seam.isHorizontal, position: seam.position, gap: seam.gap,
                                         span: seam.span, limits: seam.limits, before: before, after: after))
            }
            specs.sort { ($0.isHorizontal ? 1 : 0, $0.position) < ($1.isHorizontal ? 1 : 0, $1.position) }
            DispatchQueue.main.async { self.layoutDividers(specs) }
        }
    }

    private struct Seam {
        let isHorizontal: Bool
        let position: CGFloat          // กึ่งกลางช่องว่าง
        let gap: CGFloat               // ระยะระหว่างขอบสองฝั่ง (0 = ชิดสนิท)
        let span: ClosedRange<CGFloat>
        let limits: ClosedRange<CGFloat>
        let before: [CGWindowID]
        let after: [CGWindowID]
    }

    private struct DividerSpec {
        let isHorizontal: Bool
        let position: CGFloat
        let gap: CGFloat
        let span: ClosedRange<CGFloat>
        let limits: ClosedRange<CGFloat>
        let before: [(element: AXUIElement, rect: NSRect)]
        let after: [(element: AXUIElement, rect: NSRect)]
    }

    private static func findSeams(_ windows: [ScreenWindow]) -> [Seam] {
        guard windows.count >= 2 else { return [] }
        let maxGap: CGFloat = 14
        let minWidth: CGFloat = 220
        let minHeight: CGFloat = 140
        var seams: [Seam] = []

        /// ต้องอยู่จอเดียวกัน — หน้าต่างสองจอที่ขอบจอชนกันจะดูเหมือน "ชิดกัน" ทั้งที่คนละจอ
        func sameScreen(_ a: ScreenWindow, _ b: ScreenWindow) -> Bool {
            let screenA = Geometry.screen(containing: NSPoint(x: a.rect.midX, y: a.rect.midY))
            let screenB = Geometry.screen(containing: NSPoint(x: b.rect.midX, y: b.rect.midY))
            return screenA != nil && screenA === screenB
        }

        /// ช่วงของรอยต่อที่ไม่ถูกหน้าต่างบานอื่นซึ่งอยู่ "หน้า" ทั้งสองฝั่งบัง — ถ้าโดนบังบางส่วนเอาช่วงยาวสุดที่เหลือ
        /// (ไม่งั้นเส้นแบ่งจะลอยทับหน้าต่างที่เปิดอยู่ข้างหน้า)
        func visibleSpan(_ span: ClosedRange<CGFloat>, isHorizontal: Bool, position: CGFloat,
                         members: [ScreenWindow]) -> ClosedRange<CGFloat>? {
            let frontmost = members.map(\.order).min() ?? 0
            let ids = Set(members.map(\.number))
            let line = isHorizontal
                ? NSRect(x: span.lowerBound, y: position - 6, width: span.upperBound - span.lowerBound, height: 12)
                : NSRect(x: position - 6, y: span.lowerBound, width: 12, height: span.upperBound - span.lowerBound)
            var segments: [ClosedRange<CGFloat>] = [span]
            for other in windows where other.order < frontmost && !ids.contains(other.number) {
                let hit = other.rect.intersection(line)
                guard !hit.isNull, hit.width > 0, hit.height > 0 else { continue }
                let cut = isHorizontal ? hit.minX...hit.maxX : hit.minY...hit.maxY
                segments = segments.flatMap { seg -> [ClosedRange<CGFloat>] in
                    guard seg.overlaps(cut) else { return [seg] }
                    var out: [ClosedRange<CGFloat>] = []
                    if cut.lowerBound > seg.lowerBound { out.append(seg.lowerBound...cut.lowerBound) }
                    if cut.upperBound < seg.upperBound { out.append(cut.upperBound...seg.upperBound) }
                    return out
                }
            }
            guard let best = segments.max(by: { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }),
                  best.upperBound - best.lowerBound > 60 else { return nil }
            return best
        }

        // แนวตั้ง: ขอบขวาของ a ใกล้ขอบซ้ายของ b และช่วงแนวตั้งซ้อนกัน
        var verticalPairs: [(a: ScreenWindow, b: ScreenWindow)] = []
        for a in windows {
            for b in windows where a.number != b.number && sameScreen(a, b) {
                let gap = b.rect.minX - a.rect.maxX
                guard gap >= -2, gap <= maxGap else { continue }
                let overlap = min(a.rect.maxY, b.rect.maxY) - max(a.rect.minY, b.rect.minY)
                guard overlap > 60 else { continue }
                verticalPairs.append((a, b))
            }
        }
        // รวมคู่ที่รอยต่ออยู่ตำแหน่งเดียวกันเป็นเส้นเดียว (เช่น ซ้าย 1 บาน ขวา 2 บานซ้อน)
        var usedV = Set<Int>()
        for (i, pair) in verticalPairs.enumerated() where !usedV.contains(i) {
            let position = (pair.a.rect.maxX + pair.b.rect.minX) / 2
            var before: [ScreenWindow] = [], after: [ScreenWindow] = []
            for (j, other) in verticalPairs.enumerated() where !usedV.contains(j) {
                let otherPosition = (other.a.rect.maxX + other.b.rect.minX) / 2
                guard abs(otherPosition - position) <= maxGap else { continue }
                usedV.insert(j)
                if !before.contains(where: { $0.number == other.a.number }) { before.append(other.a) }
                if !after.contains(where: { $0.number == other.b.number }) { after.append(other.b) }
            }
            let gap = max(0, after.map(\.rect.minX).min()! - before.map(\.rect.maxX).max()!)
            let low = max(before.map(\.rect.minY).min()!, after.map(\.rect.minY).min()!)
            let high = min(before.map(\.rect.maxY).max()!, after.map(\.rect.maxY).max()!)
            let lower = before.map(\.rect.minX).max()! + minWidth
            let upper = after.map(\.rect.maxX).min()! - minWidth
            guard high - low > 60, lower < upper,
                  let span = visibleSpan(low...high, isHorizontal: false, position: position,
                                         members: before + after) else { continue }
            seams.append(Seam(isHorizontal: false, position: position, gap: gap, span: span,
                              limits: lower...upper, before: before.map(\.number), after: after.map(\.number)))
        }

        // แนวนอน: ขอบล่างของบานบน (before) ใกล้ขอบบนของบานล่าง (after)
        var horizontalPairs: [(a: ScreenWindow, b: ScreenWindow)] = []
        for a in windows {
            for b in windows where a.number != b.number && sameScreen(a, b) {
                let gap = a.rect.minY - b.rect.maxY
                guard gap >= -2, gap <= maxGap else { continue }
                let overlap = min(a.rect.maxX, b.rect.maxX) - max(a.rect.minX, b.rect.minX)
                guard overlap > 60 else { continue }
                horizontalPairs.append((a, b))
            }
        }
        var usedH = Set<Int>()
        for (i, pair) in horizontalPairs.enumerated() where !usedH.contains(i) {
            let position = (pair.a.rect.minY + pair.b.rect.maxY) / 2
            var before: [ScreenWindow] = [], after: [ScreenWindow] = []
            for (j, other) in horizontalPairs.enumerated() where !usedH.contains(j) {
                let otherPosition = (other.a.rect.minY + other.b.rect.maxY) / 2
                guard abs(otherPosition - position) <= maxGap else { continue }
                usedH.insert(j)
                if !before.contains(where: { $0.number == other.a.number }) { before.append(other.a) }
                if !after.contains(where: { $0.number == other.b.number }) { after.append(other.b) }
            }
            let gap = max(0, before.map(\.rect.minY).min()! - after.map(\.rect.maxY).max()!)
            let low = max(before.map(\.rect.minX).min()!, after.map(\.rect.minX).min()!)
            let high = min(before.map(\.rect.maxX).max()!, after.map(\.rect.maxX).max()!)
            let lower = after.map(\.rect.minY).max()! + minHeight
            let upper = before.map(\.rect.maxY).min()! - minHeight
            guard high - low > 60, lower < upper,
                  let span = visibleSpan(low...high, isHorizontal: true, position: position,
                                         members: before + after) else { continue }
            seams.append(Seam(isHorizontal: true, position: position, gap: gap, span: span,
                              limits: lower...upper, before: before.map(\.number), after: after.map(\.number)))
        }
        return seams
    }

    private func layoutDividers(_ specs: [DividerSpec]) {
        guard !specs.isEmpty else {
            hideAllDividers()
            return
        }

        while dividerPool.count < specs.count {
            let divider = DividerWindow()
            divider.onApply = { [weak self] updates, done in self?.applyDividerDrag(updates, done: done) }
            divider.onFinished = { [weak self] in self?.rebuildDividers() }
            dividerPool.append(divider)
        }
        for (index, divider) in dividerPool.enumerated() {
            guard index < specs.count else {
                divider.orderOut(nil)
                continue
            }
            let spec = specs[index]
            divider.before = spec.before
            divider.after = spec.after
            divider.gap = spec.gap
            divider.configure(isHorizontal: spec.isHorizontal, position: spec.position,
                              span: spec.span, limits: spec.limits)
        }
    }

    private func applyDividerDrag(_ updates: [(AXUIElement, CGRect, CGRect)], done: @escaping () -> Void) {
        for (element, _, rect) in updates {
            let key = AXKey(element: element)
            if var state = snapStates[key] {
                state.snappedFrame = rect
                snapStates[key] = state
            }
        }
        axQueue.async {
            for (element, previous, rect) in updates { AX.setFrameDelta(element, from: previous, to: rect) }
            DispatchQueue.main.async(execute: done)
        }
    }

    private func hideAllDividers() {
        for divider in dividerPool { divider.orderOut(nil) }
    }

    // MARK: Alt+Tab

    func cycleSwitcher(forward: Bool, modifier: NSEvent.ModifierFlags = .option) {
        guard Config.altTab, isEnabled else { return }
        if switcher.isVisible {
            guard !switcherItems.isEmpty else { return }
            move(by: forward ? 1 : -1)
            return
        }
        switcherModifier = modifier
        axQueue.async {
            let items = WindowIndex.ordered()
            DispatchQueue.main.async {
                guard items.count > 1 else { return }
                self.switcherItems = items
                self.switcherIndex = forward ? 1 : items.count - 1
                let screen = Geometry.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main!
                self.switcher.grid.onPick = { [weak self] index in
                    self?.switcherIndex = index
                    self?.commitSwitcher()
                }
                self.switcher.present(items: items, selected: self.switcherIndex, on: screen)
                self.startSwitcherWatch()
                Thumbnails.shared.startLive(for: items) { [weak self] in
                    self?.switcher.grid.needsDisplay = true
                }
            }
        }
    }

    private func move(by delta: Int) {
        guard !switcherItems.isEmpty else { return }
        switcherIndex = (switcherIndex + delta % switcherItems.count + switcherItems.count) % switcherItems.count
        switcher.grid.selected = switcherIndex
    }

    private func startSwitcherWatch() {
        stopSwitcherWatch()
        // ปล่อยปุ่ม Option เมื่อไหร่ = สลับไปหน้าต่างที่เลือก (เหมือน Alt+Tab)
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self, self.switcher.isVisible else { return }
            if !NSEvent.modifierFlags.contains(self.switcherModifier) { self.commitSwitcher() }
        }
        RunLoop.main.add(timer, forMode: .common)
        switcherTimer = timer

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.switcher.isVisible else { return }
            let columns = max(1, self.switcher.grid.columns)
            switch Int(event.keyCode) {
            case kVK_Escape:     self.closeSwitcher()
            case kVK_LeftArrow:  self.move(by: -1)
            case kVK_RightArrow: self.move(by: 1)
            case kVK_UpArrow:    self.move(by: -columns)
            case kVK_DownArrow:  self.move(by: columns)
            default: break
            }
        }
        var monitors: [Any] = []
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
        switcherMonitors = monitors
    }

    private func stopSwitcherWatch() {
        switcherTimer?.invalidate()
        switcherTimer = nil
        for monitor in switcherMonitors { NSEvent.removeMonitor(monitor) }
        switcherMonitors = []
    }

    private func commitSwitcher() {
        guard switcher.isVisible, switcherIndex < switcherItems.count else {
            closeSwitcher()
            return
        }
        let target = switcherItems[switcherIndex]
        closeSwitcher()
        axQueue.async { AX.raise(target.element) }
    }

    private func closeSwitcher() {
        Thumbnails.shared.stopLive()
        stopSwitcherWatch()
        switcher.orderOut(nil)
        switcherItems = []
    }

    // MARK: ปุ่มลัด (Carbon global hot keys — ไม่ต้องขอสิทธิ์เพิ่ม)

    private enum HotKey: UInt32 {
        case left = 1, right, up, down, switchForward, switchBackward
    }

    func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async { SnapManager.shared.perform(hotKeyID: hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)

        // ไม่จองปุ่มลัดระดับระบบแล้ว — Option+Tab / Option+Shift+Tab ปล่อยว่างเหมือน macOS เดิม
        // ตัวสลับหน้าต่างของ Deft ใช้ Cmd+Tab (โหมด Mac ตอนเปิด Live Preview) ผ่าน InputTap แทน
        // ส่วน Win+ลูกศร กับการลาก ใช้เส้นทางของ event tap อยู่แล้ว
        diag.hotKeysRegistered = true
    }

    /// ปุ่ม Win+ลูกศร = จัดหน้าต่าง ใช้เส้นทางเดียวกับการ snap ด้วยเมาส์
    func performArrow(_ direction: Int) {
        let map: [HotKey] = [.left, .right, .up, .down]
        guard direction >= 0, direction < map.count else { return }
        perform(hotKeyID: map[direction].rawValue)
    }

    private func perform(hotKeyID: UInt32) {
        guard isEnabled, let action = HotKey(rawValue: hotKeyID) else { return }
        switch action {
        case .switchForward:  cycleSwitcher(forward: true);  return
        case .switchBackward: cycleSwitcher(forward: false); return
        default: break
        }
        axQueue.async {
            guard let window = AX.focusedWindow(), let frame = AX.frame(of: window) else { return }
            DispatchQueue.main.async {
                guard let screen = Geometry.screen(containing: frame) else { return }
                self.route(action, window: window, currentFrame: frame, screen: screen)
            }
        }
    }

    private func route(_ action: HotKey, window: AXUIElement, currentFrame: CGRect, screen: NSScreen) {
        let key = AXKey(element: window)
        var previous: SnapZone?
        if case .zone(let zone)? = snapStates[key]?.target { previous = zone }

        let portrait = Config.portraitTopBottom && screen.frame.height > screen.frame.width

        var zone: SnapZone?
        switch action {
        case .left:
            switch previous {
            case .topRight:    zone = .topLeft
            case .bottomRight: zone = .bottomLeft
            default:           zone = .left
            }
        case .right:
            switch previous {
            case .topLeft:     zone = .topRight
            case .bottomLeft:  zone = .bottomRight
            default:           zone = .right
            }
        case .up:
            switch previous {
            case .left:        zone = .topLeft
            case .right:       zone = .topRight
            case .bottomLeft:  zone = .left
            case .bottomRight: zone = .right
            case .topHalf:     zone = .top                       // กดซ้ำ = เต็มจอ
            default:           zone = portrait ? .topHalf : .top
            }
        case .down:
            switch previous {
            case .left:        zone = .bottomLeft
            case .right:       zone = .bottomRight
            case .topLeft:     zone = .left
            case .topRight:    zone = .right
            case .bottom:      zone = nil                        // กดซ้ำ = คืนขนาดเดิม
            case .top, .topHalf: zone = portrait ? .bottom : nil
            default:           zone = portrait ? .bottom : nil
            }
        default:
            return
        }

        guard let zone else {
            restore(window, key: key, screen: screen)
            return
        }
        commit(target: .zone(zone), window: window, currentFrame: currentFrame, screen: screen, chain: true)
    }

    private func restore(_ window: AXUIElement, key: AXKey, screen: NSScreen) {
        dismissAssist()
        if let state = snapStates.removeValue(forKey: key), state.originalFrame.width > 40 {
            let original = state.originalFrame
            axQueue.async {
                AX.setFrame(window, original)
                DispatchQueue.main.async { self.rebuildDividers() }
            }
        } else {
            axQueue.async {
                guard let frame = AX.frame(of: window) else { return }
                DispatchQueue.main.async {
                    self.commit(target: .zone(.center), window: window,
                                currentFrame: frame, screen: screen, chain: false)
                }
            }
        }
    }

    func refreshDividerVisibility() {
        if Config.dividers { rebuildDividers() } else { hideAllDividers() }
    }
}


// MARK: - แอปที่อยู่หน้าสุด (แคชไว้ จะได้ไม่ต้องถามทุกครั้งที่กดปุ่ม) ---------

enum FrontApp {
    private(set) static var bundleID: String = ""

    /// แอปเทอร์มินัล — ห้ามแปลง Ctrl เป็น Cmd เพราะ Ctrl+C ต้องเป็นการหยุดโปรแกรม
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty",
        "com.mitchellh.ghostty", "co.zeit.hyper", "com.github.wez.wezterm",
    ]

    static var isTerminal: Bool { terminals.contains(bundleID) }
    static var isFinder: Bool { bundleID == "com.apple.finder" }

    static func start() {
        bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            bundleID = app?.bundleIdentifier ?? ""
        }
    }
}

// MARK: - สลับภาษาแบบปุ่ม ` ของ Windows ภาษาไทย -------------------------------

enum LanguageSwitcher {
    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
        (property(source, key) as? Bool) ?? false
    }

    /// ภาษาที่เปิดใช้อยู่ใน System Settings เรียงตามลำดับของระบบ
    static func enabledSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else { return [] }
        return list.filter { source in
            guard let category = property(source, kTISPropertyInputSourceCategory) as? String,
                  category == (kTISCategoryKeyboardInputSource as String) else { return false }
            return flag(source, kTISPropertyInputSourceIsSelectCapable)
                && flag(source, kTISPropertyInputSourceIsEnabled)
        }
    }

    /// สลับไปภาษาถัดไป — ถ้ามีสองภาษาก็คือสลับไป-กลับเหมือน Windows
    static func toggle() {
        let sources = enabledSources()
        guard sources.count > 1 else { return }
        var currentID: String?
        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            currentID = property(current, kTISPropertyInputSourceID) as? String
        }
        let index = sources.firstIndex {
            (property($0, kTISPropertyInputSourceID) as? String) == currentID
        } ?? 0
        TISSelectInputSource(sources[(index + 1) % sources.count])
    }

    /// input source ที่ใช้อยู่ตอนนี้เป็นภาษาไทยไหม (ดูจากตัวอักษรที่ layout ให้จริง)
    static var currentIsThai: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return false }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var thai = false
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            guard UCKeyTranslate(layout, UInt16(kVK_ANSI_Q), UInt16(kUCKeyActionDown), 0,
                                 UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                                 &dead, 8, &length, &chars) == noErr, length > 0 else { return }
            thai = String(utf16CodeUnits: chars, count: length).unicodeScalars
                .contains { (0x0E00...0x0E7F).contains($0.value) }
        }
        return thai
    }

}

// MARK: - คุยกับ Finder --------------------------------------------------------

enum FinderBridge {
    /// ตัดไฟล์ค้างอยู่หรือเปล่า (Ctrl+X แล้วรอ Ctrl+V)
    static var cutPending = false

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.apple.finder" else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.12)
        guard let window = AX.attribute(appElement, kAXFocusedWindowAttribute) else { return nil }
        return (window as! AXUIElement)
    }

    /// กำลังพิมพ์เปลี่ยนชื่อไฟล์อยู่ไหม — ถ้าใช่ ห้ามไปแปลง Backspace/Enter
    static func isEditingText() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.apple.finder" else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.06)
        guard let focused = AX.attribute(appElement, kAXFocusedUIElementAttribute) else { return false }
        let role = AX.string(focused as! AXUIElement, kAXRoleAttribute) ?? ""
        return role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String)
    }
}

/// บันทึกเหตุการณ์เรื่องจอลงไฟล์ ~/Library/Logs/Deft.log — มีแค่ตอนเสียบ/ถอดจอและตอนปิดจอซ้ำ ไว้ไล่ปัญหาภายหลัง
func knackLog(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Deft.log")
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile(); handle.write(line.data(using: .utf8)!); try? handle.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - จอภาพ: ความละเอียด อัตรารีเฟรช ตำแหน่ง และการจำค่า --------------------

enum DisplayControl {
    struct Mode: Equatable {
        let width: Int
        let height: Int
        let refresh: Int
        let scaled: Bool
        let ref: CGDisplayMode

        static func == (a: Mode, b: Mode) -> Bool {
            a.width == b.width && a.height == b.height && a.refresh == b.refresh
        }
        var resolution: String { "\(width) × \(height)" }
    }

    struct Info {
        let id: CGDirectDisplayID
        let name: String
        /// ตัวตนของจอที่คงที่ข้ามการถอด-เสียบ — serial ของจอส่วนใหญ่เป็น 0 เลยใช้ไม่ได้
        let key: String
        let bounds: CGRect
        let isMain: Bool
        let isBuiltin: Bool
        let isMirrored: Bool
        let mode: Mode?
    }

    // MARK: อ่านสถานะ

    static func list() -> [Info] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber else { continue }
            names[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }

        var seen: [String: Int] = [:]
        return ids.prefix(Int(count)).map { id in
            let name = names[id] ?? DisplayRotation.name(of: id)
                ?? "Unknown display"
            var key = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(name)"
            // จอรุ่นเดียวกันสองตัวจะได้ key ชนกัน เติมลำดับกันไว้
            let index = (seen[key] ?? 0) + 1
            seen[key] = index
            if index > 1 { key += "#\(index)" }
            return Info(id: id, name: name, key: key, bounds: CGDisplayBounds(id),
                        isMain: CGDisplayIsMain(id) != 0, isBuiltin: CGDisplayIsBuiltin(id) != 0,
                        isMirrored: CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay,
                        mode: CGDisplayCopyDisplayMode(id).map(mode(from:)))
        }
    }

    private static func mode(from raw: CGDisplayMode) -> Mode {
        Mode(width: raw.width, height: raw.height,
             refresh: Int(raw.refreshRate.rounded()),
             scaled: raw.pixelWidth > raw.width, ref: raw)
    }

    /// โหมดทั้งหมดที่จอนี้รับได้ ตัดตัวซ้ำออกแล้ว
    static func modes(of id: CGDirectDisplayID) -> [Mode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let raw = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return [] }
        var out: [Mode] = []
        for candidate in raw.map(mode(from:)) where candidate.refresh > 0 {
            if !out.contains(candidate) { out.append(candidate) }
        }
        return out.sorted {
            ($0.width, $0.height, $0.refresh) > ($1.width, $1.height, $1.refresh)
        }
    }

    /// ความละเอียดที่เลือกได้ (ไม่ซ้ำ) เรียงจากใหญ่ไปเล็ก
    static func resolutions(of id: CGDirectDisplayID) -> [(width: Int, height: Int)] {
        var out: [(Int, Int)] = []
        for mode in modes(of: id) where !out.contains(where: { $0 == (mode.width, mode.height) }) {
            out.append((mode.width, mode.height))
        }
        return out.map { (width: $0.0, height: $0.1) }
    }

    static func refreshRates(of id: CGDirectDisplayID, width: Int, height: Int) -> [Int] {
        Array(Set(modes(of: id).filter { $0.width == width && $0.height == height }
                               .map(\.refresh))).sorted(by: >)
    }

    // MARK: สั่งเปลี่ยน

    @discardableResult
    private static func configure(_ body: (CGDisplayConfigRef) -> Void) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        body(config)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    @discardableResult
    static func apply(width: Int, height: Int, refresh: Int, to id: CGDirectDisplayID) -> Bool {
        let wanted = modes(of: id).first {
            $0.width == width && $0.height == height && $0.refresh == refresh
        } ?? modes(of: id).first { $0.width == width && $0.height == height }
        guard let wanted else { return false }
        return configure { CGConfigureDisplayWithDisplayMode($0, id, wanted.ref, nil) }
    }

    @discardableResult
    static func place(_ id: CGDirectDisplayID, at origin: CGPoint) -> Bool {
        configure { CGConfigureDisplayOrigin($0, id, Int32(origin.x), Int32(origin.y)) }
    }

    /// วางหลายจอพร้อมกันในทรานแซกชันเดียว — ใช้กับหน้าต่างจัดเรียงจอ
    @discardableResult
    static func placeMany(_ origins: [CGDirectDisplayID: CGPoint]) -> Bool {
        configure { cfg in
            for (id, o) in origins { CGConfigureDisplayOrigin(cfg, id, Int32(o.x), Int32(o.y)) }
        }
    }

    /// วางจอนี้ไว้ด้านไหนของจอหลัก
    enum Side: String, CaseIterable {
        case left, right, above, below
        var label: String {
            switch self {
            case .left:  return "Left of main"
            case .right: return "Right of main"
            case .above: return "Above main"
            case .below: return "Below main"
            }
        }
    }

    @discardableResult
    static func move(_ id: CGDirectDisplayID, to side: Side) -> Bool {
        guard let main = list().first(where: \.isMain), main.id != id else { return false }
        let size = CGDisplayBounds(id)
        let origin: CGPoint
        switch side {
        case .left:  origin = CGPoint(x: -size.width, y: 0)
        case .right: origin = CGPoint(x: main.bounds.width, y: 0)
        case .above: origin = CGPoint(x: 0, y: -size.height)
        case .below: origin = CGPoint(x: 0, y: main.bounds.height)
        }
        return place(id, at: origin)
    }

    /// ตั้งเป็นจอหลัก = ย้ายให้มุมบนซ้ายอยู่ที่ (0,0) แล้วจอเดิมจะถูกดันออกเอง
    @discardableResult
    static func makeMain(_ id: CGDirectDisplayID) -> Bool {
        place(id, at: .zero)
    }

    // MARK: ปิดจอจริง

    /// CGSConfigureDisplayEnabled — private API ตัวเดียวกับที่ BetterDisplay ใช้
    /// "disconnect" จอ  ·  จอที่ปิดจะหายจากรายการของระบบเลย Deft จึงต้องจำ id ไว้เอง
    private typealias EnableFn = @convention(c) (CGDisplayConfigRef?, UInt32, Bool) -> Int32
    private static let configureEnabled: EnableFn? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(sym, to: EnableFn.self)
    }()


    private struct OffRecord: Codable {
        let id: UInt32
        let name: String
        var builtin: Bool? = false
    }
    private static let offKey = "poweredOffDisplays"

    /// จอที่ Deft ปิดไว้ — ต้องจำเองเพราะระบบไม่รายงานจอที่ปิดแล้ว
    private(set) static var poweredOff: [(id: CGDirectDisplayID, name: String, builtin: Bool)] = []

    static func loadPoweredOff() {
        guard let data = UserDefaults.standard.data(forKey: offKey),
              let records = try? JSONDecoder().decode([OffRecord].self, from: data) else { return }
        poweredOff = records.map { (CGDirectDisplayID($0.id), $0.name, $0.builtin ?? false) }
    }

    /// จอที่จำไว้ว่า "ผู้ใช้อยากให้ปิด" ตรงกับจอที่ออนไลน์อยู่ไหม — id เปลี่ยนได้ข้ามการรีสตาร์ท
    /// จึงเทียบด้วยชนิด built-in และชื่อด้วย
    static func matches(_ entry: (id: CGDirectDisplayID, name: String, builtin: Bool), _ live: Info) -> Bool {
        live.id == entry.id || (entry.builtin && live.isBuiltin) || live.name == entry.name
    }

    /// รายการที่ปิดอยู่จริง ณ ตอนนี้ (ไม่รวมตัวที่ระบบเปิดคืนมาแล้ว) — ใช้วาดแถว "Off" ในเมนู
    static var poweredOffNow: [(id: CGDirectDisplayID, name: String, builtin: Bool)] {
        let online = list()
        return poweredOff.filter { entry in !online.contains { matches(entry, $0) } }
    }

    /// รีสตาร์ท/เสียบจอแล้ว macOS เปิดจอที่ผู้ใช้เคยสั่งปิดกลับมาเอง → ปิดให้อีกครั้งตามที่ตั้งไว้
    /// ปิดเฉพาะเมื่อยังมีจออื่นเปิดอยู่ (ห้ามดับจอสุดท้าย) — ถ้าจอนั้นเป็นจอเดียวก็ปล่อยไว้ รายการยังจำอยู่
    /// ความปลอดภัย: ต้องมีจอเปิดอย่างน้อยหนึ่งจอเสมอ ถ้าไม่มีเลย (เช่นถอดจอนอกออกหมด
    /// แล้วจอ built-in ที่สั่งปิดไว้กลายเป็นจอเดียว) ให้เปิดจอที่ปิดไว้กลับมา (เลือก built-in ก่อน)
    /// ไม่ลบออกจากความจำ — พอเสียบจอนอกกลับมา reapplyPoweredOff จะปิดให้อีกที
    @discardableResult
    static func ensureVisibleDisplay() -> Bool {
        guard !poweredOff.isEmpty, let fn = configureEnabled else { return false }
        // นับจอที่ "วาดภาพได้จริง" (active) ไม่ใช่แค่ online — จอที่ถูก disconnect ไม่นับเป็น active
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        _ = CGGetActiveDisplayList(16, &ids, &n)
        guard n == 0 else { return false }   // ยังมีจอเห็นภาพได้ ไม่ต้องทำอะไร
        // จอดำสนิท — เปิดจอที่ปิดไว้กลับมาทั้งหมด (ลองทุก id ที่จำไว้ เผื่อ built-in id เปลี่ยนหลังตื่น)
        var did = false
        for entry in poweredOff {
            let ok = configure { _ = fn($0, entry.id, true) }
            knackLog("safety: no active display, re-enabling \(entry.name)#\(entry.id) → \(ok)")
            did = did || ok
        }
        return did
    }

    static func reapplyPoweredOff() {
        guard !poweredOff.isEmpty else { return }
        ensureVisibleDisplay()   // กันจอดำสนิทก่อน แล้วค่อยจัดจอที่ควรปิด
        for entry in poweredOff {
            let usable = list().filter { !$0.isMirrored }
            knackLog("reapply: entry=\(entry.name) usable=\(usable.map { "\($0.name)#\($0.id)" })")
            guard usable.count > 1, let live = usable.first(where: { matches(entry, $0) }) else { continue }
            if live.id != entry.id {   // id ใหม่หลังรีสตาร์ท — อัปเดตก่อนสั่งปิด
                poweredOff.removeAll { $0.name == entry.name && $0.builtin == entry.builtin }
                poweredOff.append((live.id, entry.name, entry.builtin))
            }
            let ok = powerOff(live.id)
            knackLog("reapply: powerOff \(live.name)#\(live.id) → \(ok)")
        }
    }

    /// เปิดจอที่ปิดไว้กลับมาทั้งหมดก่อนเครื่องหลับ (คงความจำไว้) — กันกรณีถอดจอนอกตอนหลับ
    /// แล้วตื่นมาเหลือแต่จอที่ถูก disconnect ทำให้จอดำสนิท กู้ไม่ได้ (แอปถูกพักตอนไม่มีจอ)
    /// พอตื่นถ้ายังมีจอนอก reapplyPoweredOff จะปิด built-in ให้ใหม่เอง
    static func reenableBeforeSleep() {
        guard !poweredOff.isEmpty, let fn = configureEnabled else { return }
        for entry in poweredOff {
            let ok = configure { _ = fn($0, entry.id, true) }
            knackLog("willSleep: re-enable \(entry.name)#\(entry.id) → \(ok)")
        }
    }

    private static func persistPoweredOff() {
        let records = poweredOff.map { OffRecord(id: $0.id, name: $0.name, builtin: $0.builtin) }
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: offKey)
    }

    /// ปิดจอ — จอหลักก็ปิดได้ (ย้ายตำแหน่งจอหลักไปจออื่นให้ก่อน)
    /// ที่ห้ามอย่างเดียวคือดับจอสุดท้าย ไม่งั้นมองไม่เห็นอะไรแล้วกู้ไม่ได้
    @discardableResult
    static func powerOff(_ id: CGDirectDisplayID) -> Bool {
        guard let fn = configureEnabled else { return false }
        let usable = list().filter { !$0.isMirrored }
        guard usable.count > 1, let target = usable.first(where: { $0.id == id }) else { return false }
        if target.isMain, let next = usable.first(where: { $0.id != id }) {
            makeMain(next.id)
        }
        guard configure({ _ = fn($0, id, false) }) else { return false }
        poweredOff.removeAll { $0.id == id || ($0.name == target.name && $0.builtin == target.isBuiltin) }
        poweredOff.append((id, target.name, target.isBuiltin))
        persistPoweredOff()
        return true
    }

    @discardableResult
    static func powerOn(_ id: CGDirectDisplayID) -> Bool {
        guard let fn = configureEnabled else { return false }
        guard configure({ _ = fn($0, id, true) }) else { return false }
        poweredOff.removeAll { $0.id == id }
        persistPoweredOff()
        return true
    }
}

// MARK: - หมุนจอ (MonitorPanel.framework — ตัวเดียวกับที่ System Settings ใช้) --

/// CoreGraphics ไม่มีคำสั่งหมุนจอที่เปิดให้ใช้ และ Apple Silicon ไม่มี IOFramebuffer
/// ให้เรียกแบบเครื่อง Intel — ทางเดียวที่เหลือคือ MPDisplay ของ MonitorPanel
/// ซึ่งเป็น private framework: ถ้า macOS รุ่นหน้าเปลี่ยนโครงข้างใน ฟีเจอร์นี้จะ
/// กลายเป็น "หมุนไม่ได้" เฉย ๆ ไม่พังอย่างอื่น เพราะทุกจุดเช็คก่อนเรียกเสมอ
enum DisplayRotation {
    private static var manager: NSObject?

    private static func displays() -> [NSObject] {
        if manager == nil,
           dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel",
                  RTLD_NOW) != nil,
           let mgrClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type {
            manager = mgrClass.init()
        }
        return (manager?.value(forKey: "displays") as? [NSObject]) ?? []
    }

    private static func display(for id: CGDirectDisplayID) -> NSObject? {
        displays().first {
            ($0.value(forKey: "displayID") as? NSNumber)?.uint32Value == id
        }
    }

    static func canRotate(_ id: CGDirectDisplayID) -> Bool {
        guard let d = display(for: id),
              d.responds(to: NSSelectorFromString("setOrientation:")) else { return false }
        return (d.value(forKey: "canChangeOrientation") as? NSNumber)?.boolValue ?? false
    }

    static func angle(of id: CGDirectDisplayID) -> Int {
        (display(for: id)?.value(forKey: "orientation") as? NSNumber)?.intValue ?? 0
    }

    /// ชื่อจอจาก MonitorPanel — ใช้ตอนจอถูกปิด (mirror) แล้วหายจาก NSScreen
    static func name(of id: CGDirectDisplayID) -> String? {
        display(for: id)?.value(forKey: "displayName") as? String
    }

    @discardableResult
    static func rotate(_ id: CGDirectDisplayID, to degrees: Int) -> Bool {
        guard [0, 90, 180, 270].contains(degrees), canRotate(id),
              let d = display(for: id) else { return false }
        d.setValue(NSNumber(value: degrees), forKey: "orientation")
        return true
    }
}

// MARK: - คำสั่งระบบแบบ Windows -----------------------------------------------

enum SystemActions {
    static let syntheticTag: Int64 = 0x57_4D_41_43

    /// ยิงปุ่มลัดแทนผู้ใช้ — ติดแท็กไว้ให้ tap ของเราปล่อยผ่าน
    static func postKey(_ keyCode: Int, _ flags: CGEventFlags = []) {
        DispatchQueue.main.async {
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil,
                                          virtualKey: CGKeyCode(keyCode), keyDown: isDown) else { continue }
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Win+D
    static func showDesktop() { postKey(kVK_F11, .maskSecondaryFn) }

    /// Win+E
    static func openFileManager() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
    }

    /// Win+L
    static func lockScreen() { postKey(kVK_ANSI_Q, [.maskControl, .maskCommand]) }

    /// Win+R — Spotlight ใกล้เคียงที่สุด
    static func runDialog() { postKey(kVK_Space, .maskCommand) }

    /// Win+Shift+S
    static func screenSnip() { postKey(kVK_ANSI_4, [.maskCommand, .maskShift]) }

    /// Alt+F4
    static func closeWindow() { postKey(kVK_ANSI_W, .maskCommand) }
}

// MARK: - เปิดตอนล็อกอิน --------------------------------------------------------

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func set(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Deft: ตั้งค่าเปิดตอนล็อกอินไม่สำเร็จ — \(error)")
        }
    }
}

// MARK: - ตารางปุ่มของแต่ละภาษา -------------------------------------------------

/// อ่านตารางปุ่ม→ตัวอักษรจาก layout ที่ผู้ใช้ติดตั้งไว้จริง ไม่ hardcode
/// จะเปลี่ยนไปใช้เกษมณี ปัตตะโชติ หรือภาษาอื่นก็ยังใช้ได้
struct KeyLayout {
    let source: TISInputSource
    let id: String
    let name: String
    let isThai: Bool
    private let plain: [Int: String]
    private let shifted: [Int: String]

    func text(_ code: Int, shift: Bool) -> String? {
        (shift ? shifted[code] : plain[code]) ?? plain[code]
    }

    init?(_ source: TISInputSource) {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

        func translate(_ modifiers: UInt32) -> [Int: String] {
            var out: [Int: String] = [:]
            data.withUnsafeBytes { buffer in
                guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
                for code in 0..<128 {
                    var dead: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 8)
                    var length = 0
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers,
                                                UInt32(LMGetKbdType()),
                                                UInt32(kUCKeyTranslateNoDeadKeysMask),
                                                &dead, 8, &length, &chars)
                    guard status == noErr, length > 0 else { continue }
                    let text = String(utf16CodeUnits: chars, count: length)
                    guard let first = text.unicodeScalars.first, first.value > 31 else { continue }
                    out[code] = text
                }
            }
            return out
        }

        self.source = source
        self.plain = translate(0)
        self.shifted = translate(UInt32(shiftKey) >> 8)
        guard !plain.isEmpty else { return nil }

        func property(_ key: CFString) -> String? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? String
        }
        self.id = property(kTISPropertyInputSourceID) ?? "?"
        self.name = property(kTISPropertyLocalizedName) ?? id
        // ดูจากตัวอักษรที่ออกมาจริง ไม่ดูจากชื่อ layout
        self.isThai = plain.values.contains { text in
            text.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
        }
    }
}

enum KeyLayouts {
    private(set) static var thai: KeyLayout?
    private(set) static var latin: KeyLayout?

    static var ready: Bool { thai != nil && latin != nil }

    static func reload() {
        let layouts = LanguageSwitcher.enabledSources().compactMap(KeyLayout.init)
        thai = layouts.first { $0.isThai }
        latin = layouts.first { !$0.isThai }
    }

    /// เริ่มติดตามตอนผู้ใช้เพิ่ม/ลบภาษาใน System Settings
    static func start() {
        reload()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { _ in reload() }
    }
}

// MARK: - กฎการสะกดภาษาไทย -----------------------------------------------------

/// ใช้ตัดสินว่าข้อความ "เป็นภาษาไทยที่เป็นไปได้" ไหม — ไม่ได้เช็คว่าเป็นคำจริง
/// แค่เช็คว่าวางสระ/วรรณยุกต์ถูกที่ ซึ่งพอแยกได้แล้วว่าพิมพ์ผิดแป้นหรือเปล่า
/// (macOS ไม่มี spell checker ภาษาไทยให้ใช้ — เช็คแล้วรองรับ 44 ภาษา ไม่มีไทย)
enum ThaiScript {
    static func isThai(_ scalar: Unicode.Scalar) -> Bool { (0x0E00...0x0E7F).contains(scalar.value) }
    private static func isConsonant(_ v: UInt32) -> Bool { (0x0E01...0x0E2E).contains(v) }
    private static func isTone(_ v: UInt32) -> Bool { (0x0E48...0x0E4B).contains(v) }
    /// สระบน-ล่าง ไม้ไต่คู้ ทัณฑฆาต นิคหิต — ต้องเกาะพยัญชนะเสมอ
    private static func isMark(_ v: UInt32) -> Bool {
        v == 0x0E31 || (0x0E34...0x0E3A).contains(v) || v == 0x0E47 || (0x0E4C...0x0E4E).contains(v)
    }
    private static func isFollowVowel(_ v: UInt32) -> Bool {
        v == 0x0E30 || v == 0x0E32 || v == 0x0E33 || v == 0x0E45
    }

    static func hasThai(_ text: String) -> Bool { text.unicodeScalars.contains(where: isThai) }

    /// วางสระ/วรรณยุกต์ถูกตำแหน่งไหม
    static func wellFormed(_ text: String) -> Bool {
        var previous: UInt32 = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            guard isThai(scalar) else { previous = 0; continue }

            if isTone(v) || isMark(v) {
                // ต้องเกาะพยัญชนะ หรือเกาะสระบน-ล่างที่มีพยัญชนะรองอยู่แล้ว
                guard isConsonant(previous) || (isTone(v) && isMark(previous)) else { return false }
                if isTone(v) && isTone(previous) { return false }
                if isMark(v) && isMark(previous) { return false }
            } else if isFollowVowel(v) {
                guard isConsonant(previous) || isMark(previous) || isTone(previous) else { return false }
            }
            previous = v
        }
        return true
    }
}

// MARK: - แก้คำที่พิมพ์ผิดภาษา ---------------------------------------------------

final class LayoutFixer {
    static let shared = LayoutFixer()

    private struct Stroke {
        let code: Int
        let shift: Bool
        let text: String
    }

    /// สิ่งที่เพิ่งแก้ไป ไว้ให้ย้อนกลับได้
    private struct Fix {
        let strokes: [Stroke]      // ปุ่มที่พิมพ์จริง ไว้เอากลับมาใส่บัฟเฟอร์ตอนย้อน
        let original: String
        let replacement: String
        let trailing: Int          // ตัวคั่นท้ายคำที่พิมพ์ตามมา (ปกติคือเว้นวรรค)
        let previousSource: TISInputSource?
    }

    private var word: [Stroke] = []
    private var lastWord: [Stroke] = []
    private var lastFix: Fix?
    /// ตัวอักษร (รวมเว้นวรรค) ที่พิมพ์ต่อหลังการแก้ล่าสุด — ไว้ถอยกลับไปยกเลิก
    /// การแก้นั้นได้แม้พิมพ์เลยไปไกลแล้ว: ลบหาง+คำที่แก้ แล้วพิมพ์คำเดิม+หางคืน
    private var fixTail: [String] = []
    /// คำที่ผู้ใช้สั่งย้อนกลับแล้ว — อย่าไปแก้ซ้ำอีกในรอบนี้
    private var ignored: Set<String> = []
    /// ความยาวของคำที่เพิ่งย้อนไป — ต้องพิมพ์ต่ออีกอย่างน้อย 2 ตัวถึงจะยอมแก้ใหม่
    /// ไม่งั้นพอกด Esc แล้วพิมพ์ต่อตัวเดียวมันจะเด้งกลับไปแก้ทันที เหมือนแย่งกัน
    private var undoneLength = 0
    private var busy = false
    /// ช่องที่กำลังพิมพ์อยู่เป็นช่องกรอกรหัสหรือเปล่า — ถามครั้งเดียวตอนเริ่มคำใหม่
    private var inCredentialField = false
    /// เวลาที่ผู้ใช้สั่งสลับภาษาเอง — ระบบเปลี่ยน input source ช้ากว่านิ้ว
    /// ตัวที่พิมพ์ตามมาติด ๆ จึงยังออกเป็นภาษาเดิม ต้องไม่เอาไปตัดสินว่า "เป็นไทยอยู่แล้ว"
    private var switchedAt: CFAbsoluteTime = 0

    func languageSwitched() {
        reset()
        switchedAt = CFAbsoluteTimeGetCurrent()
    }

    /// แอปที่ไม่ควรยุ่ง — พิมพ์คำสั่ง ชื่อตัวแปร หรือรหัสผ่านกันเป็นปกติ
    private static let skipped: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.jetbrains.intellij", "com.sublimetext.4", "com.apple.Terminal",
        "com.googlecode.iterm2", "com.1password.1password", "com.apple.keychainaccess",
    ]

    private var allowedHere: Bool {
        guard !inCredentialField else { return false }
        guard !FrontApp.isTerminal else { return false }
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return true }
        return !Self.skipped.contains(id)
    }

    /// ปิดตัวแก้เฉพาะ "ช่อง" ที่เป็นช่องกรอกรหัส — ไม่ใช่ปิดตาม "คำ"
    /// วิธีนี้ไม่ทำให้เสียคำไทยสักคำ เพราะในช่องพวกนี้ไม่มีใครพิมพ์ไทยอยู่แล้ว
    /// อ่านไม่ได้ = ปล่อยผ่าน ไม่ใช่ปิด จะได้ไม่เผลอปิดทั้งระบบเพราะอ่าน AX พลาด
    private static func credentialField() -> Bool {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let raw = focused else { return false }
        let field = raw as! AXUIElement
        // ช่องรหัสผ่านของจริงบอกตัวเองตรง ๆ ไม่ต้องเดา
        if AX.string(field, kAXRoleAttribute) == "AXSecureTextField" { return true }
        if AX.string(field, kAXSubroleAttribute) == "AXSecureTextField" { return true }

        // ช่อง username / OTP / API key ไม่ได้ถูกกัน ต้องดูจากป้ายของช่อง
        // คำในลิสต์นี้ตั้งใจให้แคบ ถ้ากว้างไปช่องแชทธรรมดาจะโดนปิดไปด้วย
        let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute]
            .compactMap { AX.string(field, $0) }.joined(separator: " ").lowercased()
        guard !label.isEmpty else { return false }
        return ["password", "passwd", "passcode", "username", "user name", "userid", "user id",
                "sign in", "log in", "login", "one-time", "verification code", "api key",
                "secret key", "license key", "serial",
                "รหัสผ่าน", "ชื่อผู้ใช้", "เข้าสู่ระบบ", "รหัสยืนยัน"]
            .contains { label.contains($0) }
    }

    func reset() {
        inCredentialField = false
        word.removeAll()
        lastWord.removeAll()
        lastFix = nil
        fixTail.removeAll()
        undoneLength = 0
    }

    /// จำตัวที่พิมพ์หลังการแก้ — ยาวเกิน 300 ตัวก็เลิกจำ ถอยไกลขนาดนั้นไม่ปลอดภัยแล้ว
    private func rememberTail(_ text: String) {
        guard lastFix != nil else { return }
        fixTail.append(text)
        if fixTail.count > 300 {
            lastFix = nil
            fixTail.removeAll()
        }
    }

    // MARK: รับปุ่มเข้ามา

    /// เรียกจาก InputTap ทุกครั้งที่มี keyDown ที่ไม่ได้กดร่วมกับ Cmd/Ctrl/Option
    func observe(code: Int, shift: Bool, event: CGEvent) {
        guard Config.layoutFix, !busy else { return }

        switch code {
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            finish(separator: 0)
            reset()
            return
        case kVK_Delete, kVK_ForwardDelete:
            if !word.isEmpty { word.removeLast() }
            // ลบย้อนเข้าหางก็หดหางตาม — ทะลุหางเมื่อไหร่ถือว่าแตะคำที่แก้ เลิกจำ
            if !fixTail.isEmpty { fixTail.removeLast() }
            else { lastFix = nil }
            return
        default:
            break
        }

        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return }
        var text = String(utf16CodeUnits: chars, count: length)

        // อีเวนต์พกตัวอักษรที่คำนวณไว้ตอนสร้าง ซึ่งอาจเป็นภาษาก่อนสลับแป้น
        // (วัดแล้วเจอ 19 ครั้งจากการทดสอบจริง: แป้นเป็นไทยแล้วแต่ตัวที่ติดมายังเป็นละติน)
        // แหล่งความจริงคือ layout ที่ใช้อยู่ ณ ตอนนี้ — คำนวณเองแล้วใช้ค่านั้นแทน
        if let live = (LanguageSwitcher.currentIsThai ? KeyLayouts.thai : KeyLayouts.latin)?
            .text(code, shift: shift), !live.isEmpty {
            text = live
        }
        guard let scalar = text.unicodeScalars.first, scalar.value > 31 else { return }

        // จบคำที่ช่องว่างเท่านั้น — ปุ่ม ; [ ] ' / . , เป็นตัวอักษรไทยทั้งนั้น
        // ถ้าเอาไปนับเป็นตัวคั่นด้วย คำอย่าง "l;ylfu" จะถูกหั่นเป็นสองท่อน
        if CharacterSet.whitespaces.contains(scalar) {
            rememberTail(text)
            finish(separator: text.unicodeScalars.count)
            return
        }
        if word.isEmpty { inCredentialField = Self.credentialField() }

        // ก้อนเดียวต้องภาษาเดียว ปนเมื่อไหร่ตัดสินไม่ได้ — เริ่มก้อนใหม่
        // นับเฉพาะ "ตัวอักษร" จริง ๆ ในการเทียบสคริปต์ ส่วนเครื่องหมาย/ตัวเลข (เช่น " จาก Shift+W
        // บนแป้นไทย) ถือเป็นกลาง อยู่ก้อนไหนก็ได้ — ไม่งั้นคำอย่าง "Windows" (ขึ้นต้นตัวใหญ่)
        // จะโดนตัดตัวแรกทิ้งจนแปลงไม่ผ่าน
        func letterScript(_ s: String) -> Int {   // 1 = ไทย, 2 = ละติน, 0 = เป็นกลาง
            guard let sc = s.unicodeScalars.first else { return 0 }
            if ThaiScript.isThai(sc) { return 1 }
            if sc.value < 128, CharacterSet.letters.contains(sc) { return 2 }
            return 0
        }
        let wordScript = word.lazy.map { letterScript($0.text) }.first { $0 != 0 }
        let newScript = letterScript(text)
        if let ws = wordScript, newScript != 0, ws != newScript {
            word.removeAll()
            undoneLength = 0
            inCredentialField = Self.credentialField()
        }
        word.append(Stroke(code: code, shift: shift, text: text))
        rememberTail(text)
        liveCheck()
        // ยาวผิดปกติ = ยอมแพ้ทั้งก้อน ดีกว่าตัดหัวทิ้งแล้วลบผิดจำนวนตอนแก้
        if word.count > 240 { word.removeAll() }
    }

    /// เรียกก่อนปล่อย Enter ผ่าน — ภาษาไทยไม่เว้นวรรคระหว่างคำ ประโยคทั้งประโยค
    /// จึงมาถึงตรงนี้เป็นก้อนเดียวโดยไม่เคยผ่านเว้นวรรคเลย ถ้ารอแต่เว้นวรรคจะไม่มีวันแก้ทัน
    /// คืน true = กลืน Enter ไว้ก่อน เดี๋ยวแก้เสร็จแล้วยิงตามให้เอง
    func interceptReturn(code: Int) -> Bool {
        guard Config.layoutFix, Config.layoutFixAuto, !busy, allowedHere else { return false }
        guard !word.isEmpty, let fix = correction(for: word) else { return false }
        let strokes = word
        word.removeAll()
        lastWord = strokes
        apply(strokes: strokes, to: fix.text, toThai: fix.toThai, trailing: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { SystemActions.postKey(code) }
        return true
    }

    /// จบคำแล้ว — ลองตัดสินว่าพิมพ์ผิดแป้นหรือเปล่า
    private func finish(separator: Int) {
        guard !word.isEmpty else { return }
        lastWord = word
        word.removeAll()
        undoneLength = 0
        guard Config.layoutFixAuto, separator > 0, allowedHere else { return }
        let strokes = lastWord
        DispatchQueue.main.async { [weak self] in self?.autoFix(strokes, trailing: separator) }
    }

    // MARK: ตัดสินใจ

    private func render(_ strokes: [Stroke], with layout: KeyLayout) -> String {
        strokes.map { layout.text($0.code, shift: $0.shift) ?? $0.text }.joined()
    }

    private static func isEnglishWord(_ text: String) -> Bool {
        guard text.count > 1 else { return true }
        // มีเครื่องหมายวรรคตอนปนอยู่ = ไม่ใช่คำแน่ ๆ  ·  ถ้าไม่ดักตรงนี้ spell checker
        // จะข้ามเครื่องหมายแล้วตอบว่า "ถูก" ทำให้คำไทยจริงอย่าง ทะเล→mtg] โดนแก้ผิด
        guard text.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        let range = NSSpellChecker.shared.checkSpelling(of: text, startingAt: 0, language: "en",
                                                        wrap: false, inSpellDocumentWithTag: 0,
                                                        wordCount: nil)
        return range.location == NSNotFound
    }

    /// ยังมีคำอังกฤษที่ขึ้นต้นแบบนี้เหลืออยู่ไหม — ใช้ตัดสินตั้งแต่ยังพิมพ์ไม่จบคำ
    /// "sna" ยังมีทาง (snap, snack) แต่ "l;y" ไม่มีคำไหนเป็นไปได้แล้ว
    private static func hasEnglishCompletions(_ prefix: String) -> Bool {
        guard prefix.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        let range = NSRange(location: 0, length: prefix.utf16.count)
        let list = NSSpellChecker.shared.completions(forPartialWordRange: range, in: prefix,
                                                     language: "en", inSpellDocumentWithTag: 0)
        return !(list ?? []).isEmpty
    }

    /// ตัดสินตั้งแต่ยังพิมพ์อยู่ ไม่ต้องรอเว้นวรรคหรือ Enter
    /// ยิงเร็วไม่เป็นไร เพราะพอแก้แล้วเราสลับแป้นให้ด้วย ตัวที่พิมพ์ต่อจึงออกมาถูกเอง
    private func liveCorrection(for strokes: [Stroke]) -> (text: String, toThai: Bool)? {
        guard let thai = KeyLayouts.thai, let latin = KeyLayouts.latin else { return nil }
        let typed = strokes.map(\.text).joined()
        guard !ignored.contains(typed) else { return nil }
        guard undoneLength == 0 || typed.count >= undoneLength + 2 else {
            return nil }

        if ThaiScript.hasThai(typed) {
            // แป้นเป็นไทยอยู่ แต่แปลงกลับแล้วกลายเป็นคำอังกฤษเต็มคำ
            let english = render(strokes, with: latin)
            guard english.count >= 3, Self.isEnglishWord(english) else {
                return nil }
            return (english, false)
        }
        // แป้นเป็นอังกฤษ แต่ไม่มีคำอังกฤษคำไหนขึ้นต้นแบบนี้ได้แล้ว
        guard typed.count >= 3 else { return nil }
        guard !Self.hasEnglishCompletions(typed) else {
            return nil }
        let converted = render(strokes, with: thai)
        guard converted.unicodeScalars.allSatisfy(ThaiScript.isThai) else {
            return nil }
        guard ThaiScript.wellFormed(converted) else {
            return nil }
        return (converted, true)
    }

    /// แก้สดระหว่างพิมพ์ — ปิดไว้ (แก้เฉพาะตอนเคาะเว้นวรรค/Enter เท่านั้น ไม่เด้งกลางคำ)
    /// ถ้าอยากเปิดกลับ เอา `if true { return }` ออก
    private func liveCheck() {
        if true { return }
        guard Config.layoutFixAuto, !busy, allowedHere, word.count >= 3 else { return }
        let strokes = word
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.busy, self.word.count == strokes.count,
                  let fix = self.liveCorrection(for: strokes) else { return }
            self.word.removeAll()
            self.lastWord = strokes
            self.apply(strokes: strokes, to: fix.text, toThai: fix.toThai, trailing: 0)
        }
    }

    /// คืนข้อความที่ควรจะเป็น ถ้ามั่นใจพอว่าพิมพ์ผิดแป้น
    private func correction(for strokes: [Stroke]) -> (text: String, toThai: Bool)? {
        guard let thai = KeyLayouts.thai, let latin = KeyLayouts.latin else { return nil }
        let typed = strokes.map(\.text).joined()
        guard typed.count >= 2, !ignored.contains(typed) else { return nil }

        if ThaiScript.hasThai(typed) {
            // พิมพ์อังกฤษทั้งที่แป้นเป็นไทย — เกณฑ์คือแปลงกลับแล้วต้องเป็นคำอังกฤษจริง
            // วัดกับคำไทยที่ใช้บ่อย 96 คำแล้วไม่มีคำไหนโดนแก้ผิดเลย
            let english = render(strokes, with: latin)
            guard english.count >= 3, Self.isEnglishWord(english) else { return nil }
            return (english, false)
        } else {
            // พิมพ์ไทยทั้งที่แป้นเป็นอังกฤษ → ต้องไม่ใช่คำอังกฤษ และไทยที่แปลงต้องสะกดได้
            guard typed.count >= 3, !Self.isEnglishWord(typed) else { return nil }
            let converted = render(strokes, with: thai)
            guard converted.unicodeScalars.allSatisfy(ThaiScript.isThai),
                  ThaiScript.wellFormed(converted) else { return nil }
            return (converted, true)
        }
    }

    private func autoFix(_ strokes: [Stroke], trailing: Int) {
        guard let fix = correction(for: strokes) else { return }
        apply(strokes: strokes, to: fix.text, toThai: fix.toThai, trailing: trailing)
    }

    // MARK: ลงมือแก้

    private func apply(strokes: [Stroke], to text: String, toThai: Bool, trailing: Int) {
        let original = strokes.map(\.text).joined()
        let previous = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        replace(count: original.unicodeScalars.count + trailing,
                with: text + String(repeating: " ", count: trailing))
        if let target = toThai ? KeyLayouts.thai?.source : KeyLayouts.latin?.source {
            TISSelectInputSource(target)
        }
        lastFix = Fix(strokes: strokes, original: original, replacement: text, trailing: trailing,
                      previousSource: previous)
        fixTail.removeAll()
    }

    /// ลบของเดิมทิ้งแล้วพิมพ์ใหม่ — ส่งเป็น unicode ตรง ๆ ไม่ผ่าน layout ปัจจุบัน
    private func replace(count: Int, with text: String) {
        guard count > 0 else { busy = false; return }
        busy = true
        for _ in 0..<count {
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil,
                                          virtualKey: CGKeyCode(kVK_Delete), keyDown: isDown) else { continue }
                event.setIntegerValueField(.eventSourceUserData, value: SystemActions.syntheticTag)
                event.post(tap: .cghidEventTap)
            }
        }
        var chars = Array(text.utf16)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else { continue }
            event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            event.setIntegerValueField(.eventSourceUserData, value: SystemActions.syntheticTag)
            event.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.busy = false }
    }

    // MARK: ย้อนกลับ / สั่งแก้เอง

    private func revert(_ fix: Fix) {
        let tail = fixTail.joined()
        lastFix = nil
        fixTail.removeAll()
        ignored.insert(fix.original)

        // ลบยาวถึงคำที่แก้ (หางทั้งหมด + ตัวคั่น + คำที่แก้) แล้วพิมพ์คำเดิม + หางคืนตามเดิม
        replace(count: fix.replacement.unicodeScalars.count + fix.trailing
                    + tail.unicodeScalars.count,
                with: fix.original + String(repeating: " ", count: fix.trailing) + tail)

        if tail.isEmpty {
            // ย้อนสด ๆ = ปฏิเสธการสลับภาษา คืน input source ให้ด้วย
            if let previous = fix.previousSource { TISSelectInputSource(previous) }
            // คืนปุ่มเดิมกลับเข้าบัฟเฟอร์ ไม่งั้นตัวที่พิมพ์ต่อจะนับผิด
            if fix.trailing == 0 {
                word = fix.strokes
                undoneLength = fix.original.count
            } else {
                word.removeAll()
                undoneLength = 0
            }
            lastWord = fix.strokes
        }
        // มีหาง = ตั้งใจพิมพ์ภาษาที่สลับไปต่อแล้ว ไม่สลับ source กลับ
        // ข้อความบนจอกลับมาตรงกับบัฟเฟอร์พอดี ไม่ต้องแตะ word/lastWord
    }

    /// ยกเลิกคำที่เพิ่งโดนแก้ — ใช้กับคีย์แบบกดครั้งเดียวอย่าง Esc
    /// กลืนคีย์เฉพาะตอนมีของให้ย้อนจริง ๆ (พิมพ์ตัวใหม่เมื่อไหร่ lastFix ถูกล้างอยู่แล้ว)
    func undoViaKey() -> Bool {
        guard Config.layoutFix, !busy, let fix = lastFix else { return false }
        revert(fix)
        return true
    }

    func toggleLastWord(silent: Bool = false) {
        guard Config.layoutFix else { if !silent { NSSound.beep() }; return }

        // เพิ่งแปลงเสร็จสด ๆ แล้วยังไม่พิมพ์อะไรต่อ (fixTail ว่าง) → กด Shift ซ้ำ = ย้อนกลับ (toggle)
        // แต่ถ้าพิมพ์อะไรต่อไปแล้ว ถือว่า lastFix เก่าเก็บ — ล้างทิ้ง อย่าไป revert เพราะจะลบผิดจำนวน
        if let fix = lastFix {
            if fixTail.isEmpty { revert(fix); return }
            lastFix = nil
            fixTail.removeAll()
        }

        // ไม่งั้นก็สลับภาษาให้คำล่าสุดเอง
        let target = word.isEmpty ? lastWord : word
        let trailing = word.isEmpty ? 1 : 0
        guard !target.isEmpty, let thai = KeyLayouts.thai, let latin = KeyLayouts.latin else {
            if !silent { NSSound.beep() }
            return
        }
        let typed = target.map(\.text).joined()
        let toThai = !ThaiScript.hasThai(typed)
        let converted = render(target, with: toThai ? thai : latin)
        guard converted != typed else { if !silent { NSSound.beep() }; return }
        apply(strokes: target, to: converted, toThai: toThai, trailing: trailing)
        if word.isEmpty { lastWord = [] } else { word.removeAll() }
    }

    // MARK: แปลงเฉพาะส่วนที่เลือก (คลุมดำ + กด Shift 2 ครั้ง)

    private static var latinToThai: [Character: Character]?
    private static var thaiToLatin: [Character: Character]?
    private static func buildMaps() {
        guard latinToThai == nil, let thai = KeyLayouts.thai, let latin = KeyLayouts.latin else { return }
        var l2t: [Character: Character] = [:], t2l: [Character: Character] = [:]
        for code in 0..<128 {
            for shift in [false, true] {
                guard let ls = latin.text(code, shift: shift), let ts = thai.text(code, shift: shift),
                      let lc = ls.count == 1 ? ls.first : nil,
                      let tc = ts.count == 1 ? ts.first : nil else { continue }
                if l2t[lc] == nil { l2t[lc] = tc }
                if t2l[tc] == nil { t2l[tc] = lc }
            }
        }
        latinToThai = l2t
        thaiToLatin = t2l
    }

    /// คลุมดำ + กด Shift 2 ครั้ง → สลับแป้น (ไทย↔อังกฤษ) เฉพาะส่วนที่เลือก
    /// ลองอ่านผ่าน AX ก่อน (สะอาดสุด ไม่แตะคลิปบอร์ด) — ใช้ได้กับช่องพิมพ์เนทีฟ
    /// ถ้า AX อ่านไม่ได้ (Electron/terminal/เว็บ) → ใช้คลิปบอร์ด: ก๊อป → แปลง → วางทับ → คืนคลิปบอร์ดเดิม
    /// ถ้าไม่มีอะไรเลือกเลย → ไปสลับคำล่าสุดที่พิมพ์ให้แทน
    /// แปลง "เฉพาะข้อความที่คลุมดำ" เท่านั้น — ไม่มี fallback ไปแตะบัฟเฟอร์คำที่พิมพ์
    /// (fallback แบบเก่าเคยลบยาวเกินจริงในช่องแชท/editor จนข้อความหายหมด จึงตัดทิ้ง)
    func convertSelection() {
        guard Config.layoutFix, !busy else { return }
        switch axSelectedText() {
        case .some(let sel) where !sel.isEmpty:      // มีข้อความเลือกอยู่ (ผ่าน AX) → แปลงเฉพาะส่วนนั้น
            if sel.count <= 500, let out = converted(from: sel) {
                typeOver(out, toThai: !ThaiScript.hasThai(sel))
            }
        case .some:                                  // โฟกัสอยู่แต่ไม่ได้เลือกอะไร → ไม่ทำอะไร (กันลบมั่ว)
            break
        case .none:                                  // AX อ่านไม่ได้ (Electron/terminal/เว็บ) → ใช้ clipboard
            convertViaClipboard()
        }
    }

    /// อ่านข้อความที่เลือกผ่าน Accessibility — คืน nil ถ้าแอปไม่เปิดเผยให้
    private func axSelectedText() -> String? {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let raw = focused else { return nil }
        var selRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw as! AXUIElement, kAXSelectedTextAttribute as CFString, &selRef) == .success,
              let sel = selRef as? String else { return nil }
        return sel
    }

    /// แปลงข้อความสลับแป้น — คืน nil ถ้าแปลงแล้วไม่เปลี่ยน (เช่นมีแต่ตัวเลข/สัญลักษณ์)
    private func converted(from sel: String) -> String? {
        Self.buildMaps()
        guard let l2t = Self.latinToThai, let t2l = Self.thaiToLatin else { return nil }
        let map = ThaiScript.hasThai(sel) ? t2l : l2t
        let out = String(sel.map { map[$0] ?? $0 })
        return out != sel ? out : nil
    }

    /// พิมพ์ทับ selection (แทนที่ทันที ไม่ต้องลบก่อน) แล้วสลับ input source
    private func typeOver(_ text: String, toThai: Bool) {
        busy = true
        var chars = Array(text.utf16)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
            e.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            e.setIntegerValueField(.eventSourceUserData, value: SystemActions.syntheticTag)
            e.post(tap: .cghidEventTap)
        }
        switchSource(toThai: toThai)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.busy = false }
        reset()
    }

    private func switchSource(toThai: Bool) {
        if let target = toThai ? KeyLayouts.thai?.source : KeyLayouts.latin?.source {
            TISSelectInputSource(target)
        }
    }

    // MARK: ทางคลิปบอร์ด — ใช้ได้ทุกแอป (VSCode, terminal, เว็บ ฯลฯ)

    private func convertViaClipboard() {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)            // เก็บคลิปบอร์ดเดิมไว้คืน (ทุกชนิด)
        let before = pb.changeCount
        busy = true
        SystemActions.postKey(kVK_ANSI_C, .maskCommand)   // ก๊อปสิ่งที่เลือก
        waitForCopy(pb: pb, before: before, tries: 15) { [weak self] copied in
            guard let self else { return }
            guard let sel = copied, !sel.isEmpty, sel.count <= 500, let out = self.converted(from: sel) else {
                self.restore(pb, saved)      // ไม่มีอะไรเลือก / แปลงไม่ได้ → คืนคลิปบอร์ด แล้วจบ (ไม่แตะข้อความ)
                self.busy = false
                return
            }
            pb.clearContents(); pb.setString(out, forType: .string)
            SystemActions.postKey(kVK_ANSI_V, .maskCommand)   // วางทับ
            self.switchSource(toThai: !ThaiScript.hasThai(sel))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.restore(pb, saved)      // คืนคลิปบอร์ดเดิมหลังวางเสร็จ
                self.busy = false
                self.reset()
            }
        }
    }

    /// รอจน changeCount ขยับ (แปลว่าก๊อปสำเร็จ) หรือหมดเวลา (แปลว่าไม่มีอะไรเลือก)
    private func waitForCopy(pb: NSPasteboard, before: Int, tries: Int, done: @escaping (String?) -> Void) {
        if pb.changeCount != before { done(pb.string(forType: .string)); return }
        guard tries > 0 else { done(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.waitForCopy(pb: pb, before: before, tries: tries - 1, done: done)
        }
    }

    private func snapshot(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        }
    }

    private func restore(_ pb: NSPasteboard, _ items: [NSPasteboardItem]) {
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }
}

// MARK: - รูปแบบคีย์ลัด: Windows หรือ Mac ---------------------------------------

/// จุดตัดสินใจเดียวของทั้งแอปว่า "ตอนนี้ควรทำตัวแบบ Windows ไหม"
/// Auto เปิด → ดูจากคีย์บอร์ดที่พิมพ์ล่าสุด (ยังไม่รู้ = Windows ไปก่อน)
/// Auto ปิด → ตามที่ผู้ใช้เลือกไว้ตรง ๆ
enum KeyboardStyle {
    static var windowsActive: Bool {
        Config.perKeyboard ? !KeyboardWatch.shared.suppressesWindowsKeys
                           : Config.keyboardStyleWindows
    }

    static var label: String {
        let style = windowsActive ? "Windows" : "Mac"
        guard Config.perKeyboard else { return style }
        return style + "  ·  " + (KeyboardWatch.shared.lastKind == .unknown
            ? "no key seen yet"
            : "from " + " " + KeyboardWatch.shared.lastKind.label)
    }
}

// MARK: - สวิตช์ใหญ่ (ใช้ร่วมกันทั้งเมนูบาร์และหน้าตั้งค่า) --------------------------

/// แต่ละตัวคุมฟีเจอร์ทั้งกลุ่ม — ไม่มีสวิตช์ย่อยให้ปรับอีก
enum MasterSwitch {
    case windowsSnap, livePreview
    case windowsShortcuts, autoKeyboard, layoutFix, keyboardClean
    case mouseNatural, trackpadNatural, mouseSideButtons
    case monitorCPU, monitorRAM, monitorSSD
    case launchAtLogin

    var isOn: Bool {
        switch self {
        case .windowsSnap:      return SnapManager.shared.isEnabled
        case .livePreview:      return Config.windowPreviews
        case .windowsShortcuts: return KeyboardStyle.windowsActive
        case .autoKeyboard:     return Config.perKeyboard
        case .layoutFix:        return Config.layoutFix
        case .keyboardClean:    return KeyboardClean.shared.isOn
        case .mouseNatural:     return Config.mouseNaturalScroll
        case .trackpadNatural:  return Config.trackpadNaturalScroll
        case .mouseSideButtons: return Config.mouseSideButtons
        case .monitorCPU:       return Config.monitorCPU
        case .monitorRAM:       return Config.monitorRAM
        case .monitorSSD:       return Config.monitorSSD
        case .launchAtLogin:    return LoginItem.isEnabled
        }
    }

    func set(_ value: Bool) {
        switch self {
        case .windowsSnap:
            // สวิตช์เดียวรวมทุกท่า snap: ลากชนขอบ/มุม · Snap Layouts · Snap Assist · เส้นแบ่ง
            // · ลากออก=คืนขนาด · ลากขอบ=สูงเต็มจอ · ดับเบิลคลิก=เต็มจอ
            Config.snapLayouts = value
            Config.snapAssist = value
            Config.dividers = value
            Config.unsnapOnDrag = value
            Config.verticalMaximize = value
            Config.trueMaximize = value
            SnapManager.shared.isEnabled = value
            SnapManager.shared.refreshDividerVisibility()
        case .livePreview:
            // ภาพหน้าต่างจริงทุกที่: Option+Tab · Snap Assist · ชี้ Dock — และภาพขยับตามของจริง
            Config.windowPreviews = value
            Config.livePreviews = value
            Config.dockPeek = value
            DockPeek.shared.refresh()
            if value { AppDelegate.shared?.ensureScreenRecording() }
        case .windowsShortcuts:
            // สับสวิตช์เองเมื่อไหร่ = เลือกเองแล้ว เลิกให้ Auto ตัดสินให้
            Config.perKeyboard = false
            Config.keyboardStyleWindows = value
            KeyboardWatch.shared.refresh()
        case .autoKeyboard:
            Config.perKeyboard = value
            KeyboardWatch.shared.refresh()
        case .layoutFix:
            Config.layoutFix = value
            if value { KeyLayouts.reload() }
        case .keyboardClean:
            KeyboardClean.shared.set(value)
        case .mouseNatural:
            Config.mouseNaturalScroll = value
        case .trackpadNatural:
            Config.trackpadNaturalScroll = value
        case .mouseSideButtons:
            Config.mouseSideButtons = value
        case .monitorCPU:
            Config.monitorCPU = value
            SystemMonitor.shared.refresh()
        case .monitorRAM:
            Config.monitorRAM = value
            SystemMonitor.shared.refresh()
        case .monitorSSD:
            Config.monitorSSD = value
            SystemMonitor.shared.refresh()
        case .launchAtLogin:
            Config.launchAtLogin = value
            LoginItem.set(value)
        }
        InputTap.shared.refresh()
    }
}

// MARK: - รู้ว่าปุ่มมาจากคีย์บอร์ดตัวไหน -----------------------------------------

/// CGEvent ที่ tap ดักได้ไม่บอกว่ามาจากอุปกรณ์ไหน เลยต้องฟัง HID คู่ขนานไปด้วย
/// แล้วจำว่า "ปุ่มล่าสุดมาจากคีย์บอร์ดตัวไหน" — ต้องขอสิทธิ์ Input Monitoring เพิ่ม
final class KeyboardWatch {
    static let shared = KeyboardWatch()

    enum Kind: String {
        case mac, pc, unknown
        var label: String {
            switch self {
            case .mac:     return "Mac keyboard"
            case .pc:      return "Windows keyboard"
            case .unknown: return "Unknown"
            }
        }
    }

    struct Device {
        let name: String
        let vendor: Int
        let kind: Kind
    }

    private static let appleVendor = 0x05AC   // 1452

    private var manager: IOHIDManager?
    private(set) var lastKind: Kind = .unknown
    private(set) var devices: [Device] = []
    private(set) var denied = false
    private var lastSeen: CFAbsoluteTime = 0

    /// ปิดพฤติกรรมแบบ Windows ก็ต่อเมื่อ "รู้แน่" ว่าปุ่มมาจากคีย์บอร์ด Mac
    /// ถ้ายังไม่รู้ (ไม่ได้สิทธิ์ / ยังไม่มีใครกดปุ่ม) ให้ทำงานเหมือนเดิมไปก่อน
    /// ไม่งั้นเปิดสวิตช์นี้ทั้งที่ไม่ได้สิทธิ์แล้วฟีเจอร์จะเงียบหายไปทั้งชุด
    var suppressesWindowsKeys: Bool { lastKind == .mac }

    var accessGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func refresh() {
        guard Config.perKeyboard else { stop(); return }
        requestAccess()
        start()
    }

    func requestAccess() {
        guard !accessGranted else { return }
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    private func start() {
        guard manager == nil else { return }
        guard accessGranted else { denied = true; return }
        denied = false

        let created = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(created, match as CFDictionary)

        let callback: IOHIDValueCallback = { context, _, _, value in
            guard let context else { return }
            Unmanaged<KeyboardWatch>.fromOpaque(context).takeUnretainedValue().received(value)
        }
        IOHIDManagerRegisterInputValueCallback(created, callback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(created, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        guard IOHIDManagerOpen(created, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(created, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            denied = true
            return
        }
        manager = created
        scan()
    }

    private func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        lastKind = .unknown
    }

    /// รายชื่อคีย์บอร์ดที่ต่ออยู่ — อ่านจาก IORegistry ตรง ๆ จะได้โชว์ได้
    /// ตั้งแต่ยังไม่ได้สิทธิ์ Input Monitoring (การอ่านทะเบียนอุปกรณ์ไม่ต้องขอสิทธิ์)
    func scan() {
        guard let matching = IOServiceMatching("IOHIDDevice") else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }

        var found: [Device] = []
        var seen = Set<String>()
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }
            guard (property(kIOHIDPrimaryUsagePageKey) as? Int) == kHIDPage_GenericDesktop,
                  (property(kIOHIDPrimaryUsageKey) as? Int) == kHIDUsage_GD_Keyboard,
                  let name = property(kIOHIDProductKey) as? String,
                  seen.insert(name).inserted else { continue }
            let vendor = (property(kIOHIDVendorIDKey) as? Int) ?? 0
            found.append(Device(name: name, vendor: vendor,
                                kind: Self.classify(vendor: vendor, name: name)))
        }
        devices = found.sorted { $0.name < $1.name }
    }

    private static func classify(vendor: Int, name: String) -> Kind {
        if vendor == appleVendor || name.localizedCaseInsensitiveContains("apple") { return .mac }
        return .pc
    }

    private func received(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad) else { return }
        let device = IOHIDElementGetDevice(element)
        let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let kind = Self.classify(vendor: vendor, name: name)
        lastSeen = CFAbsoluteTimeGetCurrent()
        guard kind != lastKind else { return }
        lastKind = kind
        if devices.isEmpty { scan() }
    }
}

// MARK: - ชี้ไอคอนใน Dock แล้วเห็นหน้าต่างทั้งหมดของแอปนั้น ------------------

/// อ่านตำแหน่งไอคอนใน Dock ผ่าน Accessibility — Dock ยอมบอกทั้งชื่อ ตำแหน่ง
/// และสถานะว่าแอปเปิดอยู่ไหม เลยไม่ต้องเดาตำแหน่งจากขนาด Dock เอง
enum DockItems {
    struct Item {
        let title: String
        let frame: CGRect       // พิกัด CG (มุมบนซ้าย)
        let running: Bool
    }

    private static var cache: [Item] = []
    private static var readAt: CFAbsoluteTime = 0

    /// รวมพื้นที่ไอคอนทั้งแถบ ไว้เช็คเร็ว ๆ ว่าเคอร์เซอร์เฉียดมาแถวนี้หรือยัง
    static var band: CGRect {
        cache.reduce(CGRect.null) { $0.union($1.frame) }
    }

    static func items(refreshAfter interval: CFTimeInterval = 1.0) -> [Item] {
        let now = CFAbsoluteTimeGetCurrent()
        if now - readAt < interval, !cache.isEmpty { return cache }
        readAt = now
        cache = read()
        return cache
    }

    static func item(at point: CGPoint) -> Item? {
        // ถ้าเปิด Dock magnification ไว้ ไอคอนจะขยับตอนเมาส์เข้าใกล้ ต้องอ่านถี่หน่อย
        items(refreshAfter: 0.3).first { $0.running && $0.frame.contains(point) }
    }

    /// เคอร์เซอร์อยู่แถว ๆ Dock หรือยัง — เช็คจากค่าที่แคชไว้ ไม่ต้องคุยกับ Dock
    static func isNearDock(_ point: CGPoint) -> Bool {
        let known = band
        if known.isNull { _ = items(refreshAfter: 2.0); return !band.isNull && band.insetBy(dx: -90, dy: -90).contains(point) }
        return known.insetBy(dx: -90, dy: -90).contains(point)
    }

    private static func read() -> [Item] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let lists = AX.attribute(app, kAXChildrenAttribute) as? [AXUIElement] else { return [] }

        var found: [Item] = []
        for list in lists {
            guard let children = AX.attribute(list, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            for element in children {
                guard AX.string(element, kAXSubroleAttribute) == "AXApplicationDockItem",
                      let title = AX.string(element, kAXTitleAttribute) else { continue }
                guard let frame = AX.frame(of: element) else { continue }
                let running = (AX.attribute(element, "AXIsApplicationRunning") as? Bool) ?? false
                found.append(Item(title: title, frame: frame, running: running))
            }
        }
        return found
    }
}

/// พาเนลพรีวิวที่ลอยอยู่เหนือไอคอน
final class DockPeekPanel: NSPanel {
    static let shared = DockPeekPanel()

    let grid = TileGridView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = GlassBackdrop.wrap(grid)
        grid.onPick = { [weak self] index in
            guard let self, self.grid.items.indices.contains(index) else { return }
            let target = self.grid.items[index]
            self.hide()
            DispatchQueue.global(qos: .userInitiated).async { AX.raise(target.element) }
        }
    }

    override var canBecomeKey: Bool { true }

    func show(_ windows: [WindowInfo], over icon: CGRect, title: String) {
        grid.items = windows
        grid.selected = -1
        grid.hovered = nil
        grid.headline = windows.count > 1
            ? title + "  ·  " + "\(windows.count) windows"
            : title

        if Thumbnails.isUsable {
            grid.tileSize = NSSize(width: 200, height: 158)
            grid.previewHeight = 104
        } else {
            grid.tileSize = NSSize(width: 168, height: 112)
            grid.previewHeight = 0
        }
        let columns = min(windows.count, 5)
        let size = TileGridView.gridSize(count: windows.count, columns: columns,
                                         tile: grid.tileSize, gap: grid.tileGap,
                                         padding: grid.padding, headline: grid.headline != nil)
        grid.columns = columns

        // วางไว้เหนือไอคอน กึ่งกลางกับไอคอน แล้วดันให้อยู่ในจอ
        let iconAppKit = Geometry.toAppKit(icon)
        var origin = NSPoint(x: iconAppKit.midX - size.width / 2, y: iconAppKit.maxY + 8)
        if let screen = Geometry.screen(containing: NSPoint(x: iconAppKit.midX, y: iconAppKit.midY)) {
            let visible = screen.visibleFrame
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            origin.y = min(origin.y, visible.maxY - size.height - 8)
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
        makeKey()   // เป็น key window ตั้งแต่โผล่ — ไม่งั้น macOS วาดกระจกแบบ inactive (ขุ่น) จนกว่าจะคลิก
        GlassBackdrop.adaptToBackdrop(self)

        // ภาพย่อถูกจับแบบ async — ต้องสั่งเก็บก่อน ไม่งั้นได้แต่ไอคอนแอป
        // และให้จับซ้ำเรื่อย ๆ ภาพจะได้ขยับตามของจริงตราบใดที่ยังชี้ค้างอยู่
        Thumbnails.shared.startLive(for: windows) { [weak self] in
            self?.grid.needsDisplay = true
        }
    }

    func hide() {
        guard isVisible else { return }
        Thumbnails.shared.stopLive()
        orderOut(nil)
        grid.items = []
    }
}

/// คอยดูว่าเคอร์เซอร์ไปวางอยู่บนไอคอนไหน — ใช้ timer เบา ๆ ไม่ต้องดักอีเวนต์เมาส์ทั้งเครื่อง
final class DockPeek {
    static let shared = DockPeek()

    private var timer: Timer?
    private var clickWatch: Any?
    private var hoveredTitle: String?
    /// ไอคอนที่เพิ่งถูกคลิก — ห้ามเด้งพรีวิวขึ้นมาอีกจนกว่าเมาส์จะออกไปแล้วกลับมา
    private var suppressed: String?
    private var hoveredSince: CFAbsoluteTime = 0
    private var leftAt: CFAbsoluteTime = 0
    private var building = false

    /// รอให้ชี้ค้างสักครู่ก่อนค่อยโผล่ จะได้ไม่เด้งตอนลากเมาส์ผ่าน
    private let dwell: CFTimeInterval = 0.28
    private let grace: CFTimeInterval = 0.35

    func refresh() {
        if Config.dockPeek { start() } else { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        let created = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(created, forMode: .common)
        timer = created

        // คลิกที่ไหนก็ตามนอกแอปเรา = ปิดพรีวิว โดยเฉพาะคลิกขวาที่ Dock ซึ่งจะมี
        // เมนูของ Dock เด้งขึ้นมาทับ  ·  monitor ตัวนี้ไม่เห็นคลิกบนพาเนลของเราเอง
        // (global monitor ได้เฉพาะอีเวนต์ของแอปอื่น) การคลิกเลือกหน้าต่างจึงยังทำงาน
        clickWatch = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            self.suppressed = self.hoveredTitle
            self.hoveredTitle = nil
            DockPeekPanel.shared.hide()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let clickWatch { NSEvent.removeMonitor(clickWatch) }
        clickWatch = nil
        hoveredTitle = nil
        suppressed = nil
        DockPeekPanel.shared.hide()
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let point = Geometry.toCG(mouse)
        let panel = DockPeekPanel.shared

        // อยู่บนพาเนลอยู่ ก็ค้างไว้ให้เลือก
        if panel.isVisible, panel.frame.insetBy(dx: -6, dy: -6).contains(mouse) {
            leftAt = 0
            return
        }

        // อยู่ไกล Dock ก็ไม่ต้องไปกวน Dock ให้เปลืองเวลา
        guard DockItems.isNearDock(point) || panel.isVisible else { return }

        guard let item = DockItems.item(at: point) else {
            hoveredTitle = nil
            suppressed = nil
            if panel.isVisible {
                if leftAt == 0 { leftAt = CFAbsoluteTimeGetCurrent() }
                else if CFAbsoluteTimeGetCurrent() - leftAt > grace { panel.hide(); leftAt = 0 }
            }
            return
        }

        leftAt = 0
        // เพิ่งคลิกไอคอนนี้ไป ยังไม่ยอมเด้งขึ้นมาใหม่จนกว่าเมาส์จะออกไปก่อน
        if let held = suppressed {
            if held == item.title {
                hoveredTitle = item.title
                return
            }
            suppressed = nil
        }
        if item.title != hoveredTitle {
            hoveredTitle = item.title
            hoveredSince = CFAbsoluteTimeGetCurrent()
            return
        }
        guard !panel.isVisible || panel.grid.headline?.hasPrefix(item.title) != true else { return }
        guard CFAbsoluteTimeGetCurrent() - hoveredSince > dwell, !building else { return }

        building = true
        let icon = item.frame
        let title = item.title
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = Self.windows(ofAppNamed: title)
            DispatchQueue.main.async {
                self.building = false
                guard self.hoveredTitle == title else { return }
                guard !windows.isEmpty else { DockPeekPanel.shared.hide(); return }
                DockPeekPanel.shared.show(windows, over: icon, title: title)
            }
        }
    }

    /// Dock บอกมาแค่ชื่อแอป เลยต้องจับคู่กับ process ที่กำลังรันเอง
    private static func windows(ofAppNamed name: String) -> [WindowInfo] {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.localizedName == name }
            .map(\.processIdentifier)
        guard !pids.isEmpty else { return [] }
        return WindowIndex.ordered().filter { pids.contains($0.pid) }
    }
}

// MARK: - Keyboard Clean: ล็อกคีย์บอร์ดไว้เช็ดทำความสะอาด (สวิตช์เปิด/ปิด) ----------

final class KeyboardClean {
    static let shared = KeyboardClean()
    private var panel: NSPanel?

    var isOn: Bool { InputTap.shared.cleaning }

    func set(_ on: Bool) {
        InputTap.shared.cleaning = on
        if on {
            if panel == nil { panel = makePanel() }
            if let panel, let screen = NSScreen.main {
                let frame = panel.frame
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - frame.width / 2,
                                             y: screen.visibleFrame.midY - frame.height / 2))
                panel.orderFrontRegardless()
            }
        } else {
            panel?.orderOut(nil)
        }
        AppDelegate.shared?.refreshMenu()
    }

    @objc private func unlock() { set(false) }

    /// ป้ายลอยกลางจอ บอกว่าล็อกอยู่ + ปุ่มปลดด้วยเมาส์ (เผื่อลืมว่าเปิดไว้)
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
                            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 34, weight: .regular))
        icon.contentTintColor = Skin.accent
        let title = NSTextField(labelWithString: "Keyboard locked for cleaning")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let note = NSTextField(labelWithString: "Keys, Fn and media buttons do nothing. The mouse still works.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.alignment = .center
        note.maximumNumberOfLines = 2
        note.preferredMaxLayoutWidth = 260
        let unlock = NSButton(title: "Unlock", target: self, action: #selector(unlock))
        unlock.bezelStyle = .rounded
        unlock.controlSize = .large

        let stack = NSStackView(views: [icon, title, note, unlock])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSVisualEffectView()
        content.material = .hudWindow
        content.state = .active
        content.addSubview(stack)
        panel.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        panel.setContentSize(stack.fittingSize)
        return panel
    }
}

// MARK: - ทิศทางเลื่อน: ระบบตั้งค่าเดียวใช้ทั้งเมาส์และ trackpad — Deft แยกให้ ---------

enum ScrollDirection {
    /// ค่า Natural scrolling ของ System Settings (ใช้ร่วมกันทั้งเมาส์และ trackpad)
    /// อ่านผ่าน CFPreferences ซึ่งอัปเดตเองเมื่อผู้ใช้เปลี่ยนใน System Settings
    static var systemNatural: Bool {
        (CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                   kCFPreferencesAnyApplication) as? Bool) ?? true
    }
    static var mouseNeedsFlip: Bool { Config.mouseNaturalScroll != systemNatural }
    static var trackpadNeedsFlip: Bool { Config.trackpadNaturalScroll != systemNatural }
}

// MARK: - ตัวดักอีเวนต์คีย์บอร์ด/เมาส์ (แยกจาก tap ของการลากหน้าต่าง) ----------

/// tap ตัวนี้เป็นแบบ "แก้ไขอีเวนต์ได้" ต่างจาก tap ของการลากหน้าต่างที่แค่ฟังอย่างเดียว
/// แยกกันไว้เพื่อว่าถ้าตัวนี้มีปัญหา การ snap หน้าต่างจะไม่ล้มตาม
final class InputTap {
    static let shared = InputTap()

    private init() {
        // ผู้ใช้เปลี่ยน Natural scrolling ใน System Settings → ประเมินใหม่ว่ายังต้องกลับทิศอุปกรณ์ไหน
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var isActive = false
    private(set) var creationFailed = false

    /// จับ "แตะ Shift สองครั้ง" — ต้องแตะสั้น ๆ ไม่มีปุ่มอื่นคั่น
    private var shiftDownAt: CFAbsoluteTime = 0
    private var shiftTapAt: CFAbsoluteTime = 0
    /// จับ Alt+Shift เปลี่ยนภาษา — กด Alt กับ Shift พร้อมกันแล้วปล่อยโดยไม่มีปุ่มอื่นคั่น
    private var altShiftArmed = false

    /// Ctrl+ปุ่มพวกนี้ → Cmd+ปุ่มเดียวกัน — ครอบคลุมคีย์ลัดมาตรฐานทั้ง
    /// แก้ไข/ค้นหา/แท็บเบราว์เซอร์/ซูม/จัดรูปแบบ  ·  ที่จงใจเว้น: H (Cmd+H ซ่อน
    /// หน้าต่างทั้งบาน ไม่ใช่ replace), M (Cmd+M ย่อหน้าต่าง), Q (Cmd+Q ปิดแอปทิ้ง)
    private static let commandKeys: Set<Int> = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
        kVK_ANSI_G, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_N,
        kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
        kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Z,
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        kVK_ANSI_Equal, kVK_ANSI_Minus, kVK_ANSI_Slash, kVK_Return,
    ]

    /// เปิด/ปิดตามว่ามีฟีเจอร์ไหนต้องใช้บ้าง
    func refresh() {
        KeyboardWatch.shared.refresh()
        if Config.needsInputTap || cleaning { start() } else { stop() }
    }

    /// NSSystemDefined — ปุ่มเสียง/ความสว่าง/สื่อ มาทางนี้ ไม่ใช่ keyDown
    private static let systemDefinedEvent: UInt32 = 14

    /// Keyboard Clean: กลืนทุกอย่างที่มาจากคีย์บอร์ด (ปุ่ม, modifier, Fn, ปุ่มสื่อ) จนกว่าจะปิดสวิตช์
    var cleaning = false {
        didSet { refresh() }
    }

    private func start() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            isActive = true
            return
        }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << UInt64(Self.systemDefinedEvent))     // ปุ่มสื่อ/ความสว่าง (ใช้ตอน Keyboard Clean)

        let callback: CGEventTapCallBack = { _, type, event, _ in
            InputTap.shared.handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap, eventsOfInterest: mask,
                                              callback: callback, userInfo: nil) else {
            creationFailed = true
            isActive = false
            return
        }
        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        creationFailed = false
        isActive = true
    }

    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        isActive = false
    }

    // MARK: เส้นทางหลัก

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        // อีเวนต์ที่เรายิงเอง ปล่อยผ่านเสมอ ไม่งั้นวนไม่จบ
        guard event.getIntegerValueField(.eventSourceUserData) != SystemActions.syntheticTag else {
            return pass
        }

        // Keyboard Clean: ล็อกคีย์บอร์ดทั้งหมดไว้เช็ด — เมาส์ยังใช้ได้เพื่อปิดสวิตช์
        if cleaning {
            switch type {
            case .keyDown, .keyUp, .flagsChanged: return nil
            default:
                if type.rawValue == Self.systemDefinedEvent { return nil }
            }
        }

        switch type {
        case .keyDown, .keyUp:
            return handleKey(type: type, event: event) ? nil : pass
        case .scrollWheel:
            return handleScroll(event, pass: pass)
        case .otherMouseDown, .otherMouseUp:
            return handleSideButton(type: type, event: event) ? nil : pass
        case .flagsChanged:
            handleFlags(event)
            return pass
        case .leftMouseDown:
            LayoutFixer.shared.reset()
            return pass
        default:
            return pass
        }
    }

    // MARK: คีย์บอร์ด

    /// คืน true = กลืนอีเวนต์  /  false = ปล่อยผ่าน (อาจถูกแก้ค่าไปแล้ว)
    private func handleKey(type: CGEventType, event: CGEvent) -> Bool {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)
        let hasShift = flags.contains(.maskShift)
        let hasOption = flags.contains(.maskAlternate)

        // รูปแบบคีย์ลัดตอนนี้ — Auto ดูจากคีย์บอร์ดที่พิมพ์ / Manual ตามที่เลือกไว้
        let windowsStyle = KeyboardStyle.windowsActive

        if type == .keyDown {
            shiftDownAt = 0
            shiftTapAt = 0
            altShiftArmed = false

            // คีย์ลัดที่มี Cmd/Ctrl/Option เปลี่ยนข้อความได้ทั้งหมดโดยที่ตัวจำคำมองไม่เห็น
            // (เลือกทั้งหมด ลบทั้งบรรทัด ตัด วาง undo) — เช่น Cmd+A แล้วกด Delete
            // ตัวจำจะลบออกแค่ตัวเดียวทั้งที่บนจอหายทั้งบรรทัด บัฟเฟอร์เลยค้างเป็นขยะ
            // แล้วคำใหม่ที่พิมพ์ต่อจะไม่มีวันแปลงผ่านอีกเลย — ล้างทิ้งปลอดภัยกว่าเดา
            if hasCommand || hasControl || hasOption { LayoutFixer.shared.reset() }
        }

        // ปุ่มเปลี่ยนภาษาต้องมาก่อนตัวจำคำ — ไม่งั้นอักขระแฝงของปุ่ม ` จะหลุดเข้า
        // บัฟเฟอร์ทั้งที่ไม่เคยโผล่บนจอ แล้วทำให้ทั้งประโยคแปลงเป็นไทยไม่ผ่านอีกเลย
        if KeyboardStyle.windowsActive {
            let choice = Int(Config.languageSwitchKey)
            // ไม่กิน Shift+` เพื่อให้ยังพิมพ์ ~ ได้
            if choice == 1, code == kVK_ANSI_Grave, !hasCommand, !hasControl, !hasOption, !hasShift {
                if type == .keyDown {
                    LanguageSwitcher.toggle()
                    LayoutFixer.shared.languageSwitched()
                }
                return true
            }
            if choice == 3, code == kVK_Space, hasCommand, !hasControl, !hasOption, !hasShift {
                if type == .keyDown {
                    LanguageSwitcher.toggle()
                    LayoutFixer.shared.languageSwitched()
                }
                return true
            }
        }

        // โหมด Windows: Alt+Tab (Option+Tab) = ตัวสลับหน้าต่างของ Deft เหมือนฝั่ง Windows
        // (โหมด Mac ปล่อยให้ Option+Tab ว่างตามระบบเดิมของ Mac)
        if windowsStyle, hasOption, !hasCommand, !hasControl, code == kVK_Tab {
            if type == .keyDown {
                let forward = !hasShift
                DispatchQueue.main.async {
                    SnapManager.shared.cycleSwitcher(forward: forward, modifier: .option)
                }
            }
            return true
        }

        // โหมด Mac + เปิด Live Preview: Cmd+Tab แทนตัวสลับแอปของ macOS ด้วยตัวสลับหน้าต่างของ Deft
        // (โหมด Windows ปล่อยให้ Win+Tab = Mission Control ตามเดิม)
        if !windowsStyle, Config.windowPreviews, hasCommand, !hasControl, !hasOption, code == kVK_Tab {
            if type == .keyDown {
                let forward = !hasShift
                DispatchQueue.main.async {
                    SnapManager.shared.cycleSwitcher(forward: forward, modifier: .command)
                }
            }
            return true   // กลืนทั้ง keyDown/keyUp ไม่ให้ตัวสลับของ macOS ทำงาน
        }

        if Config.layoutFix, type == .keyDown, !hasCommand, !hasControl, !hasOption {
            if code == kVK_Escape, Int(Config.layoutFixUndoKey) >= 1,
               LayoutFixer.shared.undoViaKey() { return true }
            if code == kVK_Return || code == kVK_ANSI_KeypadEnter,
               LayoutFixer.shared.interceptReturn(code: code) { return true }
            LayoutFixer.shared.observe(code: code, shift: hasShift, event: event)
        }

        // ปุ่ม Win จริงบนคีย์บอร์ด PC ส่งมาเป็น Cmd — จับเฉพาะที่ผู้ใช้กดเอง
        // (Cmd ที่เราสังเคราะห์จากการแปลง Ctrl มีแท็กและถูกปล่อยผ่านไปก่อนแล้ว)
        if windowsStyle, hasCommand, !hasControl, !hasOption {
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let down = type == .keyDown && !repeated
            switch (code, hasShift) {
            case (kVK_ANSI_E, false):      // Win+E เปิด Finder
                if down { SystemActions.openFileManager() }
                return true
            case (kVK_ANSI_D, false):      // Win+D แสดงเดสก์ท็อป
                if down { SystemActions.showDesktop() }
                return true
            case (kVK_ANSI_L, false):      // Win+L ล็อกหน้าจอ
                if down { SystemActions.lockScreen() }
                return true
            case (kVK_ANSI_R, false):      // Win+R ช่องค้นหา
                if down { SystemActions.runDialog() }
                return true
            case (kVK_ANSI_S, true):       // Win+Shift+S ตัดภาพหน้าจอ
                if down { SystemActions.screenSnip() }
                return true
            case (kVK_Tab, false):         // Win+Tab = Task View → Mission Control
                if down { SystemActions.postKey(kVK_UpArrow, .maskControl) }
                return true
            case (kVK_ANSI_I, false):      // Win+I = เปิด System Settings
                if down, let url = URL(string: "x-apple.systempreferences:") {
                    NSWorkspace.shared.open(url)
                }
                return true
            case (kVK_ANSI_Period, false): // Win+. = หน้าต่างอิโมจิ
                if down { SystemActions.postKey(kVK_Space, [.maskControl, .maskCommand]) }
                return true
            case (kVK_LeftArrow, false), (kVK_RightArrow, false),
                 (kVK_UpArrow, false), (kVK_DownArrow, false):
                // Win+ลูกศร = จัดหน้าต่าง
                if down {
                    let direction = [kVK_LeftArrow, kVK_RightArrow,
                                     kVK_UpArrow, kVK_DownArrow].firstIndex(of: code) ?? 0
                    SnapManager.shared.performArrow(direction)
                }
                return true
            default:
                break
            }
        }

        if windowsStyle {
            // Ctrl+F4 = ปิดแท็บ (แปลงเป็น Cmd+W)
            if code == kVK_F4, hasControl, !hasOption {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_W))
                var next = flags
                next.remove(.maskControl)
                next.remove(.maskSecondaryFn)
                next.insert(.maskCommand)
                event.flags = next
                return false
            }
            // F5 = รีเฟรช (Cmd+R) · Ctrl+F5 / Shift+F5 = รีเฟรชแบบล้างแคช
            if code == kVK_F5, !hasCommand, !hasOption {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_R))
                var next = flags
                next.remove(.maskControl)
                next.remove(.maskSecondaryFn)
                next.insert(.maskCommand)
                if hasControl { next.insert(.maskShift) }
                event.flags = next
                return false
            }
            // F3 = ค้นหาถัดไป (Cmd+G) · Shift+F3 = ก่อนหน้า
            if code == kVK_F3, !hasCommand, !hasControl, !hasOption {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_G))
                var next = flags
                next.remove(.maskSecondaryFn)
                next.insert(.maskCommand)
                event.flags = next
                return false
            }
            // F11 = เต็มจอของแอป (Mac คือ Ctrl+Cmd+F)
            if code == kVK_F11, !hasCommand, !hasControl, !hasOption, !hasShift {
                if type == .keyDown { SystemActions.postKey(kVK_ANSI_F, [.maskControl, .maskCommand]) }
                return true
            }
            // Ctrl+Esc = เมนู Start → ช่องค้นหา
            if code == kVK_Escape, hasControl, !hasShift, !hasOption {
                if type == .keyDown { SystemActions.runDialog() }
                return true
            }
            // Ctrl+PageDown / PageUp = แท็บถัดไป / ก่อนหน้า (แปลงเป็น Ctrl+Tab)
            if code == kVK_PageDown || code == kVK_PageUp, hasControl, !hasCommand, !hasOption {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Tab))
                var next = flags
                next.remove(.maskSecondaryFn)
                next.remove(.maskNumericPad)
                if code == kVK_PageUp { next.insert(.maskShift) }
                event.flags = next
                return false
            }
            // PrtSc บนคีย์บอร์ด PC มาเป็น F13: จับทั้งจอ · Alt+PrtSc = เลือกพื้นที่
            if code == kVK_F13, !hasCommand, !hasControl {
                if type == .keyDown {
                    SystemActions.postKey(hasOption ? kVK_ANSI_4 : kVK_ANSI_3,
                                          [.maskCommand, .maskShift])
                }
                return true
            }
            // ปุ่ม Insert (มาเป็น Help): Shift+Insert = วาง · Ctrl+Insert = คัดลอก
            if code == kVK_Help, hasControl || hasShift, !hasCommand, !hasOption {
                event.setIntegerValueField(.keyboardEventKeycode,
                                           value: Int64(hasControl ? kVK_ANSI_C : kVK_ANSI_V))
                var next = flags
                next.remove(.maskControl)
                next.remove(.maskShift)
                next.remove(.maskSecondaryFn)
                next.remove(.maskNumericPad)
                next.insert(.maskCommand)
                event.flags = next
                return false
            }
            // Alt+← / Alt+→ = ถอยหลัง / เดินหน้า (เบราว์เซอร์และแอปทั่วไป)
            if code == kVK_LeftArrow || code == kVK_RightArrow,
               hasOption, !hasCommand, !hasControl, !FrontApp.isTerminal, !FrontApp.isFinder {
                event.setIntegerValueField(.keyboardEventKeycode,
                    value: Int64(code == kVK_LeftArrow ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket))
                var next = flags
                next.remove(.maskAlternate)
                next.remove(.maskSecondaryFn)
                next.remove(.maskNumericPad)
                next.insert(.maskCommand)
                event.flags = next
                return false
            }
            // Alt+F4 = ปิดหน้าต่าง
            if code == kVK_F4, hasOption {
                if type == .keyDown { SystemActions.closeWindow() }
                return true
            }
        }

        if windowsStyle, FrontApp.isFinder,
           handleFinderKey(type: type, event: event, code: code, flags: flags) {
            return true
        }

        if windowsStyle, hasControl, !hasCommand, !hasOption, !FrontApp.isTerminal {
            // Ctrl+←/→ = กระโดดทีละคำ (Mac ใช้ Option+ลูกศร) — Shift เลือกข้อความตามปกติ
            if code == kVK_LeftArrow || code == kVK_RightArrow {
                var next = flags
                next.remove(.maskControl)
                next.insert(.maskAlternate)
                event.flags = next
                return false
            }
            // Ctrl+Home/End = หัว-ท้ายเอกสาร (Mac ใช้ Cmd+↑/↓)
            if code == kVK_Home || code == kVK_End {
                event.setIntegerValueField(.keyboardEventKeycode,
                                           value: Int64(code == kVK_Home ? kVK_UpArrow : kVK_DownArrow))
                var next = flags
                next.remove(.maskControl)
                next.insert(.maskCommand)
                event.flags = next
                return false
            }
            // Ctrl+Delete = ลบคำข้างหน้า (Mac ใช้ Option+ForwardDelete)
            if code == kVK_ForwardDelete {
                var next = flags
                next.remove(.maskControl)
                next.insert(.maskAlternate)
                event.flags = next
                return false
            }
            // Ctrl+Y = ทำซ้ำ — Mac คือ Cmd+Shift+Z ไม่ใช่ Cmd+Y
            if code == kVK_ANSI_Y {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_Z))
                var next = flags
                next.remove(.maskControl)
                next.insert(.maskCommand)
                next.insert(.maskShift)
                event.flags = next
                return false
            }
        }

        // Home / End = ต้น–ท้ายบรรทัด
        if windowsStyle, code == kVK_Home || code == kVK_End, !hasCommand, !hasControl {
            event.setIntegerValueField(.keyboardEventKeycode,
                                       value: Int64(code == kVK_Home ? kVK_LeftArrow : kVK_RightArrow))
            event.flags = flags.union(.maskCommand)
            return false
        }

        // Ctrl+Backspace = ลบทีละคำ
        if windowsStyle, code == kVK_Delete, hasControl, !FrontApp.isTerminal {
            var next = flags
            next.remove(.maskControl)
            next.insert(.maskAlternate)
            event.flags = next
            return false
        }

        // Ctrl+C/V/X/Z/A… ทำงานแทน Cmd (ยกเว้นในเทอร์มินัล Ctrl+C ต้องเป็นการหยุดโปรแกรม)
        if windowsStyle, hasControl, !hasCommand, !FrontApp.isTerminal,
           Self.commandKeys.contains(code) {
            var next = flags
            next.remove(.maskControl)
            next.insert(.maskCommand)
            event.flags = next
            return false
        }
        return false
    }

    /// ชุดปุ่มแบบ Explorer — ทำงานเฉพาะตอน Finder อยู่หน้าสุด
    private func handleFinderKey(type: CGEventType, event: CGEvent,
                                 code: Int, flags: CGEventFlags) -> Bool {
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)

        // Ctrl+X ตัดไฟล์ → คัดลอกไว้ก่อน ค่อยย้ายตอนวาง
        if code == kVK_ANSI_X, hasControl {
            if type == .keyDown {
                FinderBridge.cutPending = true
                SystemActions.postKey(kVK_ANSI_C, .maskCommand)
            }
            return true
        }
        // วางหลังตัด = ย้ายไฟล์ (Mac ใช้ Cmd+Option+V)
        if code == kVK_ANSI_V, hasControl || hasCommand, FinderBridge.cutPending {
            if type == .keyDown {
                FinderBridge.cutPending = false
                SystemActions.postKey(kVK_ANSI_V, [.maskCommand, .maskAlternate])
            }
            return true
        }
        guard !hasCommand, !hasControl else { return false }

        switch code {
        case kVK_F2:
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Return))
            return false
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard !FinderBridge.isEditingText() else { return false }   // กำลังเปลี่ยนชื่ออยู่
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_O))
            event.flags = flags.union(.maskCommand)
            return false
        case kVK_Delete:
            guard !FinderBridge.isEditingText() else { return false }
            if Config.finderBackspaceGoesUp {
                // Backspace = ขึ้นโฟลเดอร์ (Mac ใช้ Cmd+↑)
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_UpArrow))
            } else {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Delete))
            }
            event.flags = flags.union(.maskCommand)
            return false
        case kVK_ForwardDelete:
            // ปุ่ม Delete แยกบนคีย์บอร์ด PC — ลบเสมอ ไม่ว่าจะตั้ง Backspace ไว้ยังไง
            guard !FinderBridge.isEditingText() else { return false }
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Delete))
            event.flags = flags.union(.maskCommand)
            return false
        case kVK_LeftArrow, kVK_RightArrow:
            // Alt+← / Alt+→ = ถอยหลัง / เดินหน้า เหมือน Explorer
            guard flags.contains(.maskAlternate) else { return false }
            event.setIntegerValueField(.keyboardEventKeycode,
                value: Int64(code == kVK_LeftArrow ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket))
            var next = flags
            next.remove(.maskAlternate)
            next.insert(.maskCommand)
            event.flags = next
            return false
        default:
            return false
        }
    }

    /// Shift เป็น modifier จึงมาทาง flagsChanged ไม่ใช่ keyDown
    private func handleFlags(_ event: CGEvent) {
        // Alt+Shift (2) หรือ Ctrl+Shift (4) เปลี่ยนภาษาแบบ Windows — ยิงตอนปล่อยปุ่ม ถ้าไม่มีปุ่มอื่นคั่น
        let choice = Int(Config.languageSwitchKey)
        if KeyboardStyle.windowsActive, choice == 2 || choice == 4 {
            let now = event.flags
            let primary: CGEventFlags = choice == 2 ? .maskAlternate : .maskControl
            let other: CGEventFlags = choice == 2 ? .maskControl : .maskAlternate
            let combo = now.contains(primary) && now.contains(.maskShift)
                && !now.contains(.maskCommand) && !now.contains(other)
            if combo {
                altShiftArmed = true
            } else if altShiftArmed,
                      !now.contains(primary) || !now.contains(.maskShift) {
                altShiftArmed = false
                LanguageSwitcher.toggle()
                LayoutFixer.shared.languageSwitched()
            }
        }

        guard Config.layoutFix, Int(Config.layoutFixUndoKey) != 1 else { return }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard code == kVK_Shift || code == kVK_RightShift else {
            shiftDownAt = 0
            shiftTapAt = 0
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if event.flags.contains(.maskShift) {
            // กดลง — ต้องไม่มี modifier ตัวอื่นค้างอยู่ ไม่งั้นเป็นคีย์ลัดของแอปอื่น
            shiftDownAt = event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
                ? now : 0
            return
        }
        // ปล่อยขึ้น — แตะยาวไป หรือมีปุ่มอื่นคั่น ก็ไม่นับ
        guard shiftDownAt > 0, now - shiftDownAt < 0.35 else {
            shiftDownAt = 0
            shiftTapAt = 0
            return
        }
        shiftDownAt = 0
        if now - shiftTapAt < 0.45 {
            shiftTapAt = 0
            DispatchQueue.main.async {
                LayoutFixer.shared.convertSelection()
            }
        } else {
            shiftTapAt = now
        }
    }

    // MARK: ล้อเมาส์ — แยกจาก trackpad

    /// คืน nil = กลืนอีเวนต์ (Ctrl+ล้อ = ซูม) · คืน pass = ปล่อยผ่านเดิม · คืนอีเวนต์ใหม่ = ใช้แทนของเดิม
    /// แอปที่ไม่ซูมด้วย ⌘+ล้อเมาส์ แต่มีคีย์ ⌘+ / ⌘− — Ctrl+ล้อ จะถูกส่งเป็นคีย์แทน
    private static let keystrokeZoomApps: Set<String> = [
        "com.apple.Safari", "com.apple.Notes", "com.apple.TextEdit", "com.apple.mail", "com.apple.Preview",
        "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
        "com.apple.dt.Xcode", "com.apple.finder",
        "com.microsoft.VSCode", "com.google.antigravity-ide", "com.todesktop.230313mzl4w4u92" /* Cursor */,
        "jp.naver.line.mac", "com.tinyspeck.slackmacgap", "com.hnc.Discord", "notion.id",
    ]

    private func handleScroll(_ event: CGEvent, pass: Unmanaged<CGEvent>) -> Unmanaged<CGEvent>? {
        // trackpad ส่งค่าแบบต่อเนื่อง (พิกเซล + phase/momentum) ล้อเมาส์ส่งเป็นขั้น
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        // Ctrl+ล้อเมาส์ = ซูมเข้า/ออก เหมือน Windows (เฉพาะล้อเมาส์ โหมด Windows)
        // โหมด Mac ปล่อยผ่าน ให้ Ctrl+ล้อเมาส์ทำงานแบบระบบเดิม (ซูมหน้าจอของ macOS)
        // แอปส่วนใหญ่ที่ซูมด้วยล้อได้ (Chrome/Firefox/Office/Adobe/Figma/Maps…) ใช้ ⌘+ล้อ → ส่งอีเวนต์ล้อ
        // ที่ถือ ⌘ ไปให้ตรง ๆ  ·  แอปที่ไม่มีซูมด้วยล้อแต่มี ⌘+/⌘− (Safari, Notes, IDE…) → ส่งเป็นคีย์แทน
        var flags = event.flags
        if !continuous, KeyboardStyle.windowsActive,
           flags.contains(.maskControl), !flags.contains(.maskCommand),
           !FrontApp.isTerminal {
            if Self.keystrokeZoomApps.contains(FrontApp.bundleID) {
                let raw = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                if raw != 0 {
                    // ทิศซูมอิงจากทิศเลื่อนจริงหลังปรับ Natural Scroll ของเมาส์ จะได้ตรงกับการเลื่อนปกติ
                    let delta = ScrollDirection.mouseNeedsFlip ? -raw : raw
                    SystemActions.postKey(delta > 0 ? kVK_ANSI_Equal : kVK_ANSI_Minus, .maskCommand)
                    return nil
                }
            }
            flags.remove(.maskControl)
            flags.insert(.maskCommand)
            event.flags = flags   // แอปที่รองรับ ⌘+ล้อ จะซูมเอง (ตกไปทางกลับทิศ/ปรับความเร็วด้านล่างตามปกติ)
            if !(ScrollDirection.mouseNeedsFlip || Config.mouseScrollSpeed != 1.0) { return pass }
        }

        // กลับทิศเฉพาะอุปกรณ์ที่ทิศที่อยากได้ไม่ตรงกับค่า Natural scrolling ของระบบ
        let invert = continuous ? ScrollDirection.trackpadNeedsFlip : ScrollDirection.mouseNeedsFlip
        let speed = continuous ? 1.0 : Double(Config.mouseScrollSpeed)
        guard invert || speed != 1.0 else { return pass }
        let sign: Double = invert ? -1 : 1

        // แก้ค่าในอีเวนต์เดิมไม่ได้: macOS 26 ผูก point/fixed delta กับ HID payload ต้นทาง
        // setter ของสองฟิลด์นั้นเขียนไม่ติดหรือได้ค่าเพี้ยน (วัดแล้ว) แอปจึงยังเห็นทิศเดิม
        // ต้องสร้างอีเวนต์ใบใหม่ที่มี HID payload ของตัวเองแล้วส่งแทนของเดิม
        func scaled(_ field: CGEventField) -> Int32 {
            let value = Double(event.getIntegerValueField(field))
            guard value != 0 else { return 0 }
            let result = value * sign * speed
            // กันปัดลงเป็น 0 ไม่งั้นเลื่อนไม่ไปเลย
            return Int32(clamping: Int64(result < 0 ? min(-1, result.rounded()) : max(1, result.rounded())))
        }
        let replacement: CGEvent?
        if continuous {
            // trackpad: ใช้หน่วยพิกเซลจาก point delta แล้วคัดลอก phase/momentum ให้ inertia ยังทำงาน
            replacement = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: scaled(.scrollWheelEventPointDeltaAxis1),
                                  wheel2: scaled(.scrollWheelEventPointDeltaAxis2), wheel3: 0)
            replacement?.setIntegerValueField(.scrollWheelEventScrollPhase,
                                              value: event.getIntegerValueField(.scrollWheelEventScrollPhase))
            replacement?.setIntegerValueField(.scrollWheelEventMomentumPhase,
                                              value: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
        } else {
            replacement = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 3,
                                  wheel1: scaled(.scrollWheelEventDeltaAxis1),
                                  wheel2: scaled(.scrollWheelEventDeltaAxis2),
                                  wheel3: scaled(.scrollWheelEventDeltaAxis3))
        }
        guard let replacement else { return pass }
        replacement.flags = event.flags
        replacement.location = event.location
        replacement.timestamp = event.timestamp
        replacement.setIntegerValueField(.eventSourceUserData, value: SystemActions.syntheticTag)
        return Unmanaged.passRetained(replacement)
    }

    // MARK: ปุ่มข้างเมาส์ = ถอยหลัง/เดินหน้า

    private func handleSideButton(type: CGEventType, event: CGEvent) -> Bool {
        guard Config.mouseSideButtons else { return false }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard button == 3 || button == 4 else { return false }
        if type == .otherMouseDown {
            SystemActions.postKey(button == 3 ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket,
                                  .maskCommand)
        }
        return true
    }
}

// MARK: - ชิ้นส่วนหน้าตา (ใช้ร่วมกันระหว่างเมนูบาร์กับหน้าตั้งค่า) -------------

/// สีและการวาดที่ใช้ซ้ำทั่วแอป
enum Skin {
    static var accent: NSColor { .controlAccentColor }

    static let blue    = NSColor.systemBlue
    static let green   = NSColor.systemGreen
    static let gray    = NSColor.systemGray
    static let teal    = NSColor.systemTeal

    /// ไอคอนในกรอบสี่เหลี่ยมมนสีทึบ — ตัวคั่นหมวดที่อ่านง่ายที่สุด
    static func badge(_ symbolName: String, _ color: NSColor, side: CGFloat = 20) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        let radius = side * 0.30
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if let gradient = NSGradient(colors: [color.blended(withFraction: 0.18, of: .white) ?? color,
                                              color]) {
            gradient.draw(in: path, angle: -90)
        } else {
            color.setFill()
            path.fill()
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.54, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let glyphSize = glyph.size
            glyph.draw(in: NSRect(x: (side - glyphSize.width) / 2,
                                  y: (side - glyphSize.height) / 2,
                                  width: glyphSize.width, height: glyphSize.height))
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// สวิตช์เปิด-ปิด วาดเอง จะได้หน้าตาเดียวกันทั้งในเมนูและหน้าตั้งค่า
    /// เปิด = ทึบสี accent + ปุ่มขาว  ·  ปิด = พื้นโปร่ง เหลือแค่เส้นขอบกับปุ่มจาง ๆ
    static func drawSwitch(in rect: NSRect, on: Bool, dimmed: Bool = false) {
        let alpha: CGFloat = dimmed ? 0.4 : 1
        let track = NSRect(x: rect.midX - 17, y: rect.midY - 10, width: 34, height: 20)
        let path = NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10)

        if on {
            accent.withAlphaComponent(alpha).setFill()
            path.fill()
        } else {
            NSColor.labelColor.withAlphaComponent(0.32 * alpha).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let knobSide: CGFloat = 16
        let knob = NSBezierPath(ovalIn: NSRect(x: on ? track.maxX - knobSide - 2 : track.minX + 2,
                                               y: track.midY - knobSide / 2,
                                               width: knobSide, height: knobSide))
        if on {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.white.withAlphaComponent(alpha).setFill()
            knob.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // ไม่ใช้สีขาวตายตัว ไม่งั้นพอเป็นธีมสว่างปุ่มจะกลืนไปกับพื้นหลัง
            NSColor.labelColor.withAlphaComponent(0.42 * alpha).setFill()
            knob.fill()
        }
    }

}

// MARK: - แถวในเมนูบาร์ --------------------------------------------------------

/// แถวเมนูที่วาดเอง — ใช้ความกว้างร่วมกันทั้งเมนูเพื่อให้ขอบขวาตรงกัน
class MenuRowView: NSView {
    var preferredWidth: CGFloat { 200 }
    func resize(to width: CGFloat) {
        setFrameSize(NSSize(width: width, height: frame.height))
        needsDisplay = true
    }
}

/// หัวเมนู — โลโก้ ชื่อแอป สถานะการทำงาน และปุ่ม Donate ทางขวา
final class MenuHeaderView: MenuRowView {
    private let donate: () -> Void
    private var hovered = false
    private static let pillFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let pillTitle = "Donate"

    init(donate: @escaping () -> Void) {
        self.donate = donate
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 52))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var preferredWidth: CGFloat { 240 }

    /// กรอบปุ่ม Donate — หัวใจ + ตัวหนังสือ ชิดขวาของแถว
    private var pillRect: NSRect {
        let text = (Self.pillTitle as NSString).size(withAttributes: [.font: Self.pillFont]).width
        let width = 10 + 14 + 5 + text + 10
        return NSRect(x: bounds.maxX - 16 - width, y: bounds.midY - 12, width: width, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let side: CGFloat = 38
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        Brand.drawAppIcon(pixels: side)
        image.unlockFocus()
        image.draw(in: NSRect(x: 14, y: bounds.midY - side / 2, width: side, height: side))

        // ชื่อแอป + เลขเวอร์ชันใต้ชื่อ
        let textX = 14 + side + 10
        ("Deft" as NSString).draw(
            at: NSPoint(x: textX, y: bounds.midY + 1),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                             .foregroundColor: NSColor.labelColor])
        ("Version " + Updater.currentVersion as NSString).draw(
            at: NSPoint(x: textX, y: bounds.midY - 15),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor.secondaryLabelColor])

        // ปุ่ม Donate แบบเม็ดยา — ปกติโปร่งมีเส้นขอบ พอชี้ค่อยเติมสี accent
        let pill = pillRect
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        if hovered {
            Skin.accent.withAlphaComponent(0.22).setFill()
            path.fill()
        }
        NSColor.labelColor.withAlphaComponent(hovered ? 0.35 : 0.25).setStroke()
        path.lineWidth = 1
        path.stroke()

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.systemPink]))
        var x = pill.minX + 10
        if let icon = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            icon.isTemplate = false
            let size = icon.size
            icon.draw(in: NSRect(x: x, y: pill.midY - size.height / 2, width: size.width, height: size.height))
            x += 14 + 5
        }
        (Self.pillTitle as NSString).draw(
            at: NSPoint(x: x, y: pill.midY - 7),
            withAttributes: [.font: Self.pillFont, .foregroundColor: NSColor.labelColor])
    }

    override func mouseDown(with event: NSEvent) {
        guard pillRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        MenuPanel.shared.dismiss()
        DispatchQueue.main.async { self.donate() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        pillRect.contains(convert(point, from: superview)) ? self : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: pillRect,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
    override func resize(to width: CGFloat) {
        super.resize(to: width)
        updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

/// แถวสวิตช์เปิด-ปิด แทนเครื่องหมายถูกแบบเดิม
final class MenuToggleRow: MenuRowView {
    private let title: String
    private let indent: CGFloat
    private let leadingSymbol: String?
    private let apply: (Bool) -> Void
    private var on: Bool
    private var hovered = false

    init(title: String, isOn: Bool, tip: String?, indent: CGFloat = 0, leadingSymbol: String? = nil,
         apply: @escaping (Bool) -> Void) {
        self.title = title
        self.on = isOn
        self.indent = indent
        self.leadingSymbol = leadingSymbol
        self.apply = apply
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        toolTip = tip
    }
    required init?(coder: NSCoder) { fatalError() }

    private static let font = NSFont.systemFont(ofSize: 13)

    override var preferredWidth: CGFloat {
        let width = (title as NSString).size(withAttributes: [.font: MenuToggleRow.font]).width
        return 14 + indent + width + 16 + 34 + 16
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6)
            Skin.accent.withAlphaComponent(0.18).setFill()
            pill.fill()
        }
        if let name = leadingSymbol {
            // ไอคอนนำหน้า วางเยื้องซ้ายของตัวหนังสือ 22px ให้ตรงแนวกับไอคอนแถวตั้งค่าอื่น
            let tint = on ? NSColor.systemYellow : NSColor.secondaryLabelColor
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
            if let icon = NSImage(systemSymbolName: on ? name + ".fill" : name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
                ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                icon.isTemplate = false
                let sz = icon.size
                icon.draw(in: NSRect(x: 14 + indent - 22, y: bounds.midY - sz.height / 2,
                                     width: sz.width, height: sz.height))
            }
        }
        (title as NSString).draw(
            at: NSPoint(x: 14 + indent, y: bounds.midY - 8),
            withAttributes: [.font: MenuToggleRow.font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68)])
        Skin.drawSwitch(in: NSRect(x: bounds.maxX - 50, y: bounds.midY - 10, width: 34, height: 20),
                        on: on)
    }

    override func mouseDown(with event: NSEvent) {
        on.toggle()
        apply(on)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityValue() -> Any? { on ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool {
        on.toggle()
        apply(on)
        needsDisplay = true
        return true
    }
}

/// แถวชื่อจอในเมนู — ไอคอนจอ ชื่อ+สถานะสองบรรทัด สวิตช์เปิดปิด และลูกศรกางตั้งค่า
final class DisplayRowView: MenuRowView {
    private let title: String
    private let detail: String
    private let isOn: Bool
    private let isBuiltin: Bool
    private let expanded: Bool
    private let canExpand: Bool
    private let onToggleExpand: () -> Void
    private let onTogglePower: (Bool) -> Void
    private var hovered = false

    init(title: String, detail: String, isOn: Bool, isBuiltin: Bool,
         expanded: Bool, canExpand: Bool,
         onToggleExpand: @escaping () -> Void, onTogglePower: @escaping (Bool) -> Void) {
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.isBuiltin = isBuiltin
        self.expanded = expanded
        self.canExpand = canExpand
        self.onToggleExpand = onToggleExpand
        self.onTogglePower = onTogglePower
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let detailFont = NSFont.systemFont(ofSize: 11)

    override var preferredWidth: CGFloat {
        let w1 = (title as NSString).size(withAttributes: [.font: Self.titleFont]).width
        let w2 = (detail as NSString).size(withAttributes: [.font: Self.detailFont]).width
        return 14 + 18 + 8 + max(w1, w2) + 16 + 34 + (canExpand ? 28 : 16)
    }

    private var switchRect: NSRect {
        NSRect(x: bounds.maxX - (canExpand ? 28 : 16) - 34, y: bounds.midY - 10,
               width: 34, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim: CGFloat = isOn ? 1 : 0.45
        if hovered {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 2), xRadius: 7, yRadius: 7)
            Skin.accent.withAlphaComponent(0.16).setFill()
            pill.fill()
        }

        // ไอคอนจอในกรอบ badge — ขนาดพอดีฟอนต์ จอในเครื่องใช้รูปโน้ตบุ๊ก
        let badge = Skin.badge(isBuiltin ? "laptopcomputer" : "display",
                               isOn ? Skin.teal : Skin.gray, side: 18)
        badge.draw(in: NSRect(x: 14, y: bounds.midY - 9, width: 18, height: 18),
                   from: .zero, operation: .sourceOver, fraction: dim)

        if detail.isEmpty {
            (title as NSString).draw(
                at: NSPoint(x: 40, y: bounds.midY - 8),
                withAttributes: [.font: Self.titleFont,
                                 .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68 * dim)])
        } else {
            (title as NSString).draw(
                at: NSPoint(x: 40, y: bounds.midY + 1),
                withAttributes: [.font: Self.titleFont,
                                 .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68 * dim)])
            (detail as NSString).draw(
                at: NSPoint(x: 40, y: bounds.midY - 14),
                withAttributes: [.font: Self.detailFont,
                                 .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(dim)])
        }

        Skin.drawSwitch(in: switchRect, on: isOn)

        if canExpand {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor.withAlphaComponent(dim)]))
            if let chevron = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                     accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = chevron.size
                chevron.draw(in: NSRect(x: bounds.maxX - size.width - 10,
                                        y: bounds.midY - size.height / 2,
                                        width: size.width, height: size.height))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if switchRect.insetBy(dx: -6, dy: -8).contains(point) {
            onTogglePower(!isOn)
            return
        }
        if canExpand { onToggleExpand() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

/// แถวเลือกอย่างใดอย่างหนึ่ง เช่นภาษา — วาดเป็นแถบเลื่อนสองช่อง
/// แถวสวิตช์ที่มีลูกศรกางรายการตัวเลือกใต้แถว — แบบเดียวกับแถวจอภาพแต่ไม่มีไอคอน
final class MenuSwitchExpandRow: MenuRowView {
    private let title: String
    private let isOn: Bool
    private let expanded: Bool
    private let onToggle: (Bool) -> Void
    private let onExpand: () -> Void
    private var hovered = false
    private static let font = NSFont.systemFont(ofSize: 13)

    init(title: String, isOn: Bool, expanded: Bool,
         onToggle: @escaping (Bool) -> Void, onExpand: @escaping () -> Void) {
        self.title = title
        self.isOn = isOn
        self.expanded = expanded
        self.onToggle = onToggle
        self.onExpand = onExpand
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var preferredWidth: CGFloat {
        let width = (title as NSString).size(withAttributes: [.font: Self.font]).width
        return 14 + width + 16 + 34 + 30 + 14
    }
    private var switchRect: NSRect {
        NSRect(x: bounds.maxX - 30 - 34, y: bounds.midY - 10, width: 34, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6)
            Skin.accent.withAlphaComponent(0.18).setFill()
            pill.fill()
        }
        (title as NSString).draw(
            at: NSPoint(x: 14, y: bounds.midY - 8),
            withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68)])
        Skin.drawSwitch(in: switchRect, on: isOn)

        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
        if let chevron = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                 accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            chevron.isTemplate = false
            let size = chevron.size
            chevron.draw(in: NSRect(x: bounds.maxX - size.width - 12, y: bounds.midY - size.height / 2,
                                    width: size.width, height: size.height))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if switchRect.insetBy(dx: -6, dy: -6).contains(point) {
            onToggle(!isOn)
            return
        }
        onExpand()   // เมนูวาดใหม่ในที่ ไม่ปิด
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

/// แถวคำสั่ง: ข้อความซ้าย ไอคอนขวา (ไม่มีไอคอนหน้าและไม่มีคีย์ลัด) กดแล้วปิดเมนูและทำงาน
final class MenuActionRow: MenuRowView {
    private let title: String
    private let symbolName: String
    private let action: () -> Void
    private var hovered = false
    private static let font = NSFont.systemFont(ofSize: 13)

    init(title: String, symbolName: String, action: @escaping () -> Void) {
        self.title = title
        self.symbolName = symbolName
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var preferredWidth: CGFloat {
        let width = (title as NSString).size(withAttributes: [.font: Self.font]).width
        return 14 + width + 16 + 20 + 16
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6)
            Skin.accent.withAlphaComponent(0.18).setFill()
            pill.fill()
        }
        (title as NSString).draw(
            at: NSPoint(x: 14, y: bounds.midY - 8),
            withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68)])
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
        if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            icon.isTemplate = false
            let size = icon.size
            icon.draw(in: NSRect(x: bounds.maxX - 16 - size.width, y: bounds.midY - size.height / 2,
                                 width: size.width, height: size.height))
        }
    }

    override func mouseDown(with event: NSEvent) {
        MenuPanel.shared.dismiss()
        DispatchQueue.main.async { self.action() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

// MARK: - แถบสถานะระบบ: CPU · RAM · SSD บนเมนูบาร์ ------------------------------

/// ช่องละค่า ความกว้างคงที่ — ตัวเลขเปลี่ยนแล้วช่องไม่ขยับ พื้นช่องเติมสีตาม % ให้เห็นระดับได้ทันที
final class MonitorCellsView: NSView {
    struct Cell { var symbol: String; var percent: Int }
    var cells: [Cell] = [] { didSet { needsDisplay = true } }

    static let cellWidth: CGFloat = 60   // ไอคอน + "100%" ไม่ชนกัน
    static let cellHeight: CGFloat = 18
    static let gap: CGFloat = 4
    static let inset: CGFloat = 4

    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return inset * 2 + CGFloat(count) * cellWidth + CGFloat(count - 1) * gap
    }

    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
    private static var iconCache: [String: NSImage] = [:]

    private static func icon(_ name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfiguration)
        image?.isTemplate = false
        if let image { iconCache[name] = image }
        return image
    }

    /// ให้คลิกทะลุไปที่ปุ่มของ status item เพื่อเปิดเมนูรายละเอียด
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - Self.cellHeight) / 2
        for (index, cell) in cells.enumerated() {
            let x = Self.inset + CGFloat(index) * (Self.cellWidth + Self.gap)
            let rect = NSRect(x: x, y: y, width: Self.cellWidth, height: Self.cellHeight)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)

            // พื้นช่อง
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            shape.fill()

            // แถบสัดส่วนเติมจากซ้ายตาม % — สีเปลี่ยนตามระดับ
            let level = max(0, min(100, cell.percent))
            let tint: NSColor = level >= 85 ? .systemRed : level >= 70 ? .systemOrange : Skin.accent
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            tint.withAlphaComponent(0.28).setFill()
            NSRect(x: rect.minX, y: rect.minY,
                   width: rect.width * CGFloat(level) / 100, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()

            // ไอคอนซ้าย ตัวเลขขวา — ตัวเลขชิดขวาเสมอ ช่องจึงไม่ขยับ
            if let icon = Self.icon(cell.symbol) {
                let size = icon.size
                icon.draw(in: NSRect(x: rect.minX + 5, y: rect.midY - size.height / 2,
                                     width: size.width, height: size.height))
            }
            let value = NSAttributedString(string: "\(level)%", attributes: [
                .font: Self.valueFont, .foregroundColor: level >= 85 ? NSColor.systemRed : NSColor.labelColor])
            let valueSize = value.size()
            value.draw(at: NSPoint(x: rect.maxX - 5 - valueSize.width, y: rect.midY - valueSize.height / 2))
        }
    }
}

/// status item ตัวที่สองทางซ้ายไอคอน Deft แสดงช่อง CPU · RAM · SSD คลิกแล้วเห็นรายละเอียด
/// อ่านค่าจาก Mach โดยตรง ไม่ต้อง spawn โปรเซสและไม่ต้องขอสิทธิ์
final class SystemMonitor: NSObject {
    static let shared = SystemMonitor()

    struct Sample {
        var cpu: Double = 0                       // 0–100
        var ramUsed: UInt64 = 0, ramTotal: UInt64 = 0
        var diskBusy: Double = 0                  // 0–100 สัดส่วนเวลาที่ดิสก์ยุ่ง (แบบ iostat %util)
        var readRate: Double = 0, writeRate: Double = 0   // bytes/s
        var diskUsed: Int64 = 0, diskTotal: Int64 = 0     // ความจุ ใช้แค่ในเมนูรายละเอียด
    }
    private(set) var sample = Sample()

    private var item: NSStatusItem?
    private let cellsView = MonitorCellsView(frame: .zero)
    private var timer: Timer?
    private var lastCPU: (idle: UInt64, total: UInt64)?
    /// สถิติดิสก์รอบก่อน แยกตามไดรฟ์ (registry id) — เอาตัวที่ยุ่งที่สุดมาโชว์
    private var lastDisk: (perDrive: [UInt64: UInt64], read: UInt64, write: UInt64, at: CFAbsoluteTime)?
    private static let interval: TimeInterval = 2.0

    func refresh() {
        if Config.monitorAny { start() } else { stop() }
        if item != nil { layout(); tick() }   // เปลี่ยนชุดที่โชว์แล้ววาดใหม่ทันที
    }

    /// ความกว้างคงที่ตามจำนวนช่องที่เปิด ไม่ขึ้นกับตัวเลขข้างใน
    private func layout() {
        guard let item, let button = item.button else { return }
        let count = [Config.monitorCPU, Config.monitorRAM, Config.monitorSSD].filter { $0 }.count
        item.length = MonitorCellsView.width(for: count)
        cellsView.frame = button.bounds
        cellsView.autoresizingMask = [.width, .height]
    }

    private func start() {
        if item == nil {
            let created = NSStatusBar.system.statusItem(withLength: 0)
            created.autosaveName = "DeftSystemMonitor"
            created.button?.title = ""
            created.button?.addSubview(cellsView)
            created.button?.target = self
            created.button?.action = #selector(toggleDetails)
            created.button?.sendAction(on: [.leftMouseDown])
            item = created
            layout()
        }
        guard timer == nil else { return }
        lastCPU = nil
        lastDisk = nil
        tick()
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    // MARK: อ่านค่า

    private func tick() {
        var next = Sample()

        if Config.monitorCPU, let now = Self.cpuTicks() {
            if let last = lastCPU, now.total > last.total {
                let busy = Double((now.total - last.total) - (now.idle - last.idle))
                next.cpu = min(100, max(0, busy / Double(now.total - last.total) * 100))
            } else {
                next.cpu = sample.cpu
            }
            lastCPU = now
        }

        if Config.monitorRAM {
            let memory = Self.memory()
            next.ramUsed = memory.used
            next.ramTotal = memory.total
        }

        if Config.monitorSSD {
            let disk = Self.disk()
            next.diskUsed = disk.used
            next.diskTotal = disk.total
            if let stats = Self.diskStats() {
                let at = CFAbsoluteTimeGetCurrent()
                if let last = lastDisk, at > last.at {
                    let seconds = at - last.at
                    // busy% ของไดรฟ์ที่ยุ่งที่สุด (รวมทุกไดรฟ์จะเกิน 100 ตอนมีดิสก์นอกหลายตัว)
                    var busiest: Double = 0
                    for (id, nanos) in stats.perDrive {
                        guard let before = last.perDrive[id], nanos >= before else { continue }
                        busiest = max(busiest, Double(nanos - before) / (seconds * 1_000_000_000) * 100)
                    }
                    next.diskBusy = min(100, busiest)
                    next.readRate = Double(stats.read &- last.read) / seconds
                    next.writeRate = Double(stats.write &- last.write) / seconds
                } else {
                    next.diskBusy = sample.diskBusy
                }
                lastDisk = (stats.perDrive, stats.read, stats.write, at)
            }
        }

        sample = next
        cellsView.cells = cells()
    }

    /// ticks สะสมของ CPU ทุกคอร์รวมกัน (user+system+idle+nice)
    private static func cpuTicks() -> (idle: UInt64, total: UInt64)? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (idle, user + system + idle + nice)
    }

    /// "Memory Used" แบบเดียวกับ Activity Monitor = app memory + wired + compressed
    private static func memory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(max(0, Int64(stats.internal_page_count) - Int64(stats.purgeable_count)))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    /// พื้นที่ดิสก์ของ volume ระบบ ใช้ค่า "important usage" ให้ตรงกับที่ Finder โชว์
    private static func disk() -> (used: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                              .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return (0, 0) }
        return (max(0, Int64(total) - available), Int64(total))
    }

    /// สถิติสะสมจาก IOBlockStorageDriver ของทุกไดรฟ์ — ตัวเดียวกับที่ iostat ใช้
    /// เวลาอ่าน+เขียนสะสม (นาโนวินาที) ต่อไดรฟ์ และ bytes อ่าน/เขียนรวม
    private static func diskStats() -> (perDrive: [UInt64: UInt64], read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var perDrive: [UInt64: UInt64] = [:]
        var read: UInt64 = 0, write: UInt64 = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let stats = dictionary["Statistics"] as? [String: Any] else { continue }
            func value(_ key: String) -> UInt64 { (stats[key] as? NSNumber)?.uint64Value ?? 0 }
            perDrive[id] = value("Total Time (Read)") + value("Total Time (Write)")
            read += value("Bytes (Read)")
            write += value("Bytes (Write)")
        }
        return (perDrive, read, write)
    }

    // MARK: แสดงผล

    private static func rate(_ bytesPerSecond: Double) -> String {
        let mb = bytesPerSecond / 1_048_576
        if mb < 0.1 { return "0 MB/s" }
        return mb < 10 ? String(format: "%.1f MB/s", mb) : "\(Int(mb.rounded())) MB/s"
    }

    private static func percent(_ used: some BinaryInteger, _ total: some BinaryInteger) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(used) / Double(total) * 100).rounded())
    }

    private static func gigabytes(_ bytes: some BinaryInteger) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    private func cells() -> [MonitorCellsView.Cell] {
        var result: [MonitorCellsView.Cell] = []
        if Config.monitorCPU { result.append(.init(symbol: "cpu", percent: Int(sample.cpu.rounded()))) }
        if Config.monitorRAM { result.append(.init(symbol: "memorychip", percent: Self.percent(sample.ramUsed, sample.ramTotal))) }
        if Config.monitorSSD { result.append(.init(symbol: "internaldrive", percent: Int(sample.diskBusy.rounded()))) }
        return result
    }

    // MARK: เมนูรายละเอียด

    /// คลิกตัวเลข = เมนูกระจกรายละเอียด (แผ่นเดียวกับเมนูหลัก ใช้สลับกัน)
    @objc private func toggleDetails() {
        let panel = MenuPanel.shared
        if panel.isVisible || CFAbsoluteTimeGetCurrent() - panel.dismissedAt < 0.25 {
            panel.dismiss()
            return
        }
        guard let button = item?.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let s = sample
        var rows: [MenuRowView] = []
        if Config.monitorCPU { rows.append(MenuNoteRow("CPU  \(Int(s.cpu.rounded()))%")) }
        if Config.monitorRAM {
            rows.append(MenuNoteRow("RAM  \(Self.gigabytes(s.ramUsed)) / \(Self.gigabytes(s.ramTotal))  (\(Self.percent(s.ramUsed, s.ramTotal))%)"))
        }
        if Config.monitorSSD {
            rows.append(MenuNoteRow("SSD  busy \(Int(s.diskBusy.rounded()))%   ↓ \(Self.rate(s.readRate))   ↑ \(Self.rate(s.writeRate))"))
            rows.append(MenuNoteRow("       used \(Self.gigabytes(s.diskUsed)) / \(Self.gigabytes(s.diskTotal))  (\(Self.percent(s.diskUsed, s.diskTotal))%)"))
        }
        rows.append(MenuSeparatorRow())
        rows.append(MenuActionRow(title: "Open Activity Monitor", symbolName: "chart.bar.xaxis") { [weak self] in
            self?.openActivityMonitor()
        })
        rows.append(MenuActionRow(title: "Hide all from the menu bar", symbolName: "eye.slash") { [weak self] in
            self?.hideMonitor()
        })
        panel.present(rows: rows, below: anchor, on: screen)
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func hideMonitor() {
        MasterSwitch.monitorCPU.set(false)
        MasterSwitch.monitorRAM.set(false)
        MasterSwitch.monitorSSD.set(false)
        AppDelegate.shared?.refreshMenu()
    }
}

// MARK: - ข้อมูลร้านและเซิร์ฟเวอร์ (แก้ที่เดียว) ----------------------------------

/// ค่าที่ต้องเปลี่ยนก่อนวางขาย — ทุกอย่างที่ชี้ออกนอกแอปรวมอยู่ตรงนี้
enum Sales {
    /// ไฟล์ JSON บอกรุ่นล่าสุด: {"version":"4.1","build":5,"url":"https://…/Deft-4.1.dmg","notes":"…"}
    static let updateFeed = URL(string: "https://github.com/ninjait07/deft/releases/latest/download/appcast.json")!
    /// PromptPay QR (payload มาตรฐาน EMVCo ที่ถอดจาก QR ของธนาคาร) — สแกนได้จากแอปธนาคารไทยทุกแอป
    static let promptPayPayload = "00020101021129390016A000000677010111031508898400069126953037645802TH6304C60B"
    static let promptPayName = "นนท์ บรรณวัฒน์"
    /// หน้า GitHub Sponsors สำหรับผู้ใช้ต่างชาติ (เปลี่ยนเป็นของจริงเมื่อเปิดแล้ว)
    static let sponsorsURL = URL(string: "https://github.com/sponsors/ninjait07")!
}

// MARK: - Donate --------------------------------------------------------------

/// หน้าต่างบริจาค: QR PromptPay สร้างสดจาก payload (คมทุกขนาด) + ปุ่ม GitHub Sponsors
final class DonateWindow: NSWindow {
    static let shared = DonateWindow()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 540),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        let icon = NSImageView(image: Brand.appIconImage(pixels: 48))
        let heading = NSTextField(labelWithString: "Deft is free")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let sub = NSTextField(wrappingLabelWithString: "If it makes your Mac feel like home, a small tip keeps it going. Thank you!")
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor
        sub.alignment = .center
        sub.preferredMaxLayoutWidth = 300

        let qr = NSImageView(image: Self.qrImage(Sales.promptPayPayload, side: 220))
        qr.imageScaling = .scaleNone
        qr.wantsLayer = true
        qr.layer?.backgroundColor = NSColor.white.cgColor
        qr.layer?.cornerRadius = 12
        let promptPay = NSTextField(labelWithString: "PromptPay  ·  " + Sales.promptPayName)
        promptPay.font = .systemFont(ofSize: 13, weight: .medium)
        let hint = NSTextField(labelWithString: "Scan with any Thai banking app")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        // ปุ่ม GitHub Sponsors — สีชมพูแบรนด์ Sponsors + หัวใจ ให้เด่นชัด
        let sponsors = NSButton(title: "", target: self, action: #selector(openSponsors))
        sponsors.bezelStyle = .rounded
        sponsors.controlSize = .large
        sponsors.bezelColor = NSColor(calibratedRed: 0.75, green: 0.22, blue: 0.54, alpha: 1)
        sponsors.contentTintColor = .white
        sponsors.imagePosition = .imageLeading
        sponsors.imageHugsTitle = true
        if let heart = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)) {
            sponsors.image = heart
        }
        sponsors.attributedTitle = NSAttributedString(string: "  Sponsor on GitHub", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, heading, sub, qr, promptPay, hint, sponsors, close])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(18, after: sub)
        stack.setCustomSpacing(18, after: hint)
        stack.setCustomSpacing(22, after: sponsors)
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 24, bottom: 24, right: 24)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 540))
        container.autoresizingMask = [.width, .height]
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            qr.widthAnchor.constraint(equalToConstant: 244),
            qr.heightAnchor.constraint(equalToConstant: 244),
        ])
        contentView = GlassBackdrop.wrap(container, cornerRadius: 22, frosted: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }   // Esc = ปิด
    }
    @objc private func closeWindow() { close() }

    func present() {
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeKey()   // ให้กระจกเรนเดอร์แบบ active ไม่ขุ่น
        GlassBackdrop.adaptToBackdrop(self)
    }

    @objc private func openSponsors() { NSWorkspace.shared.open(Sales.sponsorsURL) }

    /// สร้าง QR จากข้อความด้วย CoreImage แล้วขยายแบบไม่เบลอ
    static func qrImage(_ payload: String, side: CGFloat) -> NSImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return NSImage(size: NSSize(width: side, height: side)) }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - คู่มือการใช้งาน (Manual) --------------------------------------------

/// หน้าต่างคู่มือ Liquid Glass — อธิบายทุกฟังก์ชัน สลับอังกฤษ/ไทยได้
final class ManualWindow: NSWindow {
    static let shared = ManualWindow()
    private var thai = false
    private let stack = NSStackView()
    private let langButton = NSButton()

    /// (หัวข้อ EN, หัวข้อ TH, [ (ชื่อฟังก์ชัน, คำอธิบาย EN, คำอธิบาย TH) ])
    private typealias Item = (name: String, en: String, th: String)
    private typealias Section = (en: String, th: String, items: [Item])
    private static let sections: [Section] = [
        ("Windows", "หน้าต่าง", [
            ("Windows Snap",
             "Drag a window to a screen edge or corner to snap it to half, a quarter, or full screen. Includes Snap Layouts, Snap Assist, shared resize dividers, and Win+Arrow keys.",
             "ลากหน้าต่างไปชนขอบหรือมุมจอเพื่อจัดเป็นครึ่งจอ เสี้ยวจอ หรือเต็มจอ มีแถบเลย์เอาต์ ตัวช่วยเลือกหน้าต่างอีกฝั่ง เส้นแบ่งปรับขนาดสองหน้าต่างพร้อมกัน เขย่าหน้าต่างเพื่อย่ออันอื่น และปุ่ม Win+ลูกศร"),
            ("Live Preview",
             "Shows real, moving thumbnails of your windows in the switcher, Snap Assist, and when hovering the Dock. Needs Screen Recording permission.",
             "แสดงภาพตัวอย่างหน้าต่างจริงแบบเคลื่อนไหวในตัวสลับหน้าต่าง ตัวช่วย Snap และตอนชี้ที่ Dock ต้องเปิดสิทธิ์ Screen Recording"),
        ]),
        ("Keyboard", "คีย์บอร์ด", [
            ("Windows Shortcuts",
             "Makes the keyboard behave like Windows: Ctrl works as Command, plus the Win key, F-keys, Home/End, the language switch key, and Explorer keys in Finder. Off = normal Mac shortcuts.",
             "ทำให้คีย์บอร์ดทำงานแบบ Windows: Ctrl ทำหน้าที่เป็น Command มีปุ่ม Win ปุ่ม F ปุ่ม Home/End ปุ่มเปลี่ยนภาษา และปุ่ม Explorer ใน Finder ปิด = ใช้คีย์ลัดแบบ Mac ปกติ"),
            ("Auto-Detect Keyboard",
             "Automatically follows whichever keyboard you type on — a Windows keyboard gets Windows shortcuts, a Mac keyboard gets Mac ones. Needs Input Monitoring.",
             "ปรับตามคีย์บอร์ดที่คุณพิมพ์ล่าสุดอัตโนมัติ คีย์บอร์ด Windows ได้คีย์ลัดแบบ Windows คีย์บอร์ด Mac ได้แบบ Mac ต้องเปิดสิทธิ์ Input Monitoring"),
            ("Convert Layout",
             "Typed on the wrong layout (e.g. \"l;ylfu\" instead of \"สวัสดี\")? Select the text and double-tap Shift — Deft converts it (Thai↔English) and switches the input language. Works in any app. With nothing selected, it converts the last word you typed.",
             "พิมพ์ผิดแป้น (เช่น \"l;ylfu\" แทน \"สวัสดี\") ใช่ไหม? คลุมดำข้อความนั้นแล้วกด Shift สองครั้ง Deft จะแปลงให้ (ไทย↔อังกฤษ) พร้อมสลับภาษาให้ ใช้ได้ทุกแอป ถ้าไม่ได้เลือกอะไร จะแปลงคำล่าสุดที่พิมพ์ให้แทน"),
            ("Language Switch Key",
             "Pick a Windows-style key to switch the input language: ` (~), Alt+Shift, Ctrl+Shift, or Win+Space. Works while Windows Shortcuts is on.",
             "เลือกปุ่มเปลี่ยนภาษาแบบ Windows: ` (~), Alt+Shift, Ctrl+Shift หรือ Win+Space ใช้ได้ตอนเปิด Windows Shortcuts"),
            ("Clean Keyboard",
             "Locks every key, Fn, and media button so you can wipe the keyboard safely. Turn it off from the menu or the floating Unlock button.",
             "ล็อกทุกปุ่ม รวมปุ่ม Fn และปุ่มมีเดีย เพื่อเช็ดทำความสะอาดคีย์บอร์ด ปิดได้จากเมนูหรือปุ่ม Unlock ที่ลอยอยู่"),
        ]),
        ("Mouse", "เมาส์", [
            ("Mouse Natural Scroll",
             "Scroll direction for the mouse. On = Mac direction, Off = Windows direction. Independent from the trackpad.",
             "ทิศทางการเลื่อนของเมาส์ เปิด = แบบ Mac ปิด = แบบ Windows แยกอิสระจากแทร็กแพด"),
            ("Trackpad Natural Scroll",
             "Scroll direction for the trackpad, independent from the mouse.",
             "ทิศทางการเลื่อนของแทร็กแพด แยกอิสระจากเมาส์"),
            ("Mouse Side Buttons",
             "Side buttons 4 and 5 act as Back and Forward (Cmd+[ / Cmd+]).",
             "ปุ่มข้าง 4 และ 5 ทำหน้าที่ย้อนกลับ/ไปข้างหน้า (Cmd+[ / Cmd+])"),
        ]),
        ("System Monitor", "มอนิเตอร์ระบบ", [
            ("CPU · RAM · SSD",
             "Shows live CPU load, memory in use, and disk activity right in the menu bar. Toggle each independently; click a cell for details.",
             "แสดงการใช้งาน CPU หน่วยความจำที่ใช้ และการทำงานของดิสก์สด ๆ บนแถบเมนู เปิด/ปิดแยกกันได้ คลิกที่ช่องเพื่อดูรายละเอียด"),
        ]),
        ("Display", "จอภาพ", [
            ("Per-display controls",
             "For each display you can change resolution, refresh rate, rotation, set it as the main display, or power it off (Deft remembers powered-off displays across restarts).",
             "แต่ละจอปรับความละเอียด อัตรารีเฟรช การหมุน ตั้งเป็นจอหลัก หรือสั่งปิดจอได้ (Deft จำจอที่ปิดไว้ข้ามการรีสตาร์ต)"),
            ("Arrange Displays",
             "Open the Arrange Displays window to drag displays into position with edge snapping, rotate a selected display, and set the main one.",
             "เปิดหน้าต่าง Arrange Displays เพื่อลากจัดตำแหน่งจอแบบขอบดูดเข้าหากัน หมุนจอที่เลือก และตั้งจอหลัก"),
        ]),
        ("Window Switcher", "ตัวสลับหน้าต่าง", [
            ("Alt+Tab / Cmd+Tab",
             "In Windows mode, Alt+Tab (Option+Tab) cycles through windows. In Mac mode, Cmd+Tab does it when Live Preview is on. Hold the key and tap Tab to move; release to select.",
             "โหมด Windows ใช้ Alt+Tab (Option+Tab) สลับหน้าต่าง โหมด Mac ใช้ Cmd+Tab เมื่อเปิด Live Preview กดปุ่มค้างแล้วแตะ Tab เพื่อเลื่อน ปล่อยปุ่มเพื่อเลือก"),
        ]),
        ("System", "ระบบ", [
            ("Open at Login",
             "Starts Deft automatically when you log in. Needs macOS 13 or later.",
             "เปิด Deft อัตโนมัติเมื่อล็อกอิน ต้องใช้ macOS 13 ขึ้นไป"),
            ("Donate",
             "Deft is free. If it makes your Mac feel like home, a small tip via PromptPay or GitHub Sponsors keeps it going.",
             "Deft แจกฟรี ถ้าถูกใจ สนับสนุนเล็ก ๆ น้อย ๆ ผ่าน PromptPay หรือ GitHub Sponsors ได้ เพื่อให้พัฒนาต่อ"),
        ]),
    ]

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 620))
        container.autoresizingMask = [.width, .height]

        let heading = NSTextField(labelWithString: "Manual")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false

        langButton.title = "ภาษาไทย"
        langButton.bezelStyle = .rounded
        langButton.target = self
        langButton.action = #selector(toggleLang)
        langButton.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\r"
        close.translatesAutoresizingMaskIntoConstraints = false

        // การ์ดกระจกฝ้าครอบเนื้อหา ให้ตัวหนังสืออ่านง่าย (ขอบนอกยังเป็นกระจกใส)
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.appearance = NSAppearance(named: .darkAqua)
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.drawsBackground = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        container.addSubview(heading)
        container.addSubview(langButton)
        container.addSubview(card)
        container.addSubview(scroll)
        container.addSubview(close)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            langButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            langButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
            card.topAnchor.constraint(equalTo: scroll.topAnchor),
            card.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            close.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            close.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        contentView = GlassBackdrop.wrap(container, cornerRadius: 22, frosted: false)
        rebuild()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }
    @objc private func closeWindow() { close() }
    @objc private func toggleLang() {
        thai.toggle()
        langButton.title = thai ? "English" : "ภาษาไทย"
        rebuild()
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let bodyWidth: CGFloat = 540 - 18 * 2 - 16 * 2 - 16   // เผื่อขอบการ์ดและ scroller
        for section in Self.sections {
            let head = NSTextField(labelWithString: thai ? section.th : section.en)
            head.font = .systemFont(ofSize: 14, weight: .bold)
            head.textColor = .labelColor
            stack.addArrangedSubview(head)
            stack.setCustomSpacing(8, after: head)
            for item in section.items {
                let name = NSTextField(labelWithString: item.name)
                name.font = .systemFont(ofSize: 13, weight: .semibold)
                name.textColor = Skin.accent
                stack.addArrangedSubview(name)
                stack.setCustomSpacing(2, after: name)
                let desc = NSTextField(wrappingLabelWithString: thai ? item.th : item.en)
                desc.font = .systemFont(ofSize: 12)
                desc.textColor = .secondaryLabelColor
                desc.preferredMaxLayoutWidth = bodyWidth
                desc.translatesAutoresizingMaskIntoConstraints = false
                desc.widthAnchor.constraint(equalToConstant: bodyWidth).isActive = true
                stack.addArrangedSubview(desc)
                stack.setCustomSpacing(12, after: desc)
            }
        }
    }

    func present() {
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeKey()
        GlassBackdrop.adaptToBackdrop(self)
    }
}

/// view พิกัดกลับหัว (y ลง) สำหรับ documentView ของ scroll view
final class FlippedView: NSView { override var isFlipped: Bool { true } }

// MARK: - หน้าขอสิทธิ์ (onboarding) --------------------------------------------

/// รวมสิทธิ์ทั้ง 3 ไว้หน้าเดียว มีสถานะสด ๆ และปุ่มเปิดหน้าตั้งค่าที่ถูกต้อง
/// แทนการเด้ง alert ทีละอัน — จุดที่ทำให้ผู้ใช้ใหม่คิดว่าแอปพังมากที่สุด
final class PermissionsWindow: NSWindow {
    static let shared = PermissionsWindow()

    struct Permission {
        let title: String
        let why: String
        let settingsURL: String
        let granted: () -> Bool
        let required: Bool
        let relaunchAfter: Bool
    }

    static let all: [Permission] = [
        Permission(title: "Accessibility",
                   why: "Required. Moves windows, reads which window is under the cursor, and translates keys.",
                   settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                   granted: { AXIsProcessTrusted() }, required: true, relaunchAfter: false),
        Permission(title: "Screen Recording",
                   why: "For Live Preview only — real window pictures in the Cmd+Tab switcher, Snap Assist and Dock hover. Nothing is recorded.",
                   settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                   granted: { Thumbnails.isAuthorized }, required: false, relaunchAfter: true),
        Permission(title: "Input Monitoring",
                   why: "For Auto-Detect Keyboard only — tells a Windows keyboard from a Mac one.",
                   settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                   granted: { KeyboardWatch.shared.accessGranted }, required: false, relaunchAfter: false),
    ]

    /// สิทธิ์ที่ "ควรมี" ตามฟีเจอร์ที่เปิดอยู่ แต่ยังไม่ได้
    static var missing: [Permission] {
        all.filter { permission in
            guard !permission.granted() else { return false }
            switch permission.title {
            case "Screen Recording":  return Config.windowPreviews
            case "Input Monitoring":  return Config.perKeyboard
            default:                  return true
            }
        }
    }

    private var statusViews: [NSTextField] = []
    private var timer: Timer?
    private let relaunchNote = NSTextField(wrappingLabelWithString: "")
    private let guideNote = NSTextField(wrappingLabelWithString: "")
    private let grantAll = NSButton(title: "Grant all…", target: nil, action: nil)
    /// โหมดเดินทีละสิทธิ์: index ของสิทธิ์ที่กำลังรออยู่ (nil = ไม่ได้อยู่ในโหมด)
    private var guidedIndex: Int?

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Deft needs a few permissions"
        isReleasedWhenClosed = false
        center()

        let heading = NSTextField(labelWithString: "Set up Deft")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString:
            "macOS asks for these once. Tick Deft in each list, then come back here — the status updates by itself.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = 480

        var rows: [NSView] = []
        for (index, permission) in Self.all.enumerated() {
            let name = NSTextField(labelWithString: permission.title + (permission.required ? "  ·  required" : ""))
            name.font = .systemFont(ofSize: 13, weight: .semibold)
            let why = NSTextField(wrappingLabelWithString: permission.why)
            why.font = .systemFont(ofSize: 11)
            why.textColor = .secondaryLabelColor
            why.preferredMaxLayoutWidth = 330
            let text = NSStackView(views: [name, why])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 12, weight: .medium)
            statusViews.append(status)
            let open = NSButton(title: "Open Settings", target: self, action: #selector(openSettings(_:)))
            open.bezelStyle = .rounded
            open.tag = index
            let right = NSStackView(views: [status, open])
            right.orientation = .vertical
            right.alignment = .trailing
            right.spacing = 4
            let row = NSStackView(views: [text, NSView(), right])
            row.spacing = 12
            row.alignment = .top
            rows.append(row)
            if index < Self.all.count - 1 {
                let line = NSBox()
                line.boxType = .separator
                rows.append(line)
            }
        }

        relaunchNote.font = .systemFont(ofSize: 11)
        relaunchNote.textColor = .systemOrange
        relaunchNote.preferredMaxLayoutWidth = 480

        guideNote.font = .systemFont(ofSize: 12, weight: .medium)
        guideNote.textColor = Skin.accent
        guideNote.preferredMaxLayoutWidth = 480

        let relaunch = NSButton(title: "Relaunch Deft", target: self, action: #selector(relaunch))
        relaunch.bezelStyle = .rounded
        grantAll.target = self
        grantAll.action = #selector(startGuided)
        grantAll.bezelStyle = .rounded
        grantAll.keyEquivalent = "\r"
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        let buttons = NSStackView(views: [relaunch, NSView(), grantAll, done])
        buttons.spacing = 8

        let stack = NSStackView(views: [heading, intro] + rows + [guideNote, relaunchNote, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView = NSView()
        contentView?.addSubview(stack)
        var constraints = [
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ]
        for row in rows { constraints.append(row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)) }
        NSLayoutConstraint.activate(constraints)
    }

    func present() {
        refreshStatuses()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refreshStatuses() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// สิทธิ์ที่ยังขาดตามฟีเจอร์ที่เปิดอยู่ (index ใน `all`)
    private var missingIndices: [Int] {
        Self.all.indices.filter { index in Self.missing.contains { $0.title == Self.all[index].title } }
    }

    private func refreshStatuses() {
        var needsRelaunch = false
        for (index, permission) in Self.all.enumerated() {
            let ok = permission.granted()
            let waiting = guidedIndex == index && !ok
            statusViews[index].stringValue = ok ? "✓ Granted" : (waiting ? "← tick Deft in the list" : "Not granted")
            statusViews[index].textColor = ok ? .systemGreen : (waiting ? Skin.accent : .systemOrange)
            if permission.relaunchAfter && ok && !Thumbnails.isUsable && Config.windowPreviews { needsRelaunch = true }
        }
        relaunchNote.stringValue = needsRelaunch
            ? "Screen Recording was just granted — relaunch Deft once to start using it."
            : ""
        grantAll.isHidden = missingIndices.isEmpty
        // โหมดเดินทีละสิทธิ์: ติ๊กอันปัจจุบันเสร็จ → เปิดอันถัดไปให้เอง
        if let current = guidedIndex, Self.all[current].granted() {
            advanceGuided(after: current)
        }
    }

    /// กดปุ่มเดียว: ขอสิทธิ์แรกที่ยังขาด แล้วขออันถัดไปเองเมื่อผู้ใช้ติ๊กเสร็จ
    @objc private func startGuided() {
        guard let first = missingIndices.first else { return }
        request(first)
    }

    private func advanceGuided(after index: Int) {
        if let next = missingIndices.first(where: { $0 > index }) {
            request(next)
        } else {
            guidedIndex = nil
            guideNote.stringValue = "All set. " + (relaunchNote.stringValue.isEmpty ? "You can close this window." : "Relaunch Deft to finish.")
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
        }
    }

    /// เด้งหน้าต่างขอสิทธิ์ของระบบ + เปิดหน้าตั้งค่าหมวดที่ถูกต้องพร้อมกัน
    private func request(_ index: Int) {
        let permission = Self.all[index]
        guidedIndex = index
        guideNote.stringValue = "Step \(missingIndices.firstIndex(of: index).map { $0 + 1 } ?? 1) of \(missingIndices.count): tick Deft under \(permission.title), then come back — the next one opens by itself."
        if permission.title == "Accessibility" {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if permission.title == "Screen Recording" { Thumbnails.requestAccess() }
        if permission.title == "Input Monitoring" { KeyboardWatch.shared.requestAccess() }
        if let url = URL(string: permission.settingsURL) { NSWorkspace.shared.open(url) }
        refreshStatuses()
    }

    @objc private func openSettings(_ sender: NSButton) {
        request(sender.tag)
    }

    @objc private func relaunch() { AppDelegate.shared?.relaunch() }

    @objc private func finish() {
        timer?.invalidate()
        timer = nil
        guidedIndex = nil
        guideNote.stringValue = ""
        close()
        AppDelegate.shared?.refreshMenu()
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        super.close()
    }
}

// MARK: - ตัวเช็คอัปเดต (JSON เล็ก ๆ ไม่ต้องใช้ Sparkle) -----------------------------

enum Updater {
    struct Feed: Decodable {
        let version: String
        let build: Int
        let url: String
        let notes: String?
    }

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private static var skippedBuild: Int {
        get { UserDefaults.standard.integer(forKey: "updateSkippedBuild") }
        set { UserDefaults.standard.set(newValue, forKey: "updateSkippedBuild") }
    }
    private static var timer: Timer?

    /// เช็คตอนเปิดแอป (หน่วง 10 วิ) แล้วทุก 24 ชั่วโมง — เงียบถ้าไม่มีอะไรใหม่
    static func scheduleAutomatic() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { check(manual: false) }
        let t = Timer(timeInterval: 24 * 3600, repeats: true) { _ in check(manual: false) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    static func check(manual: Bool) {
        var request = URLRequest(url: Sales.updateFeed, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data, error == nil, let feed = try? JSONDecoder().decode(Feed.self, from: data) else {
                    if manual { notify("Could not check for updates", "Try again later.") }
                    return
                }
                guard feed.build > currentBuild else {
                    if manual { notify("You're up to date", "Deft \(currentVersion) is the latest version.") }
                    return
                }
                if !manual && feed.build == skippedBuild { return }
                offer(feed)
            }
        }.resume()
    }

    private static func offer(_ feed: Feed) {
        let alert = NSAlert()
        alert.messageText = "Deft \(feed.version) is available"
        alert.informativeText = "You have \(currentVersion)." + (feed.notes.map { "\n\n" + $0 } ?? "")
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: feed.url) { NSWorkspace.shared.open(url) }
        case .alertThirdButtonReturn:
            skippedBuild = feed.build
        default:
            break
        }
    }

    private static func notify(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - เมนูกระจก: แถวเสริมและหน้าต่างเมนู (แทน NSMenu) ------------------------

/// เส้นคั่นระหว่างหมวด
/// แถวเครดิตล่างสุด — ธงไทยเล็ก ๆ กับชื่อผู้สร้าง กดไม่ได้
final class MenuFooterRow: MenuRowView {
    private let text: String
    private let onManual: () -> Void
    private var hovered = false
    private static let font = NSFont.systemFont(ofSize: 11)
    private static let manualFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let manualTitle = "Manual"
    init(_ text: String, onManual: @escaping () -> Void) {
        self.text = text
        self.onManual = onManual
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var preferredWidth: CGFloat { 240 }

    /// กรอบปุ่ม Manual ชิดขวา
    private var manualRect: NSRect {
        let tw = (Self.manualTitle as NSString).size(withAttributes: [.font: Self.manualFont]).width
        let w = 12 + 14 + 5 + tw + 12
        return NSRect(x: bounds.maxX - 14 - w, y: bounds.midY - 12, width: w, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        // ธงชาติไทย + เครดิต ชิดซ้าย
        let flagW: CGFloat = 20, flagH: CGFloat = 13
        var x: CGFloat = 14
        let fy = bounds.midY - flagH / 2
        let unit = flagH / 6
        let red = NSColor(calibratedRed: 0.643, green: 0.106, blue: 0.204, alpha: 1)
        let blue = NSColor(calibratedRed: 0.180, green: 0.216, blue: 0.427, alpha: 1)
        let bands: [(CGFloat, NSColor)] = [(unit, red), (unit, .white), (unit*2, blue), (unit, .white), (unit, red)]
        var by = fy + flagH
        let clip = NSBezierPath(roundedRect: NSRect(x: x, y: fy, width: flagW, height: flagH), xRadius: 2, yRadius: 2)
        NSGraphicsContext.saveGraphicsState(); clip.addClip()
        for (bh, col) in bands { by -= bh; col.setFill(); NSRect(x: x, y: by, width: flagW, height: bh).fill() }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.15).setStroke(); clip.lineWidth = 1; clip.stroke()

        x += flagW + 8
        (text as NSString).draw(at: NSPoint(x: x, y: bounds.midY - 7),
                                withAttributes: [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor])

        // ปุ่ม Manual ชิดขวา — เม็ดยาโปร่งมีเส้นขอบ พอชี้ค่อยเติมสี
        let pill = manualRect
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        if hovered { Skin.accent.withAlphaComponent(0.22).setFill(); path.fill() }
        NSColor.labelColor.withAlphaComponent(hovered ? 0.35 : 0.25).setStroke()
        path.lineWidth = 1; path.stroke()
        var ix = pill.minX + 12
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.labelColor]))
        if let icon = NSImage(systemSymbolName: "book", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            icon.isTemplate = false
            let sz = icon.size
            icon.draw(in: NSRect(x: ix, y: pill.midY - sz.height / 2, width: sz.width, height: sz.height))
            ix += 14 + 5
        }
        (Self.manualTitle as NSString).draw(at: NSPoint(x: ix, y: pill.midY - 7),
                                            withAttributes: [.font: Self.manualFont, .foregroundColor: NSColor.labelColor])
    }

    override func mouseDown(with event: NSEvent) {
        guard manualRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        MenuPanel.shared.dismiss()
        DispatchQueue.main.async { self.onManual() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        manualRect.contains(convert(point, from: superview)) ? self : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: manualRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func resize(to width: CGFloat) { super.resize(to: width); updateTrackingAreas() }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

final class MenuSeparatorRow: MenuRowView {
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 9)) }
    required init?(coder: NSCoder) { fatalError() }
    override var preferredWidth: CGFloat { 0 }
    override func draw(_ dirtyRect: NSRect) {}   // เว้นเป็นช่องว่างเฉย ๆ — ใช้การ์ดจางแบ่งกลุ่มแทนเส้นคั่น
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// หัวข้อหมวด — ตัวเล็กสีจาง
final class MenuHeaderLabelRow: MenuRowView {
    private let symbolName: String
    private let fallbackText: String
    private let badge: String?
    init(symbol: String, text: String, badge: String? = nil) {
        self.symbolName = symbol
        self.fallbackText = text
        self.badge = badge
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
    }
    required init?(coder: NSCoder) { fatalError() }
    private static let font = NSFont.systemFont(ofSize: 13, weight: .bold)
    private static let badgeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    override var preferredWidth: CGFloat {
        let title = 14 + 22 + 8 + (fallbackText as NSString).size(withAttributes: [.font: Self.font]).width
        let tail = badge.map { 12 + ($0 as NSString).size(withAttributes: [.font: Self.badgeFont]).width + 14 } ?? 14
        return title + 12 + tail
    }
    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 14
        // ไอคอน + ตัวหนังสือใช้สีเข้ม (labelColor) และหนักเท่ากัน ให้ดูเป็นชุดเดียว
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.labelColor]))
        if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: fallbackText)?
            .withSymbolConfiguration(config) {
            icon.isTemplate = false
            let sz = icon.size
            icon.draw(in: NSRect(x: x, y: bounds.midY - sz.height / 2, width: sz.width, height: sz.height))
            x += 22 + 8
        }
        (fallbackText as NSString).draw(
            at: NSPoint(x: x, y: bounds.midY - 8),
            withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor])

        // ป้ายสถานะชิดขวา เช่น Mac / Windows — เม็ดยาโปร่งมีเส้นขอบ
        if let badge {
            let tw = (badge as NSString).size(withAttributes: [.font: Self.badgeFont]).width
            let pill = NSRect(x: bounds.maxX - 14 - (tw + 18), y: bounds.midY - 9, width: tw + 18, height: 18)
            let path = NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9)
            Skin.accent.withAlphaComponent(0.16).setFill(); path.fill()
            Skin.accent.withAlphaComponent(0.5).setStroke(); path.lineWidth = 1; path.stroke()
            (badge as NSString).draw(at: NSPoint(x: pill.minX + 9, y: pill.midY - 7),
                                     withAttributes: [.font: Self.badgeFont, .foregroundColor: NSColor.labelColor])
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// ข้อความอธิบายบรรทัดเดียว (ไม่กดได้)
final class MenuNoteRow: MenuRowView {
    private let text: String
    private let indent: CGFloat
    private static let font = NSFont.systemFont(ofSize: 12)
    init(_ text: String, indent: CGFloat = 14) {
        self.text = text
        self.indent = indent
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var preferredWidth: CGFloat {
        indent + (text as NSString).size(withAttributes: [.font: Self.font]).width + 14
    }
    override func draw(_ dirtyRect: NSRect) {
        (text as NSString).draw(at: NSPoint(x: indent, y: bounds.midY - 8),
                                withAttributes: [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor])
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// รายการทั่วไป: [ไอคอนซ้าย] ชื่อ … [เครื่องหมายถูก] กดแล้วปิดเมนูและทำงาน
final class MenuItemRow: MenuRowView {
    private let title: String
    private let leadingSymbol: String?
    private let leadingColor: NSColor
    private let checked: Bool
    private let indent: CGFloat
    private let closesMenu: Bool
    private let action: () -> Void
    private var hovered = false
    private static let font = NSFont.systemFont(ofSize: 13)

    init(title: String, leadingSymbol: String? = nil, leadingColor: NSColor = .secondaryLabelColor,
         checked: Bool = false, indent: CGFloat = 0, closesMenu: Bool = true,
         action: @escaping () -> Void) {
        self.title = title
        self.leadingSymbol = leadingSymbol
        self.leadingColor = leadingColor
        self.checked = checked
        self.indent = indent
        self.closesMenu = closesMenu
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var preferredWidth: CGFloat {
        let width = (title as NSString).size(withAttributes: [.font: Self.font]).width
        return 14 + indent + (leadingSymbol != nil ? 22 : 0) + 18 + width + 16 + 30
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6)
            Skin.accent.withAlphaComponent(0.18).setFill()
            pill.fill()
        }
        var x = 14 + indent
        if checked {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.labelColor]))
            if let mark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                mark.isTemplate = false
                let size = mark.size
                mark.draw(in: NSRect(x: x, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
        x += 18
        if let leadingSymbol {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [leadingColor]))
            if let icon = NSImage(systemSymbolName: leadingSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                icon.isTemplate = false
                let size = icon.size
                icon.draw(in: NSRect(x: x, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            }
            x += 22
        }
        (title as NSString).draw(at: NSPoint(x: x, y: bounds.midY - 8),
                                 withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68)])
    }

    override func mouseDown(with event: NSEvent) {
        if closesMenu { MenuPanel.shared.dismiss() }
        DispatchQueue.main.async { self.action() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

/// แถวกางตัวเลือก: [ไอคอน] ชื่อ · ค่าปัจจุบัน … ˅  (ใช้กับความละเอียด/Hz/หมุนจอ/ตำแหน่ง)
final class MenuDisclosureRow: MenuRowView {
    private let title: String
    private let value: String?
    private let symbolName: String
    private let expanded: Bool
    private let indent: CGFloat
    private let onToggle: () -> Void
    private var hovered = false
    private static let font = NSFont.systemFont(ofSize: 13)

    init(title: String, value: String?, symbolName: String, expanded: Bool, indent: CGFloat = 14,
         onToggle: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.symbolName = symbolName
        self.expanded = expanded
        self.indent = indent
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    private var label: String { value.map { title + "  ·  " + $0 } ?? title }

    override var preferredWidth: CGFloat {
        14 + indent + 22 + (label as NSString).size(withAttributes: [.font: Self.font]).width + 16 + 30
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6)
            Skin.accent.withAlphaComponent(0.18).setFill()
            pill.fill()
        }
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
        if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) {
            icon.isTemplate = false
            let size = icon.size
            icon.draw(in: NSRect(x: 14 + indent, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
        }
        (label as NSString).draw(at: NSPoint(x: 14 + indent + 22, y: bounds.midY - 8),
                                 withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.68)])
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
        if let chevron = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                 accessibilityDescription: nil)?.withSymbolConfiguration(chevronConfig) {
            chevron.isTemplate = false
            let size = chevron.size
            chevron.draw(in: NSRect(x: bounds.maxX - size.width - 12, y: bounds.midY - size.height / 2,
                                    width: size.width, height: size.height))
        }
    }

    override func mouseDown(with event: NSEvent) { onToggle() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

/// รายการแถวของเมนู (แทน NSMenu) — populate() เติมแถวลงตรงนี้
final class MenuList {
    private(set) var rows: [MenuRowView] = []
    func addItem(_ row: MenuRowView) { rows.append(row) }
}

/// หน้าต่างเมนูกระจกใต้ไอคอน Deft — Liquid Glass แบบเดียวกับ Cmd+Tab
/// ปิดเมื่อคลิกที่อื่น กด Esc หรือกดไอคอนซ้ำ  ·  แถวที่สับสวิตช์จะวาดใหม่ในที่โดยเมนูไม่ปิด
final class MenuPanel: NSPanel {
    static let shared = MenuPanel()

    private let container = NSView()
    private var sectionCards: [NSView] = []
    private var monitors: [Any] = []
    private(set) var dismissedAt: CFAbsoluteTime = 0
    private static let padding: CGFloat = 8

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        container.wantsLayer = true
        contentView = GlassBackdrop.wrap(container, cornerRadius: 22, frosted: false)   // กระจกใสแบบเดียวกับพาเนลพรีวิว
    }

    override var canBecomeKey: Bool { true }

    /// วางแถวบนลงล่าง ความกว้างเท่ากันทั้งเมนู (แถวที่กว้างสุดเป็นตัวกำหนด)
    private func layout(_ rows: [MenuRowView]) -> NSSize {
        container.subviews.forEach { $0.removeFromSuperview() }
        let width = max(300, rows.map(\.preferredWidth).max() ?? 300)
        var height = Self.padding * 2
        for row in rows { height += row.frame.height }
        container.setFrameSize(NSSize(width: width, height: height))
        var y = height - Self.padding
        for row in rows {
            row.resize(to: width)
            y -= row.frame.height
            row.setFrameOrigin(NSPoint(x: 0, y: y))
        }

        // การ์ดใต้แต่ละหมวด — เริ่มที่หัวหมวด ยาวถึงแถวสุดท้ายก่อนหมวดถัดไป (วางไว้ข้างหลังแถว)
        sectionCards.removeAll()
        let inset: CGFloat = 6
        var i = 0
        while i < rows.count {
            guard rows[i] is MenuHeaderLabelRow else { i += 1; continue }
            var j = i + 1, last = i
            while j < rows.count, !(rows[j] is MenuHeaderLabelRow) {
                if !(rows[j] is MenuSeparatorRow), !(rows[j] is MenuFooterRow) { last = j }
                j += 1
            }
            let topY = rows[i].frame.maxY, botY = rows[last].frame.minY
            let card = NSView(frame: NSRect(x: inset, y: botY - 3,
                                            width: width - inset * 2, height: topY - botY + 6))
            card.wantsLayer = true
            card.layer?.cornerRadius = 12
            card.layer?.borderWidth = 1
            container.addSubview(card)
            sectionCards.append(card)
            i = j
        }
        // แถวจริงวางทับการ์ด
        for row in rows { container.addSubview(row) }
        tintCards()
        return NSSize(width: width, height: height)
    }

    /// ย้อมสีการ์ดตามพื้นหลัง: พื้นสว่าง = การ์ดเข้ม  ·  พื้นมืด = การ์ดสว่าง (ให้ขุ่นเห็นชัดทั้งสองแบบ)
    private func tintCards() {
        let light = (Thumbnails.backdropLuminance(below: self) ?? 0) > 0.5
        let fill = light ? NSColor.black.withAlphaComponent(0.20) : NSColor.white.withAlphaComponent(0.16)
        let border = light ? NSColor.black.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.14)
        for card in sectionCards {
            card.layer?.backgroundColor = fill.cgColor
            card.layer?.borderColor = border.cgColor
        }
    }

    func present(rows: [MenuRowView], below anchor: NSRect, on screen: NSScreen) {
        let size = layout(rows)
        let visible = screen.visibleFrame
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - 6 - size.height)
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        origin.y = max(origin.y, visible.minY + 4)
        setFrame(NSRect(origin: origin, size: size), display: true)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        GlassBackdrop.adaptToBackdrop(self)
        tintCards()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.animator().alphaValue = 1
        }
        installMonitors()
    }

    /// วาดใหม่ระหว่างเปิดอยู่ — ขอบบนอยู่ที่เดิม ความสูงเปลี่ยนตามแถว
    func reload(rows: [MenuRowView]) {
        guard isVisible else { return }
        let top = frame.maxY
        let size = layout(rows)
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        GlassBackdrop.adaptToBackdrop(self)
        tintCards()
    }

    func dismiss() {
        guard isVisible else { return }
        dismissedAt = CFAbsoluteTimeGetCurrent()
        removeMonitors()
        orderOut(nil)
        alphaValue = 1
    }

    private func installMonitors() {
        removeMonitors()
        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in self?.dismiss() })
        if let global { monitors.append(global) }
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                if let self, event.window !== self { self.dismiss() }
                return event
            })
        if let local { monitors.append(local) }
        let keys = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                if event.keyCode == 53 { self?.dismiss(); return nil }   // Esc
                return event
            })
        if let keys { monitors.append(keys) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

// MARK: - App ----------------------------------------------------------------

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var displaySettleWork: DispatchWorkItem?
    private var trustTimer: Timer?
    private var engineStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        Config.migrate()
        Geometry.refresh()
        FrontApp.start()
        Updater.scheduleAutomatic()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            Geometry.refresh()
            SnapManager.shared.rebuildDividers()
            // เสียบจอ/รีสตาร์ทแล้วจอที่เคยสั่งปิดกลับมา → รอให้ระบบจัดจอเสร็จแล้วปิดให้ซ้ำ
            knackLog("screen parameters changed")
            self.displaySettleWork?.cancel()
            let work = DispatchWorkItem {
                DisplayControl.ensureVisibleDisplay()
                DisplayControl.reapplyPoweredOff()
            }
            self.displaySettleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }

        // ก่อนเครื่องหลับ — เปิดจอที่ปิดไว้กลับมาก่อน กันถอดจอนอกตอนหลับแล้วตื่นมาจอดำสนิท
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            knackLog("system will sleep")
            DisplayControl.reenableBeforeSleep()
        }

        // เครื่องตื่นจากสลีป/เปิดฝา — เช็คทันทีว่ามีจอเปิดไหม กันกรณีถอดจอนอกออกหมดแล้ว
        // จอ built-in ที่สั่งปิดไว้กลายเป็นจอเดียวที่เหลือ ทำให้จอดำสนิทเปิดกลับไม่ได้
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            knackLog("system woke")
            // ลองหลายรอบเพราะระบบจอกว่าจะพร้อมหลังตื่นใช้เวลาไม่แน่นอน
            for delay in [0.3, 1.0, 2.5, 5.0, 9.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    DisplayControl.ensureVisibleDisplay()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                DisplayControl.reapplyPoweredOff()
            }
        }


        buildStatusItem()
        SystemMonitor.shared.refresh()   // สร้างหลังไอคอน Deft เพื่อให้ไปอยู่ทางซ้ายของไอคอน
        startWhenTrusted()
    }

    // MARK: สิทธิ์ Accessibility

    /// ถ้ายังไม่ได้สิทธิ์ก็รอ พอผู้ใช้ติ๊กให้เมื่อไหร่ก็เริ่มทำงานทันทีโดยไม่ต้องเปิดแอปใหม่
    private func startWhenTrusted() {
        if AXIsProcessTrusted() {
            startEngine()
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        updateStatusItem()
        PermissionsWindow.shared.present()            // หน้ารวมสิทธิ์ ครั้งแรกจะเห็นหน้านี้คู่กับหน้าต่างของระบบ

        trustTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else { return }
            self?.trustTimer?.invalidate()
            self?.trustTimer = nil
            self?.startEngine()
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    private func startEngine() {
        guard !engineStarted else { return }
        guard SnapManager.shared.startEventTap() else {
            updateStatusItem()
            let alert = NSAlert()
            alert.messageText = "Could not create the event tap"
            alert.informativeText = "Remove Deft from Privacy & Security → Accessibility, tick it again, then relaunch the app."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        SnapManager.shared.registerHotKeys()
        KeyLayouts.start()
        DisplayControl.loadPoweredOff()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { DisplayControl.reapplyPoweredOff() }
        InputTap.shared.refresh()
        DockPeek.shared.refresh()
        engineStarted = true
        updateStatusItem()

        if Config.launchAtLogin != LoginItem.isEnabled { LoginItem.set(Config.launchAtLogin) }
        if Config.windowPreviews && !Thumbnails.isAuthorized {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.ensureScreenRecording() }
        }
    }

    /// Screen Recording ต่างจาก Accessibility ตรงที่ต้องเปิดแอปใหม่หลังให้สิทธิ์
    func ensureScreenRecording() {
        if Thumbnails.isAuthorized { return }
        Thumbnails.requestAccess()
        PermissionsWindow.shared.present()
    }

    func relaunch() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open '" + Bundle.main.bundlePath + "'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: เมนูบาร์

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
        statusItem.button?.sendAction(on: [.leftMouseDown])
        updateStatusItem()
    }

    /// คลิกไอคอน = เปิด/ปิดเมนูกระจกใต้ไอคอน
    @objc private func toggleMenu() {
        let panel = MenuPanel.shared
        // คลิกไอคอนขณะเมนูเปิด: local monitor ปิดให้ก่อนแล้ว — อย่าเพิ่งเปิดใหม่
        if panel.isVisible || CFAbsoluteTimeGetCurrent() - panel.dismissedAt < 0.25 {
            panel.dismiss()
            return
        }
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let list = MenuList()
        populate(list)
        panel.present(rows: list.rows, below: anchor, on: screen)
    }

    private func updateStatusItem() {
        if SnapManager.shared.isRunning {
            statusItem.button?.image = Brand.menuBarMark()
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                                               accessibilityDescription: "Deft")
            statusItem.button?.image?.isTemplate = true
        }
        refreshMenu()
    }

    /// วาดเมนูใหม่ในที่ (ถ้าเปิดอยู่) — สวิตช์ที่พึ่งกันจะได้ตรงสภาพจริง
    func refreshMenu() {
        guard MenuPanel.shared.isVisible else { return }
        let list = MenuList()
        populate(list)
        MenuPanel.shared.reload(rows: list.rows)
    }

    // MARK: ตัวช่วยสร้างเมนู

    private func symbol(_ name: String, _ color: NSColor, size: CGFloat = 13) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = base.withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }

    /// หัวข้อกลุ่มในเมนู — ตัวเล็กสีจาง คั่นของให้อ่านเป็นกลุ่มได้
    private static let sectionIcons: [String: String] = [
        "Windows": "macwindow", "Keyboard": "keyboard", "Mouse": "computermouse",
        "System Monitor": "chart.bar.xaxis", "Display": "display", "System": "gearshape"]
    private func header(_ text: String, badge: String? = nil) -> MenuRowView {
        MenuHeaderLabelRow(symbol: Self.sectionIcons[text] ?? "circle", text: text, badge: badge)
    }

    private func note(_ text: String) -> MenuRowView { MenuNoteRow(text) }

    private func row(_ view: MenuRowView) -> MenuRowView { view }

    private func separator() -> MenuRowView { MenuSeparatorRow() }

    /// สวิตช์หนึ่งแถว
    private func toggle(_ title: String, _ setting: MasterSwitch, tip: String? = nil,
                        indent: CGFloat = 0) -> MenuRowView {
        MenuToggleRow(title: title, isOn: setting.isOn, tip: tip, indent: indent) {
            [weak self] value in
            setting.set(value)
            // สวิตช์บางตัวพึ่งกัน (เช่น Auto กับ Windows Shortcut Key) — วาดเมนูใหม่ให้ตรงสภาพจริง
            DispatchQueue.main.async { self?.refreshMenu() }
        }
    }

    // MARK: เมนูหลัก

    private func populate(_ menu: MenuList) {
        let running = SnapManager.shared.isRunning

        menu.addItem(row(MenuHeaderView {
            DonateWindow.shared.present()
        }))

        if !running {
            menu.addItem(MenuItemRow(title: "Tick Deft to start it right away",
                                     leadingSymbol: "exclamationmark.triangle.fill", leadingColor: .systemOrange) {
                [weak self] in self?.fixPermission()
            })
        }

        // ---- Windows -------------------------------------------------------
        menu.addItem(separator())
        menu.addItem(header("Windows"))
        menu.addItem(toggle("Windows Snap", .windowsSnap,
                            tip: "Edge & corner snapping · Snap Layouts · Snap Assist · shared dividers · Win+arrows"))
        menu.addItem(toggle("Live Preview", .livePreview,
                            tip: "Real, moving window previews in the switcher (Cmd+Tab), Snap Assist and when hovering the Dock. Needs Screen Recording"))

        // ---- Keyboard ------------------------------------------------------
        menu.addItem(separator())
        menu.addItem(header("Keyboard", badge: KeyboardStyle.windowsActive ? "Windows" : "Mac"))
        menu.addItem(toggle("Windows Shortcuts", .windowsShortcuts,
                            tip: "Ctrl acts as Cmd · the Win key · F-keys · Home/End · language switch key · Explorer keys in Finder. Off = Mac shortcuts"))
        menu.addItem(toggle("Auto-Detect Keyboard", .autoKeyboard,
                            tip: "Follows whichever keyboard you type on: a Windows keyboard gets Windows shortcuts, a Mac keyboard gets Mac ones. Needs Input Monitoring"))
        menu.addItem(toggle("Convert Layout", .layoutFix,
                            tip: ("Typed on the wrong layout, like \"l;ylfu\" for \"สวัสดี\"? Select the text and double-tap Shift to convert it (Thai↔English) and switch the input language. Nothing selected → converts the last word")))
        // แถวสวิตช์ + ลูกศรกาง แบบเดียวกับแถวจอ: สวิตช์ = เปิด/ปิดปุ่มเปลี่ยนภาษา ลูกศร = เลือกว่าปุ่มไหน
        let languageKeys: [(String, CGFloat)] = [("` (~ key)", 1), ("Alt+Shift", 2), ("Ctrl+Shift", 4), ("Win+Space", 3)]
        let languageRow = MenuSwitchExpandRow(
            title: "Language Switch Key",
            isOn: Config.languageSwitchKey != 0,
            expanded: languageKeyExpanded,
            onToggle: { [weak self] on in
                Config.languageSwitchKey = on ? Config.languageSwitchKeyLast : 0
                InputTap.shared.refresh()
                DispatchQueue.main.async { self?.refreshMenu() }
            },
            onExpand: { [weak self] in
                guard let self else { return }
                self.languageKeyExpanded.toggle()
                self.refreshMenu()
            })
        languageRow.toolTip = "Windows-style input language switch key. Works while Windows Shortcuts is on. Use the arrow to pick the key"
        menu.addItem(row(languageRow))
        if languageKeyExpanded {
            for (label, value) in languageKeys {
                menu.addItem(MenuItemRow(title: label, checked: abs(value - Config.languageSwitchKey) < 0.5,
                                         indent: 16) { [weak self] in
                    self?.setLanguageKey(value)
                })
            }
        }
        menu.addItem(toggle("Clean Keyboard", .keyboardClean,
                            tip: "Locks every key, Fn and media button so you can wipe the keyboard. Turn it off here or with the Unlock button"))

        // ---- Mouse ---------------------------------------------------------
        menu.addItem(separator())
        menu.addItem(header("Mouse"))
        menu.addItem(toggle("Mouse Natural Scroll", .mouseNatural,
                            tip: "On = Mac direction. Off = Windows direction. Independent of the trackpad"))
        menu.addItem(toggle("Trackpad Natural Scroll", .trackpadNatural,
                            tip: "Trackpad direction, independent of the mouse"))
        menu.addItem(toggle("Mouse Side Buttons", .mouseSideButtons,
                            tip: "Side buttons 4/5 go back / forward (Cmd+[ / Cmd+])"))

        // ---- System Monitor ------------------------------------------------
        menu.addItem(separator())
        menu.addItem(header("System Monitor"))
        menu.addItem(toggle("CPU", .monitorCPU,
                            tip: "Total CPU use across all cores, updated every 2 seconds"))
        menu.addItem(toggle("RAM", .monitorRAM,
                            tip: "Memory used (app + wired + compressed), as Activity Monitor counts it"))
        menu.addItem(toggle("SSD", .monitorSSD,
                            tip: "Disk activity (share of time busy reading/writing, as iostat measures it). Click for speed and capacity"))

        // ---- Display -------------------------------------------------------
        menu.addItem(separator())
        appendDisplaySection(into: menu)

        // ---- System --------------------------------------------------------
        menu.addItem(separator())
        menu.addItem(header("System"))
        menu.addItem(toggle("Open at Login", .launchAtLogin,
                            tip: "Starts Deft automatically when you log in. Needs macOS 13 or later"))
        if !PermissionsWindow.missing.isEmpty {
            menu.addItem(MenuItemRow(title: "Permissions…  (\(PermissionsWindow.missing.count) missing)",
                                     leadingSymbol: "lock.open.fill", leadingColor: .systemOrange) {
                PermissionsWindow.shared.present()
            })
        }
        menu.addItem(row(MenuActionRow(title: "Check for Updates…", symbolName: "arrow.down.circle") {
            Updater.check(manual: true)
        }))
        // Quit: ไม่มีไอคอนหน้าและไม่โชว์คีย์ลัด — มีรูปประตูออกทางขวาแทน
        menu.addItem(row(MenuActionRow(title: "Quit Deft",
                                       symbolName: "rectangle.portrait.and.arrow.right") {
            NSApp.terminate(nil)
        }))

        // เครดิตล่างสุด — นอกการ์ด
        menu.addItem(separator())
        menu.addItem(row(MenuFooterRow("Crafted by Ninjait07") { ManualWindow.shared.present() }))
    }

    // MARK: หมวดจอภาพ

    /// จอไหนถูกกางดูตั้งค่าอยู่บ้าง — คงไว้ข้ามการเปิดเมนูรอบใหม่
    private var expandedDisplays: Set<CGDirectDisplayID> = []
    /// รายการปุ่มเปลี่ยนภาษากางอยู่ไหม — หุบเองเมื่อเลือกแล้ว
    private var languageKeyExpanded = false

    private func setLanguageKey(_ value: CGFloat) {
        Config.languageSwitchKey = value
        if value != 0 { Config.languageSwitchKeyLast = value }
        languageKeyExpanded = false
        InputTap.shared.refresh()
    }

    /// ส่วนจอภาพในเมนูหลัก: แถวละจอ มีสวิตช์เปิด-ปิดและลูกศรกางดูตั้งค่า
    /// กาง/หุบหรือสับสวิตช์แล้วเมนูทั้งชุดวาดใหม่ตรงนั้นเลย (NSMenu จัด layout ใหม่ให้เอง)
    private func appendDisplaySection(into menu: MenuList) {
        menu.addItem(header("Display"))

        /// สวิตช์บนแถวจอ: ปิด-เปิดได้ทันทีไม่ต้องกางก่อน แล้วเมนูจัดรายการใหม่ตามสภาพจริง
        func powerHandler(_ id: CGDirectDisplayID) -> (Bool) -> Void {
            { [weak self] wantOn in
                // ปิดเมนูก่อน — ถ้าเมนูค้างอยู่บนจอที่กำลังดับ ระบบจะย้ายมันไปกลางจอที่เหลือ
                MenuPanel.shared.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let ok = wantOn ? DisplayControl.powerOn(id) : DisplayControl.powerOff(id)
                    if !ok { NSSound.beep() }
                    // จอจัดตัวเสร็จแล้วค่อยเปิดเมนูใหม่ใต้ไอคอนบนจอที่เหลือ
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.toggleMenu() }
                }
            }
        }
        func expandHandler(_ id: CGDirectDisplayID) -> () -> Void {
            { [weak self] in
                guard let self else { return }
                if self.expandedDisplays.contains(id) { self.expandedDisplays.remove(id) }
                else { self.expandedDisplays.insert(id) }
                self.refreshMenu()
            }
        }

        let active = DisplayControl.list().filter { !$0.isMirrored }
        for (index, display) in active.enumerated() {
            let id = display.id
            menu.addItem(row(DisplayRowView(
                title: display.name,
                detail: "",
                isOn: true, isBuiltin: display.isBuiltin,
                expanded: expandedDisplays.contains(id), canExpand: true,
                onToggleExpand: expandHandler(id), onTogglePower: powerHandler(id))))
            if expandedDisplays.contains(id) {
                appendDisplaySettings(for: display, into: menu)
            }
            if index < active.count - 1 || !DisplayControl.poweredOffNow.isEmpty {
                menu.addItem(separator())
            }
        }

        // จอที่ปิดอยู่จริง — เหลือแค่สวิตช์บนแถว สับกลับเมื่อไหร่จอก็กลับมา
        let offNow = DisplayControl.poweredOffNow
        for (index, entry) in offNow.enumerated() {
            menu.addItem(row(DisplayRowView(
                title: entry.name,
                detail: "",
                isOn: false, isBuiltin: entry.builtin,
                expanded: false, canExpand: false,
                onToggleExpand: {}, onTogglePower: powerHandler(entry.id))))
            if index < offNow.count - 1 { menu.addItem(separator()) }
        }
        // จัดเรียงจอแบบลากวาง — เปิดได้เมื่อมีจอตั้งแต่ 2 ตัวขึ้นไป
        if active.count > 1 {
            menu.addItem(row(MenuActionRow(title: "Arrange Displays…", symbolName: "square.grid.2x2") {
                ArrangeDisplaysWindow.shared.present()
            }))
        }
    }

    /// ตัวเลือกของจอที่กางดูอยู่ (ความละเอียด/Hz/หมุน/ตำแหน่ง) — กางได้ทีละอย่าง
    private var expandedDisplayChoice: String?

    /// รายการตั้งค่าของจอที่เปิดอยู่ — โผล่ใต้สวิตช์ตอนกางออก แต่ละอย่างกางรายการในที่พร้อมเครื่องหมายถูก
    private func appendDisplaySettings(for display: DisplayControl.Info, into menu: MenuList) {
        let id = display.id

        func choiceGroup(key: String, title: String, value: String?, symbol: String,
                         options: [(label: String, checked: Bool, apply: () -> Void)]) {
            let expanded = expandedDisplayChoice == key
            menu.addItem(MenuDisclosureRow(title: title, value: value, symbolName: symbol, expanded: expanded) {
                [weak self] in
                guard let self else { return }
                self.expandedDisplayChoice = expanded ? nil : key
                self.refreshMenu()
            })
            guard expanded else { return }
            for option in options {
                menu.addItem(MenuItemRow(title: option.label, checked: option.checked, indent: 30) { [weak self] in
                    option.apply()
                    self?.expandedDisplayChoice = nil
                })
            }
        }

        if let mode = display.mode {
            let resolutions = DisplayControl.resolutions(of: id).prefix(16)
            choiceGroup(key: "res-\(id)", title: "Resolution", value: "\(mode.width) × \(mode.height)",
                        symbol: "aspectratio",
                        options: resolutions.map { r in
                            ("\(r.width) × \(r.height)", r.width == mode.width && r.height == mode.height, {
                                let rates = DisplayControl.refreshRates(of: id, width: r.width, height: r.height)
                                DisplayControl.apply(width: r.width, height: r.height,
                                                     refresh: rates.first ?? mode.refresh, to: id)
                            })
                        })

            let rates = DisplayControl.refreshRates(of: id, width: mode.width, height: mode.height)
            if rates.count > 1 {
                choiceGroup(key: "hz-\(id)", title: "Refresh rate", value: "\(mode.refresh) Hz",
                            symbol: "speedometer",
                            options: rates.map { hz in
                                ("\(hz) Hz", hz == mode.refresh, {
                                    DisplayControl.apply(width: mode.width, height: mode.height, refresh: hz, to: id)
                                })
                            })
            }
        }

        if DisplayRotation.canRotate(id) {
            let current = DisplayRotation.angle(of: id)
            choiceGroup(key: "rot-\(id)", title: "Rotation", value: "\(current)°", symbol: "rotate.right",
                        options: [0, 90, 180, 270].map { degrees in
                            ("\(degrees)°", degrees == current, { DisplayRotation.rotate(id, to: degrees) })
                        })
        }

        // สวิตช์ "จอหลัก" — เปิดได้จอเดียว เปิดจอนี้ = จออื่นกลายเป็นปิดเอง ปิดจอหลักเองไม่ได้
        let isMain = display.isMain
        menu.addItem(row(MenuToggleRow(title: "Make main display", isOn: isMain,
                                       tip: "Only one display can be the main display", indent: 36,
                                       leadingSymbol: "star") { [weak self] on in
            if on, !isMain { DisplayControl.makeMain(id) }
            DispatchQueue.main.async { self?.refreshMenu() }
        }))
    }

    @objc private func fixPermission() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startWhenTrusted()
    }

}


// MARK: - จัดเรียงจอ (ลากวาง + หมุน) ------------------------------------------

/// หน้าต่างจัดเรียงจอแบบลากวาง เหมือนหน้า Displays ของ System Settings
/// ลากสี่เหลี่ยมจอไปวางตำแหน่ง เลือกจอแล้วกดหมุน/ตั้งเป็นจอหลักได้
final class ArrangeDisplaysWindow: NSWindow {
    static let shared = ArrangeDisplaysWindow()
    private let canvas = ArrangeCanvas()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                   styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 540))
        container.autoresizingMask = [.width, .height]

        let heading = NSTextField(labelWithString: "Arrange Displays")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.textColor = .labelColor
        heading.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "Drag a display to reposition it. Select one to rotate or set as main.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onChange = { ArrangeDisplaysWindow.refreshMenus() }

        let rotate = NSButton(title: "", target: self, action: #selector(rotateSelected))
        if let icon = NSImage(systemSymbolName: "rotate.right", accessibilityDescription: "Rotate 90°") {
            rotate.image = icon
            rotate.imagePosition = .imageOnly
        } else {
            rotate.title = "Rotate 90°"
        }
        rotate.toolTip = "Rotate the selected display 90°"
        let main = NSButton(title: "Make Main", target: self, action: #selector(makeMainSelected))
        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        done.keyEquivalent = "\r"
        for b in [rotate, main, done] { b.bezelStyle = .rounded }
        let buttons = NSStackView(views: [rotate, main, NSView(), done])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(heading)
        container.addSubview(hint)
        container.addSubview(canvas)
        container.addSubview(buttons)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            hint.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            canvas.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            canvas.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),
            buttons.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])
        contentView = GlassBackdrop.wrap(container, cornerRadius: 22, frosted: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }   // Esc = ปิด
    }

    func present() {
        canvas.reload()
        center()
        makeKeyAndOrderFront(nil)
        makeKey()   // ให้กระจกเรนเดอร์แบบ active ไม่ขุ่น
        GlassBackdrop.adaptToBackdrop(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func rotateSelected() { canvas.rotateSelected() }
    @objc private func makeMainSelected() { canvas.makeMainSelected() }
    @objc private func closeWindow() { close() }

    static func refreshMenus() {
        (NSApp.delegate as? AppDelegate)?.refreshMenu()
    }
}

/// พื้นที่วาดจอ — แต่ละจอเป็นสี่เหลี่ยมมนลากได้ ขอบดูดเข้าหากันอัตโนมัติ
final class ArrangeCanvas: NSView {
    struct Tile { let id: CGDirectDisplayID; let name: String; var isMain: Bool
                  let isBuiltin: Bool; var global: CGRect; var angle: Int }   // global = พิกัดจริง (y ลง)
    private var tiles: [Tile] = []
    private var selected: CGDirectDisplayID?
    private var dragging: Int?
    private var dragOffset: CGSize = .zero
    private var scale: CGFloat = 0.1
    private var bbox: CGRect = .zero
    var onChange: () -> Void = {}

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func reload() {
        tiles = DisplayControl.list().filter { !$0.isMirrored }.map {
            Tile(id: $0.id, name: $0.name, isMain: $0.isMain, isBuiltin: $0.isBuiltin,
                 global: $0.bounds, angle: DisplayRotation.angle(of: $0.id))
        }
        if selected == nil || !tiles.contains(where: { $0.id == selected }) {
            selected = tiles.first(where: \.isMain)?.id ?? tiles.first?.id
        }
        recomputeScale()
        needsDisplay = true
    }

    private func recomputeScale() {
        guard !tiles.isEmpty else { return }
        var box = tiles[0].global
        for t in tiles { box = box.union(t.global) }
        bbox = box
        let inset: CGFloat = 24
        let availW = bounds.width - inset * 2, availH = bounds.height - inset * 2
        scale = min(availW / max(box.width, 1), availH / max(box.height, 1))
    }

    override func layout() { super.layout(); recomputeScale(); needsDisplay = true }

    /// global (y ลง) -> พิกัดใน view (y ขึ้น) จัดกึ่งกลาง
    private func viewRect(_ g: CGRect) -> CGRect {
        let contentW = bbox.width * scale, contentH = bbox.height * scale
        let offX = (bounds.width - contentW) / 2, offY = (bounds.height - contentH) / 2
        let x = offX + (g.minX - bbox.minX) * scale
        let y = offY + (bbox.maxY - g.maxY) * scale
        return NSRect(x: x, y: y, width: g.width * scale, height: g.height * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        // พื้นหลังโปร่งบาง ๆ ให้เห็นกระจก Liquid Glass ทะลุ
        NSColor(calibratedWhite: 0, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        for tile in tiles {
            let r = viewRect(tile.global).insetBy(dx: 3, dy: 3)
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            let isSel = tile.id == selected
            (isSel ? Skin.teal.withAlphaComponent(0.45) : NSColor(calibratedWhite: 1, alpha: 0.24)).setFill()
            path.fill()
            (isSel ? Skin.teal : NSColor(calibratedWhite: 1, alpha: 0.5)).setStroke()
            path.lineWidth = isSel ? 2.5 : 1
            path.stroke()

            // ชื่อจอ + ดาวเหนือชื่อถ้าเป็นจอหลัก ทั้งคู่หมุนตามมุมจอ
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white]
            let sz = (tile.name as NSString).size(withAttributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            let xform = NSAffineTransform()
            xform.translateX(by: r.midX, yBy: r.midY)
            xform.rotate(byDegrees: CGFloat(tile.angle))
            xform.concat()
            (tile.name as NSString).draw(at: NSPoint(x: -sz.width / 2, y: -sz.height / 2), withAttributes: attrs)
            if tile.isMain {
                let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.systemYellow]))
                if let icon = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "main")?
                    .withSymbolConfiguration(cfg) {
                    icon.isTemplate = false
                    let s = icon.size
                    icon.draw(in: NSRect(x: -s.width / 2, y: sz.height / 2 + 5, width: s.width, height: s.height))
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func tileIndex(at p: NSPoint) -> Int? {
        for i in tiles.indices.reversed() where viewRect(tiles[i].global).contains(p) { return i }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = tileIndex(at: p) else { return }
        selected = tiles[i].id
        dragging = i
        let r = viewRect(tiles[i].global)
        dragOffset = CGSize(width: p.x - r.minX, height: p.y - r.minY)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let i = dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        // ตำแหน่งใหม่ใน view แล้วแปลงกลับเป็น global
        var vr = viewRect(tiles[i].global)
        vr.origin = NSPoint(x: p.x - dragOffset.width, y: p.y - dragOffset.height)
        var g = tiles[i].global
        g.origin = CGPoint(x: bbox.minX + (vr.minX - (bounds.width - bbox.width * scale) / 2) / scale,
                           y: bbox.maxY - g.height - (vr.minY - (bounds.height - bbox.height * scale) / 2) / scale)
        tiles[i].global = snap(index: i, moved: g)
        needsDisplay = true
    }

    /// ดูดขอบให้ชนขอบจออื่น — เกณฑ์แคบ (~10px บนจอจริงในหน้านี้) เพื่อให้วางได้ละเอียด
    /// แต่ละแกนเลือก "คู่ที่ใกล้สุด" คู่เดียว ไม่ใช่เจอคู่ไหนก่อนก็ดูดเลย จะได้ไม่กระโดดไกล
    private func snap(index i: Int, moved: CGRect) -> CGRect {
        var g = moved
        let threshold: CGFloat = 10 / scale   // 10px ในหน้าจอจัดเรียง แปลงกลับเป็นพิกัดจริง
        var bestX: (dist: CGFloat, shift: CGFloat)?
        var bestY: (dist: CGFloat, shift: CGFloat)?
        for (j, other) in tiles.enumerated() where j != i {
            let o = other.global
            // แนวนอน: ขอบซ้าย/ขวา ชนกัน + กึ่งกลางตรงกัน
            for (a, b) in [(g.maxX, o.minX), (g.minX, o.maxX), (g.minX, o.minX),
                           (g.maxX, o.maxX), (g.midX, o.midX)] {
                let d = abs(a - b)
                if d < threshold, bestX == nil || d < bestX!.dist { bestX = (d, b - a) }
            }
            // แนวตั้ง: ขอบบน/ล่าง + กึ่งกลางตรงกัน
            for (a, b) in [(g.maxY, o.minY), (g.minY, o.maxY), (g.minY, o.minY),
                           (g.maxY, o.maxY), (g.midY, o.midY)] {
                let d = abs(a - b)
                if d < threshold, bestY == nil || d < bestY!.dist { bestY = (d, b - a) }
            }
        }
        if let x = bestX { g.origin.x += x.shift }
        if let y = bestY { g.origin.y += y.shift }
        return g
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragging = nil }
        guard dragging != nil else { return }
        commit()
    }

    /// ย้ายจอหลักไปอยู่ (0,0) แล้วเลื่อนจออื่นตามค่าที่จัดไว้
    private func commit() {
        guard let mainTile = tiles.first(where: \.isMain) else { return }
        let dx = mainTile.global.minX, dy = mainTile.global.minY
        var origins: [CGDirectDisplayID: CGPoint] = [:]
        for t in tiles {
            origins[t.id] = CGPoint(x: (t.global.minX - dx).rounded(), y: (t.global.minY - dy).rounded())
        }
        DisplayControl.placeMany(origins)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.reload(); self?.onChange()
        }
    }

    func rotateSelected() {
        guard let id = selected, DisplayRotation.canRotate(id) else { return }
        // ไอคอนเป็นลูกศรตามเข็ม → หมุนจอตามเข็มด้วย ค่า orientation ของ macOS เพิ่มขึ้น = ทวนเข็ม จึงลบ 90 (บวก 270)
        let next = (DisplayRotation.angle(of: id) + 270) % 360
        DisplayRotation.rotate(id, to: next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.reload(); self?.onChange()
        }
    }

    func makeMainSelected() {
        guard let id = selected else { return }
        DisplayControl.makeMain(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.reload(); self?.onChange()
        }
    }
}

// MARK: - โลโก้ --------------------------------------------------------------

/// ตัว K ที่ประกอบขึ้นจาก "บานหน้าต่าง" สามชิ้น — เสาซ้ายหนึ่งบาน แขนบนล่างอีกสองบาน
/// มีช่องไฟคั่นระหว่างชิ้นเหมือนหน้าต่างที่ snap ชิดกัน
enum Brand {
    // สีพื้นไอคอน (ไล่เฉด) — จากเครื่องมือปรับโลโก้: ดำล้วน
    static let deepBlue = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 1)     // ล่างขวา
    static let brightBlue = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 1)   // บนซ้าย

    /// ตัว K จาก "บานหน้าต่าง" สามชิ้น — เสาซ้ายเต็มความสูง + สองบานขวาแยกด้วยร่องทแยงเป็นแขน K
    /// พิกัด 0–1 อิงด้านสั้นสุด, `weight` = ความกว้างร่องระหว่างบาน (ไอคอนเล็กใช้ร่องกว้างขึ้น)
    /// ตัว K จากสองบานหน้าต่างมนสูง — บานซ้ายเต็ม บานขวาถูกผ่าด้วยแถบทแยง "/" เป็นแขนบน/ล่าง
    /// `weight` = ความกว้างของร่องทแยง (สัดส่วนของด้าน) ไอคอนเล็กใช้ร่องกว้างขึ้นให้ยังแยกออก
    /// เครื่องหมาย Deft — ตัว D มีลิ้นกลาง (แกนขวา + แถบบน/ล่าง + ลิ้นกลางสั้น)
    /// วาดเต็มกรอบที่ให้มา (เป็นตัวมาร์กหลักที่กินพื้นที่ไอคอนเกือบหมด)
    static func drawMark(in rect: NSRect, color: NSColor, weight: CGFloat = 0.16) {
        let side = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - side) / 2
        let oy = rect.minY + (rect.height - side) / 2
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: NSRect(x: ox + x * side, y: oy + y * side, width: w * side, height: h * side),
                         xRadius: rad * side, yRadius: rad * side)
        }
        color.setFill()
        let path = NSBezierPath()
        path.append(box(0.72, 0.05, 0.23, 0.90, 0.11))   // แกนขวา
        path.append(box(0.05, 0.73, 0.85, 0.22, 0.11))   // แถบบน
        path.append(box(0.05, 0.05, 0.85, 0.22, 0.11))   // แถบล่าง
        path.append(box(0.30, 0.40, 0.52, 0.20, 0.10))   // ลิ้นกลาง (สั้นกว่า)
        path.windingRule = .nonZero
        path.fill()
        _ = weight
    }

    /// ไอคอนบน menu bar — ขาวดำ ให้ระบบย้อมสีเอง
    static func menuBarMark() -> NSImage {
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size)
        image.lockFocus()
        drawMark(in: NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), color: .black, weight: 0.16)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// ไอคอนแอปเต็มใบ — สี่เหลี่ยมมนไล่สีน้ำเงินพร้อมตัว K สีขาว
    /// ไอคอนแอปเป็น NSImage (ใช้ในหน้าต่าง license / สิทธิ์)
    static func appIconImage(pixels: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        drawAppIcon(pixels: pixels)
        image.unlockFocus()
        return image
    }

    static func drawAppIcon(pixels: CGFloat) {
        let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor.clear.setFill()
        canvas.fill()

        // กรอบศิลป์ตามสัดส่วนไอคอน macOS (เว้นขอบไว้ให้เงา)
        let art = canvas.insetBy(dx: pixels * 0.094, dy: pixels * 0.094)
        let radius = art.width * 0.2237
        let squircle = NSBezierPath(roundedRect: art, xRadius: radius, yRadius: radius)

        // เงาอ่อน ๆ ใต้ไอคอน
        if pixels >= 64 {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
            shadow.shadowBlurRadius = pixels * 0.035
            shadow.shadowOffset = NSSize(width: 0, height: -pixels * 0.016)
            shadow.set()
            NSColor.black.setFill()
            squircle.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        if let gradient = NSGradient(colors: [brightBlue, deepBlue]) {
            gradient.draw(in: art, angle: -60)
        }
        // แสงตกกระทบด้านบน
        if let sheen = NSGradient(colors: [NSColor(calibratedWhite: 1, alpha: 0.22),
                                           NSColor(calibratedWhite: 1, alpha: 0)]) {
            sheen.draw(in: NSRect(x: art.minX, y: art.midY, width: art.width, height: art.height / 2),
                       angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        // ขอบในบาง ๆ ให้ดูมีมิติ
        NSColor(calibratedWhite: 1, alpha: 0.20).setStroke()
        squircle.lineWidth = max(1, pixels * 0.004)
        squircle.stroke()

        let markSide = art.width * 0.72
        let markRect = NSRect(x: art.midX - markSide / 2, y: art.midY - markSide / 2,
                              width: markSide, height: markSide)
        NSGraphicsContext.saveGraphicsState()
        if pixels >= 64 {
            let glyphShadow = NSShadow()
            glyphShadow.shadowColor = NSColor(calibratedRed: 0.05, green: 0.18, blue: 0.45, alpha: 0.35)
            glyphShadow.shadowBlurRadius = pixels * 0.018
            glyphShadow.shadowOffset = NSSize(width: 0, height: -pixels * 0.008)
            glyphShadow.set()
        }
        drawMark(in: markRect, color: .white, weight: 0.16)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func png(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawAppIcon(pixels: CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// เรียกจาก build.sh: Deft --export-icon <โฟลเดอร์.iconset>
    static func exportIconSet(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            guard let data = png(pixels: pixels) else { continue }
            try? data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        // ไฟล์ตัวอย่างไว้ดูเฉย ๆ
        if let data = png(pixels: 512) {
            try? data.write(to: directory.deletingLastPathComponent()
                .appendingPathComponent("knack-logo.png"))
        }
    }
}

// MARK: - main ---------------------------------------------------------------

let app = NSApplication.shared

// โหมดสร้างไอคอน — build.sh เรียกใช้หลังคอมไพล์เสร็จ จะได้ไม่ต้องเก็บไฟล์ภาพไว้ในรีโป
if let flag = CommandLine.arguments.firstIndex(of: "--export-icon") {
    let target = CommandLine.arguments.count > flag + 1 ? CommandLine.arguments[flag + 1] : "."
    Brand.exportIconSet(to: URL(fileURLWithPath: target))
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
