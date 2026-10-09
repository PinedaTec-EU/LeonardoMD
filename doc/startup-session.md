# Startup session

Preferences → On startup is a global choice, including when editing project preferences:

- **Restore previous session** (default): reopen the projects and documents in the previous windows, retaining tab order and selected tabs.
- **Start clean**: show an empty viewer, retaining recent items and other preferences.

The choice applies on the next fresh application launch. Opening files explicitly (Finder or command line) takes priority over restoration. New windows and tabs open empty. Reopening an application that is still running brings its existing windows forward.

Command-W closes the active tab, leaving an empty tab when it was the last one. Command-Shift-W closes a window. Command-Q quits after pending saves finish; a protected conflict can prevent quitting.

Session capture stores file locations only in `~/Library/Application Support/LeonardoMD/session.json`. Missing locations are skipped and leave their tabs empty. Preferences remain in `preferences.json`; projects cannot override the startup choice. A corrupt session reports an error and keeps the empty viewer usable. Session recovery after an abrupt crash is limited to the last successful capture.

Tracking: [#90](https://github.com/PinedaTec-EU/LeonardoMD/issues/90).
