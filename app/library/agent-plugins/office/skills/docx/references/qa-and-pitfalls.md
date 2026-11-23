# OfficeCLI DOCX QA, Delivery Gate, and Pitfalls

**Assume there are problems — QA is a bug hunt, not a confirmation step.** Your first document is almost never correct; zero issues on first inspection means you weren't looking hard enough. Headings look fine until `view outline` shows an H3 directly under an H1; the footer shows "Page 1" until `get --depth 3` reveals a static run, not a field.

## Minimum cycle before "done"

1. `officecli view "$FILE" issues` — empty paras, missing alt text, formatting anomalies.
2. `officecli view "$FILE" outline` — heading hierarchy (no H1 → H3 skips), TOC presence, section count.
3. `officecli view "$FILE" text --max-lines 400` — typos, stray `\$`/`\t`/`\n` literals, placeholder tokens.
4. `officecli validate "$FILE"` — schema check (the Delivery Gate re-runs this on the closed, on-disk file).
5. **Visual pass — whole document as a contact sheet** (vision-capable agents only — if you cannot interpret images, skip this step: steps 1–4 are your ceiling, and flag the document "not visually verified" at handoff). `officecli view "$FILE" screenshot --grid auto -o /tmp/sheet.png`, then Read it. `--grid auto` tiles **every page** into one image (auto column count; `--grid 4` to force) — you *see* pagination, blank pages, heading rhythm, lopsided margins, and TOC/cover placement, not just the DOM. Windows+Word renders each page through real Word; elsewhere HTML. If the screenshot fails, fall back to `view html` and flag cross-page breaks / alignment / rhythm as "not visually verified". Thumbnails only **locate**: confirm any fine call (column alignment, line spacing, indents, dark-on-dark, caption placement) on the suspect page at full resolution with `screenshot --page N` (no `--grid`; real Word on Windows). "validate pass" is not delivery; "looks like a real document" is.
6. If anything failed, fix, then **rerun the full cycle** — one fix commonly creates another problem.

## Delivery Gate (run before handing off — any failure = REJECT, do NOT deliver)

Copy-paste, set `FILE`, and refuse to declare done until every gate prints OK.

```bash
FILE="your-file.docx"

# Gate 1 — schema.
officecli close "$FILE" 2>/dev/null
officecli validate "$FILE" | grep -q "no errors found" || { echo "REJECT Gate 1: validate failed"; exit 1; }
echo "Gate 1 OK"

# Gate 2 — token leak (shell-escape / template tokens / literal \$ \t \n). grep -c never false-PASSes.
LEAK=$(officecli view "$FILE" text | grep -cE '(\$[A-Za-z_]+\$|\{\{[^}]+\}\}|<TODO>|xxxx|lorem|\\[\$tn])')
[ "$LEAK" -eq 0 ] && echo "Gate 2 OK" || { echo "REJECT Gate 2: $LEAK leak line(s)"; officecli view "$FILE" text | grep -nE '(\$[A-Za-z_]+\$|\{\{[^}]+\}\}|<TODO>|xxxx|lorem|\\[\$tn])'; exit 1; }
# A TOC placeholder is valid before a Word-compatible field engine updates it. Check the TOC field and updateFields setting structurally instead.

# Gate 3 — live PAGE field exists when a footer is expected.
FLD=$(officecli query "$FILE" 'field[fieldType=page]' --json | jq '.data.results | length')
[ "$FLD" -ge 1 ] && echo "Gate 3 OK" || { echo "REJECT Gate 3: no live PAGE field"; exit 1; }
echo "Delivery Gate PASS"
```

## Field / cached-value spot-check

Fields carry cached values that may be stale or empty at write time — confirm existence by **structure, not text**.

- **Footer PAGE:** `get /footer[N] --depth 3` lists the begin / instrText / separate / cached / end run chain — >= 5 runs for one PAGE, >= 11 for composite "Page X of Y". A single run with text `"Page"` = field missing; re-add with `--prop field=page`.
- **TOC:** `get /toc[1] --depth 2` shows field structure. Page numbers may read `1 1 1 1` or `Update field to see…` until recalculated. Set `updateFields=true`.
- **MERGEFIELD:** `query 'field[fieldType=mergefield]'` — one per slot, no literal `{{name}}` elsewhere.

## Honest limit & QA display notes

`validate` catches schema errors, not design errors — a document can pass it with wrong heading hierarchy, fake-Heading-1 sizes, placeholder tokens as body text, or an empty first-page footer on a coverless document.

QA display notes (don't chase these):
- `view text` shows `"1."` for every numbered list item regardless of rendered number — actual output increments correctly.
- `view issues` flags "body paragraph missing first-line indent" on cover paragraphs, centered headings, list items, bibliography entries — first-line indent is only required for APA/academic body text; on block-style professional documents these are expected.

## Known Issues & Pitfalls

When something "looks broken", attribute it before chasing: **[AGENT-ERROR]** the document is wrong (fix it) · **[RENDERER-BUG]** the document is correct, a viewer renders it differently (don't chase) · **[SKILL gap]** the skill didn't teach the rule (file an issue).

### Renderer quirks (cross-viewer, [RENDERER-BUG] — don't chase)

Before calling a color/field/chart broken, open the file in the user's target viewer; if it looks correct there it's a viewer quirk.

- **PAGE field may render literal "Page"** (no number) until recalculated — judge by `fldChar` presence, not the digit.
- **TOC cached page numbers may read "1 1 1 1"** until F9.
- **Pie / doughnut fill may collapse to one color** in some viewers (column/bar render fine).
- **Form-control checkboxes may render double-boxed**; **OMML equation baselines** may shift across viewers (XML identical).

### Common pitfalls

| Pitfall | Correct approach |
|---|---|
| `--index` vs `[N]` | `--index` is 0-based; `[N]` paths are 1-based |
| Multiple `add --index N` with the same N | Each insert shifts later content down; reusing N puts later items BEFORE earlier ones — insert in reverse order, or `move --after/--before` anchored on `paraId` |
| Unquoted `[N]` in zsh/bash | Quote every path: `"/body/p[1]"` |
| `[last]` as predicate | Must be `[last()]` with parens |
| Raw twips in spacing | Use unit-qualified values: `12pt`, `0.5cm`, `1.5x` |
| Empty paragraphs for spacing | Use `spaceBefore` / `spaceAfter` |
| Row-level `set` for cell formatting | Row `set` only supports `height`, `header`, `c1..cN` text; format goes on the cell paragraph / run |
| `listStyle` on a run | It's a paragraph property |
| Indent via leading spaces | `indent=720` / `firstLineIndent=360` / `hangingIndent=720` (dotted `ind.left` / `ind.firstLine` also work) |
| Cover page-number suppression via `set differentFirstPage=true` | UNSUPPORTED — add a first-type footer: `--type footer --prop type=first --prop text=""` |
| Need a fresh chapter page | Use `pageBreakBefore=true` on the heading; use an explicit `pagebreak` only as an alternative, never both |
| Multiple bullet paragraphs in one cell | `c1="a\nb"` makes a `<w:br/>` line break (one paragraph); for separate bullet paragraphs use recipe (e) |
| `raw-set` when dotted-attr would work | Prefer L2 dotted-attr over L3 raw-set |
| Next paragraph inherits the previous Heading style | Set explicit `--prop style=Normal` on the following paragraph |
| Modifying a file open in Word | Close it in Word first |
| Echo into batch breaks on `$`/`'` | Heredoc with single-quoted delimiter: `cat <<'EOF' \| officecli batch …` |
