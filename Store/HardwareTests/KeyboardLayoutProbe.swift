import Carbon
import Foundation

func property(_ source: TISInputSource, _ key: CFString) -> String {
    guard let value = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

func translate(_ layout: UnsafePointer<UCKeyboardLayout>, key: UInt16,
               modifiers: UInt32, keyboardType: UInt32, state: inout UInt32) -> String {
    var output = [UniChar](repeating: 0, count: 16)
    var count = 0
    let result = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), modifiers,
                                keyboardType, 0, &state, output.count, &count, &output)
    precondition(result == noErr, "Keyboard translation failed: \(result)")
    return String(utf16CodeUnits: output, count: count)
}

let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--verify" {
    struct Entry: Decodable { let ascii: UInt32; let keys: [UInt16] }
    let entries = try JSONDecoder().decode([Entry].self,
        from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    let expectedScalars = Array(UInt32(32)...UInt32(126)) +
        [0x00C7, 0x00D6, 0x00DC, 0x00E7, 0x00F6, 0x00FC, 0x011E, 0x011F, 0x0130, 0x0131, 0x015E, 0x015F]
    precondition(entries.map(\.ascii) == expectedScalars, "Incomplete ASCII/Turkish coverage")
    guard let source = sources.first(where: { property($0, kTISPropertyInputSourceID) == "com.apple.keylayout.Turkish-QWERTY-PC" }),
          let value = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        fatalError("Apple Turkish-QWERTY-PC input source is not installed")
    }
    let data = Unmanaged<CFData>.fromOpaque(value).takeUnretainedValue()
    let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
    var virtualKeys: [UInt16: UInt16] = [
        0x2c: 49, 0x2d: 27, 0x2e: 24, 0x2f: 33, 0x30: 30, 0x31: 42,
        0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44, 0x64: 10,
    ]
    let letters: [UInt16] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35,
                             12, 15, 1, 17, 32, 9, 13, 7, 16, 6]
    let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    for (offset, key) in letters.enumerated() { virtualKeys[UInt16(offset) + 4] = key }
    for (offset, key) in digits.enumerated() { virtualKeys[UInt16(offset) + 0x1e] = key }
    let keyboardTypes = Set([UInt32(40), 41, UInt32(LMGetKbdType())])
    for keyboardType in keyboardTypes {
        for entry in entries {
            var state: UInt32 = 0
            var actual = ""
            for hid in entry.keys {
                guard let key = virtualKeys[hid & 0xff] else { fatalError("Unknown printable HID key: \(hid)") }
                let modifier = UInt8(hid >> 8)
                precondition(modifier & 0x99 == 0, "Literal text must not send Control or Command")
                let flags: UInt32 = (modifier & 0x22 != 0 ? UInt32(shiftKey >> 8) : 0)
                    | (modifier & 0x44 != 0 ? UInt32(optionKey >> 8) : 0)
                actual += translate(layout, key: key, modifiers: flags, keyboardType: keyboardType, state: &state)
            }
            let expected = String(UnicodeScalar(entry.ascii)!)
            // UCKeyTranslate's state is opaque; a following letter detects pending accents.
            let following = translate(layout, key: UInt16(kVK_ANSI_A), modifiers: 0,
                                      keyboardType: keyboardType, state: &state)
            guard actual == expected, following == "a" else {
                fputs("Scalar \(entry.ascii), keyboard type \(keyboardType): got \(String(reflecting: actual + following))\n", stderr)
                exit(1)
            }
        }
    }
    print("All 95 printable ASCII and 12 Turkish letters match Apple Turkish-QWERTY-PC with no pending dead keys (\(keyboardTypes.count) keyboard types)")
    exit(0)
}

let current = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
print("Current input source: \(property(current, kTISPropertyInputSourceID))")
print("Keyboard type: \(LMGetKbdType())")
for source in sources where property(source, kTISPropertyInputSourceID).localizedCaseInsensitiveContains("turkish") {
    let id = property(source, kTISPropertyInputSourceID)
    print("\nInput source: \(id) / \(property(source, kTISPropertyLocalizedName))")
    guard let value = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
    let data = Unmanaged<CFData>.fromOpaque(value).takeUnretainedValue()
    let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
    let wanted: Set<String> = ["\"", "<", ">", "|", "`", "^", "~"]
    for keyboardType: UInt32 in [40, 41, UInt32(LMGetKbdType())] {
        for modifiers: UInt32 in [0, UInt32(shiftKey >> 8), UInt32(optionKey >> 8), UInt32((shiftKey | optionKey) >> 8)] {
            for key: UInt16 in 0..<51 {
                var state: UInt32 = 0
                let first = translate(layout, key: key, modifiers: modifiers, keyboardType: keyboardType, state: &state)
                let dead = state != 0
                let text = dead ? first + translate(layout, key: UInt16(kVK_Space), modifiers: 0,
                                                   keyboardType: keyboardType, state: &state) : first
                if wanted.contains(text) {
                    print("type=\(keyboardType) vk=\(key) modifiers=\(modifiers) dead=\(dead) text=\(String(reflecting: text))")
                }
            }
        }
    }
}
