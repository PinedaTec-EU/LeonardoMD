# Developer ID signed Mac walkthrough

The synthetic form and its offline signed copy were opened in the actual QA application from candidate 25755406ff170d777c59ff63e72416f7277c2e4a. Version 0.3.1969/build 1969, macOS arm64, PID 15806, started 2026-11-22 at 08:41:36 CET.

After verifying the signing key using its separately recorded fingerprint, the copy displayed the ink and the local verification status. The tester closed the form, edited its text externally and reopened it. The toolbar warned immediately, the verified ink was withheld, and the inspector presented the correction path. The header still tinted the historical signing count green in this package. The next candidate neutralizes that count.

In this instance both Help guides v116 passed enabled extension examples, disabled Math fallback and the separate practice form save and reopen checks. These are native window captures of the application, using synthetic fixtures only.
