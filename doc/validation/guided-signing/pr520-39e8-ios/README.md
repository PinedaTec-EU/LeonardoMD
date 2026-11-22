# PR #520 iOS captures

These original simulator captures use synthetic documents and production views
from source `39e8a0a2ea86708a975af9e7d49158106ea063d8` on iOS Simulator 26.5.
The original sidecars record the state, capture time, dimensions and SHA-256.

- [Full document before trust confirmation](documento-sin-confianza-confirmada.png)
- [Verified ink in the native text view](documento-con-rubrica-verificada.png)
- [Referenced image visible in the native text view](imagen-referenciada-visible.png)
- [Unavailable referenced image blocks confirmation](imagen-ilegible-confirmacion-bloqueada.png)

The verified-ink screenshot shows the native text view. WebKit overlay behavior
is covered by `testTrustedSignedReaderRendersVerifiedRubricOverlay` in the
[exact-source iOS CI run](https://github.com/PinedaTec-EU/LeonardoMD/actions/runs/44995834758/job/137126583171).
This branch contains evidence only.
