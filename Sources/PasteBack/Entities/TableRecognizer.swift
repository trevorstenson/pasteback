import Foundation
import CoreGraphics

/// Recovers tabular structure from positioned text when no Accessibility table
/// role is exposed. Pure geometry over element/line bounding boxes, so it is
/// fully covered by `--selftest` without a live screen:
///   • rung 2 — AX leaves (ground-truth text, screen-point frames)
///   • rung 3 — OCR lines (pixel floor, Vision-normalized boxes)
/// Both feed one coordinate-agnostic inference (`infer`) that bands rows, finds
/// mostly-empty vertical gutters, and rejects multi-column *prose* so we never
/// mistake reflowed paragraphs for a table.
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

    /// Rung 3: geometry inference over OCR tokens when available, falling back
    /// to line boxes for fixtures/providers that only expose line geometry.
    /// Vision boxes are normalized (0–1, origin bottom-left); flip Y into the
    /// top-left reading space.
    func inferFromOCR(lines: [OCRLine]) -> TableData? {
        let tokenCells = lines.flatMap { line -> [Cell] in
            line.tokens.compactMap { token in
                let text = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return Cell(rect: Self.topLeftRect(fromVisionBox: token.boundingBox), text: text)
            }
        }
        let lineCells = lines.compactMap { line -> Cell? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Cell(rect: Self.topLeftRect(fromVisionBox: line.boundingBox), text: text)
        }
        return infer(cells: tokenCells.count >= 6 ? tokenCells : lineCells, source: .ocr)
    }

    // MARK: - Shared inference

    private func infer(cells: [Cell], source: EntitySource) -> TableData? {
        guard cells.count >= 6 else { return nil }   // floor: 2 cols × 3 rows

        let rowBands = bandRows(cells)
        guard rowBands.count >= 3 else { return nil }

        let columns = columnBands(rowBands: rowBands)
        guard columns.count >= 2 else { return nil }

        // Assemble rectangular grid, top→bottom rows, left→right columns.
        var grid: [[String]] = []
        for band in rowBands {
            var cols = Array(repeating: [String](), count: columns.count)
            for cell in band.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                let index = columnIndex(for: cell.rect.midX, in: columns)
                cols[index].append(cell.text)
            }
            grid.append(cols.map { $0.joined(separator: " ") })
        }

        // Sparse rows are usually captions/notes caught inside the lasso. Keep
        // the table core when at least three real rows remain.
        let populatedGrid = grid.filter { row in row.filter { !$0.isEmpty }.count >= 2 }
        guard populatedGrid.count >= 3 else { return nil }
        if Double(populatedGrid.count) / Double(grid.count) < 0.8 {
            guard Double(populatedGrid.count) / Double(grid.count) >= 0.6 else { return nil }
            grid = populatedGrid
        }

        // Reject multi-column prose: table cells are usually short. Strong edge
        // alignment can override this for real tables with description columns.
        let lengths = grid.flatMap { $0 }.filter { !$0.isEmpty }.map(\.count).sorted()
        guard !lengths.isEmpty else { return nil }
        let hasStrongAlignment = Self.hasStrongColumnAlignment(rowBands: rowBands, columns: columns)
        let shortCellRatio = Double(lengths.filter { $0 <= 40 }.count) / Double(lengths.count)
        guard lengths[lengths.count / 2] <= 40
                || (hasStrongAlignment && shortCellRatio >= 0.5) else { return nil }

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
        return bands.map { $0.sorted(by: { $0.rect.minX < $1.rect.minX }) }
    }

    /// Find column bands from a gutter profile. A gutter is an x-range where all
    /// or nearly all rows have no cell; one spanning/caption cell can dirty its
    /// own row without vetoing the split for the whole table.
    private func columnBands(rowBands: [[Cell]]) -> [(lo: CGFloat, hi: CGFloat)] {
        let cells = rowBands.flatMap { $0 }
        let minX = cells.map(\.rect.minX).min()!
        let maxX = cells.map(\.rect.maxX).max()!
        let span = maxX - minX
        guard span > 0 else { return [] }
        let widths = cells.map(\.rect.width).sorted()
        let medianWidth = widths[widths.count / 2]
        let minGutterWidth = max(span * 0.04, medianWidth * 0.15, 0.001)

        let edges = Array(Set(cells.flatMap { [$0.rect.minX, $0.rect.maxX] }))
            .sorted()
        guard edges.count >= 2 else { return [] }

        let rowCount = rowBands.count
        let requiredClearRows = max(1, min(rowCount - 1, Int(ceil(Double(rowCount) * 0.85))))
        var gutters: [(lo: CGFloat, hi: CGFloat)] = []
        for pair in zip(edges, edges.dropFirst()) {
            let lo = pair.0
            let hi = pair.1
            guard hi - lo >= minGutterWidth else { continue }
            let clearRows = rowBands.filter { row in
                !row.contains { $0.rect.maxX > lo && $0.rect.minX < hi }
            }.count
            if clearRows >= requiredClearRows {
                gutters.append((lo, hi))
            }
        }

        let mergedGutters = gutters.reduce(into: [(lo: CGFloat, hi: CGFloat)]()) { out, gutter in
            if var last = out.last, gutter.lo <= last.hi + minGutterWidth {
                last.hi = max(last.hi, gutter.hi)
                out[out.count - 1] = last
            } else {
                out.append(gutter)
            }
        }
        let boundaries = mergedGutters.map { ($0.lo + $0.hi) / 2 }
        var bands: [(lo: CGFloat, hi: CGFloat)] = []
        var lo = minX
        for boundary in boundaries where boundary > lo && boundary < maxX {
            bands.append((lo, boundary))
            lo = boundary
        }
        bands.append((lo, maxX))
        return bands.filter { $0.hi - $0.lo > 0 }
    }

    private func columnIndex(for x: CGFloat, in bands: [(lo: CGFloat, hi: CGFloat)]) -> Int {
        if let index = bands.firstIndex(where: { x >= $0.lo && x <= $0.hi }) { return index }
        return bands.enumerated().min {
            abs(($0.1.lo + $0.1.hi) / 2 - x) < abs(($1.1.lo + $1.1.hi) / 2 - x)
        }!.offset
    }

    private static func topLeftRect(fromVisionBox box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    private static func hasStrongColumnAlignment(
        rowBands: [[Cell]],
        columns: [(lo: CGFloat, hi: CGFloat)]
    ) -> Bool {
        var strongColumns = 0
        for column in columns {
            let lefts = rowBands.compactMap { row -> CGFloat? in
                row.first { $0.rect.midX >= column.lo && $0.rect.midX <= column.hi }?.rect.minX
            }
            guard lefts.count >= max(3, Int(ceil(Double(rowBands.count) * 0.6))) else { continue }
            let sorted = lefts.sorted()
            let median = sorted[sorted.count / 2]
            let deviations = sorted.map { abs($0 - median) }.sorted()
            let medianDeviation = deviations[deviations.count / 2]
            if medianDeviation <= max((column.hi - column.lo) * 0.08, 0.003) {
                strongColumns += 1
            }
        }
        return strongColumns >= 2
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
