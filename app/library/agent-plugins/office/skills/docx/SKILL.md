---
name: docx
description: "Use this skill for local .docx files as input or output: create, read, edit, and validate Word files. Lark cloud documents and tokens belong to lark-office-suite."
default_enabled: true
category: productivity
ankole-runtime: background_job
tags: [docx, document, word, officecli]
metadata:
  upstream: https://github.com/iOfficeAI/OfficeCLI/tree/v1.0.144/skills/officecli-docx
  modified_for: Ankole Agent Plugin runtime
---

# OfficeCLI DOCX Skill

For visual styling, use `design-md` when the user requests the internal design system or VIS, skip it when they opt out or choose another style instead, and treat it as optional when no style source is specified.

## Setup

The Worker image build installs OfficeCLI and checks its version. Run `officecli --version` and `officecli help docx`. If both commands succeed, continue with the installed CLI (version numbers in upstream references and known-issue notes are not runtime requirements); if either fails, report the command and error as the runtime blocker.

## Playbooks

A Playbook carries the extra rules for one kind of document. Before you plan the document, list the Playbooks and read every one that matches the request:

```bash
bun /repo/app/library/agent-plugins/office/tools/list_playbooks.ts docx
```

Each line gives the Playbook name, its absolute path, and the condition that selects it. A Playbook inherits every rule in this skill and adds to it, so read this skill first and keep both. When no Playbook matches, build from this skill alone.

## ⚠️ Help-First Rule

**This skill teaches what good docx looks like, not every command flag. When a property name, enum value, or alias is uncertain, consult help BEFORE guessing.**

```bash
officecli help docx                         # List all docx elements
officecli help docx <element>               # Full element schema (e.g. paragraph, field, numbering, watermark, toc)
officecli help docx <verb> <element>        # Verb-scoped (e.g. add field, set section)
officecli help docx <element> --json        # Machine-readable schema
```

Help is pinned to the installed CLI version and is authoritative over this skill. `officecli help docx ...` covers schema elements only; use top-level help (`officecli batch --help`, `officecli open --help`, `officecli view --help`) for command syntax.

## Mental Model & Shell Discipline

A `.docx` is a ZIP of XML parts (`document.xml`, `styles.xml`, `numbering.xml`, `header*.xml`, `footer*.xml`, `comments.xml`, …). `officecli` exposes XPath-style semantic paths (`/body/p[1]/r[2]`) over them.

- **Shell quoting:** ALWAYS quote element paths (`"/body/p[1]"`) and single-quote any prop value containing `$` (`--prop text='$50M'`) so shells neither glob `[N]` nor strip `$50`.
- **Escaping:** `\n` and `\t` in `--prop text=` (and table `c1…cN`) become `<w:br/>` and `<w:tab/>`; double them (`\\n`) for literal text. Use `"\\n"` inside `batch` JSON heredocs (`<<'EOF'`).
- **Incremental execution & lifecycle:** Run structural commands one at a time and `get` back after new styles, tables, TOCs, or section breaks. Use `officecli open "$FILE"` at start, `officecli save "$FILE"` (or `close "$FILE"` on one-shot handoff) only before non-officecli programs read the file. Never copy literal `doc.docx` / `review.docx` filenames—set `FILE="your-doc.docx"`.

## Requirements for Outputs

- **Clear hierarchy & explicit heading sizes:** Title → Heading 1 (>= 18pt, 20pt for long reports) → Heading 2 (14pt bold) → Heading 3 (12pt bold) → body (11–12pt, 1.15–1.5x line spacing). Set explicit sizes rather than relying on template defaults.
- **Typography & spacing:** One readable body font (Calibri, Cambria, Georgia, Times New Roman; note the worker renders locally using only `IBM Plex Sans SC`, `IBMPlexMonoSCHalf`, and `寒蝉锦书宋` / `ChillJinshuSong`, or follow `design-md` for internal VIS) + one accent color. Use `spaceBefore`/`spaceAfter` (never empty paragraphs), curly quotes (`‘’` `“”`), en-dash `–`, em-dash `—`.
- **Headers, footers, live page numbers (> 1 page):** Use `--prop field=page` (never literal `"Page 1"`). Suppress cover numbers via `--type footer --prop type=first --prop text=""` (never `set differentFirstPage=true`).
- **Preserve existing templates:** Match existing file styling when editing.
- **Visual delivery floor (verify via `officecli view "$FILE" html` + Read returned HTML):** No placeholder tokens (`$xxx$`, `{var}`, `{{name}}`, `<TODO>`, `lorem`, `xxxx`), no truncated titles or overflowing cells, TOC present when 3+ headings (`updateFields=true` for Word recalculation), cover page >= 60% filled, last page >= 40% filled, and no literal `\$`, `\t`, `\n` in text.

## Common Workflow

1. **Create or open** (`officecli create "$FILE"` then `officecli open "$FILE"`).
2. **Orient** on existing files with `officecli view "$FILE" outline`.
3. **Build incrementally:** styles & numbering defs → sections / page setup → headings & body → tables / images / fields / TOC → headers / footers → comments. `get` back after structural ops.
4. **Format to spec:** heading sizes, spacing, widths, alignment, tabs, list indents.
5. **Save & verify field structure:** TOC / PAGE / NUMPAGES / PAGEREF carry cached values until Word recalculates (`set /settings --prop updateFields=true`); recompute SEQ via `set / --prop recalcFields=seq`. Confirm fields exist structurally with `get --depth 3` (`fldChar`).
6. **QA — assume there are problems:** Run `issues`, `outline`, `text`, `validate`, visual pass (`screenshot --grid auto` / `view html`), and the Delivery Gate before declaring done.

## Reference Library

- [references/elements-and-editing.md](references/elements-and-editing.md) — Quick Start recipe, `view`/`get`/`query` navigation, paragraphs/tables (`pbdr.bottom` horizontal rules), single/multi-level lists, tab stops (`\t` leader caveat), fields/MERGEFIELD/SEQ, headers/footers, TOC (`outlineLvl`), images (`alt` required), native charts, internal hyperlinks (`anchor=`), sections, and mutually exclusive page breaks.
- [references/recipes-and-specialty.md](references/recipes-and-specialty.md) — Report-level recipes `(a)`–`(f)` (cover page, Page X of Y footer, header/financial tables, multi-bullet cells, dynamic TOC), Template Notes removal gate, equations/footnotes/comments/revisions/watermark, L1/L2/L3 `raw-set` XML appendix.
- [references/qa-and-pitfalls.md](references/qa-and-pitfalls.md) — Complete 6-step QA cycle, copy-pasteable Delivery Gate script (Gates 1–3), field spot-checks, renderer quirks, and full common pitfalls table.
