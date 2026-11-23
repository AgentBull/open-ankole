# OfficeCLI XLSX QA, Checklist, and Known Issues

**Assume there are problems. Your job is to find them.**

Your first workbook is almost never correct. Treat QA as a bug hunt, not a confirmation step. If you found zero issues on first inspection, you were not looking hard enough.

## Minimum cycle before "done"

1. `officecli view "$FILE" issues` — empty sheets, broken formulas, missing refs.
2. `officecli view "$FILE" annotated` (sample ranges) — values + types + warnings.
3. For every Excel error type, query it:
   ```bash
   officecli query "$FILE" 'cell:contains("#REF!")'
   officecli query "$FILE" 'cell:contains("#DIV/0!")'
   officecli query "$FILE" 'cell:contains("#VALUE!")'
   officecli query "$FILE" 'cell:contains("#NAME?")'
   officecli query "$FILE" 'cell:contains("#N/A")'
   ```
4. `officecli validate "$FILE"` — safe with a resident open; `validate` flushes pending edits to disk itself.
5. **Visual pass — walk every sheet via the HTML preview.** Run `officecli view "$FILE" html` and Read the returned HTML path. Each sheet renders with charts inline. Scan for `###`, truncated titles, placeholder tokens (`$fy$24`, `{var}`, `<TODO>`), sliced charts, white-slice pie charts, empty chart anchors — **STOP and fix before declaring done**. "validate pass" is not delivery; "the preview looks like a real workbook" is delivery. For human preview, run `officecli watch "$FILE"` or have them open `.xlsx` in Excel / WPS / Numbers.
6. **Print layout fix (wide tables / multi-chart sheets):**
   ```bash
   # Short summary or chart sheet: fit to one page.
   officecli set "$FILE" "/Summary" --prop orientation=landscape --prop fitToPage=true
   # Tall data table: fit the width only.
   officecli set "$FILE" "/Data" --prop orientation=landscape --prop fitToPage=1x0
   ```
   Apply this to every sheet that holds a chart or a table with more than eight columns.
7. If anything failed, fix, then **rerun the full cycle**. One fix commonly creates another problem.

`officecli view issues` + `view html` are the structural QA pair. Chart fill colors / theme tints can vary across viewers — spot-check in the user's target viewer when color fidelity matters.

## Formula verification checklist

- Pick 2-3 formulas at random. Run `officecli get` on each. Confirm the formula string is what you intended **and** `cachedValue=` is what you expect — arithmetic in your head.
- **Cached value sanity on every summary cell.** Any cell that aggregates (`COUNTA` / `COUNTIF` / `SUMPRODUCT` / `INDEX`&`MATCH`) must have a plausible `cachedValue`. If stale, re-touch the formula via non-resident `set` or manually set a correct cached value.
- **Spot-check one cell per numeric column.** `%` columns showing integer `0.0%` throughout means the denominator is wrong or cached stale.
- Ranges include every row (watch for off-by-one like `SUM(B2:B12)` when data goes to `B13`).
- Cross-sheet formulas (`Sheet1!A1`) contain no `\!`. If `officecli get` shows `Sheet1\!A1`, delete and re-enter via batch/heredoc.
- Named ranges (`officecli get "$FILE" "/namedrange[1]"`) point at what their names claim.
- Every `/` denominator is guarded — `IFERROR(x/y, 0)` or `IF(y=0, 0, x/y)`.
- Chart data vs source cells: spot-check inline chart points against source cells.
- Chart title / series name / legend contain **no** unreplaced tokens (`$...$`, `{var}`, `<TODO>`).

## Template QA & Fresh Eyes

When editing a template, check for leftover placeholders:

```bash
officecli query "$FILE" 'cell:contains("{{")'
officecli query "$FILE" 'cell:contains("xxxx")'
officecli query "$FILE" 'cell:contains("TBD")'
```

Open it fresh and read `view text` / HTML preview top-to-bottom as a new reviewer.

**Honest limit:** `validate` catches schema errors, not design errors. A workbook can pass `validate` with every number wrong.

## Known Issues & Pitfalls

### The cross-sheet `!` trap

Shells and CLI arg parsing mangle `!` in `Sheet1!A1` into `\!`, breaking the formula silently. Always use a batch heredoc with single-quoted delimiter (`<<'EOF'`):

```bash
cat <<'EOF' | officecli batch "$FILE"
[{"command":"set","path":"/Summary/B2","props":{"formula":"Revenue!B13"}}]
EOF
```

Verify with `officecli get` that `formula=` shows a plain `!` with no backslash.

### CLI bug backlog

- **Chart series are immutable after create** — `remove` + `add` with full series list (`remove chart[N]` shifts indices; re-add appends at end).
- **Standalone `import` does not persist reliably in 1.0.144** — use the non-resident import batch with `calc.fullCalcOnLoad=true` and verify cells on disk with a fresh non-resident `query` (see `operations-and-import.md`).
- **Cross-sheet formula batches run fine through one resident**, and pure value-set batches stay reliable at 50-80+ ops; if you hit a hang, fall back to a non-resident batch or individual `set` calls. Keep one serial writer per file.
- **Conditional formatting naming asymmetry** — `--type conditionalformatting`, path `/cf[N]`.
- **Sheet `position` prop on add** — often ignored; reorder with `officecli move --index` / `--after` / `--before`.
- **`remove /sheet[N]` cascade guard** — rejects removal/rename when referenced on another sheet by validation / CF / sparkline / hyperlink / named range; remove dependent elements first.
- **Batch JSON rejects cell `color` alias** — use `"font.color"`, `"font.size"`, `"font.name"`, or `"fill"`.

### Renderer caveats (cross-viewer color fidelity)

`officecli view html` is authoritative for structural QA (`###`, truncation, placeholder leakage, layout). Viewer rendering quirks across target apps:
- Pie / doughnut fill colors may collapse to one theme tint in some viewers.
- Line / column series colors may drift from the workbook theme.
- Form-control checkboxes may render double-boxed.
Before calling a color or chart broken, open the file in the user's target viewer.

### Escape layers

`$` is the shell layer (single-quote it). `\n` / `\t` in a prop value are interpreted by the CLI into a real newline / tab. In batch JSON use `"\n"`, `"\t"`, `"\""`, and `"\\\\"` for a literal backslash. Pair `\n` in cells with `--prop wrapText=true`.

### Common pitfalls

| Pitfall | Fix |
|---|---|
| `--name "foo"` | All attrs go through `--prop`: `--prop name="foo"` |
| Guessing a prop name | `officecli help xlsx <element>` — don't improvise |
| `--prop color=...` on a cell | Ambiguous — use `font.color` (text) or `fill` (bg); always use full dotted names in batch JSON |
| `#FF0000` hex colors | Drop the `#`: `FF0000` |
| `--index` vs `[N]` | `--index` is 0-based (array); `[N]` paths are 1-based (XPath) |
| Unquoted `[N]` in zsh/bash | Quote every path: `"/Sheet1/row[1]"` |
| Sheet name with spaces | Quote full path: `"/My Sheet/A1"` |
| Year showing as `2,026` | `--prop type=string` or `numFmt="@"` |
| Modifying a file open in Excel | Close it in Excel first |
| `swap` not reordering sheets | `swap` is for rows/cells. Use `move --after` / `--before` / `--index` for sheets |
| Cached values missing after write | New formulas get cached values when a human opens the file; `validate` accepts them either way |
