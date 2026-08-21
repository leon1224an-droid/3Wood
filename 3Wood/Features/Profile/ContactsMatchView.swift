import SwiftUI
import Contacts

/// Find friends from the address book: matches contacts' numbers against
/// linked 3Wood accounts, and offers a text-message invite for everyone else.
struct ContactsMatchView: View {
    /// A 3Wood user found in the contact book.
    struct Match: Identifiable {
        var person: ProfileSummary
        let contactName: String
        var id: UUID { person.id }
    }

    /// A contact not on 3Wood yet — an invite candidate.
    struct InviteCandidate: Identifiable {
        let name: String
        let phone: String
        var id: String { phone }
    }

    @Environment(Router.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL

    @State private var status = CNContactStore.authorizationStatus(for: .contacts)
    @State private var matches: [Match] = []
    @State private var invitees: [InviteCandidate] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    private var myUsername: String? {
        if case .signedIn(let profile) = session.state { return profile.username }
        return nil
    }

    /// Full or limited (iOS 18+) contacts access — enough to match.
    private var hasContactsAccess: Bool {
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }

    var body: some View {
        Group {
            if hasContactsAccess {
                resultsList
            } else if status == .notDetermined {
                // Guideline 5.1.1(iv): the pre-prompt button must be neutral
                // ("Continue"), not phrased as if it's granting the permission.
                explainer(buttonTitle: "Continue") {
                    Task { await requestAccess() }
                }
            } else { // .denied, .restricted
                explainer(
                    message: "Contacts access is off. Enable it in Settings to find friends by phone number.",
                    buttonTitle: "Open Settings"
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
        .creamScreen()
        .navigationTitle("From Contacts")
        .navigationBarTitleDisplayMode(.inline)
        // Attached to the stable container — hanging it on the empty-state
        // view would cancel the load the moment ProgressView replaces it.
        .task(id: status) {
            if hasContactsAccess {
                await loadIfNeeded()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: Invite.link(from: myUsername),
                    message: Text(Invite.message(from: myUsername))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share invite link")
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if isLoading {
            ProgressView("Matching contacts…")
        } else if loadFailed {
            LoadFailedView { await load() }
        } else if matches.isEmpty, invitees.isEmpty {
            ContentUnavailableView(
                "No contacts with numbers",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Contacts need a phone number to be matched or invited.")
            )
        } else {
            List {
                Section {
                    if matches.isEmpty {
                        Text("None of your contacts have linked their number yet. Invite them below!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach($matches) { $match in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.contactName)
                                    Text("@\(match.person.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                FollowButton(person: $match.person)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { router.push(.person(match.person)) }
                            .personRowAccessibility(person: $match.person) {
                                router.push(.person(match.person))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.sand)
                        }
                    }
                } header: {
                    Text("On 3Wood")
                }

                Section {
                    ForEach(invitees) { contact in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                Text(PhoneNumber.display(contact.phone))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Invite") { invite(contact) }
                                .buttonStyle(.borderless)
                                .tint(Color.fairwayGreen)
                                .controlSize(.small)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.sand)
                    }
                } header: {
                    Text("Invite to 3Wood")
                } footer: {
                    Text("Sends a text with your invite link. Numbers are only used for matching and never stored.")
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }
        }
    }

    private func explainer(
        message: String = "See which of your contacts are already on 3Wood and invite the rest. Only phone numbers are used for matching — names stay on your device.",
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        ContentUnavailableView {
            Label("Find friends from contacts", systemImage: "person.2.badge.plus")
        } description: {
            Text(message)
        } actions: {
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color.fairwayGreen)
        }
    }

    /// Opens Messages pre-addressed to the contact with the invite text.
    private func invite(_ contact: InviteCandidate) {
        let body = Invite.message(from: myUsername)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(contact.phone)&body=\(body)") {
            openURL(url)
        }
    }

    private func requestAccess() async {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        // The status change re-fires .task(id: status), which loads.
        status = CNContactStore.authorizationStatus(for: .contacts)
    }

    private func loadIfNeeded() async {
        guard matches.isEmpty, invitees.isEmpty, !isLoading, !loadFailed else { return }
        await load()
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        // Contact enumeration is synchronous — keep it off the main actor.
        let contacts = await Task.detached(priority: .userInitiated) { fetchContacts() }.value
        do {
            let found = try await PhoneRepo.matchContacts(Array(contacts.keys))
            let matchedPhones = Set(found.map(\.phone))
            matches = found.map {
                Match(person: $0.person, contactName: contacts[$0.phone] ?? $0.username)
            }
            invitees = contacts
                .filter { !matchedPhones.contains($0.key) }
                .map { InviteCandidate(name: $0.value, phone: $0.key) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

/// All device contacts with at least one parseable number: [E.164: name].
private func fetchContacts() -> [String: String] {
    let store = CNContactStore()
    let request = CNContactFetchRequest(keysToFetch: [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ])
    var result: [String: String] = [:]
    try? store.enumerateContacts(with: request) { contact, _ in
        let name = "\(contact.givenName) \(contact.familyName)"
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        for number in contact.phoneNumbers {
            if let e164 = PhoneNumber.normalize(number.value.stringValue) {
                result[e164] = name
            }
        }
    }
    return result
}
