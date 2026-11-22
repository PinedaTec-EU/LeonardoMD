# Signed macOS validation

Source 0de2f6ad8f0be1d9745f9aa750b520fbf20295c6. Developer ID signed 0.3.1969 build 1969. The fresh Mac process PID
18954 started at 11:59:14 CET on 22 Nov 2026, displayed its first
window and exited normally after the following tests.

The signed package rejected invalid signing-copy JSON, then unlocked the same
unsigned draft and opened its writable source editor. It warned immediately
when opening an altered sealed document and the warning followed a live change
to Spanish. The exact AppSession regression also verifies that changing a sealed
image during inspection or export invalidates the proof display, clears the
previous success status, prevents writing a stale copy and keeps protected history.

Both v117 Help guides opened through the actual Help workflow with packaged and
personal copies matching byte for byte. Live examples covered Mermaid, images,
tables, charts and tagged display math. Math fallback was checked separately.
Both practice forms were filled, saved and reopened through their guide links.
