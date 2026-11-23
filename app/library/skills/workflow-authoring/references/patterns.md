# Workflow Script Patterns

Reference examples for `workflow-authoring`. Each pattern shows bounded fanout, `null` filtering for exhausted task retries, and valid JSON Schema construction (`properties`, `required`, and `additionalProperties: false` on every object).

## Map and reduce

Start independent calls together. Filter failed values before reduction.

```js
const rows = await Promise.all(
  args.items.map((item, index) =>
    agent(`Analyze this item and return one finding: ${JSON.stringify(item)}`, {
      label: `analyze:${index}`,
      schema: {
        type: "object",
        properties: {
          finding: { type: "string" },
          confidence: { type: "number", minimum: 0, maximum: 1 }
        },
        required: ["finding", "confidence"],
        additionalProperties: false
      }
    })
  )
);
const findings = rows.filter((row) => row !== null);
return { findings };
```

## Run stages

Wait for one batch, then use its compact output in the next batch. Keep the second-stage prompt bounded.

```js
const collected = await Promise.all(
  args.sources.map((source, index) =>
    agent(`Extract up to three claims from ${source}.`, {
      label: `collect:${index}`,
      schema: { type: "array", items: { type: "string" }, maxItems: 3 }
    })
  )
);
const claims = collected.filter((value) => value !== null).flat();
if (claims.length === 0) return { claims: [], verdicts: [] };
const verdicts = await Promise.all(
  claims.map((claim, index) =>
    agent(`Verify this claim and return a short verdict: ${claim}`, {
      label: `verify:${index}`,
      schema: { type: "string", maxLength: 1000 }
    })
  )
);
return { claims, verdicts };
```

## Use a verification panel

Give the same candidate to independent reviewers. Let the script preserve disagreement for the main Agent.

```js
const reviews = await Promise.all(
  ["evidence", "logic", "risk"].map((role) =>
    agent(`Review the candidate for ${role}: ${args.candidate}`, {
      label: `panel:${role}`,
      schema: {
        type: "object",
        properties: {
          pass: { type: "boolean" },
          reason: { type: "string", maxLength: 1200 }
        },
        required: ["pass", "reason"],
        additionalProperties: false
      }
    })
  )
);
return { reviews };
```

## Run a tournament

Reduce a finite candidate set in pairs. A failed comparison keeps the first candidate, so one failed task does not erase the bracket.

```js
let round = args.candidates.slice(0, 32);
for (let roundIndex = 0; round.length > 1 && roundIndex < 5; roundIndex += 1) {
  const next = [];
  for (let index = 0; index < round.length; index += 2) {
    if (index + 1 >= round.length) {
      next.push(round[index]);
      continue;
    }
    const winner = await agent(
      `Choose the stronger candidate and return it exactly: ${JSON.stringify([round[index], round[index + 1]])}`,
      { label: `round:${roundIndex}:pair:${index / 2}`, schema: { type: "string" } }
    );
    next.push(winner === null ? round[index] : winner);
  }
  round = next;
}
return { winner: round[0] ?? null };
```

The final `null` in this example is a Workflow result field, not an `agent()` success value. Do not use a nullable task schema.

## Loop until dry

Use a small fixed round limit. Stop early when one round finds no new work.

```js
let frontier = args.seeds.slice(0, 20);
const seen = new Set(frontier);
for (let round = 0; round < 4 && frontier.length > 0; round += 1) {
  const expansions = await Promise.all(
    frontier.map((item, index) =>
      agent(`Find up to three new related items for: ${item}`, {
        label: `expand:${round}:${index}`,
        schema: { type: "array", items: { type: "string" }, maxItems: 3 }
      })
    )
  );
  frontier = expansions
    .filter((value) => value !== null)
    .flat()
    .filter((item) => !seen.has(item))
    .slice(0, 20);
  frontier.forEach((item) => seen.add(item));
}
return { items: [...seen] };
```
