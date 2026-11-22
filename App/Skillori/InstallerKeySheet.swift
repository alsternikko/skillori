import SkilloriCore
import SkilloriUI
import SwiftUI

/// Takes the reader's install command for an installer run with their own key, and keeps what
/// follows the installer's name (the key) in the Keychain, so Skillori can check the skill for
/// new versions. The field hides what is pasted; nothing of it is shown again.
struct InstallerKeySheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let installation: Installation

    @State private var text = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var installer: PackageInstaller? { store.packageInstaller(of: installation) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LabelText("Add key")
                Spacer(minLength: 8)
                LabelText(installation.displayName)
            }
            .foregroundStyle(Palette.ink2)
            Text("Check \(installation.displayName) for new versions")
                .font(TypeRole.sans(20, .medium))
                .tracking(-0.4)
                .padding(.top, 14)
            Text("Paste your install command from \(installer?.name ?? "the author’s site"), key included. Skillori keeps what follows the installer’s name in your Keychain, not in its own files. Now and then it runs the installer into a folder of its own, compares what it gets with this copy, and removes the folder. Your key goes only where the installer sends it, and you can remove it from the skill’s page.")
                .font(TypeRole.sans(12))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            SecureField(installer.map { "\($0.command) --token=…" } ?? "Your install command", text: $text)
                .textFieldStyle(.plain)
                .font(TypeRole.mono(11.5))
                .focused($focused)
                .onSubmit(keep)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .circular))
                .padding(.top, 16)

            if let problem {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StatusChip("Not kept", kind: .attention, mark: "✕")
                    Text(problem).font(TypeRole.sans(12)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            }

            HStack(spacing: 6) {
                Button("Keep key", action: keep)
                    .buttonStyle(PillButtonStyle(prominent: !text.isEmpty))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 520)
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .font(TypeRole.sans(13))
        .onAppear { focused = true }
    }

    private func keep() {
        guard let installer else { dismiss(); return }
        guard PackageInstaller(text)?.package == installer.package else {
            problem = "That isn’t the command for \(installer.package). Copy the whole install command from \(installer.name)."
            return
        }
        guard let arguments = PackageInstaller.arguments(in: text) else {
            problem = "That command has no key in it. Copy the whole command, key included, from \(installer.name)."
            return
        }
        guard store.keepKey(arguments, for: installation) else {
            problem = "Skillori couldn’t keep the key in your Keychain. Try again, or check Keychain Access."
            return
        }
        text = ""
        dismiss()
    }
}
