//
//  PhoneNumberHelper.swift
//  WebRTCDialer
//

import Foundation
import PhoneNumberKit

struct Country: Identifiable, Hashable {
    let regionCode: String
    let name: String
    let dialCode: String

    var id: String { regionCode }

    var flag: String {
        regionCode.unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

enum PhoneNumberHelper {
    // PhoneNumberUtility loads metadata on init, so share one instance.
    private static let utility = PhoneNumberUtility()

    static let defaultRegion = PhoneNumberUtility.defaultRegionCode()

    static let allCountries: [Country] = utility.allCountries()
        .compactMap { country(for: $0) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func country(for regionCode: String) -> Country? {
        guard let code = utility.countryCode(for: regionCode),
              let name = Locale.current.localizedString(forRegionCode: regionCode) else { return nil }
        return Country(regionCode: regionCode, name: name, dialCode: "+\(code)")
    }

    static var defaultCountry: Country {
        country(for: defaultRegion) ?? Country(regionCode: "US", name: "United States", dialCode: "+1")
    }

    static func exampleNumber(for region: String) -> String {
        utility.getFormattedExampleNumber(forCountry: region, ofType: .mobile, withFormat: .national) ?? "Phone number"
    }

    static func formatAsYouType(_ input: String, region: String) -> String {
        PartialFormatter(utility: utility, defaultRegion: region, withPrefix: false).formatPartial(input)
    }

    /// Returns the number in E.164 (e.g. +14087684570), or nil if it isn't a valid number.
    static func e164(from input: String, region: String) -> String? {
        guard let parsed = try? utility.parse(input, withRegion: region) else { return nil }
        return utility.format(parsed, toType: .e164)
    }

    static func isTooShort(_ input: String, region: String) -> Bool {
        let minLength = utility.possiblePhoneNumberLengths(forCountry: region, phoneNumberType: .mobile, lengthType: .national).min() ?? 0
        let digits = input.filter(\.isNumber).drop(while: { $0 == "0" })
        return digits.count < minLength
    }

    /// Splits an E.164 number back into its country and nationally formatted number.
    static func split(e164 number: String) -> (country: Country, national: String)? {
        guard let parsed = try? utility.parse(number, withRegion: defaultRegion),
              let region = parsed.regionID,
              let match = country(for: region) else { return nil }
        return (match, utility.format(parsed, toType: .national))
    }

    static func displayString(fromE164 number: String) -> String {
        guard let parsed = try? utility.parse(number, withRegion: defaultRegion) else { return number }
        let type: PhoneNumberFormat = parsed.regionID == defaultRegion ? .national : .international
        return utility.format(parsed, toType: type)
    }
}
