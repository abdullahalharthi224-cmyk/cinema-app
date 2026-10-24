import Foundation

/// Turns age certificates from around the world ("PG-13", "TV-Y7", "12A", "+13", "U")
/// into the youngest age a title suits.
enum AgeRating {
    /// Countries whose certificate is trusted first.
    static let preferredCountries = ["US", "GB", "SA", "AE", "CA", "AU", "DE", "FR", "NL", "ES", "BR"]

    /// The youngest suitable age from a title's certificates by country, or nil when it has none.
    static func minimumAge(certifications: [String: String]) -> Int? {
        let ordered = preferredCountries.compactMap { country in certifications[country].map { (country, $0) } }
            + certifications.filter { !preferredCountries.contains($0.key) }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        for (country, certificate) in ordered {
            if let age = minimumAge(certificate: certificate, country: country) { return age }
        }
        return nil
    }

    static func minimumAge(certificate raw: String, country: String) -> Int? {
        let certificate = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !certificate.isEmpty, !["NR", "UNRATED", "NOT RATED", "TBC", "E", "EXEMPT", "-"].contains(certificate) else { return nil }
        let us: [String: Int] = [
            "G": 0, "PG": 7, "PG-13": 13, "R": 17, "NC-17": 18,
            "TV-Y": 0, "TV-G": 0, "TV-Y7": 7, "TV-Y7-FV": 7, "TV-PG": 7, "TV-14": 14, "TV-MA": 17,
        ]
        if country == "US" || certificate.hasPrefix("TV-") { return us[certificate] }
        if country == "GB" {
            let gb: [String: Int] = ["U": 0, "UC": 0, "PG": 8, "12": 12, "12A": 12, "15": 15, "18": 18, "R18": 18]
            return gb[certificate]
        }
        // Everyone: "U", "G", "L" (Brazil), "AL" (Netherlands), "TP" (France), "Btl" (Sweden), "0".
        if ["U", "G", "L", "AL", "TP", "BTL", "ALL", "TODOS", "T", "A.A", "AA"].contains(certificate) { return 0 }
        if certificate == "PG" { return 8 }
        // Numbers: "12", "+13", "16+", "R13", "M18", "FSK 12".
        let digits = certificate.filter(\.isNumber)
        if let age = Int(digits), age <= 21 { return age }
        return nil
    }

    static func isAllowed(minimumAge: Int?, maxAge: Int) -> Bool {
        guard let minimumAge else { return false }   // No rating: not for kids.
        return minimumAge <= maxAge
    }

    /// TMDB's US movie certificate at or below an age, for discover filters.
    static func usMovieCertificate(forMaxAge age: Int) -> String {
        if age >= 13 { return "PG-13" }
        if age >= 7 { return "PG" }
        return "G"
    }
}
