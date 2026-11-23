# OfficeCLI DOCX Elements, Reading, and Editing

## Quick Start

Minimal viable docx: a heading, a body paragraph, a subheading, and a footer with a live page-number field. Adapt, don't copy-paste — your file, your content.

```bash
FILE="review.docx"
officecli create "$FILE"
officecli open "$FILE"
officecli add "$FILE" /body --type paragraph --prop text="Q4 2026 Review" --prop style=Heading1 --prop size=20pt --prop bold=true --prop spaceAfter=12pt
officecli add "$FILE" /body --type paragraph --prop text="Revenue grew 18% year-over-year, ahead of plan." --prop size=11pt --prop spaceAfter=8pt
officecli add "$FILE" /body --type paragraph --prop text="Key Drivers" --prop style=Heading2 --prop size=14pt --prop bold=true --prop spaceBefore=12pt --prop spaceAfter=6pt
officecli add "$FILE" /body --type paragraph --prop text="Enterprise renewals, upsell, and a new EMEA region." --prop size=11pt
officecli add "$FILE" / --type footer --prop type=default --prop size=9pt --prop text="Page " --prop field=page
officecli set "$FILE" "/footer[1]/p[1]" --prop align=center
officecli save "$FILE"
officecli validate "$FILE"
```

Verified: `validate` returns `no errors found`; `get /footer[1] --depth 3` shows the 5-run PAGE field chain (begin / instrText / separate / cached value / end).

## Reading & Analysis

Start wide, then narrow. `outline` tells you what's already there; jump into `view text` / `get` / `query` once you know where to look.

```bash
officecli view "$FILE" outline            # heading tree, section count, table/image counts, watermark, tracked-changes presence — orient here first
officecli view "$FILE" html               # Read the returned HTML path: first visual check after a batch of edits (hierarchy, empty-para spacing, missing TOC)
officecli view "$FILE" text --start 1 --end 80   # text for content QA; paths shown as [/body/p[N]] so you can jump back with get
officecli view "$FILE" annotated          # values + style/font/size + warnings per run
officecli view "$FILE" stats              # paragraph counts, font usage, style distribution
officecli view "$FILE" issues             # empty paras, missing alt text, spacing anomalies
```

`officecli watch "$FILE"` keeps a live preview running for the human user to open at their discretion — agent self-check uses `view html`. Final visual verification is the user opening the `.docx` in Word / WPS / Pages.

**Inspect one element.** XPath-style semantic paths (1-based). Always quote — shells glob `[N]`. Use `[last()]` (with parens) for the last element; `[last]` errors. Add `--json` for machine output.

```bash
officecli get "$FILE" /                          # document root: metadata, page setup
officecli get "$FILE" "/body/p[1]"                # one paragraph
officecli get "$FILE" "/body/p[1]/r[1]"           # one run (character-level formatting)
officecli get "$FILE" "/body/tbl[1]" --depth 3    # table with rows and cells
officecli get "$FILE" "/footer[1]" --depth 3      # footer — check for fldChar
officecli get "$FILE" "/styles/Heading1"          # style definition
officecli get "$FILE" /numbering --depth 2        # numbering abstractNum + num bindings
```

**Query across the document.** CSS-like selectors, for systematic checks rather than hand-walking. Operators: `=`, `!=`, `~=` (contains), `>=`, `<=`, `[attr]` (exists). Full reference: `officecli query --help`.

```bash
officecli query "$FILE" 'paragraph[style=Heading1]'       # all H1s
officecli query "$FILE" 'p:contains("quarterly")'         # text match
officecli query "$FILE" 'p:empty'                         # empty paragraphs (clutter)
officecli query "$FILE" 'image:no-alt'                    # accessibility gaps
officecli query "$FILE" 'paragraph[size>=24pt]'           # numeric comparison
officecli query "$FILE" 'field[fieldType!=page]'          # fields other than PAGE
```

`query --json` wraps results in `.data.results[]` — `jq '.data.results | length'` to count.

