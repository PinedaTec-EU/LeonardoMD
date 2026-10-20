(() => {
  "use strict";
  let exported = [];

  function prepare(root) {
    root.querySelectorAll("img").forEach(image => {
      image.addEventListener("error", () => {
        // Retain the authored alt text as the visible fallback. PDF readiness
        // still reports this as a failure rather than exporting missing content.
        image.dataset.leonardoImageFailed = "true";
        image.title = "Image unavailable: resource limit or read error.";
      });
    });
  }

  function preparePDF(root) {
    restorePreview();
    exported = Array.from(root.querySelectorAll("img")).flatMap(image => {
      const url = new URL(image.src, document.baseURI);
      if (url.protocol !== "leonardo-document:" || url.pathname.toLowerCase().endsWith(".svg")) return [];
      const rect = image.getBoundingClientRect();
      const previous = { image, srcset: image.getAttribute("srcset"), style: image.getAttribute("style") };
      // Freeze CSS dimensions while swapping the raster; source pixels must not
      // change the pagination or the image's intrinsic display size during PDF.
      image.style.width = `${rect.width}px`;
      image.style.height = `${rect.height}px`;
      url.searchParams.set("leonardo-image-purpose", "pdf");
      url.searchParams.set("leonardo-image-width", String(rect.width));
      url.searchParams.set("leonardo-image-height", String(rect.height));
      image.srcset = `${url.href} 1x`;
      return [previous];
    });
  }

  function restorePreview() {
    exported.forEach(({ image, srcset, style }) => {
      if (srcset === null) image.removeAttribute("srcset");
      else image.setAttribute("srcset", srcset);
      if (style === null) image.removeAttribute("style");
      else image.setAttribute("style", style);
    });
    exported = [];
  }

  window.LeonardoImages = { prepare, preparePDF, restorePreview };
})();
