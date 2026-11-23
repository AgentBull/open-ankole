# OfficeCLI DOCX Recipes, Specialty Features, and Raw XML

## Report-level recipes

Patterns that come up on every long-form report. Each has been executed and `validate`-passed.

### (a) Rich cover page — hit the >= 60% filled floor

Stack a confidentiality banner, title, subtitle, client/project/date block, and a key-themes strip, then force the next section onto a new page:

```bash
officecli add "$FILE" /body --type paragraph --prop text="CONFIDENTIAL — CLIENT USE ONLY" --prop align=center --prop size=9pt --prop color=C00000 --prop spaceAfter=24pt
officecli add "$FILE" /body --type paragraph --prop text="Strategic Growth Review" --prop style=Title --prop size=32pt --prop bold=true --prop align=center --prop font=Cambria --prop spaceAfter=8pt
officecli add "$FILE" /body --type paragraph --prop text="FY26 Outlook and Scenario Planning" --prop italic=true --prop size=16pt --prop align=center --prop spaceAfter=36pt
officecli add "$FILE" /body --type paragraph --prop text='Prepared for: Acme Corp. Leadership Team' --prop align=center --prop size=11pt
officecli add "$FILE" /body --type paragraph --prop text='Engagement: 2026-04 — 2026-06' --prop align=center --prop size=11pt --prop spaceAfter=36pt
officecli add "$FILE" /body --type paragraph --prop text="Key themes: 1) margin resilience, 2) EMEA expansion, 3) capital allocation." --prop align=center --prop italic=true --prop size=10pt
officecli add "$FILE" /body --type paragraph --prop text="Executive Summary" --prop style=Heading1 --prop pageBreakBefore=true
```

### (b) Page X of Y footer — composite PAGE + NUMPAGES

Add the footer paragraph, then three child ops build `Page <X> of <Y>` live. The official `help docx footer` recipe.

```bash
officecli add "$FILE" / --type footer --prop type=default --prop text="Page " --prop align=center --prop size=9pt
officecli add "$FILE" "/footer[1]/p[1]" --type field --prop fieldType=page
officecli add "$FILE" "/footer[1]/p[1]" --type run --prop text=" of "
officecli add "$FILE" "/footer[1]/p[1]" --type field --prop fieldType=numpages
officecli get "$FILE" "/footer[1]/p[1]" --depth 1 | grep -o fldChar | wc -l   # expect >= 4; use grep -o ... | wc -l, NOT grep -c (single-line XML returns 1)
```

### (c) Header row with fill and white bold text