**Large documents.** Navigate by heading with `view outline` and jump with `query`; don't dump the whole body into context.

## Creating & Editing

Verbs: `add` (new element), `set` (change a prop), `remove`, `move`, `swap`, `batch`, `raw-set` (last-resort XML). Ninety percent of a build is paragraphs, runs, tables, a couple of images, a TOC, and a footer.

### Paragraphs, runs, styles

A paragraph (`p`) is a block; a run (`r`) is a span of consistent character formatting inside it. Set paragraph-level props (style, alignment, spacing, indent) on the `p`; set font / size / color / bold on the `r`.

```bash
officecli add "$FILE" /body --type paragraph --prop text="Executive Summary" --prop style=Heading1 --prop size=18pt --prop bold=true --prop spaceAfter=12pt
officecli set "$FILE" "/body/p[1]/r[1]" --prop color=1F4E79
```

Use `spaceBefore` / `spaceAfter` for vertical spacing — never chains of empty paragraphs. For left indent use `--prop indent=720` (twips), `firstLineIndent=360` for first line, `hangingIndent=720` for hanging; leading spaces fire `view issues`.

### Tables

Tables are `/body/tbl[N]` with rows `tr[N]` and cells `tc[N]`. Add with row/column counts, then fill.

```bash
officecli add "$FILE" /body --type table --prop rows=4 --prop cols=3 --prop width=100%
officecli set "$FILE" "/body/tbl[1]/tr[1]" --prop header=true --prop c1=Quarter --prop c2="Revenue" --prop c3="Growth"
officecli set "$FILE" "/body/tbl[1]/tr[1]/tc[1]/p[1]/r[1]" --prop bold=true
```

Row-level `set` supports `height`, `header`, and `c1 / c2 / … / cN` text shortcuts (`cN` generalises to any column count). Cell formatting (bold, fill, color) goes on the cell's paragraph / run — **not** row-level. For per-cell borders, set cell-level `border.*` on the `tc` (`--prop border.bottom="single;6;000000;0"`), or paragraph-level `pbdr.*` on the inner paragraph.

**Horizontal rule = a paragraph bottom border, never a 1-row table.** A table-as-divider renders as an empty min-height box (worst in headers/footers). Use `pbdr.bottom` (`STYLE;SIZE;COLOR`) on the paragraph instead:

```bash
officecli set "$FILE" "/body/p[3]" --prop pbdr.bottom="single;6;2E75B6"
```

### Lists (bullets, numbered, multi-level)

For single-level bullets/numbers, set `listStyle` on the paragraph (`listStyle` is a paragraph prop, NOT a run prop — common mistake):

```bash
officecli add "$FILE" /body --type paragraph --prop text="First item" --prop listStyle=bullet
```

For multi-level (legal-style 1 / 1.1 / 1.1.1), add an `abstractNum`, then a `num`, then reference the `numId` per paragraph:

```bash
officecli add "$FILE" /numbering --type abstractnum --prop format=decimal     # → abstractNum id=0
officecli add "$FILE" /numbering --type num --prop abstractNumId=0             # → num id=1
officecli add "$FILE" /body --type paragraph --prop text="Section one" --prop numId=1 --prop ilvl=0
```

IDs are 0-based: the first `abstractNum` is id=0; the `num` references it via `abstractNumId=0` and is itself assigned id=1. A non-existent `abstractNumId` errors, so check ids after creating. Verify with `officecli query "$FILE" 'paragraph[numId>0]'`. See `help docx abstractnum` / `help docx num` for level and format options.

### Tab stops (signature lines, leader rows)

Tab stops are a first-class `tab` child of the paragraph; `pos` accepts `6in`/`6cm`/twips, `val` ∈ `left`/`center`/`right`, `leader` ∈ `none`/`dot`/`hyphen`/`underscore`. See `help docx tab`.

```bash
officecli add "$FILE" "/body/p[1]" --type tab --prop pos=6in --prop val=right --prop leader=dot
```

