//
//  PhoneNumberHelper.swift
//  WebRTCDialer
//

import Foundation
import PhoneNumberKit

enum PhoneNumberHelper {
    // PhoneNumberUtility loads metadata on init, so share one instance.
    private static let utility = PhoneNumberUtility()

    static let region = PhoneNumberUtility.defaultRegionCode()

    static var countryCodePrefix: String {
        guard let code = utility.countryCode(for: region) else { return "+1" }
        return "+\(code)"
    }

    static func formatAsYouType(_ input: String) -> String {
        PartialFormatter(utility: utility, defaultRegion: region, withPrefix: false).formatPartial(input)
    }

    /// Returns the number in E.164 (e.g. +14087684570), or nil if it isn't a valid number.
    static func e164(from input: String) -> String? {
        guard let parsed = try? utility.parse(input, withRegion: region) else { return nil }
        return utility.format(parsed, toType: .e164)
    }

    static func displayString(fromE164 number: String) -> String {
        guard let parsed = try? utility.parse(number, withRegion: region) else { return number }
        let type: PhoneNumberFormat = parsed.regionID == region ? .national : .international
        return utility.format(parsed, toType: type)
    }

    static func digitCount(_ input: String) -> Int {
        input.filter(\.isNumber).count
    }
}
