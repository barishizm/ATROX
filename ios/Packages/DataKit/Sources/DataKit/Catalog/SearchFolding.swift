import Foundation

/// Accent-, case- and Turkish-i-insensitive folding used for catalog search. Matches the server's
/// `normalize_search_text` (İ ı I → i, then unaccent + lowercase).
public enum SearchFolding {
    public static func fold(_ text: String) -> String {
        var mapped = String()
        mapped.reserveCapacity(text.utf8.count)
        for ch in text {
            switch ch {
            case "İ", "ı", "I": mapped.append("i")
            default: mapped.append(ch)
            }
        }
        return mapped.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

/// File-name convention of `tools/catalog/catalog/images.py`: `<hash>.f.webp` (full) and `<hash>.t.webp` (thumbnail).
public enum ImageNaming {
    public static func thumb(forFull full: String) -> String {
        full.hasSuffix(".f.webp") ? String(full.dropLast(".f.webp".count)) + ".t.webp" : full
    }
}
