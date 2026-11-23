---
title: Prompt assembly
description: How the system prompt an agent sees each turn is built — the control-plane data providers, the two channels that carry it to the worker, and the worker-side assembly that produces the final prompt.
section: Developer guide
order: 118
---

Every turn, the worker builds the system prompt the model sees. That prompt is assembled from PostgreSQL-backed agent context, resolved at turn time, and rendered on the worker. This page documents how the pieces get from the control plane to the worker, what each piece is, and where the assembly happens. It builds on the [Agent Computer Worker](../agent-computer-worker/) and [AIGateway](../ai-gateway/) pages.

The system prompt is **assembled on the Worker**, not on the control plane. The control plane supplies durable Agent documents, Skills, Agent settings, and chat context through two paths. The Worker renders these facts into the final prompt.

## The two data channels

The worker receives context from the control plane through two paths, each carrying a different class of data:

| Channel | What it carries | When |
|---|---|---|
| `turn_start.request_context` | agent-loop settings (`ai_agent.max_iterations`, `max_output_tokens`, `inactivity_timeout_ms`) and turn-local facts (the signal and the kind of turn) | embedded in the TurnStart envelope, before the loop begins |
| `AgentConversationContextBroker` RPC | durable Agent documents (`SOUL`/`MISSION`/`DESIGN`), enabled skills, conversation origin channel, instance timezone, agent profile | fetched by the worker at loop start, through an RPC over RuntimeFabric |

The split is deliberate: turn-local facts travel on `turn_start` because they change every turn; conversation-scoped context is fetched by the worker through the broker because it is stable across turns within a conversation and the broker caches it. The broker's moduledoc is explicit: "This RPC intentionally does not return transcript messages or turn-local request context. Transcript history is owned by AIGateway; turn-local facts travel on `turn_start`."

## What the control plane provides

### Durable Agent documents

`AgentConversationContextBroker` reads the Agent's durable documents through `Library.list_agent_documents/1`. It returns them as `soul`, `mission`, and `design`. `SOUL.md` defines communication and judgment, `MISSION.md` defines responsibilities, and `DESIGN.md` supplies the design system for visual work.

### Enabled skills

`Library.runtime_skills_for_agent/1` sends the Agent's complete effective Skill set, with descriptions and metadata, to the Worker. The Worker keeps the complete set for `skill_view`. When it builds the model-visible catalog, it omits Skills that declare `brain-recall-only: true`, so Brain can discover them without listing them in every prompt.

### Conversation origin channel

`SignalsGateway.ConversationChannel` projects the provider channel declared by the AIGateway conversation. It reads a group label from the current channel mirror and a DM label from the peer Principal. It reports the `lark` adapter as one Lark / Feishu surface; the adapter domain only selects the API server. The broker sends this projection through `ConversationInfo.origin_channel`, so an internal wakeup does not lose the conversation origin when its ActorEvent payload has no channel object.

### Agent settings (from AppConfigure)

`AgentConfig` resolves the loop-level settings from AppConfigure and snapshots them into `turn_start.request_context.ai_agent`:

- `ai_agent.max_iterations` (default 90) — the agent loop's iteration budget
- `ai_agent.max_output_tokens` (default nil = no explicit cap) — per-response token cap
- `ai_agent.inactivity_timeout_ms` (default 30 minutes) — how long a turn may be inactive

These belong to the actor turn, not to any individual model response, so they ride on `turn_start`.

## The worker-side assembly

`system_prompt.ts` on the worker builds the final system prompt. Its moduledoc states the design: "Slow-changing instructions lead; conversation-scoped runtime and skill context form the suffix." The blocks, in order:

1. **Identity and durable Agent documents** — the agent identity line, `SOUL.md`, and `MISSION.md` (when non-empty), rendered from the broker's response. (`DESIGN.md` and `ConfidentialityPolicy.md` are materialized as read-only files in Agent Home rather than embedded in the system prompt.)
2. **Completion and capability policy contracts** — `<completion_contract>` followed by capability-gated policy blocks (`<background_agent_job_policy>`, `<workflow_policy>`, `<long_term_memory>`, `<agent_environment_info_policy>`, and `<tools>`), driven only by stable turn capabilities.
3. **Skills** — the enabled skill catalog under `## Skills` (omitting `brain-recall-only: true` entries and, when Background Agent Jobs are unavailable, `ankole-runtime: background_job` entries), telling the model which Skills it can load on demand with `skill_view`.
4. **Session runtime context** — `<runtime_context>` carrying the agent UID, display name, workspace and `user-files` paths, timezone, optional role, conversation start time, and conversation origin channel.

The worker re-renders the prompt every turn from current PostgreSQL-backed context — it does not trust a cached version — while keeping the system prompt prefix byte-identical across main, ambient (`FOREGROUND_REPLY`, `NEW_WORK`), and scheduled turns when identity and capabilities match. Local `tools` and `hostedTools` declarations likewise stay identical across those turns; Worker `beforeToolCall` and AIGateway `HostedTools.Brain` enforce ambient route boundaries at execution time instead of mutating the system prompt or tool schema prefix. AIGateway retains prior request instructions for audit, while each turn renders the current state.

## What is NOT in the system prompt

- **Transcript history** — owned by AIGateway's stateful Responses; the system prompt does not repeat it.
- **Turn-local observations and directives** — the signal, `<agent_environment_info>`, `<ambient_route>` route directives, scheduled-turn reply instructions, and the user's current input. `buildTextTurnUserPrompt` places `<ambient_route>` and scheduled-turn reminders in the current turn's user message alongside `<agent_environment_info>`, keeping them out of the system prompt.

This separation keeps the system prompt and tool declarations prefix-cacheable (they change when persona, capabilities, or skills change, not per message or turn route) and keeps the per-turn payload small.

## Ambient recognizer prompt layout

In `ambient_prompt.ts`, the ambient intent router follows the same prefix-stability split:

- `buildAmbientRecognizerSystemPrompt` places the static routing policy (`routingPolicySection`) before the agent-specific `<about>` block (`display_name`, `<agent_soul>`, `<mission>`).
- `buildAmbientRecognizerUserPrompt` puts stable room metadata (`<runtime_context>` with `timezone`, `platform`, and `group_name`), standing orders, active work candidates, earlier context, and new messages ahead of `current_time`, placing `current_time` at the very end of the user prompt so the changing timestamp never invalidates the prefix ahead of it.

## What this guide is not

It is not a prompt-engineering tutorial — the literal strings in `system_prompt.ts` are the contract with the model, and changing them is a behavior change, not a documentation change. It is not a control-plane-side description of prompt assembly — the assembly is on the worker, and the control plane's role is to provide the data. And it is not a substitute for reading `system_prompt.ts`; it is the map to it.

## Next steps

- For the agent loop that uses this prompt, read [The agent loop](../agent-loop/).
- For the Agent Computer Worker that runs the assembly, read [Agent Computer Worker](../agent-computer-worker/).
- For the skills block, read [Agent Library](../agent-library/).