**Leader caveat.** `leader=dot` alone emits no dots — the leader renders only when a real `<w:tab/>` character sits in a run between the text and the tab stop. Put one there with `\t` in the text: define the stop (`add tab --prop pos=6in --prop val=right --prop leader=dot`), then `--prop text="Chapter 1\t12"` — the `\t` becomes the `<w:tab/>` and dots fill to the right-aligned page number. (Literal `text="Chapter 1 ......... 12"` also ships, but a real tab stop aligns cleanly.)

### Fields (PAGE / NUMPAGES / DATE / MERGEFIELD / REF)

Fields are live values computed at render time. `fieldType` picks the field; `name` supplies the target (merge name or `ref` bookmark); `format` / `instr` add switches.

| Field | Use | Example |
|---|---|---|
| `page` | current page number | `--prop field=page` on footer, or `--prop fieldType=page` inline |
| `numpages` | total pages | `--prop field=numpages` / `--prop fieldType=numpages` |
| `date` | today | `--prop fieldType=date --prop format='yyyy-MM-dd'` |
| `mergefield` | template merge token | `--prop fieldType=mergefield --prop name=CustomerName` |
| `ref` | cross-reference to a bookmark | `--prop fieldType=ref --prop name=bookmarkName` |

Full `fieldType` enum (30+ values incl. `pageref`, `seq`, `styleref`, `docproperty`, `createdate`, …) is in `help docx field`. **There is NO `fieldInstr` fieldType** — use the `instruction` prop for raw field instruction text when typed shortcuts fall short. Picture switches (`MERGEFIELD Amount \# "#,##0.00"`, `DATE \@ "yyyy年MM月"`) go via `--prop instruction='…'` (mergefield's `format` prop is ignored with a warning — use `instruction`).

```bash
officecli add "$FILE" "/body/p[3]" --type field --prop fieldType=mergefield --prop name=customer_name
# Renders «customer_name» — visible placeholder, replaced in Word at mail-merge time.
```

**MERGEFIELD templates: never render placeholder literals.** A `{{customer_name}}` or `$NAME$` shown as body text is a failed template the recipient sees — insert a real MERGEFIELD (above), or confine literal tokens to an obvious instruction paragraph. Confirm with `query 'field[fieldType=mergefield]'`.

**SEQ / PAGEREF / TOC field values.** officecli doesn't store rendered field values at write time. Recompute by what each path needs:

- **SEQ numbering** (`Figure 1/2/3`): `officecli set "$FILE" / --prop recalcFields=seq` counts SEQ fields in body document order and writes the cached values (`evaluated` flips true; switches/formats in `help docx document`). Heading-relative `\s` and SEQ in headers/footers defer to Word.
- **PAGE / PAGEREF / NUMPAGES / TOC page numbers** need pagination, which officecli has no engine for — `officecli set "$FILE" /settings --prop updateFields=true` defers them to Word on open.

Use both on a multi-figure document. Academic papers: see the `academic-paper` Playbook.

### Headers & Footers (page numbering)

Single-command pattern — the CLI injects `<w:fldChar>`, so you never compose the field by hand:

```bash
# Empty first-page footer — auto-enables differentFirstPage so the cover has no page number
officecli add "$FILE" / --type footer --prop type=first --prop text=""
# Default footer with live page number
officecli add "$FILE" / --type footer --prop type=default --prop align=center --prop size=9pt --prop text="Page " --prop field=page
```

When both exist, the default footer is `/footer[2]`; alone it is `/footer[1]`. **Verify**: `get --depth 3` must show `fldChar` children, not just a run with literal `"Page"` (`view outline` prints "Footer: Page" for both live fields AND static text — don't rely on it). Do NOT `set --prop differentFirstPage=true` — that prop is unsupported (rejected with exit 2, not silently); adding a first-type footer flips the bit. For composite **Page X of Y**, see recipe (b) in `recipes-and-specialty.md`.

### Table of Contents

For any document with three or more headings, first verify that the requested range has real sources. A TOC source must use a built-in Heading style or a custom paragraph style with `outlineLvl`; bold or large Normal text is not a source. If no eligible source exists, fix the heading structure instead of inserting a TOC that renders "Error! No table of contents entries found."

```bash
# Built-in Heading styles are TOC sources.
officecli add "$FILE" /body --type paragraph --prop text="Introduction" --prop style=Heading1
# Custom paragraph styles need an outline level (0 is Heading 1).
officecli add "$FILE" /styles --type style --prop id=ThesisH1 --prop type=paragraph --prop outlineLvl=0
# Add the TOC only after its sources exist.
officecli add "$FILE" /body --type toc --prop levels="1-3" --prop title="Table of Contents" --prop hyperlinks=true --index 0
```

Page numbers need pagination; OfficeCLI cannot calculate TOC page numbers itself. Set `updateFields=true` so Word recomputes the TOC and all fields on open. Without a Word-compatible field engine, report the TOC as dynamic and uncomputed; do not claim ready page numbers or guess a static TOC.

```bash
officecli set "$FILE" /settings --prop updateFields=true
```

Address the TOC directly with `/toc[1]` or `/tableofcontents` for `get`, `set`, or `remove`.

### Images

Pictures go inside a run. Alt text is mandatory for accessibility — pass `alt` directly at create time:

```bash
officecli add "$FILE" "/body/p[5]" --type picture --prop src=logo.png --prop width=1.5in --prop alt="Acme logo"
```

Confirm `officecli query "$FILE" 'image:no-alt'` is empty before delivery.

### Charts

For data, add a **native chart** — editable, themeable, accessible, re-renders in Word — never a flat PNG screenshot of a chart. `data="Label:v1,v2,…"` per series; one `data=` per series (or `series1=`/`series2=`).

```bash
officecli add "$FILE" /body --type chart --prop chartType=bar --prop title="Revenue by Region" --prop categories="EMEA,APAC,Americas" --prop data="2026:120,150,180"
```

`chartType` ∈ bar / column / line / pie / area / scatter (`help docx chart` for axis/legend/series styling). A PNG via `--type picture` is only a fallback for an exotic chart officecli can't build.

### Hyperlinks and bookmarks

External links go via `hyperlink`:

```bash
officecli add "$FILE" "/body/p[2]" --type hyperlink --prop url="https://example.com" --prop text="our site"
```

**Internal links** (to a bookmark) use `--prop anchor=bookmarkName` — not a `#fragment` in `url`:

```bash
officecli add "$FILE" "/body/p[2]" --type hyperlink --prop anchor=chapter1 --prop text="See Chapter 1"
```

Pairing a `PAGEREF` field with visible text is the alternative. See `help docx hyperlink` / `help docx bookmark`.

### Sections and page setup

Document root `/` carries page setup (`pageWidth`, `pageHeight`, margins, in twips). Multi-section documents (landscape insert, columns) add a `section` break — see `help docx section`. Both camelCase (`pageWidth`, canonical) and lowercase alias (`pagewidth`) are accepted; prefer camelCase.

```bash
officecli set "$FILE" / --prop pageWidth=12240 --prop pageHeight=15840 --prop marginTop=1440 --prop marginLeft=1440
# Newspaper-style multi-column flow (columnSpace in twips; 720 = 0.5in):
officecli set "$FILE" / --prop columns=2 --prop columnSpace=720
```

### Forcing page breaks

Use exactly one page-break mechanism per logical boundary. The default is `pageBreakBefore=true` on the target heading. Alternatively, insert one explicit `pagebreak` before the heading. Never combine both mechanisms for the same boundary: the double break can create a blank page. Never set `pageBreakBefore` on `p[last()]` immediately after adding a `pagebreak`.

```bash
# Default: apply the break directly to the heading.
officecli add "$FILE" /body --type paragraph --prop text="Introduction" --prop style=Heading1 --prop pageBreakBefore=true
```

`--prop break=newPage` is an alias for `pageBreakBefore=true`. Preview with `view html` and check for blank pages.
