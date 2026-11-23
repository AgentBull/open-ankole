# OfficeCLI PPTX Command and QA Reference

## OfficeCLI Runtime & Gotchas

- Help reflects the installed CLI version. When this Skill and help disagree, help is authoritative. Run help before guessing a property, alias, enum value, animation preset, chart type, or canvas control, and after any `UNSUPPORTED props:` or unknown-enum error.
- `officecli help pptx ...` covers schema elements only. Use a top-level command's own help for its syntax, such as `officecli batch --help`, `officecli open --help`, or `officecli view --help`.
- Always quote element paths such as `"/slide[1]/shape[@name=Title]"`; zsh treats unquoted brackets as globs.
- Single-quote values that contain `$`, such as `--prop text='$15M'`. After writing currency or escaped text, use `view text` and compare it character for character.
- The CLI interprets `\n` and `\t` in `text=` values.
- For custom slides, use `layout=blank` and ordinary shapes or text boxes. Slide-level title/text shorthand creates placeholders that some viewers import incorrectly.
- Name important shapes when creating them. Prefer `@name=` selectors to positional shape indexes after any reorder.

```bash
officecli help pptx
officecli help pptx <element>
officecli help pptx <verb> <element>
officecli help pptx <element> --json
```

Run structural operations incrementally. After adding a slide, chart, animation, or connector, inspect the affected slide before adding more elements.

## File Lifecycle

Start wide, then narrow:

```bash
officecli view "$FILE" outline
officecli view "$FILE" annotated
officecli view "$FILE" text --start 1 --end 5
officecli view "$FILE" issues
officecli view "$FILE" stats
```

Use stable shape names and quoted selectors:

```bash
officecli get "$FILE" "/slide[1]" --depth 1
officecli get "$FILE" "/slide[1]/shape[@name=Title]"
officecli query "$FILE" 'picture:no-alt'
```

For a new deck, create and open it. For an existing deck, inspect it before editing:

```bash
officecli create "$FILE"
officecli open "$FILE"
```

Build in display order. Add the slide and its background, then the title, then the main visual, then supporting elements. Check the slide structure after each structural change.

Save only when a non-OfficeCLI program must read the current file, at a delivery boundary, or before closing:

```bash
officecli save "$FILE"
officecli close "$FILE"
```

## Core operations

Confirm uncertain properties with help. These examples show the basic command shape:

```bash
# Blank slide with an explicit background
officecli add "$FILE" / --type slide --prop layout=blank --prop background=FFFFFF

# Named text shape
officecli add "$FILE" "/slide[1]" --type shape \
  --prop name=Title --prop text="Section title" \
  --prop x=2cm --prop y=1.4cm --prop width=29.8cm --prop height=2.2cm \
  --prop font="IBM Plex Sans SC" --prop size=36 --prop bold=true \
  --prop color=171717 --prop fill=none

# Picture
officecli add "$FILE" "/slide[1]" --type picture --prop src=hero.jpg \
  --prop x=18cm --prop y=4cm --prop width=13cm --prop height=10cm \
  --prop alt="Product image"

# Connector between named nodes
officecli add "$FILE" "/slide[2]" --type connector \
  --prop "from=/slide[2]/shape[@name=BoxA]" \
  --prop "to=/slide[2]/shape[@name=BoxB]" \
  --prop shape=elbow --prop color=333333 --prop tailEnd=triangle
```

Use `officecli help pptx add chart`, `officecli help pptx table`, and the element-specific help for charts, tables, groups, comments, hyperlinks, or animation.

## QA

Do not deliver after a structural check alone. Verify the file, the source transformation, and the visual result to the degree the request needs.

### 1. Structure

```bash
officecli validate "$FILE"
officecli view "$FILE" issues
```

Fix every schema, overflow, clipping, off-slide, or structural issue. Then inspect `view text` for leftover placeholders such as `xxxx`, `lorem`, `<TODO>`, or empty chart labels.

### 2. Narrative and source preservation

Compare the final slide map with the supplied material. Confirm that the page sequence is coherent and that every required source span, definition, constraint, qualification, number, label, and relationship remains present after conversion.

### 3. Visual review

Rendered slide views are expensive. Use `officecli view "$FILE" screenshot` only when a rendered view is necessary to meet the request or resolve a real layout uncertainty. Choose the least expensive view that answers the question:

```bash
officecli view "$FILE" screenshot --grid 3 -o overview.png
officecli view "$FILE" screenshot --page 1 -o slide-1.png
```

When visual inspection is warranted, check for:

- overlap, clipping, overflow, or shapes outside the canvas;
- narrow text boxes and broken line wrapping;
- weak contrast or dark-on-dark elements;
- stretched images, destructive crops, or text over busy imagery;
- missing arrowheads or connectors crossing text;
- inconsistent margins, gaps, baselines, and repeat-element sizes;
- headers, footers, page numbers, or footnotes colliding with body content;
- page skeletons that repeat without narrative reason;
- a slide order that differs from the checked page map.

Use `officecli view "$FILE" html` when it answers the question more cheaply. State any visual property that remains unverified. After a fix, rerun only the checks that establish whether the fix worked.

Finally, save the deck and open it in the target presentation viewer when one is available. OfficeCLI previews cannot prove target-viewer font substitution, chart rendering, animation, or import behavior.
