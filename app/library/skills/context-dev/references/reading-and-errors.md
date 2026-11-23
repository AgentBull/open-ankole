# Reading Rules and Errors

## Reading Rules

1. Pass a bare domain, such as `stripe.com`, where the tool asks for `domain`. Pass a full `http` or `https` URL where the tool asks for `url` or `directUrl`.
2. A cached answer returns in under a second. A cold answer takes about 7 seconds at p50 and can reach a minute, so raise `timeoutMS` toward its 300000 ms maximum for a first look at a slow site, and keep the mcporter `--timeout` above it.
3. `[N entries omitted]` or `...[truncated]` means the business result is incomplete. Do not analyze it and do not advance a cursor. Ask again with fewer pages, fewer results, or a narrower range.
4. Follow `next_cursor` while the response says more results exist. A page can close early to stay under its size limit, so trust the cursor instead of counting records.
5. Any field can be absent. Check the fields you need before you build an answer on them.
6. Report the URL or domain you read, the tool you called, and any page that failed or was skipped.

## Errors

| Status | Meaning | Next step |
| --- | --- | --- |
| 400 | Malformed input, `WEBSITE_ACCESS_ERROR` for an unreachable or blocked site, or `NOT_FOUND` for no brand match | Fix the input, or report the site as unreadable. `NOT_FOUND` is free |
| 401 | `CONTEXT_DEV_API_KEY` is missing or wrong | Report the variable name and ask the operator to set it in Console |
| 403 | `FORBIDDEN` for a paid-plan feature, or `USAGE_EXCEEDED` | Report the plan or quota limit. Browser `actions` need a paid plan |
| 408 | Cold answer or `timeoutMS` exceeded | Raise `timeoutMS`, or narrow the request |
| 422 | Free or disposable address on an email lookup | Skip enrichment for that address |
| 429 | Rate limit | Wait, then retry with growing delays |

A tool name that the server rejects means the catalog changed. Inspect the selected tool again and use its current replacement.
