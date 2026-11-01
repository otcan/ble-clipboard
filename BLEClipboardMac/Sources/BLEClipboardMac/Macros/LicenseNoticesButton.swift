import SwiftUI

struct LicenseNoticesButton: View {
    @State private var showing = false
    var body: some View {
        Button("License Notices") { showing = true }
            .sheet(isPresented: $showing) {
                VStack(spacing: 16) {
                    HStack {
                        Text("License Notices").font(.title3.weight(.semibold))
                        Spacer()
                        Button("Done") { showing = false }.keyboardShortcut(.cancelAction)
                    }
                    ScrollView {
                        Text(["NOTICE", "LICENSE"].map { name in
                            guard let url = Bundle.main.url(forResource: name, withExtension: nil),
                                  let contents = try? String(contentsOf: url, encoding: .utf8) else {
                                return "\(name): see the source repository for the complete license."
                            }
                            return contents
                        }.joined(separator: "\n\n"))
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(24).frame(width: 650, height: 550)
            }
    }
}
