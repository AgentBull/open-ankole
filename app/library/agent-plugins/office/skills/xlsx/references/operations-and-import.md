# OfficeCLI XLSX Operations, Charts, Validation, and Import

## Quick Start

Minimal viable xlsx: 3 months of revenue + a total formula + column widths + a currency format. Adapt, don't copy-paste — your file, your data.

```bash
officecli create "$FILE"
officecli open "$FILE"
officecli set "$FILE" /Sheet1/A1 --prop value=Month --prop bold=true
officecli set "$FILE" /Sheet1/B1 --prop value=Revenue --prop bold=true
officecli set "$FILE" /Sheet1/A2 --prop value=Jan
officecli set "$FILE" /Sheet1/A3 --prop value=Feb
officecli set "$FILE" /Sheet1/A4 --prop value=Mar
officecli set "$FILE" /Sheet1/B2 --prop value=42000 --prop numFmt='$#,##0'
officecli set "$FILE" /Sheet1/B3 --prop value=45000 --prop numFmt='$#,##0'
officecli set "$FILE" /Sheet1/B4 --prop value=48000 --prop numFmt='$#,##0'
officecli set "$FILE" /Sheet1/A5 --prop value=Total --prop bold=true
officecli set "$FILE" /Sheet1/B5 --prop formula="SUM(B2:B4)" --prop bold=true --prop numFmt='$#,##0'
officecli set "$FILE" "/Sheet1/col[A]" --prop width=12
officecli set "$FILE" "/Sheet1/col[B]" --prop width=15
officecli close "$FILE"
officecli validate "$FILE"
```

Verified: `validate` returns `no errors found`, `B5` resolves to `135000`.

## CSV / bulk import

**OfficeCLI 1.0.144 import phase.** `import` is a top-level command, so its syntax comes from `officecli import --help`. Do not use a standalone `officecli import` in a delivery workflow: 1.0.144 can print an imported row count while an import-only handler leaves the on-disk sheet unchanged. Close any resident, then run the import and a real workbook mutation in one non-resident batch. The `calc.fullCalcOnLoad` write below is the persistence fence and also tells spreadsheet applications to recalculate imported formulas.

```bash
officecli close "$FILE" 2>/dev/null
jq -Rs '[
  {"command":"import","parent":"/Sheet1","text":.,"props":{"header":"true"}},
  {"command":"set","path":"/","props":{"calc.fullCalcOnLoad":"true"}}
]' data.csv \
  | OFFICECLI_NO_AUTO_RESIDENT=1 officecli batch "$FILE" --stop-on-error

# Accept the import only after a fresh non-resident read finds cells on disk.
OFFICECLI_NO_AUTO_RESIDENT=1 officecli query "$FILE" cell --json \
  | jq -e '.data.results | length > 0'
OFFICECLI_NO_AUTO_RESIDENT=1 officecli view "$FILE" outline
```

For TSV, add `"format":"tsv"` to the import item's `props`. For another anchor, add `"start-cell":"B2"`. `--header` maps to `"header":"true"`. Column widths and `numFmt` still need a follow-up pass.

**Python + batch fallback** — use when you need custom type coercion, formula injection, or the CSV lives inside another data pipeline. Recipe for 600-6000+ cells:

```python
# gen_batch.py — produces batch chunks of 80 value-set ops each
import csv, json
ops = []
with open("data.csv") as f:
    reader = csv.reader(f)
    for r, row in enumerate(reader, start=1):
        for c, val in enumerate(row):
            col = chr(ord('A') + c)
            ops.append({"command":"set","path":f"/Data/{col}{r}",
                        "props":{"value": val}})
for i in range(0, len(ops), 80):
    print(json.dumps(ops[i:i+80]))
```

```bash
python gen_batch.py | while IFS= read -r chunk; do
  printf '%s\n' "$chunk" | officecli batch "$FILE"
done
```

Tune: start at 80 ops/chunk, drop to 40 if any chunk fails. Numeric type inference and formulas come later via targeted `set` — batch in this recipe is pure value injection.

## Reading & Analysis

Start wide, then narrow. `outline` first tells you what sheets exist and where the data is; jump into `view` / `get` / `query` only once you know where to look.

- `officecli view "$FILE" html` — Read the returned HTML to audit the rendered output. Each sheet is addressable, charts render inline. Catches `###`, placeholder leakage, pivot layout, row-height clipping.
- `officecli watch "$FILE"` keeps a live preview running for the human user — agent self-check uses `view html` above.
- `officecli view "$FILE" outline` — sheets, dimensions, formula counts.
- `officecli view "$FILE" text --start 1 --end 50 --cols A,B,C` — plain text dump scoped for large files.
- Other `view` modes: `annotated` (cell values + types/formulas + warnings), `stats` (numeric summaries), `issues` (broken formulas, empty sheets, missing refs).

