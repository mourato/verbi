import Foundation

enum ShortcutKeyCode {
    static let leftCommand: UInt16 = 0x37
    static let rightCommand: UInt16 = 0x36
    static let leftOption: UInt16 = 0x3A
    static let rightOption: UInt16 = 0x3D
    static let leftShift: UInt16 = 0x38
    static let rightShift: UInt16 = 0x3C
    static let leftControl: UInt16 = 0x3B
    static let rightControl: UInt16 = 0x3E
    static let fn: UInt16 = 0x3F
    static let escape: UInt16 = 0x35
    static let space: UInt16 = 0x31

    static let functionKeyByCode: [UInt16: Int] = [
        0x7A: 1,
        0x78: 2,
        0x63: 3,
        0x76: 4,
        0x60: 5,
        0x61: 6,
        0x62: 7,
        0x64: 8,
        0x65: 9,
        0x6D: 10,
        0x67: 11,
        0x6F: 12,
        0x69: 13,
        0x6B: 14,
        0x71: 15,
        0x6A: 16,
        0x40: 17,
        0x4F: 18,
        0x50: 19,
        0x5A: 20
    ]
}
