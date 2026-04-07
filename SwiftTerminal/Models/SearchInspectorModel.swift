import Foundation
import SwiftUI

struct SearchFileResult: Identifiable {
    var id: String { relativePath }
    let fileURL: URL
    let fileName: String
    let relativePath: String
    let matches: [SearchMatch]
}

struct SearchMatch: Identifiable {
    var id: String { "\(relativePath):\(lineNumber):\(columnRange.lowerBound)" }
    let fileURL: URL
    let relativePath: String
    let lineNumber: Int
    let columnRange: Range<Int>
    let highlightedContent: AttributedString
}

@Observable
final class SearchInspectorModel {
    var query = ""
    private(set) var results: [SearchFileResult] = []
    private(set) var isSearching = false

    private static let maxFiles = 100
    private static let maxMatches = 1000

    func search(in directoryURL: URL) async {
        guard !query.isEmpty else {
            results = []
            return
        }

        let query = query

        isSearching = true
        defer { isSearching = false }

        var fileResults: [SearchFileResult] = []
        var matchCount = 0
        let basePath = directoryURL.path

        let fileURLs = Self.collectFiles(in: directoryURL)

        for fileURL in fileURLs {
            guard !Task.isCancelled else { return }
            guard fileResults.count < Self.maxFiles, matchCount < Self.maxMatches else { break }

            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8)
            else { continue }

            let relativePath = String(fileURL.path.dropFirst(basePath.count + 1))
            var matches: [SearchMatch] = []
            let lines = content.components(separatedBy: .newlines)

            for (index, line) in lines.enumerated() {
                guard !Task.isCancelled else { return }
                guard matchCount + matches.count < Self.maxMatches else { break }

                let trimmedLine = String(line.prefix(500))
                if let matchRange = trimmedLine.range(of: query, options: .caseInsensitive) {
                    let colStart = trimmedLine.distance(from: trimmedLine.startIndex, to: matchRange.lowerBound)
                    let colEnd = trimmedLine.distance(from: trimmedLine.startIndex, to: matchRange.upperBound)
                    matches.append(SearchMatch(
                        fileURL: fileURL,
                        relativePath: relativePath,
                        lineNumber: index + 1,
                        columnRange: colStart..<colEnd,
                        highlightedContent: Self.highlight(line: trimmedLine, match: matchRange)
                    ))
                }
            }

            if !matches.isEmpty {
                fileResults.append(SearchFileResult(
                    fileURL: fileURL,
                    fileName: fileURL.lastPathComponent,
                    relativePath: relativePath,
                    matches: matches
                ))
                matchCount += matches.count
            }
        }

        guard !Task.isCancelled else { return }
        results = fileResults
    }

    private static func highlight(line: String, match: Range<String.Index>) -> AttributedString {
        let trimmed = String(line.drop(while: \.isWhitespace))
        let offset = line.count - trimmed.count

        var attributed = AttributedString(trimmed)
        attributed.font = .system(.caption, design: .monospaced)
        attributed.foregroundColor = .secondary

        let shiftedLower = line.index(match.lowerBound, offsetBy: -offset, limitedBy: trimmed.startIndex) ?? trimmed.startIndex
        let shiftedUpper = line.index(match.upperBound, offsetBy: -offset, limitedBy: trimmed.endIndex) ?? trimmed.endIndex

        if let start = AttributedString.Index(shiftedLower, within: attributed),
           let end = AttributedString.Index(shiftedUpper, within: attributed) {
            attributed[start..<end].foregroundColor = .accentColor
            attributed[start..<end].font = .system(.caption, design: .monospaced).bold()
        }

        return attributed
    }

    private static func collectFiles(in directoryURL: URL) -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if FileItem.ignoredNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }
}
