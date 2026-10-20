(() => {
  "use strict";
  let exported = [];
  const fallbacks = new WeakMap();

  function prepare(root) {
    root.querySelectorAll("img").forEach(image => {
      const failed = () => {
        image.dataset.leonardoImageFailed = "true";
        if (fallbacks.has(image)) return;
        const fallback = document.createElement("span");
        fallback.className = "leonardo-image-unavailable";
        fallback.setAttribute("role", "status");
        fallback.textContent = image.alt || "Image unavailable";
        fallback.title = "Image unavailable: resource limit or read error.";
        image.after(fallback);
        fallbacks.set(image, fallback);
      };
      image.addEventListener("error", failed);
      image.addEventListener("load", () => {
        delete image.dataset.leonardoImageFailed;
        fallbacks.get(image)?.remove();
        fallbacks.delete(image);
      });
      if (image.complete && image.naturalWidth === 0) failed();
    });
  }

  async function preparePDF(root) {
    restorePreview();
    exported = Array.from(root.querySelectorAll("img")).flatMap(image => {
      const url = new URL(image.src, document.baseURI);
      if (url.protocol !== "leonardo-document:" || url.pathname.toLowerCase().endsWith(".svg")) return [];
      const rect = image.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) return [];
      const style = getComputedStyle(image);
      const previous = { image, srcset: image.getAttribute("srcset"), style: image.getAttribute("style") };
      // Freeze CSS dimensions while swapping the raster; source pixels must not
      // change the pagination or the image's intrinsic display size during PDF.
      image.style.width = style.width;
      image.style.height = style.height;
      url.searchParams.set("leonardo-image-purpose", "pdf");
      url.searchParams.set("leonardo-image-width", String(rect.width));
      url.searchParams.set("leonardo-image-height", String(rect.height));
      image.srcset = `${url.href} 1x`;
      return [previous];
    });
    // decode() follows source selection and waits for the new srcset variant.
    // Checking complete immediately after assigning srcset can see old pixels.
    await Promise.all(exported.map(({ image }) => image.decode()));
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