Order matters — populate header cell text FIRST (runs don't exist in empty cells; a `set …/tc[N]/p[1]/r[1]` on an empty cell errors "No r found"), THEN cell fill, THEN run formatting:

```bash
officecli add "$FILE" /body --type table --prop rows=5 --prop cols=4 --prop width=100%
officecli set "$FILE" "/body/tbl[1]/tr[1]" --prop header=true --prop c1=Quarter --prop c2=Revenue --prop c3=Growth --prop c4=Status
for col in 1 2 3 4; do
  officecli set "$FILE" "/body/tbl[1]/tr[1]/tc[$col]" --prop fill=1F4E79
  officecli set "$FILE" "/body/tbl[1]/tr[1]/tc[$col]/p[1]/r[1]" --prop bold=true --prop color=FFFFFF
done
for row in 3 5; do for col in 1 2 3 4; do
  officecli set "$FILE" "/body/tbl[1]/tr[$row]/tc[$col]" --prop fill=D9E2F3      # zebra stripe
done; done
```

### (d) Financial table — right-align numbers, bold totals, bottom border on total row

```bash
for row in 2 3 4 5; do for col in 2 3 4; do
  officecli set "$FILE" "/body/tbl[1]/tr[$row]/tc[$col]/p[1]" --prop align=right
done; done
for col in 1 2 3 4; do
  officecli set "$FILE" "/body/tbl[1]/tr[5]/tc[$col]/p[1]/r[1]" --prop bold=true
  officecli set "$FILE" "/body/tbl[1]/tr[4]/tc[$col]/p[1]" --prop pbdr.bottom="single;6;000000;0"
done
```

### (e) Cell with multiple bullets (SWOT / risk matrix)

`c1="a\nb"` gives a `<w:br/>` line break within **one** paragraph — fine for plain multi-line text, but bullets need separate paragraphs. Seed the first via `set c1=`, then `add paragraph` (with `listStyle=bullet`) under the cell per subsequent bullet:

```bash
officecli set "$FILE" "/body/tbl[1]/tr[1]" --prop c1="Installed base of 18k enterprise seats"
officecli add "$FILE" "/body/tbl[1]/tr[1]/tc[1]" --type paragraph --prop text="Margin structure above peer median" --prop listStyle=bullet
officecli set "$FILE" "/body/tbl[1]/tr[1]/tc[1]/p[1]" --prop listStyle=bullet
```

If the seeded line lands at the bottom, re-order: `officecli move "$FILE" "/body/tbl[1]/tr[1]/tc[1]/p[N]" --index 0`.

### (f) TOC without a field engine

A CLI-only pipeline cannot calculate reliable page numbers. Keep the live TOC, set `updateFields=true`, and tell the recipient to open the document in Word or another compatible field engine. Do not replace it with guessed static page numbers.

## Template delivery — separating Template Notes from end-user content

HR / legal / vendor templates carry internal-only guidance ("replace `{{CompanyName}}`") that must NOT ship. Two working patterns:

- **Trailing "Template Notes" section** under a clear `Heading 1` ("Template Notes for HR Users") with all instructions below it; before distribution, `remove` from the heading downward (locate with `query 'paragraph[style=Heading1]:contains("Template Notes")'`).
- **Bookmark-bounded internal section** between `__template_notes_start` / `_end` bookmarks; at delivery `raw-set` removes everything between the anchors.

Delivery gate for templates: after removal, `query 'p:contains("Template Notes")'` AND `query 'p:contains("{{")'` both return empty. If a notes paragraph survives, a downstream employee reads internal language.

## Advanced / specialty topics

Reports, memos, letters, proposals, and HR templates don't need this. Keep reading only if your document is academic (equations, footnotes, bibliography), reviewed (comments, tracked changes), or marked (watermark).

**Equations and footnotes.** `--type equation` takes LaTeX — `\frac`, `\sum`, Greek, `\mathit`, `\mathcal` all render. By default it creates a standalone `/body/oMathPara[N]` display block; pass `--prop mode=inline` with a paragraph parent path (`add "/body/p[N]" --type equation --prop formula=… --prop mode=inline`) to drop an inline `<m:oMath>` into running text. Footnotes auto-number by paragraph index. Bibliography hanging indent: `firstLineIndent=-720 indent=720` per entry.

```bash
officecli add "$FILE" /body --type equation --prop formula="\\frac{a}{b} + \\sum_{i=1}^{n} x_i"
officecli add "$FILE" "/body/p[3]" --type footnote --prop text="See Appendix A for methodology."
```

**Comments and tracked changes.** Bulk accept/reject: `set "$FILE" /revision --prop revision.action=accept` (or `--prop revision.action=reject`); narrow with a selector like `/revision[@author=Alice]` or `/revision[@type=ins]`. Locate individual changes with `query ins` and `query del` (`trackedchange` is not a selector). Create tracked changes on a run with `--prop revision.type=ins|del --prop revision.author=…` (`help docx run` for the full `revision.*` set — `format`/`moveFrom`/`moveTo` too). Add a comment: `add "/body/p[4]" --type comment --prop author=… --prop text=…`; reply-thread it with `--prop parentId=N` and mark it resolved with `set "/comments/comment[N]" --prop done=true` (resolve rather than delete to keep the audit trail — `query 'comment[done=false]'` then lists what's still open). Prop schema: `help docx comment` / `help docx run`.

**Watermark.** `add / --type watermark --prop text="DRAFT" --prop color=BFBFBF --prop opacity=0.8` in one command (default opacity 0.5); `set /watermark --prop opacity=…` adjusts it later.

**When to switch to a Playbook.** Stay in docx for chapter drafts, <= 3 footnotes, <= 2 equations, no bibliography/cross-refs. Read the **`academic-paper` Playbook** for citation styles (APA / Chicago / IEEE / GB 7714), in-text↔reference auto-linking, numbered equations with `\ref`, "List of Figures", or auto-updating cross-refs. For **data capture** — fillable forms, contracts with user-fill slots, questionnaires, mail-merge templates (`<w:sdt>` content controls, `<w:ffData>`, `documentProtection=forms`) — stay in docx and consult `officecli help docx`.

## Raw-set escape hatch (L1 / L2 / L3)

Three tiers of precision; use the lowest that does the job.

- **L1 — high-level props** (`--prop text=…`, `--prop style=Heading1`): your default. Covers 80%.
- **L2 — dotted-attr fallback** (`pbdr.top=`, `ind.left=`, `shd.fill=`, `padding.top=`, `font.size=`): when L1 lacks the knob. Example: `--prop pbdr.bottom="single;6;1F4E79;0"`. Emits schema-valid XML.
- **L3 — `raw-set` with XML**: last resort, no schema protection. Use for internal hyperlinks, composite fields, and other shapes the typed verbs can't express (below).

Borders use the format `style;size;color;space`: `single;4;FF0000;1`. Hex colors never start with `#`: `FF0000`. Scheme color names (`accent1..6`, `dark1`/`dark2`, `light1`/`light2`, `hyperlink`) are accepted anywhere a hex color is — prefer hex for stable colors across themes.

### Raw-set XML appendix (L3 patterns)

`raw-set` injects literal OOXML — no schema protection. Element order in `<w:pPr>`: `pStyle`, `numPr`, `spacing`, `ind`, `jc`, `rPr` (last). Smart quotes as entities (`&#x2018;`/`&#x2019;`/`&#x201C;`/`&#x201D;`). Add `xml:space="preserve"` to any `<w:t>` with leading/trailing spaces. RSIDs are 8-digit hex. Use "Claude" as the author for tracked changes/comments unless the user names another.

**Tracked-change insertion / deletion** — prefer `--prop revision.type=ins|del` on a run; raw-set only for rejecting/restoring another author's change. Replace the whole `<w:r>…</w:r>`, never inject tags inside a run; copy original `<w:rPr>` into both. Inside `<w:del>` use `<w:delText>` (and `<w:delInstrText>` for instructions):

```xml
<w:r><w:t>The term is </w:t></w:r>
<w:del w:id="1" w:author="Claude" w:date="2026-01-01T00:00:00Z"><w:r><w:delText>30</w:delText></w:r></w:del>
<w:ins w:id="2" w:author="Claude" w:date="2026-01-01T00:00:00Z"><w:r><w:t>60</w:t></w:r></w:ins>
<w:r><w:t> days.</w:t></w:r>
```

When deleting ALL content of a paragraph/list item, also mark the paragraph mark deleted (`<w:del/>` inside `<w:pPr><w:rPr>`) — otherwise accepting changes leaves an empty paragraph. To **reject another author's insertion**, nest your `<w:del>` inside their `<w:ins>`; to **restore their deletion**, add a `<w:ins>` after it (don't modify theirs).

**Internal hyperlink to a bookmark** (prefer `--prop anchor=`):

```xml
<w:hyperlink w:anchor="chapter1"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr><w:t>See Chapter 1</w:t></w:r></w:hyperlink>
```

**Composite field in one run** — the `fldChar begin / instrText / separate / value / end` chain:

```xml
<w:r><w:fldChar w:fldCharType="begin"/></w:r>
<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
<w:r><w:fldChar w:fldCharType="separate"/></w:r>
<w:r><w:t>1</w:t></w:r>
<w:r><w:fldChar w:fldCharType="end"/></w:r>
```

**Comment markers** are siblings of `<w:r>`, NEVER inside one (reply threading and resolved-state are high-level — `--prop parentId=`/`done=`):

```xml
<w:commentRangeStart w:id="0"/><w:r><w:t>annotated text</w:t></w:r><w:commentRangeEnd w:id="0"/>
<w:r><w:rPr><w:rStyle w:val="CommentReference"/></w:rPr><w:commentReference w:id="0"/></w:r>
```

Force field recalc on open with `officecli set "$FILE" /settings --prop updateFields=true` (writes `<w:updateFields w:val="true"/>`; covers PAGE / PAGEREF / NUMPAGES / TOC page numbers). For SEQ numbering, prefer `set / --prop recalcFields=seq`.
