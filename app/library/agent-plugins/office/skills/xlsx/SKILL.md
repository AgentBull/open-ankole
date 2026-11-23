---
name: xlsx
description: "Use this skill for local .xlsx, .xls, .csv, or .tsv files as input or output. This skill edits and validates local workbooks. Lark cloud sheets and tokens belong to lark-office-suite."
default_enabled: true
ankole-runtime: background_job
category: productivity
tags: [xlsx, spreadsheet, excel, officecli]
---

# OfficeCLI XLSX Skill

For visual styling, use `design-md` when the user requests the internal design system or VIS, skip it when they opt out or choose another style instead, and treat it as optional when no style source is specified.

## Setup

The Worker image build installs OfficeCLI and checks its version. Run `officecli --version` and `officecli help xlsx`. If both succeed, continue with the installed CLI (version numbers in notes are not runtime requirements); if either fails, report the command and error as the runtime blocker.

## Playbooks

A Playbook carries the extra rules for one kind of workbook. Before you plan the workbook, list the Playbooks and read every one that matches the request:

```bash
bun /repo/app/library/agent-plugins/office/tools/list_playbooks.ts xlsx
```

Each line gives the Playbook name, its absolute path, and the condition that selects it. A Playbook inherits every rule in this skill and adds to it, so read this skill first and keep both. When no Playbook matches, build from this skill alone.

## ⚠️ Help-First Rule

**This skill teaches what good xlsx looks like, not every command flag. When a property name, enum value, or alias is uncertain, consult help BEFORE guessing.**

```bash
officecli help xlsx                         # List all xlsx elements
officecli help xlsx <element>               # Full element schema (e.g. pivottable, chart, cf)
officecli help xlsx <verb> <element>        # Verb-scoped (e.g. add chart, set cell)
officecli help xlsx <element> --json        # Machine-readable schema
```

Help reflects the installed CLI version and is authoritative over this skill. `officecli help xlsx ...` covers schema elements only; use top-level help (`officecli import --help`, `officecli batch --help`, `officecli open --help`) for command syntax.

## Shell & Execution Discipline

- ALWAYS quote element paths (`"/Sheet1/row[1]"`), because zsh/bash glob `[]`.
- Use **single quotes** for any prop value containing `$` (`numFmt='$#,##0'`).
- For formulas with cross-sheet `!` references, use `batch` with a `<<'EOF'` heredoc (otherwise `!` becomes `\!` and breaks silently).
- `\n` and `\t` in prop values are interpreted as in-cell newline (pair with `--prop wrapText=true`) and tab; double them (`\\n`) for literal text.
- Run commands incrementally one at a time and check each exit code, or use `batch` (50–80 ops/chunk).

## Requirements for Outputs

- **Zero formula errors:** ZERO `#REF!`, `#DIV/0!`, `#VALUE!`, `#NAME?`, `#N/A`. Guard denominators with `IFERROR` or `IF(x=0,...)`.
- **Formulas, not hardcoded values:** If a number can be computed from other cells, write a formula. Never write leading `=` in `--prop formula=`.
- **Consistent typography & explicit widths:** Use one consistent font (Arial / Calibri / Times New Roman) and set explicit `width` on every readable column (default 8.43 clips).
- **Preserve existing templates:** Match existing template styling when editing.
- **Visual delivery floor:** Before declaring done, run `officecli view "$FILE" html` and Read the returned HTML to confirm zero `###` cells, no truncated titles, no placeholder tokens (`$fy$24`, `{var}`, `<TODO>`, `xxxx`), distinct pie/doughnut slice fills (or switch to `bar`/`column`), and no empty trailing pages or empty chart anchors.
- **Print layout & Financial models:** Read [references/financial-models.md](references/financial-models.md) for print fit modes (`fitToPage=true` vs `1x0`), the 5-color financial model coding contract (`0000FF` inputs, `000000` formulas, `008000` cross-sheet, `FF0000` external, `FFFF00` assumptions), number formatting rules, and source notes for hardcoded inputs.

## Common Workflow

1. **Use one resident phase** (`open` … `save`/`close`). Never run CSV/TSV `import` inside a resident phase — in 1.0.144 use a non-resident batch with `calc.fullCalcOnLoad=true` and verify cells on disk (see [references/operations-and-import.md](references/operations-and-import.md)).
2. **Create or orient** (`officecli create "$FILE"` or `officecli view "$FILE" outline`).
3. **Build incrementally** and run `get` after structural ops (sheets, charts, named ranges, pivots).
4. **Format** column widths, number formats, freeze panes, tab colors, and print layout.
5. **Save & re-touch downstream formula caches:** `officecli save <file>` flushes XML, but downstream `INDEX/MATCH`, `SUMPRODUCT`, or cross-sheet formulas cache upstream values (`0`/stale) until re-touched via non-resident `set`; verify `cachedValue=` with `officecli get`.
6. **QA — assume there are problems:** Run `issues`, `annotated`, all 5 formula-error queries, `validate`, `view html`, and spot-check formulas before declaring done.

## Reference Library

- [references/operations-and-import.md](references/operations-and-import.md) — Quick Start recipe, CSV/TSV & Python bulk import, reading/dump/query/pivot/sparkline commands, batch JSON dotted-name rules (`font.color`/`fill`), charts (3 data forms, single-column trap, axis-by-role), conditional formatting, and data validation (3 list patterns).
- [references/financial-models.md](references/financial-models.md) — Print layout setup and full financial-model color, number-format, and source-documentation rules.
- [references/qa-and-pitfalls.md](references/qa-and-pitfalls.md) — Full 7-step QA cycle, formula/template checklists, 1.0.144 CLI bug backlog, cross-viewer renderer caveats, escape layers, and common pitfalls table.
