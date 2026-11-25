# macOS Home validation

App source `58096da5fcc7df8c7276cf0a215d3d86a85076b2`, packaged QA build 0.3.2288 on macOS 27.2.1. Launch with `LEONARDO_SOURCE_PR=599 ./launch.sh --qa`; for an empty Home, use a disposable macOS profile without favorites, history or accepted shares. Open a new tab.

- [Projects with all sections expanded](home-empty.jpg) shows the order and the empty remote guidance.
- [Documents with Favorites and Recents collapsed](home-documents.jpg) shows that the selected type controls Open and that Remotes stays expanded.
- English, Leonardo Classic. Window 2520 by 1700 backing pixels, images reduced to 1150 pixels wide. Captured from the running native app at 17:13–17:15 CET on 2026-11-25.
- [Packaged remote preview and bilingual Help checks](https://github.com/PinedaTec-EU/LeonardoMD/pull/599#issuecomment-7166218977) used the same executable and a synthetic remote project.
