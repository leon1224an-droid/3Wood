import SwiftUI

/// Link a phone number to the account so friends who have it in their
/// contacts can find you. No SMS verification in v1 — the number is only
/// used for matching, never shown to anyone.
struct PhoneLinkSheet: View {
    let existing: String?
    let onSaved: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(existing: String?, onSaved: @escaping (String?) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _input = State(initialValue: existing.map(PhoneNumber.display) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("(555) 555-5555", text: $input)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } footer: {
                    Text("Friends who have your number in their contacts can find you on 3Wood. Your number is never shown on your profile.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Color.clayRed)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if existing != nil {
                        Button("Unlink number", role: .destructive) {
                            Task { await unlink() }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .creamScreen()
            .navigationTitle(existing == nil ? "Link phone number" : "Phone number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        guard let normalized = PhoneNumber.normalize(input) else {
            errorMessage = "That doesn't look like a valid phone number. Use 10 digits, or include a country code."
            return
        }
        isSaving = true
        do {
            try await PhoneRepo.setPhone(normalized)
            onSaved(normalized)
            dismiss()
        } catch {
            errorMessage = "Couldn't save the number. \(error.localizedDescription)"
        }
        isSaving = false
    }

    private func unlink() async {
        isSaving = true
        do {
            try await PhoneRepo.setPhone(nil)
            onSaved(nil)
            dismiss()
        } catch {
            errorMessage = "Couldn't unlink the number. \(error.localizedDescription)"
        }
        isSaving = false
    }
}
