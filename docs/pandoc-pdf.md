# Pandoc PDF defaults

Repo-wide Markdown → PDF builds use **`docs/pandoc-pdf-defaults.yaml`** plus **`docs/pandoc-pdf-header.tex`** (included with Pandoc `-H`). Defaults use **`xelatex`** with **DejaVu Serif / Sans / Sans Mono** for readable body text, clean monospace for inline code, and solid Unicode coverage without extra glyph hacks. Install **`texlive-xetex`**, **`texlive-latex-recommended`**, and ensure **DejaVu** fonts are present (Debian/Ubuntu: **`fonts-dejavu-core`**; Pandoc finds them via **fontspec**).

- **`make -C docs pdf`** — uses these defaults.
- **`make -C uvm_bench pdf`** — same.
- **`make -C vlate_bench pdf`** — same.

Override or extend ad hoc:

```bash
make -C uvm_bench pdf PANDOC_PDF_OPTS='--toc'
```

Avoid **nested** `` `backticks` `` inside `**bold**` inside pipe-table cells; that markup confuses Pandoc’s LaTeX tables and hurts alignment. Prefer bullets or short plain identifiers.
