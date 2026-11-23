---
name: context-dev
description: "Get web data from Context.dev: inventory/crawl sites or run large async batches; extract JSON in a supplied schema; resolve company profiles (logos, colors, socials, industry, address, ticker) from domain, name, work email, ticker, card descriptor, or URL; or monitor pages on a schedule."
default_enabled: false
ankole-runtime: any
category: data
tags:
  - web-data
  - scraping
  - brand
  - extraction
  - mcp
---

# Context.dev

Context.dev turns a URL, a domain, or file bytes into typed JSON. Every call spends credits from the operator's Context.dev account, so select the narrowest tool that answers the question, and keep a result instead of asking for it a second time.

## Select the Owner First

Ankole already owns most of this work. Use the built-in owner when it applies:

| Work | Owner |
| --- | --- |
| Find a page, or read the text of a page that a plain fetch reaches | `web_search`, `web_fetch` |
| Read a PDF or an image that is already in the workspace | `pdf` Skill, `ocr` Skill |
| Click, sign in, or drive one rendered browser session | `browser` Skill |

Route to Context.dev for the work those owners do not cover:

- A page that refuses an ordinary fetch, or that shows its content only after a wait or a click.
- A site inventory, a whole-site crawl, or an asynchronous batch of up to 25,000 URLs.
- A page or site that must answer in a caller-defined JSON Schema.
- A company profile, design system, font list, page screenshot, or NAICS or SIC code.
- A page, sitemap, or extraction that must be watched on a schedule.

## MCP Entry Point

The configured mcporter server is `context-dev`. Use **Tool Selection** below to choose one exact tool before you inspect or call the server.

When the arguments are not already fixed by this Skill and its references, inspect only the selected tool:

```bash
mcporter list 'context-dev.<tool-name>' --schema --json --timeout 360000
```

Write the argument object as JSON to a temporary file, then call the tool without shell interpolation. Send the result to an absolute file path and read that file:

```bash
mcporter call 'context-dev.<tool-name>' --json - --output json --timeout 360000 \
  < /absolute/path/to/arguments.json > /absolute/path/to/result.json
```

Read `result.json`, or reduce it first with `jq` or `python3` when it is large. Remove the argument file and the result file after each call.

mcporter loses most of its own output when stdout is a pipe, and the command tool captures stdout through a pipe. Page Markdown, crawl results, sitemaps, and batch pages are large enough to be cut in the middle of a token with exit code 0 and no error on stderr. Write to a file, and treat a JSON parse failure on mcporter output as this truncation until you prove otherwise.

In an Automation Job, use `Bun.spawn` with the same argv and JSON on stdin, and write stdout to a file. Check the process exit code and read stderr as a failure diagnostic.

Ankole generates `MCPORTER_CONFIG` for each Main turn, Background Agent Job execution, or Automation attempt from this enabled Skill. The declaration fixes the endpoint and names `CONTEXT_DEV_API_KEY`; the value stays in the execution WorkerEnv. A `401` means that variable is empty or wrong, not that the request was malformed.

## Tool Selection

### Web reading

- `web-search`: Search the live web (1 credit/result, `numResults` starts at 10; `markdownOptions.enabled: true` scrapes each hit).
- `web-scrape-markdown`: Turn one known URL into clean Markdown (1 credit, 2 with `actions`). Default page reader.
- `web-scrape-html`: Return rendered raw HTML (1 credit, 2 with `actions`) when DOM structure/scripts are needed.
- `web-scrape-images`: List page image assets (1 credit, 2 with `actions`, 5 with `enrichment`).
- `web-scrape-sitemap`: Discover URLs of a domain (1 credit; returns URLs only).
- `web-crawl`: Follow internal links synchronously (1 credit/page, `maxPages` <= 500). Set `maxPages` to what you will read.
- `web-extract`: Crawl relevant pages and return data shaped by a JSON Schema (10 credits, `maxPages` <= 50).
- `parse-document`: Convert base64 file bytes <= 25 MiB to Markdown (1 credit, 5 with OCR). Use only for formats Ankole's local Skills do not read (e.g., `.doc`, `.rtf`, `.srt`).

Read [references/web-reading.md](references/web-reading.md) before composing any of these calls.

### Brand intelligence

- `brand-retrieve-unified`: Structured company profile (10 credits); all arguments go in one `body` object whose `type` selects the lookup.
- `get-brand`: Same profile for a bare domain as a visual card (10 credits). Prefer `brand-retrieve-unified` for structured fields.

### Design, visual, and classification

- `web-styleguide`: Colors, typography, spacing, shadows, and component CSS (10 credits).
- `web-fonts`: Font families of a site with fallbacks and usage share (5 credits).
- `web-screenshot`: Hosted PNG URL for a rendered page (5 credits).
- `web-naics`: 2022 NAICS codes for a domain or company name (10 credits).
- `web-sic`: SIC codes against `original_sic` or `latest_sec` (10 credits).

Read [references/brand-and-design.md](references/brand-and-design.md) for the `body` union, returned brand fields, and the `domain`/`directUrl` rule.

### Monitors & Batches

- **Monitors** (`list-monitors`, `create-monitor`, `get-monitor`, `update-monitor`, `delete-monitor`, `run-monitor-now`, `list-monitor-runs`, `get-monitor-run`, `list-monitor-changes`, `list-changes`, `get-change`, `list-account-runs`, `list-monitor-credit-usage`): recurring checks that spend credits per run.
- **Batches** (`submit-batch`, `list-batches`, `get-batch`, `get-batch-results`, `cancel-batch`, `delete-batch`): async jobs for up to 25,000 URLs or large crawls.

Read [references/monitors-and-batches.md](references/monitors-and-batches.md) for both lifecycles.

## Account Writes

`create-monitor`, `update-monitor`, `delete-monitor`, `run-monitor-now`, `submit-batch`, `cancel-batch`, and `delete-batch` change durable state in the operator's Context account, and a monitor keeps spending credits until removed. Call them for the user's request and report the returned monitor or batch ID.

Treat submissions as non-idempotent: list monitors/batches after a timeout or unclear error before retrying, and reuse the same `Idempotency-Key` when retrying `submit-batch`.

## Reading Rules and Error Handling

Pass a bare `domain` where requested and a full `http`/`https` URL for `url`/`directUrl`. Raise `timeoutMS` toward `300000` (and keep `--timeout` higher) for slow cold pages, follow `next_cursor` instead of counting records, never analyze `[N entries omitted]` or `...[truncated]` responses, check for absent fields, and report the target, tool called, and any skipped/failed pages.

Read [references/reading-and-errors.md](references/reading-and-errors.md) for the full reading rules and HTTP error handling (`400`, `401`, `403`, `408`, `422`, `429`).
