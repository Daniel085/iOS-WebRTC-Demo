# Contacts Framework Integration

## Overview

The Contacts framework provides access to the user's contacts database. This integration allows the app to display contact names, show profile pictures, and enable users to select contacts for calling.

## Privacy & Permissions

### Info.plist Configuration

Add privacy description to `Info.plist`:

```xml
<key>NSContactsUsageDescription</key>
<string>We need access to your contacts to help you easily call your friends and family using our service.</string>
```

### Requesting Permission

```swift
import Contacts

class ContactsManager {
    let store = CNContactStore()

    func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestAccess(for: .contacts) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Contacts access error: \(error)")
                }
                completion(granted)
            }
        }
    }

    func checkAuthorizationStatus() -> CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }
}
```

## Reading Contacts

### Fetch All Contacts

```swift
func fetchAllContacts() -> [CNContact] {
    var contacts: [CNContact] = []

    let keys = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactPhoneNumbersKey,
        CNContactImageDataKey,
        CNContactThumbnailImageDataKey
    ] as [CNKeyDescriptor]

    let request = CNContactFetchRequest(keysToFetch: keys)

    do {
        try store.enumerateContacts(with: request) { contact, stop in
            // Only add contacts with phone numbers
            if !contact.phoneNumbers.isEmpty {
                contacts.append(contact)
            }
        }
    } catch {
        print("Error fetching contacts: \(error)")
    }

    return contacts
}
```

### Fetch Specific Contact

```swift
func fetchContact(by phoneNumber: String) -> CNContact? {
    let keys = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactPhoneNumbersKey,
        CNContactImageDataKey
    ] as [CNKeyDescriptor]

    // Normalize phone number for comparison
    let normalizedNumber = normalizePhoneNumber(phoneNumber)

    let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalizedNumber))

    do {
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
        return contacts.first
    } catch {
        print("Error fetching contact: \(error)")
        return nil
    }
}
```

## Contact Model

Create a simplified model for app use:

```swift
struct Contact {
    let identifier: String
    let firstName: String
    let lastName: String
    let phoneNumbers: [PhoneNumber]
    let image: UIImage?

    var displayName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? phoneNumbers.first?.number ?? "Unknown" : name
    }

    var initials: String {
        let first = firstName.first.map { String($0) } ?? ""
        let last = lastName.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }
}

struct PhoneNumber {
    let label: String
    let number: String

    var formattedNumber: String {
        // Format phone number for display
        return formatPhoneNumber(number)
    }
}

// Convert CNContact to Contact
extension Contact {
    init(cnContact: CNContact) {
        self.identifier = cnContact.identifier
        self.firstName = cnContact.givenName
        self.lastName = cnContact.familyName

        self.phoneNumbers = cnContact.phoneNumbers.map { phoneNumber in
            let label = CNLabeledValue<CNPhoneNumber>.localizedString(
                forLabel: phoneNumber.label ?? ""
            )
            return PhoneNumber(
                label: label,
                number: phoneNumber.value.stringValue
            )
        }

        if let imageData = cnContact.thumbnailImageData {
            self.image = UIImage(data: imageData)
        } else {
            self.image = nil
        }
    }
}
```

## Phone Number Normalization

Essential for matching incoming calls with contacts:

```swift
import PhoneNumberKit

// Using PhoneNumberKit library (recommended)
// Add via SPM: https://github.com/marmelroy/PhoneNumberKit.git

class PhoneNumberFormatter {
    static let shared = PhoneNumberFormatter()
    private let phoneNumberKit = PhoneNumberKit()

    // Convert to E.164 format (+12345678900)
    func normalize(_ phoneNumber: String, region: String = "US") -> String? {
        do {
            let parsed = try phoneNumberKit.parse(phoneNumber, withRegion: region)
            return phoneNumberKit.format(parsed, toType: .e164)
        } catch {
            print("Phone number parse error: \(error)")
            return nil
        }
    }

    // Format for display
    func format(_ phoneNumber: String, region: String = "US") -> String {
        do {
            let parsed = try phoneNumberKit.parse(phoneNumber, withRegion: region)
            return phoneNumberKit.format(parsed, toType: .national)
        } catch {
            return phoneNumber
        }
    }
}

// Manual normalization (if not using library)
func normalizePhoneNumberManually(_ phoneNumber: String) -> String {
    // Remove all non-numeric characters
    let digits = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

    // Add country code if missing (assumes US)
    if digits.count == 10 {
        return "+1" + digits
    } else if digits.count == 11 && digits.hasPrefix("1") {
        return "+" + digits
    } else if digits.hasPrefix("+") {
        return "+" + digits.dropFirst().components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    return "+" + digits
}
```

