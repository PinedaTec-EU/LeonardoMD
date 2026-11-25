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

    func testHeadingBoundaryDoesNotCreateBlankPageWhenPairCannotFitTogether() async throws {
        let body = "## Table heading\n\n| Key | Detail |\n| --- | --- |\n| First | Row |\n| Second | Row |\n\n<!-- leonardo:page-break -->\n\nAfter the table"
        // The heading plus the first 50-point row is larger than this page's
        // remaining area, while the table fragment fits on a fresh page.
        try await withPreview(body, tables: [.init(occurrence: 1, rowHeights: [24, 50, 24])], height: 180) { _, web in
            let probe = try await web.evaluateJavaScript("""
            (() => {
              const pages = Array.from(document.querySelectorAll('.leonardo-page'));
              const headingPage = document.querySelector('h2').closest('.leonardo-page');
              const tablePages = Array.from(document.querySelectorAll('.table-viewport'))
                .map(table => Number(table.closest('.leonardo-page').dataset.page));
              return {
                pageCount: pages.length,
                headingPage: Number(headingPage.dataset.page),
                tablePages,
                blankPage: pages.some(page => !page.innerText.trim()),
                overflow: pages.some(page => page.dataset.overflow === 'true')
              };
            })()
            """) as? [String: Any]
            let result = try XCTUnwrap(probe)
            let tablePages = try XCTUnwrap(result["tablePages"] as? [Int])
            XCTAssertGreaterThanOrEqual(result["pageCount"] as? Int ?? 0, 2)
            XCTAssertEqual(result["headingPage"] as? Int, 1)
            XCTAssertTrue(tablePages.allSatisfy { $0 > 1 })
            XCTAssertEqual(result["blankPage"] as? Bool, false)
            XCTAssertEqual(result["overflow"] as? Bool, false)
        }
    }

    func testUnsupportedSpanTableMarksOverflowAndRejectsPDF() async throws {
        let body = "| Header | Detail |\n| --- | --- |\n"
            + String(repeating: "| Record | Description |\n", count: 3)
            + "\n<!-- leonardo:page-break -->\n\nAfter the table"
        for attribute in ["colspan", "rowspan"] {
            try await withPreview(body, tables: [.init(occurrence: 1, rowHeights: [24, 80, 80, 80])], height: 180) { host, web in
                let probe = try await web.evaluateJavaScript("""
                (() => {
                  const cell = document.querySelector('table tbody tr td');
                  cell.setAttribute('\(attribute)', '2');
                  window.LeonardoObjects.refresh();
                  return {
                    attribute: cell.getAttribute('\(attribute)'),
                    fragmented: document.querySelectorAll('.table-fragmented').length,
                    overflow: document.querySelectorAll('.leonardo-page[data-overflow]').length
                  };
                })()
                """) as? [String: Any]
                let result = try XCTUnwrap(probe)
                XCTAssertEqual(result["attribute"] as? String, "2")
                XCTAssertEqual(result["fragmented"] as? Int, 0)
                XCTAssertGreaterThan(result["overflow"] as? Int ?? 0, 0)
                do {
                    _ = try await host.exportPDF()
                    XCTFail("Unsupported spanning tables must not be clipped silently")
                } catch {
                    XCTAssertTrue(error.localizedDescription.contains("Content exceeds page height"))
                }
            }
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
}
