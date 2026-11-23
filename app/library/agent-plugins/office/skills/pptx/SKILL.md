---
name: pptx
description: "Create, read, edit, replicate, combine, or split PowerPoint (.pptx) decks. Use whenever .pptx is input or output, or supplied Markdown, documents, outlines, PDFs, or reference images must become an editable slide presentation. Lark cloud slides and tokens belong to lark-office-suite."
default_enabled: true
category: productivity
ankole-runtime: background_job
tags: [pptx, slides, presentation, officecli]
---

# PPTX

This Skill turns supplied material into an editable PowerPoint presentation and uses OfficeCLI for the file operations. It owns slide narrative, page selection, layout, typography, visual hierarchy, diagrams, charts, images, and rendering QA. It can split, merge, reorder, and condense supplied material to make a coherent slide sequence while preserving source meaning, notes, and footnotes.

For visual styling, use `design-md` when the user requests the internal design system or VIS. Skip it when the user opts out or chooses another style. Treat it as optional when no style source is specified. The selected style source supplies colors, type, surfaces, and brand rules; a Playbook supplies scene-specific information architecture and page grammar.

## Setup

The Worker image build installs OfficeCLI and checks its version. Run `officecli --version` and `officecli help pptx`. If both succeed, continue with the installed CLI (version numbers in notes are not runtime requirements); if either fails, report the command and error as the runtime blocker.

## Classify the Work

Determine primary mode: **Create** (new deck from request, material, or template), **Edit** (modify existing PPTX), or **Replicate** (reproduce appearance from images, PDF pages, or other non-PPTX sources).

Determine design direction precedence: `user requirements → supplied template → supplied design system → supplied style reference → self-directed design`.

Identify supplied content shape (full document, page-by-page outline/script, existing deck, or visual reference). Use the user's page count when specified and match a page-by-page outline/script unless asked to restructure; otherwise decide page count from material and the selected Playbook.

## Playbooks

A Playbook adds page organization and presentation grammar for one kind of deck. Before planning the deck, list the PPTX Playbooks:

```bash
bun /repo/app/library/agent-plugins/office/tools/list_playbooks.ts pptx
```

Read the one primary Playbook that best matches the requested deck. Use `poster-infographic` only when the user explicitly requests a poster, infographic, or highly visual single-page or few-page composition. When no Playbook matches, use this Skill alone.

A Playbook may reorganize supplied Markdown into a page sequence and define page types, narrative rhythm, density, and the visual role of figures, diagrams, images, and text. User requirements, an existing template, or a supplied design system take priority over Playbook defaults.

## Plan, Check, Then Build

Before any OfficeCLI edit, build a page map recording for each page:

> source span / page title / page type / role in the sequence / main visual / supporting text / density

Verify every supplied section has a destination (unless removed by user), repeated material is intentional, titles form a readable arc, and page count matches the request. Use section pages only on narrative phase changes, and vary page skeletons when material changes role. Preserve definitions, constraints, qualifications, numbers, labels, and relationships; move long supporting text into speaker notes only when permitted, or split/ask to narrow scope if content cannot fit legibly.

## Construction, Assets, and Templates

- Use the source deck's canvas and masters when editing or using a template; for a new deck, set background and text colors explicitly.
- Follow the user, template, design system, style reference, or selected Playbook for font hierarchy, grid, and color system; keep text readable at the viewing distance and split pages before shrinking below readable range.
- Prefer whitespace, alignment, type, rules, and image composition before generic cards; every container needs a grouping or state role. Keep one or two recurring visual motifs.
- Build editable diagrams with shapes and connectors (directional arrowheads; terminate at node edges without crossing text) and restyle editable charts to match the deck.
- Keep animations readable as static frames and check them in the target viewer.

Read [references/templates-and-style-transfer.md](references/templates-and-style-transfer.md) for visual asset selection, template preservation, style transfer, and replication rules.

## OfficeCLI Execution & QA

- Help (`officecli help pptx`, `officecli help pptx <element>`, `officecli <cmd> --help`) is authoritative over this Skill.
- Quote element paths (`"/slide[1]/shape[@name=Title]"`), single-quote values containing `$` (`--prop text='$15M'`), and remember `\n`/`\t` are interpreted in `text=`.
- Use `layout=blank` with ordinary shapes/text boxes for custom slides; name shapes (`@name=`) and run structural operations incrementally (`create`/`open` → build in display order → `save`/`close`).
- Before delivery, run `officecli validate "$FILE"` and `officecli view "$FILE" issues`, check `view text` for placeholder leaks (`xxxx`, `lorem`, `<TODO>`), confirm source preservation against the page map, and use `view html` or `view screenshot --grid 3` / `--page N` only when visual verification is needed.

Read [references/officecli-reference.md](references/officecli-reference.md) for complete OfficeCLI commands, gotchas, lifecycle, core element blueprints, and the full QA checklist.
