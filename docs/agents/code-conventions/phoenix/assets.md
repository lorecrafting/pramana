# Phoenix asset conventions

Applies to Pramāṇa's Phoenix JS, CSS and Tailwind asset pipeline. These are project
defaults derived from the Phoenix generator, not generic Elixir requirements.

- Use Tailwind classes and custom CSS for the existing Phoenix asset stack.
- For this Tailwind v4 project, retain the `source(none)` import structure in
  `app.css` and keep the applicable source roots declared.
- Do not use `@apply` in raw CSS.
- Prefer project-owned Tailwind components rather than adding daisyUI merely for
  prebuilt components.
- The generated project supports the `app.js` and `app.css` bundles; import vendor
  dependencies into those bundles rather than adding external script/link tags to
  layouts.
- Do not add raw inline `<script>` tags to HEEx templates. LiveView-specific inline
  behavior belongs in colocated hooks described in the
  [LiveView conventions](liveview.md).

[Code convention router](../README.md)
