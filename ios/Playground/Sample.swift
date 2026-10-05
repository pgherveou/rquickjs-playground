import Foundation

/// A script from the repository's `samples/` directory, copied into the app bundle.
struct Sample: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String

    static func bundled() -> [Sample] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "js", subdirectory: nil) ?? []
        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return Sample(id: url.lastPathComponent, title: title(in: source) ?? url.lastPathComponent, source: source)
            }
    }

    private static func title(in source: String) -> String? {
        let prefix = "// title: "
        return source.split(separator: "\n")
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}
