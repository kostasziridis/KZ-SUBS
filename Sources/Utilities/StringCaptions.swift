import Foundation

extension String {
    /// Uppercases caption text the way Greek typography expects.
    ///
    /// Greek drops the acute accent in capitals - ΚΑΛΗΜΕΡΑ, not ΚΑΛΗΜΈΡΑ - and Swift's
    /// `uppercased()` keeps it, which looks wrong to any Greek reader. The diaeresis
    /// stays, because it marks pronunciation rather than stress.
    func captionUppercased() -> String {
        var result = ""
        result.reserveCapacity(count)

        for scalar in uppercased().unicodeScalars {
            switch scalar {
            case "Ά": result.append("Α")
            case "Έ": result.append("Ε")
            case "Ή": result.append("Η")
            case "Ί": result.append("Ι")
            case "Ό": result.append("Ο")
            case "Ύ": result.append("Υ")
            case "Ώ": result.append("Ω")
            // Uppercasing ΐ and ΰ yields a diaeresis plus a combining acute; keep the
            // diaeresis, drop the accent.
            case "\u{0301}", "\u{0341}":
                break
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