## Contacts Manager

Complete implementation:

```swift
import Contacts

class ContactsManager: ObservableObject {
    static let shared = ContactsManager()

    private let store = CNContactStore()
    private let phoneNumberFormatter = PhoneNumberFormatter.shared

    @Published var contacts: [Contact] = []
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined

    private init() {
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    func updateAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            await MainActor.run {
                updateAuthorizationStatus()
            }
            return granted
        } catch {
            print("Error requesting contacts access: \(error)")
            return false
        }
    }

    // MARK: - Fetch Contacts

    func loadContacts() async {
        guard authorizationStatus == .authorized else {
            print("Not authorized to access contacts")
            return
        }

        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactThumbnailImageDataKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        var fetchedContacts: [Contact] = []

        do {
            try store.enumerateContacts(with: request) { cnContact, _ in
                // Only include contacts with phone numbers
                if !cnContact.phoneNumbers.isEmpty {
                    let contact = Contact(cnContact: cnContact)
                    fetchedContacts.append(contact)
                }
            }

            await MainActor.run {
                self.contacts = fetchedContacts.sorted { $0.displayName < $1.displayName }
            }
        } catch {
            print("Error loading contacts: \(error)")
        }
    }

    // MARK: - Search

    func searchContacts(query: String) -> [Contact] {
        guard !query.isEmpty else { return contacts }

        return contacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(query) ||
            contact.phoneNumbers.contains { $0.number.contains(query) }
        }
    }

    // MARK: - Lookup

    func findContact(byPhoneNumber phoneNumber: String) -> Contact? {
        guard let normalized = phoneNumberFormatter.normalize(phoneNumber) else {
            return nil
        }

        return contacts.first { contact in
            contact.phoneNumbers.contains { phone in
                phoneNumberFormatter.normalize(phone.number) == normalized
            }
        }
    }

    func getContactName(forPhoneNumber phoneNumber: String) -> String? {
        return findContact(byPhoneNumber: phoneNumber)?.displayName
    }

    // MARK: - Observe Changes

    func observeContactChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contactsDidChange),
            name: .CNContactStoreDidChange,
            object: nil
        )
    }

    @objc private func contactsDidChange() {
        Task {
            await loadContacts()
        }
    }
}
```

## UI Integration

### Contacts List View (SwiftUI)

```swift
import SwiftUI

struct ContactsListView: View {
    @StateObject private var contactsManager = ContactsManager.shared
    @State private var searchText = ""

    var filteredContacts: [Contact] {
        contactsManager.searchContacts(query: searchText)
    }

    var body: some View {
        NavigationView {
            Group {
                switch contactsManager.authorizationStatus {
                case .authorized:
                    contactsList

                case .denied, .restricted:
                    permissionDeniedView

                case .notDetermined:
                    requestPermissionView

                @unknown default:
                    EmptyView()
                }
            }
            .navigationTitle("Contacts")
        }
        .task {
            await contactsManager.loadContacts()
        }
    }

    private var contactsList: some View {
        List(filteredContacts, id: \.identifier) { contact in
            ContactRow(contact: contact)
        }
        .searchable(text: $searchText, prompt: "Search contacts")
        .refreshable {
            await contactsManager.loadContacts()
        }
    }

    private var requestPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Access Your Contacts")
                .font(.title2)
                .bold()

            Text("To call your contacts, we need permission to access your contacts list.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button("Allow Access") {
                Task {
                    _ = await contactsManager.requestAccess()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Contacts Access Denied")
                .font(.title2)
                .bold()

            Text("Please enable contacts access in Settings to view and call your contacts.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 12) {
            // Contact image or initials
            if let image = contact.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(contact.initials)
                            .foregroundColor(.white)
                            .font(.headline)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.headline)

                if let primaryNumber = contact.phoneNumbers.first {
                    Text(primaryNumber.formattedNumber)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Call buttons
            HStack(spacing: 16) {
                Button {
                    makeCall(to: contact, isVideo: false)
                } label: {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.green)
                }

                Button {
                    makeCall(to: contact, isVideo: true)
                } label: {
                    Image(systemName: "video.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func makeCall(to contact: Contact, isVideo: Bool) {
        guard let phoneNumber = contact.phoneNumbers.first?.number else { return }
        // Initiate call
        CallKitManager.shared.startCall(phoneNumber: phoneNumber, isVideo: isVideo) { uuid in
            if uuid != nil {
                print("Call started to \(contact.displayName)")
            }
        }
    }
}
```