**Round-trip dump.** `officecli dump "$FILE" [path]` serializes the workbook — or one worksheet (`/Sheet1`, `/sheet[N]`) — into a replayable batch JSON; `officecli batch new.xlsx --input dump.json` replays it. Subtree dumps don't carry workbook-level resources (settings, named ranges) — the replay target must already define them.

```bash
officecli dump "$FILE" -o blueprint.json            # whole workbook
officecli dump "$FILE" /Sheet1 -o sheet.json        # one worksheet
officecli batch new.xlsx --input blueprint.json
```

**Inspect one element.** Use XPath-style paths. Always quote — shells glob `[N]`. Add `--depth N` to expand children; `--json` for machine output.

```bash
officecli get "$FILE" "/Sheet1/A1"            # one cell
officecli get "$FILE" "/Sheet1/A1:D10"        # range
officecli get "$FILE" "/Sheet1/chart[1]"      # chart
officecli get "$FILE" "/Sheet1/table[1]"      # ListObject
officecli get "$FILE" "/namedrange[1]"        # workbook-level named range
```

**Query across the workbook.** CSS-like selectors. Operators: `=`, `!=`, `~=` (contains), `>=`, `<=`, `[attr]` (exists).

```bash
officecli query "$FILE" 'cell:has(formula)'       # every formula cell
officecli query "$FILE" 'cell:contains("#REF!")'  # broken references
officecli query "$FILE" 'cell[type=Number]'       # typed filter
officecli query "$FILE" 'Sheet1!B[value!=0]'      # sheet-scoped
```

**Merge cells shortcut.** `officecli query $FILE merge` or `mergedrange` — both are aliases for `mergeCell`.

**Analytical elements for large data:**

- **Pivot table** (`--type pivottable`) + **slicer** (`--type slicer`) to group/aggregate and filter without writing 20 SUMIFs.
- **Sparkline** (`--type sparkline`) for inline per-row trends. `type` is a strict enum: **`line | column | stacked`** (plus aliases `winloss` / `win-loss` → `stacked`); invalid `type=` hard-fails.
- Run `officecli help xlsx pivottable`, `officecli help xlsx slicer`, `officecli help xlsx sparkline` for exact prop names.

## Creating & Editing

Verbs: `add`, `set`, `remove`, `move`, `swap`, `batch`.

### Cells and formulas

Set a value and its format in one call. Never write `=` at the start of a formula — the CLI strips it.

```bash
officecli set "$FILE" /Sheet1/B5 --prop formula="SUM(B2:B4)" --prop numFmt='$#,##0'
officecli set "$FILE" /Sheet1/C5 --prop formula="B5/A5" --prop numFmt="0.0%"
```

Structural properties (`width`, `height`, `freeze`, `tabColor`) live on row / col / sheet nodes:

```bash
officecli set "$FILE" "/Sheet1/col[A]" --prop width=20
officecli set "$FILE" "/Sheet1/row[1]" --prop height=22
officecli set "$FILE" "/Sheet1" --prop freeze=A2 --prop tabColor=1F4E79
```

### Named ranges & batch JSON rules

Prefer named ranges over `$B$6` in formulas. Because `ref` values contain both `!` and `$`, add them through a batch heredoc:

```bash
cat <<'EOF' | officecli batch "$FILE"
[
  {"command":"add","parent":"/","type":"namedrange","props":{"name":"GrowthRate","ref":"Sheet1!$B$6"}}
]
EOF
```

See `officecli help xlsx namedrange` for the full schema.

**Batch JSON does NOT accept shell aliases.** Inside batch `props`, always use full dotted names — `"font.color": "FF0000"`, `"font.size": 14`, never `"color": "FF0000"` (ambiguous: text vs fill). On a bare cell, even `--prop color=...` errors with `ambiguous in cell context — use 'font.color' (text) or 'fill' (bg)`. `parent` should be `"/"` for workbook-level elements and `"/SheetName"` for sheet-scoped; empty string is not equivalent.

### Charts

Chart types live under `officecli help xlsx chart` (20+ types, plus extended `boxWhisker`, `waterfall`, `funnel`, `histogram`, `treemap`, `sunburst`, `pareto`).

**Three ways to feed chart data (pick one per chart — do not mix at add-time):**

