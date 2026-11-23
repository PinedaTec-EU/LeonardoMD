import AppKit
import WebKit
import XCTest
import LeonardoCore
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

    func testGuidedSigningRubricFieldsCannotUseInsertRubricBypass() async throws {
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        let ready = expectation(description: "Guided form renderer ready")
        host.onReady = { [weak host] isReady in
            guard isReady else { return }
            host?.onReady = nil
            ready.fulfill()
        }
        var configuration = MarkdownPreviewConfiguration.default
        configuration.allowsFormFilling = true
        configuration.allowsLeonardoFormat = true
        configuration.guidedSigningFieldIDs = ["signature"]
        configuration.guidedSigningRubricOverlays = [
            "signature#1": LeonardoRubric(strokes: [
                .init(color: "#224488", width: 3, style: .solid,
                      points: [.init(x: 20, y: 40), .init(x: 300, y: 100)])
            ])
        ]
        let source = """
        ---
        {"format":"mdlf","formatVersion":2,"document":{"id":"guided-render-test","kind":"form","title":"Guided signing","revision":1},"fields":{"signature":{"type":"rubric","label":"Signature"}},"values":{}}
        ---
        # Guided signing

        Signature: {{field:signature}} / {{field:signature}}
        """
        host.apply(content: source, baseURL: nil, configuration: configuration,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const payload = JSON.parse(document.getElementById('leonardo-payload').textContent);
          const root = document.createElement('main'); document.body.append(root);
          LeonardoForms.begin(payload, root);
          const field = LeonardoForms.field('signature', {type: 'rubric', label: 'Signature'}, null);
          root.append(field);
          const button = field.querySelector('button.leonardo-rubric-field');
          button.dispatchEvent(new MouseEvent('click', {bubbles: true}));
          field.querySelector('.leonardo-field-help').dispatchEvent(new MouseEvent('click', {bubbles: true}));
          const overlayRoot = document.createElement('main');
          overlayRoot.innerHTML = '<p>{{field:signature}} / {{field:signature}}</p>';
          document.body.append(overlayRoot);
          const overlayPayload = Object.assign({}, payload, {
            leonardo: {fields: {signature: {type: 'rubric', label: 'Signature'}}, values: {}, layout: {}}
          });
          LeonardoLayout.apply(overlayRoot, overlayPayload);
          const occurrences = [...overlayRoot.querySelectorAll('.leonardo-form-field')];
          return {
            payloadIDs: payload.guidedSigningFieldIDs,
            overlayKeys: Object.keys(payload.guidedSigningRubricOverlays || {}),
            disabled: button.disabled,
            text: button.textContent,
            aria: button.getAttribute('aria-label'),
            helpDisabled: field.querySelector('.leonardo-field-help').disabled,
            guidedClass: field.classList.contains('leonardo-guided-signing-field'),
            changes: Object.keys(LeonardoForms.snapshot().changes).length,
            overlayCount: occurrences.length,
            firstOverlay: occurrences[0].querySelector('svg') !== null,
            secondOverlay: occurrences[1].querySelector('svg') !== null,
            secondOccurrence: occurrences[1].dataset.fieldOccurrence === '1'
          };
        })()
        """) as? [String: Any]
        let checks = try XCTUnwrap(result)
        XCTAssertEqual(checks["payloadIDs"] as? [String], ["signature"])
        XCTAssertEqual(checks["overlayKeys"] as? [String], ["signature#1"])
        XCTAssertEqual(checks["disabled"] as? Bool, true)
        XCTAssertEqual(checks["text"] as? String, "Guided signing")
        XCTAssertEqual(checks["aria"] as? String, "Guided signing Signature")
        XCTAssertEqual(checks["helpDisabled"] as? Bool, true)
        XCTAssertEqual(checks["guidedClass"] as? Bool, true)
        XCTAssertEqual(checks["changes"] as? Int, 0)
        XCTAssertEqual(checks["overlayCount"] as? Int, 2)
        XCTAssertEqual(checks["firstOverlay"] as? Bool, false)
        XCTAssertEqual(checks["secondOverlay"] as? Bool, true)
        XCTAssertEqual(checks["secondOccurrence"] as? Bool, true)
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
