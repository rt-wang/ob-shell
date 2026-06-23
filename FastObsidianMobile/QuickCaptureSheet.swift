import SwiftUI

struct QuickCaptureSheet: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var destination: CaptureDestination = .inbox
    @State private var captureText = ""
    @State private var sourceURL = ""
    @State private var includeTimestamp = true
    @State private var captureError: String?

    private var canAppend: Bool {
        vault.hasVault && !captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(EditorialColor.divider)
                    .frame(width: 44, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick capture")
                        .font(EditorialFont.display(28))
                        .foregroundStyle(EditorialColor.primaryText)

                    HStack(spacing: 8) {
                        Text("Note to")
                            .font(EditorialFont.ui(.subheadline))
                            .foregroundStyle(EditorialColor.secondaryText)

                        Picker("Destination", selection: $destination) {
                            ForEach(CaptureDestination.allCases) { destination in
                                Text(destination.rawValue).tag(destination)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(EditorialFont.ui(.subheadline, weight: .medium))

                        Spacer()

                        Toggle("Timestamp", isOn: $includeTimestamp)
                            .labelsHidden()
                            .tint(EditorialColor.darkOverlay)
                            .accessibilityLabel("Include Timestamp")
                    }

                    Text(destinationPath)
                        .font(EditorialFont.ui(.caption))
                        .foregroundStyle(EditorialColor.mutedText)
                }

                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: $captureText)
                        .font(EditorialFont.markdown(.body))
                        .foregroundStyle(EditorialColor.primaryText)
                        .lineSpacing(5)
                        .frame(minHeight: 170)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)

                    Hairline()

                    TextField("Source URL", text: $sourceURL)
                        .font(EditorialFont.ui(.body))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(.vertical, 12)

                    Hairline()
                }

                Spacer(minLength: 0)

                Button {
                    append()
                } label: {
                    Label(vault.hasVault ? "Append" : "Choose a vault first", systemImage: "plus")
                        .font(EditorialFont.ui(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(EditorialColor.darkOverlay)
                .disabled(!canAppend)
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .accessibilityLabel("Cancel")
                }
            }
            .presentationDetents([.medium, .large])
            .alert("Capture Error", isPresented: errorBinding) {
                Button("OK") {
                    captureError = nil
                }
            } message: {
                Text(captureError ?? "")
            }
            .editorialScreen()
        }
    }

    private var destinationPath: String {
        guard vault.hasVault else {
            return "No vault selected"
        }

        return "\(vault.vaultName)/\(vault.captureRelativePath(for: destination))"
    }

    private func append() {
        do {
            try vault.appendCapture(
                captureText,
                sourceURL: sourceURL,
                includeTimestamp: includeTimestamp,
                destination: destination
            )
            dismiss()
        } catch {
            captureError = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { captureError != nil },
            set: { isPresented in
                if !isPresented {
                    captureError = nil
                }
            }
        )
    }
}
