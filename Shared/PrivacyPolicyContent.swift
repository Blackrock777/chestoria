import SwiftUI

struct PrivacyPolicyContent: View {
    let unavailableMessage: String

    private static let paragraphs: [String] = {
        guard let url = Bundle.main.url(forResource: "privacy", withExtension: "md"),
              let policy = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return policy.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("# ") }
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if Self.paragraphs.isEmpty { Text(unavailableMessage) }
                ForEach(Array(Self.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if paragraph.hasPrefix("## ") {
                        Text(paragraph.dropFirst(3)).font(.headline).accessibilityAddTraits(.isHeader)
                    } else {
                        Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                    }
                }
                Link("Read the online privacy policy", destination: URL(string: "https://blackrock777.github.io/chestoria/")!)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
