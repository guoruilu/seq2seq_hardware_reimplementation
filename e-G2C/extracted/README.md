# Extracted Paper Assets

Source PDF: `../2022_VLSI_e-G2C.pdf`

Generated on 2026-06-26 with Poppler tools.

## Tracked Files

| File | How it was generated | Purpose |
|---|---|---|
| `paper_text.txt` | `pdftotext -layout ../2022_VLSI_e-G2C.pdf paper_text.txt` | Searchable paper text for architecture notes and implementation assumptions |
| `README.md` | Manual notes | Extraction manifest and reproduction commands |

## Local Ignored Files

The following files are useful for manual paper inspection but are ignored by Git to keep the repository small:

| File | How it was generated | Purpose |
|---|---|---|
| `pages/page_01.png` | `pdftoppm -png -r 200 ../2022_VLSI_e-G2C.pdf pages/page` then renamed | Full rendered page 1 |
| `pages/page_02.png` | `pdftoppm -png -r 200 ../2022_VLSI_e-G2C.pdf pages/page` then renamed | Full rendered page 2 |

## Reproduction Commands

Run from the repository root:

```sh
mkdir -p e-G2C/extracted/pages
pdftotext -layout e-G2C/2022_VLSI_e-G2C.pdf e-G2C/extracted/paper_text.txt
pdftoppm -png -r 200 e-G2C/2022_VLSI_e-G2C.pdf e-G2C/extracted/pages/page
mv e-G2C/extracted/pages/page-1.png e-G2C/extracted/pages/page_01.png
mv e-G2C/extracted/pages/page-2.png e-G2C/extracted/pages/page_02.png
```

`pdfimages -list` reports many small page-2 drawing/image objects, so figure-specific assets should be cropped from the rendered page images when needed instead of committed as raw extracted fragments.
