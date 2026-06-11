import Foundation
import CoreGraphics

/// Recovers tabular structure from positioned text when no Accessibility table
/// role is exposed. Pure geometry over element/line bounding boxes, so it is
/// fully covered by `--selftest` without a live screen:
///   • rung 2 — AX leaves (ground-truth text, screen-point frames)
///   • rung 3 — OCR lines (pixel floor, Vision-normalized boxes)
/// Both feed one coordinate-agnostic inference (`infer`) that bands rows, merges
/// column intervals, and rejects multi-column *prose* so we never mistake
/// reflowed paragraphs for a table.
struct TableRecognizer {

    /// One positioned text run in a top-left reading space (y grows downward).
    private struct Cell {
        let rect: CGRect
        let text: String
    }

    // MARK: - Rungs

    /// Rung 2: geometry inference over harvested AX leaves (frames already in
    /// top-left screen points).
    func inferFromAX(elements: [AXElement]) -> TableData? {
        let cells = elements.compactMap { element -> Cell? in
            guard let text = element.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return Cell(rect: element.frame, text: text)
        }
        return infer(cells: cells, source: .ax)
    }

    /// Rung 3: geometry inference over OCR lines. Vision boxes are normalized
    /// (0–1, origin bottom-left); flip Y into the top-left reading space.
    func inferFromOCR(lines: [OCRLine]) -> TableData? {
        let cells = lines.compactMap { line -> Cell? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let b = line.boundingBox
            let rect = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            return Cell(rect: rect, text: text)
        }
        return infer(cells: cells, source: .ocr)
    }

    // MARK: - Shared inference

    private func infer(cells: [Cell], source: EntitySource) -> TableData? {
        guard cells.count >= 6 else { return nil }   // floor: 2 cols × 3 rows

        let rowBands = bandRows(cells)
        guard rowBands.count >= 3 else { return nil }

        let columns = columnBands(cells)
        guard columns.count >= 2 else { return nil }

        // Assemble rectangular grid, top→bottom rows, left→right columns.
        var grid: [[String]] = []
        for band in rowBands {
            var cols = Array(repeating: [String](), count: columns.count)
            for cell in band {
                let index = columnIndex(for: cell.rect.midX, in: columns)
                cols[index].append(cell.text)
            }
            grid.append(cols.map { $0.joined(separator: " ") })
        }

        // ≥80% of rows must populate ≥2 columns — a real grid, not a list with a
        // stray second token.
        let populated = grid.filter { row in row.filter { !$0.isEmpty }.count >= 2 }.count
        guard Double(populated) / Double(grid.count) >= 0.8 else { return nil }

        // Reject multi-column prose: table cells are short. Use the median of
        // non-empty cell lengths so a single long cell can't sink a real table.
        let lengths = grid.flatMap { $0 }.filter { !$0.isEmpty }.map(\.count).sorted()
        guard !lengths.isEmpty, lengths[lengths.count / 2] <= 40 else { return nil }

        return TableData(headers: nil, rows: grid, source: source)
    }

    /// Group cells into visual rows by vertical proximity of their centers.
    private func bandRows(_ cells: [Cell]) -> [[Cell]] {
        let heights = cells.map(\.rect.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let tolerance = max(medianHeight * 0.6, 0.001)

        var bands: [[Cell]] = []
        var anchorY: CGFloat = -.greatestFiniteMagnitude
        for cell in cells.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if bands.isEmpty || cell.rect.midY - anchorY > tolerance {
                bands.append([cell])
                anchorY = cell.rect.midY
            } else {
                bands[bands.count - 1].append(cell)
            }
        }
        return bands
    }

    /// Merge cell X-intervals into column bands; a horizontal gutter wider than
    /// `gap` starts a new column. Merging intervals (not just left edges) keeps
    /// right-aligned numeric columns in one band.
    private func columnBands(_ cells: [Cell]) -> [(lo: CGFloat, hi: CGFloat)] {
        let minX = cells.map(\.rect.minX).min()!
        let maxX = cells.map(\.rect.maxX).max()!
        let gap = max((maxX - minX) * 0.02, 0.001)

        var bands: [(lo: CGFloat, hi: CGFloat)] = []
        for cell in cells.sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if var last = bands.last, cell.rect.minX <= last.hi + gap {
                last.hi = max(last.hi, cell.rect.maxX)
                bands[bands.count - 1] = last
            } else {
                bands.append((cell.rect.minX, cell.rect.maxX))
            }
        }
        return bands
    }

    private func columnIndex(for x: CGFloat, in bands: [(lo: CGFloat, hi: CGFloat)]) -> Int {
        if let index = bands.firstIndex(where: { x >= $0.lo && x <= $0.hi }) { return index }
        return bands.enumerated().min {
            abs(($0.1.lo + $0.1.hi) / 2 - x) < abs(($1.1.lo + $1.1.hi) / 2 - x)
        }!.offset
    }
}

/// Serializes a `TableData` into the clipboard/file formats Stage 6 ships:
/// RFC-4180 CSV (explicit "Copy CSV" / "Save CSV…"), TSV (spreadsheet-native
/// bare-paste flavor), and a Markdown pipe table.
enum TableFormatter {

    /// RFC-4180: quote fields containing `,` `"` CR or LF; double embedded
    /// quotes; CRLF row endings.
    static func csv(_ table: TableData) -> String {
        allRows(table).map { row in
            row.map(escapeCSVField).joined(separator: ",")
        }.joined(separator: "\r\n")
    }

    /// Tab-separated — what Excel/Numbers/Sheets parse into cells on a bare ⌘V.
    /// Tabs/newlines inside a field are flattened to spaces (TSV can't escape).
    static func tsv(_ table: TableData) -> String {
        allRows(table).map { row in
            row.map { $0.replacingOccurrences(of: "\t", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\r", with: " ") }
                .joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// Markdown pipe table. Uses `headers` when present, else the first row.
    static func markdown(_ table: TableData) -> String {
        let rows = allRows(table)
        guard let header = rows.first else { return "" }
        let body = Array(rows.dropFirst())
        let columns = header.count
        func line(_ fields: [String]) -> String {
            let padded = (0..<columns).map { $0 < fields.count ? fields[$0] : "" }
            return "| " + padded.map { $0.replacingOccurrences(of: "|", with: "\\|") }
                .joined(separator: " | ") + " |"
        }
        var out = [line(header), "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |"]
        out += body.map(line)
        return out.joined(separator: "\n")
    }

    private static func allRows(_ table: TableData) -> [[String]] {
        let columns = table.columnCount
        func pad(_ row: [String]) -> [String] {
            row.count >= columns ? row : row + Array(repeating: "", count: columns - row.count)
        }
        var rows: [[String]] = []
        if let headers = table.headers { rows.append(pad(headers)) }
        rows += table.rows.map(pad)
        return rows
    }

    private static func escapeCSVField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
