import Foundation
import SwiftUI

struct TypingTiming: Equatable {
    let pauseMilliseconds: Int
    let variationMilliseconds: Int
    static let fast = TypingTiming(pauseMilliseconds: 0, variationMilliseconds: 0)
    static let slow = TypingTiming(pauseMilliseconds: 80, variationMilliseconds: 0)
    static let variable = TypingTiming(pauseMilliseconds: 80, variationMilliseconds: 30)

    var isValid: Bool {
        (0...1000).contains(pauseMilliseconds) && variationMilliseconds >= 0 &&
        variationMilliseconds <= pauseMilliseconds && pauseMilliseconds + variationMilliseconds <= 1000
    }
    var summary: String {
        self == .fast ? "Fast (standard USB timing)" :
            "\(pauseMilliseconds) ms pause" + (variationMilliseconds > 0 ? " ± \(variationMilliseconds) ms" : "")
    }
    static func selected(mode: Int, pause: Int, variation: Int) -> Self {
        switch mode {
        case 1: return .slow
        case 2: return .variable
        case 3: return .init(pauseMilliseconds: pause, variationMilliseconds: variation)
        default: return .fast
        }
    }
}

struct TypingTimingControls: View {
    @Binding var mode: Int
    @Binding var pause: Int
    @Binding var variation: Int
    var body: some View {
        HStack(spacing: 10) {
            Picker("Typing", selection: $mode) {
                Text("Fast").tag(0); Text("Slow").tag(1)
                Text("Variable").tag(2); Text("Custom").tag(3)
            }.frame(width: 170)
            if mode == 3 {
                Text("Pause (ms)").font(.caption)
                TextField("Pause", value: $pause, format: .number).frame(width: 55)
                Text("Variation ±").font(.caption)
                TextField("Variation", value: $variation, format: .number).frame(width: 55)
            } else {
                Text(TypingTiming.selected(mode: mode, pause: pause, variation: variation).summary)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
