# Provider logo sources

All marks are stored locally so the plugin never depends on a network request at runtime. They are rendered inside a square `PreserveAspectFit` box with transparent canvases, then colorized uniformly with the user-configurable provider-logo color (the current DankMaterialShell primary color by default). The source files may contain vendor colors, but runtime rendering is intentionally monochrome for consistent contrast in light and dark modes.

## Sources

- Most SVGs: [Lobe Icons `@lobehub/icons-static-svg` 1.91.0](https://github.com/lobehub/lobe-icons), MIT. The exact upstream slugs are the provider filename except: `glm` uses `zhipu-color`, `kilo` uses `kilocode`, and `ai21` uses `ai21-brand-color`.
- 9Router: [official `public/favicon.svg`](https://github.com/decolua/9router/blob/master/public/favicon.svg), MIT.
- BytePlus Ark: [official BytePlus favicon](https://sf-bpcms.bytepluscdn.com/obj/byteplus-public-aiso/portal/assets/favicon.png), discovered from the ModelArk product page.
- Warp: [Simple Icons `warp`](https://simpleicons.org/?q=warp), CC0-1.0, brand color `#01A4FF`.
- GitHub Copilot: [Simple Icons `githubcopilot`](https://simpleicons.org/?q=githubcopilot), CC0-1.0.
- pi: [official `logo-auto.svg`](https://pi.dev/logo-auto.svg) from [pi.dev](https://pi.dev/). Normalized to a single flat `fill` (the upstream `<style>`/`@media prefers-color-scheme` is dropped since QtSvg ignores media queries and the plugin re-tints the silhouette to the theme). Geometry unchanged.
- Hermes: original line art created for this plugin (caduceus staff with wing arcs, echoing the project's ☆ mark) — **not** a vendor asset, so no upstream trademark is redistributed. Stroke-only geometry on a transparent canvas, tinted at runtime like every other mark. Hermes Agent itself is MIT-licensed by [Nous Research](https://github.com/NousResearch/hermes-agent); swap this file for an official mark if one is published under a redistributable license.

The included license files cover the MIT-licensed Lobe Icons and 9Router assets. Product names and logos remain trademarks of their respective owners.
