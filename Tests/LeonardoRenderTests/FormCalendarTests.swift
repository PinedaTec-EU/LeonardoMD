import AppKit
import WebKit
import XCTest
@testable import LeonardoRender

@MainActor
final class FormCalendarTests: XCTestCase {
    func testCalendarKeepsDraftsSynchronizesDatesAndUsesTheme() async throws {
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        let ready = expectation(description: "Bundled renderer ready")
        host.onReady = { [weak host] isReady in
            guard isReady else { return }
            host?.onReady = nil
            ready.fulfill()
        }
        host.apply(content: "# Calendar", baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const root = document.createElement('main'); document.body.append(root);
          LeonardoForms.begin({allowsFormFilling: true, source: 'calendar', leonardo: {document: {locale: 'es'}}}, root);
          for (let i = 0; i < 2; i++) root.append(LeonardoForms.field('date', {type: 'date', label: 'Fecha'}, '2024-02-29'));
          const input = root.querySelector('input');
          root.querySelector('.leonardo-calendar-toggle').click();
          const panel = root.querySelector('.leonardo-calendar');
          const leap = panel.querySelectorAll('[data-date]').length === 29;
          panel.querySelector('[data-date="2024-02-29"]').dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowRight', bubbles: true}));
          const keyboard = document.activeElement.dataset.date === '2024-03-01';
          panel.querySelector('[data-date="2024-03-01"]').click();
          const saved = LeonardoForms.snapshot().changes.date === '2024-03-01';
          const synchronized = [...root.querySelectorAll('input')].every(e => e.value === '2024-03-01');
          input.value = 'incomplete'; input.dispatchEvent(new Event('input'));
          root.querySelector('.leonardo-calendar-toggle').click();
          const draft = input.value === 'incomplete';
          document.documentElement.style.setProperty('--ld-background', 'rgb(20, 30, 40)');
          const themed = getComputedStyle(panel).backgroundColor === 'rgb(20, 30, 40)';
          root.querySelector('.leonardo-calendar-toggle').dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
          const escaped = panel.hidden;
          LeonardoForms.begin({allowsFormFilling: true, source: 'locale', leonardo: {document: {locale: 'not_a_locale'}}}, root);
          const malformed = LeonardoForms.field('malformed', {type: 'date'}, '2024-02-29'); root.append(malformed);
          malformed.querySelector('.leonardo-calendar-toggle').click();
          const fallbackLocale = malformed.querySelector('.leonardo-calendar-header').textContent.includes('February') && malformed.querySelectorAll('[data-date]').length === 29;
          malformed.querySelector('[data-date="2024-02-28"]').click();
          const fallbackSelection = LeonardoForms.snapshot().changes.malformed === '2024-02-28';
          LeonardoForms.begin({allowsFormFilling: true, source: 'gregorian', leonardo: {document: {locale: 'en-u-ca-islamic'}}}, root);
          const gregorian = LeonardoForms.field('gregorian', {type: 'date'}, '2024-02-29'); root.append(gregorian);
          gregorian.querySelector('.leonardo-calendar-toggle').click();
          const gregorianLocale = gregorian.querySelector('.leonardo-calendar-header').textContent.includes('February 2024') && gregorian.querySelector('[data-date="2024-02-29"]').getAttribute('aria-label').includes('February 29, 2024');
          LeonardoForms.setExporting(true);
          const exported = getComputedStyle(root.querySelector('.leonardo-calendar-toggle')).display === 'none';
          LeonardoForms.begin({allowsFormFilling: false}, root);
          const locked = LeonardoForms.field('locked', {type: 'date'}, '2024-02-29'); root.append(locked);
          const lockedInput = locked.querySelector('input');
          locked.querySelector('.leonardo-calendar-toggle').click();
          lockedInput.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowDown', altKey: true, bubbles: true}));
          const protectedDate = locked.querySelector('.leonardo-calendar-toggle').disabled && locked.querySelector('.leonardo-calendar').hidden && lockedInput.value === '2024-02-29' && Object.keys(LeonardoForms.snapshot().changes).length === 0;
          return {leap, keyboard, saved, synchronized, draft, themed, escaped, exported, protectedDate, fallbackLocale, fallbackSelection, gregorianLocale};
        })()
        """) as? [String: Bool]
        let checks = try XCTUnwrap(result)
        for (name, passed) in checks { XCTAssertTrue(passed, name) }
        XCTAssertEqual(checks.count, 12)
    }

    func testBlurBeforePointerActivationDoesNotDismissInsideControls() async throws {
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        let ready = expectation(description: "Blur sequence ready")
        host.onReady = { [weak host] value in
            guard value else { return }
            host?.onReady = nil
            ready.fulfill()
        }
        host.apply(content: "# Pointer calendar", baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        _ = try await webView.evaluateJavaScript("""
        (() => {
          const root = document.createElement('main'); root.id = 'blur-calendar'; document.body.append(root);
          LeonardoForms.begin({allowsFormFilling: true, source: 'blur'}, root);
          root.append(LeonardoForms.field('date', {type: 'date'}, '2026-10-17'));
          root.querySelector('.leonardo-calendar-toggle').click();
          document.activeElement.blur();
          return true;
        })()
        """)
        // A second WebKit task lets the blur microtask run before pointer activation.
        let visible = try await webView.evaluateJavaScript("!document.querySelector('#blur-calendar .leonardo-calendar').hidden") as? Bool
        XCTAssertEqual(visible, true)
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const root = document.querySelector('#blur-calendar');
          root.querySelector('[aria-label="Next month"]').click();
          const next = root.querySelector('.leonardo-calendar-header').textContent.includes('November');
          root.querySelector('[data-date="2026-11-18"]').click();
          const selected = LeonardoForms.snapshot().changes.date === '2026-11-18';
          root.querySelector('.leonardo-calendar-toggle').click();
          const outside = document.createElement('input'); document.body.append(outside); outside.focus();
          return next && selected && root.querySelector('.leonardo-calendar').hidden;
        })()
        """) as? Bool
        XCTAssertEqual(result, true)
    }
}