### Contact Picker (UIKit)

```swift
import ContactsUI

class ContactPickerViewController: UIViewController {

    func showContactPicker() {
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.predicateForEnablingContact = NSPredicate(
            format: "phoneNumbers.@count > 0"
        )
        present(picker, animated: true)
    }
}

extension ContactPickerViewController: CNContactPickerDelegate {
    func contactPicker(_ picker: CNContactPickerViewController,
                      didSelect contact: CNContact) {
        // User selected a contact
        let appContact = Contact(cnContact: contact)

        // Show phone number selection if multiple
        if appContact.phoneNumbers.count > 1 {
            showPhoneNumberSelection(for: appContact)
        } else if let phoneNumber = appContact.phoneNumbers.first {
            initiateCall(to: phoneNumber.number)
        }
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        // User cancelled
    }
}
```

## Indexing for Fast Lookup

For large contact lists, create an index:

```swift
class ContactsIndex {
    private var phoneNumberIndex: [String: Contact] = [:]
    private let phoneNumberFormatter = PhoneNumberFormatter.shared

    func buildIndex(from contacts: [Contact]) {
        phoneNumberIndex.removeAll()

        for contact in contacts {
            for phoneNumber in contact.phoneNumbers {
                if let normalized = phoneNumberFormatter.normalize(phoneNumber.number) {
                    phoneNumberIndex[normalized] = contact
                }
            }
        }
    }

    func findContact(byPhoneNumber phoneNumber: String) -> Contact? {
        guard let normalized = phoneNumberFormatter.normalize(phoneNumber) else {
            return nil
        }
        return phoneNumberIndex[normalized]
    }
}
```

## Handling Contact Updates

```swift
class ContactsObserver {
    private let contactsManager: ContactsManager

    init(contactsManager: ContactsManager) {
        self.contactsManager = contactsManager
        setupObserver()
    }

    private func setupObserver() {
        NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.contactsManager.loadContacts()
            }
        }
    }
}
```

## Best Practices

### 1. Permission Timing

- Don't request immediately on app launch
- Request when user needs the feature
- Explain why you need access

### 2. Graceful Degradation

- Allow manual phone number entry if permission denied
- Show useful UI even without contact access

### 3. Performance

- Cache contacts list
- Use background thread for fetching
- Build search index for large lists
- Limit number of keys fetched

### 4. Privacy

- Only fetch needed contact fields
- Don't upload contacts to server without explicit consent
- Respect user's privacy settings

### 5. User Experience

- Show loading states
- Implement search
- Group contacts alphabetically
- Show contact photos

## Complete Example

```swift
// AppDelegate or SceneDelegate
func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    // Setup contacts observer
    ContactsManager.shared.observeContactChanges()

    // Request contacts permission if needed
    if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
        Task {
            await ContactsManager.shared.requestAccess()
        }
    }

    return true
}
```

## Testing

### Unit Tests

```swift
import XCTest
@testable import YourApp

class PhoneNumberFormatterTests: XCTestCase {

    let formatter = PhoneNumberFormatter.shared

    func testNormalization() {
        XCTAssertEqual(formatter.normalize("(555) 123-4567"), "+15551234567")
        XCTAssertEqual(formatter.normalize("555-123-4567"), "+15551234567")
        XCTAssertEqual(formatter.normalize("+1 555 123 4567"), "+15551234567")
    }

    func testFormatting() {
        let formatted = formatter.format("+15551234567")
        XCTAssertEqual(formatted, "(555) 123-4567")
    }
}
```

### Manual Testing

1. Grant contacts permission
2. Verify contacts display correctly
3. Test search functionality
4. Test contact selection
5. Verify phone number formatting
6. Test with no contacts
7. Test permission denial flow
