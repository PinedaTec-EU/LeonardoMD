import AppKit
import LeonardoCore
import PDFKit
@testable import LeonardoRender
import WebKit
import XCTest

@MainActor
final class TablePaginationTests: XCTestCase {
    func testLongTableKeepsRowsAndColumnWidthsAcrossPreviewRefreshAndPDF() async throws {
        let rows = (1...22).map { String(format: "Record%02dZ", $0) }
        let table = rows.enumerated().map { index, value in
            let detail = index.isMultiple(of: 3) ? "Wrapped details with a longer description for this sample record" : "Short"
            return "| \(value) | \(detail) |"
        }.joined(separator: "\n")
        let body = "First physical page\n\n<!-- leonardo:page-break -->\n\nIntro on page two\n\n## Records\n\n"
            + "| RecordKey | Details |\n| --- | --- |\n" + table
            + "\n\n<!-- leonardo:page-break -->\n\n| Last table |\n| --- |\n| Footnote |"
        try await withPreview(body, height: 360) { host, web in
            let probe = """
            (() => {
              const tables = Array.from(document.querySelectorAll('table')).slice(0, -1);
              const rows = tables.flatMap(table => Array.from(table.tBodies[0].rows, row => row.cells[0].textContent));
              const widths = tables.map(table => Array.from(table.tBodies[0].rows[0].cells,
                cell => cell.getBoundingClientRect().width));
              return {
                rows, pages: tables.map(table => Number(table.closest('.leonardo-page').dataset.page)),
                introPage: Number(document.querySelector('h2').closest('.leonardo-page').dataset.page),
                headers: tables.map(table => table.tHead.rows[0].cells[0].textContent),
                overflow: !!document.querySelector('.leonardo-page[data-overflow]'),
                matchingWidths: widths.every(set => set.every((width, index) => Math.abs(width - widths[0][index]) < 1)),
                finalPage: Number(Array.from(document.querySelectorAll('table')).at(-1).closest('.leonardo-page').dataset.page)
              };
            })()
            """
            for _ in 0..<3 {
                let measured = try await web.evaluateJavaScript(probe)
                let result = try XCTUnwrap(measured as? [String: Any])
                let pages = try XCTUnwrap(result["pages"] as? [Int])
                XCTAssertGreaterThanOrEqual(pages.count, 3)
                XCTAssertEqual(pages.first, 2)
                XCTAssertEqual(pages.first, result["introPage"] as? Int)
                XCTAssertEqual(pages.last.map { $0 + 1 }, result["finalPage"] as? Int)
                XCTAssertEqual(result["rows"] as? [String], rows)
                XCTAssertEqual(result["headers"] as? [String], Array(repeating: "RecordKey", count: pages.count))
                XCTAssertEqual(result["overflow"] as? Bool, false)
                XCTAssertEqual(result["matchingWidths"] as? Bool, true)
                _ = try await web.evaluateJavaScript("window.LeonardoObjects.refresh()")
            }

            try await captureIfRequested(web)
            let data = try await host.exportPDF()
            let pdf = try XCTUnwrap(PDFDocument(data: data))
            let text = try XCTUnwrap(pdf.string)
            for row in rows { XCTAssertEqual(text.components(separatedBy: row).count, 2, row) }
            XCTAssertTrue(pdf.page(at: 0)?.string?.contains("First physical page") == true)
            XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Records") == true)
            for index in 1..<(pdf.pageCount - 1) {
                XCTAssertTrue(pdf.page(at: index)?.string?.contains("RecordKey") == true)
            }
            XCTAssertTrue(pdf.page(at: pdf.pageCount - 1)?.string?.contains("Footnote") == true)
        }
    }

    func testShortTableMovesWithItsHeadingAndLongTableCanOmitRepeatedHeader() async throws {
        let filler = String(repeating: "Filler paragraph.\n\n", count: 4)
        let body = filler + "## Short table\n\n| Key |\n| --- |\n| One |\n| Two |\n"
            + "\n<!-- leonardo:page-break -->\n\n| Unique header |\n| --- |\n"
            + String(repeating: "| Another record |\n", count: 14)
        try await withPreview(body, tables: [.init(occurrence: 2, repeatHeader: false)]) { _, web in
            let samePage = try await web.evaluateJavaScript("""
            document.querySelector('h2').closest('.leonardo-page') === document.querySelector('table').closest('.leonardo-page') &&
            document.querySelector('h2').closest('.leonardo-page').dataset.page === '2'
            """) as? Bool
            XCTAssertEqual(samePage, true)
            let headers = try await web.evaluateJavaScript("document.querySelectorAll('table thead').length") as? Int
            XCTAssertEqual(headers, 2)
            let continuation = try await web.evaluateJavaScript("document.querySelectorAll('.table-fragmented').length") as? Int
            XCTAssertGreaterThan(try XCTUnwrap(continuation), 1)
        }
    }

    func testOneOverHeightRowStopsPDFWithoutDroppingLaterRows() async throws {
        let body = "| Header |\n| --- |\n| Tall row |\n| Next row |\n\n<!-- leonardo:page-break -->\n\nAfterwards"
        try await withPreview(body, tables: [.init(occurrence: 1, rowHeights: [24, 300, 24])]) { host, web in
            let lastRowPageOverflows = try await web.evaluateJavaScript("""
            Array.from(document.querySelectorAll('.table-fragmented tbody tr')).map(row =>
              [row.textContent.trim(), row.closest('.leonardo-page').dataset.overflow ?? 'false'].join(':')).join(',')
            """) as? String
            XCTAssertEqual(lastRowPageOverflows, "Tall row:true,Next row:false")
            do {
                _ = try await host.exportPDF()
                XCTFail("Oversized rows must not be clipped silently")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("Content exceeds page height"))
            }
        }
    }

    private func withPreview(
        _ body: String,
        tables: [LeonardoTableLayout] = [],
        height: Double = 280,
        _ assertions: @MainActor (MarkdownPreviewHost, WKWebView) async throws -> Void
    ) async throws {
        let page = LeonardoPageLayout(size: .custom, widthPoints: 420, heightPoints: height)
        let source = try LeonardoFormatParser.serialize(.init(body: body, metadata: .init(layout: .init(page: page, tables: tables))))
        var config = MarkdownPreviewConfiguration()
        config.allowsLeonardoFormat = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 900, height: 820))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        host.apply(content: source, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.first as? WKWebView)
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("!!document.querySelector('.leonardo-page table')")) as? Bool == true {
                try await assertions(host, web)
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Paginated table never appeared")
    }

    private func captureIfRequested(_ web: WKWebView) async throws {
        guard let directory = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else { return }
        let output = URL(fileURLWithPath: directory).appendingPathComponent("table-pagination")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = try await web.evaluateJavaScript("document.querySelector('.leonardo-page[data-page=\"2\"]').scrollIntoView()")
        try await Task.sleep(for: .milliseconds(150))
        let image = try await web.takeSnapshot(configuration: nil)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("records-preview.png"))
        let environment = try await web.evaluateJavaScript("""
        JSON.stringify({browser: navigator.userAgent, width: innerWidth, height: innerHeight, capturedAt: new Date().toISOString()})
        """)
        try XCTUnwrap(environment as? String).write(
            to: output.appendingPathComponent("webkit-environment.json"), atomically: true, encoding: .utf8
        )
    }
}
