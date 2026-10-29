import { Cite } from '@citation-js/core';
import '@citation-js/plugin-bibtex';
import '@citation-js/plugin-csl';

// Keep the browser bundle's public surface deliberately small. The renderer
// loads this value through its feature-owned callback rather than consulting a
// mutable global directly.
globalThis.LeonardoCitationEngine = Object.freeze({ Cite });
