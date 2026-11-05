//
//  PhoneNumberEntryView.swift
//  WebRTCDialer
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct PhoneNumberEntryView: View {
    @Binding var phoneNumber: String
    @Binding var isVerifying: Bool
    @Binding var devCode: String?
    @StateObject private var viewModel = PhoneNumberEntryViewModel()
    @State private var input = ""
    @State private var country = PhoneNumberHelper.defaultCountry
    @State private var showCountryPicker = false
    @FocusState private var isFieldFocused: Bool

    private var e164Number: String? {
        PhoneNumberHelper.e164(from: input, region: country.regionCode)
    }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Logo or App Name
            VStack(spacing: 10) {
                Image(systemName: "phone.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)

                Text("WebRTC Dialer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            Spacer()

            // Phone Number Entry
            VStack(spacing: 16) {
                Text("Enter your phone number")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Button {
                        isFieldFocused = false
                        showCountryPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(country.flag) \(country.dialCode)")
                                .font(.title3)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Country: \(country.name), \(country.dialCode)")

                    Divider()
                        .frame(height: 24)

                    TextField(PhoneNumberHelper.exampleNumber(for: country.regionCode), text: $input)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.title3)
                        .focused($isFieldFocused)
                        .disabled(viewModel.isLoading)

                    if e164Number != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.errorMessage == nil ? Color(.systemGray4) : Color.red, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.15), value: e164Number != nil)

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Enter your mobile number, including area code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: {
                    guard let number = e164Number else { return }
                    isFieldFocused = false
                    Task {
                        await viewModel.sendVerificationCode(phoneNumber: number)
                        if viewModel.codeSent {
                            phoneNumber = number
                            devCode = viewModel.devCode
                            isVerifying = true
                        }
                    }
                }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(e164Number == nil ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(e164Number == nil || viewModel.isLoading)
            }
            .padding(.horizontal, 40)

            Spacer()

            Text("We'll send you a verification code")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 30)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = false }
        .onAppear {
            if input.isEmpty, let saved = PhoneNumberHelper.split(e164: phoneNumber) {
                country = saved.country
                input = saved.national
            }
        }
        .onChange(of: input) { _, newValue in
            let formatted = PhoneNumberHelper.formatAsYouType(newValue, region: country.regionCode)
            if formatted != newValue {
                input = formatted
            }
            viewModel.errorMessage = nil
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && !input.isEmpty && e164Number == nil {
                viewModel.errorMessage = PhoneNumberEntryViewModel.incompleteNumberMessage(for: input, country: country)
            }
        }
        .onChange(of: country) { _, newCountry in
            input = PhoneNumberHelper.formatAsYouType(input, region: newCountry.regionCode)
            viewModel.errorMessage = nil
            isFieldFocused = true
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selection: $country)
        }
    }
}

@MainActor
class PhoneNumberEntryViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var codeSent = false
    @Published var devCode: String?

    func sendVerificationCode(phoneNumber: String) async {
        isLoading = true
        errorMessage = nil
        codeSent = false
        devCode = nil

        do {
            devCode = try await AuthenticationService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            codeSent = true
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }

        isLoading = false
    }

    static func incompleteNumberMessage(for input: String, country: Country) -> String {
        if PhoneNumberHelper.isTooShort(input, region: country.regionCode) {
            return "That number looks too short. Include the area code."
        }
        return "That doesn't look like a valid \(country.name) number. Check the country and area code."
    }

    static func friendlyMessage(for error: Error) -> String {
        if error is URLError {
            return "Can't reach the server. Check your connection and try again."
        }
        if case AuthError.serverError(let message) = error {
            if message.contains("phoneNumber") || message.contains("pattern") {
                return "That doesn't look like a valid phone number. Check the area code and try again."
            }
            if message.count <= 80 {
                return message
            }
        }
        return "Something went wrong sending your code. Please try again."
    }
}

struct CountryPickerView: View {
    @Binding var selection: Country
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredCountries: [Country] {
        guard !searchText.isEmpty else { return PhoneNumberHelper.allCountries }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return PhoneNumberHelper.allCountries.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.dialCode.contains(query)
                || $0.regionCode.caseInsensitiveCompare(query) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button {
                    selection = country
                    dismiss()
                } label: {
                    HStack {
                        Text(country.flag)
                        Text(country.name)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(country.dialCode)
                            .foregroundColor(.secondary)
                        if country == selection {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries or codes")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PhoneNumberEntryView(phoneNumber: .constant(""), isVerifying: .constant(false), devCode: .constant(nil))
}