| Form | Shape | When to use |
|---|---|---|
| (a) inline `data` | `--prop data="Sales:100,200,300" --prop categories="Jan,Feb,Mar"` | Tiny demo charts, numbers you will not edit. Source of truth lives in chart XML, not a cell. |
| (b) 2D `dataRange` | `--prop dataRange="Sheet1!A1:B4"` (first col = categories, first row = header / series name) | Normal case. Must be **2-D** — single column fails with "Chart requires data". |
| (c) dotted per-series | `--prop series1.name=Sales --prop series1.values="Sheet1!B2:B4" --prop series1.categories="Sheet1!A2:A4"` | Multi-series non-contiguous ranges or explicit naming. `series1.values` alone emits `1,2,3` on x-axis. |

- **The single-column trap.** `dataRange="Sheet1!B2:B13"` fails with `Chart requires data`. Widen to `A2:B13` or use form (c) with explicit `series1.categories`.
- **Move / resize after create:** `set chart[N] --prop anchor="F5:N25"` (or `--prop x= --prop y= --prop width= --prop height=`). **Series are immutable** — to add/change a series, `remove` and `add` with the full series list (`remove chart[1]` shifts `chart[2] → chart[1]` and re-add appends at the end; rebuild in order to preserve order).
- **Anchor sizing.** No auto-fit. A column chart with 5-6 categories + 2 series needs roughly `A5:L22` (12 cols × 18 rows); check via `view html`.
- **Chart `dataRange` — always prefix with the sheet.** Write `dataRange="Summary!A17:C22"`, not `A17:C22`.
- **NEVER put unreplaced template tokens in chart title / series name / legend / axis title** (`$fy$24`, `{var}`, `<TODO>`, `$VAR`, `{{placeholder}}`).

**Chart Axis-by-Role:** address axes by **role** (`value` = Y, `category` = X), not by index — XML order isn't stable. Safe props: `title`, `min`, `max`, `majorGridlines`, `visible`, `labelRotation`.

```bash
officecli get "$FILE" "/Sheet1/chart[1]/axis[@role=value]"
officecli set "$FILE" "/Sheet1/chart[1]/axis[@role=value]" --prop min=0 --prop max=100000
officecli set "$FILE" "/Sheet1/chart[1]/axis[@role=category]" --prop title="Month"
```

### Conditional formatting

Consult `officecli help xlsx cf`. Three common flavors:
- **Color scales**: `type=colorscale` with `minColor` / `midColor` / `maxColor`.
- **Data bars**: `type=databar` (set explicit `min` / `max` for consistent column scaling).
- **Formula rules** (element `formulacf`, path `/cf[N]`): `type=formula` with `formula="$C2>1000"` and fill/font.
Apply CF sparingly so coloring stays meaningful.

### Data validation

Input cells in trackers and templates MUST carry data validation. Three list-source patterns:

**(a) Inline list:**
```bash
officecli add "$FILE" /Sheet1 --type validation \
  --prop sqref="C2:C100" --prop type=list \
  --prop formula1="Yes,No,Maybe" \
  --prop showError=true --prop errorTitle="Invalid" --prop error="Select from list"
```

**(b) Named range (preferred for cross-sheet lookups):**
```bash
cat <<'EOF' | officecli batch "$FILE"
[
  {"command":"add","parent":"/","type":"namedrange","props":{"name":"StatusList","ref":"Lookups!$A$2:$A$4"}},
  {"command":"add","parent":"/Sheet1","type":"validation","props":{"sqref":"B2:B100","type":"list","formula1":"=StatusList"}}
]
EOF
```

**(c) Direct cross-sheet range:**
```bash
cat <<'EOF' | officecli batch "$FILE"
[
  {"command":"add","parent":"/Sheet1","type":"validation","props":{"sqref":"C2:C100","type":"list","formula1":"Lookups!$A$2:$A$4"}}
]
EOF
```

If written on the shell, `!` becomes `\!` and the dropdown silently breaks. Verify with `officecli get "$FILE" /Sheet1/validation[N]` (`formula1=` must show a plain `!`). Other `type` values: `decimal`, `whole`, `date`, `textLength`, `custom` (`officecli help xlsx validation`).

### Other elements

- **Tables** (`ListObjects`): `add --type table` with a range (`officecli help xlsx table`).
- **Comments**: `add --type comment` for documenting hardcoded assumptions (`officecli help xlsx comment`).
- **Sheet reordering**: `officecli move`, not `swap` (`swap` only works on row/cell paths).
