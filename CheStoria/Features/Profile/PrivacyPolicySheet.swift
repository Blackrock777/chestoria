import SwiftUI

struct PrivacyPolicySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        NavigationStack {
            PrivacyPolicyContent(unavailableMessage: t("privacy.unavailable"))
                .navigationTitle(t("privacy.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
    }
}

struct AppleAuthorizationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = model.strings
        NavigationStack {
            List {
                Text(t("privacy.appleRevokeNote"))
                Link(t("privacy.appleAccount"), destination: URL(string: "https://account.apple.com/")!)
            }
            .navigationTitle(t("privacy.appleRevoke"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
        }
    }
}
