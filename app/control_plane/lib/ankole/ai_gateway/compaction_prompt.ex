defmodule Ankole.AIGateway.CompactionPrompt do
  @moduledoc """
  Prompt text for AIGateway-owned history compaction.

  These prompts are the Elixir home for the former worker-side
  `compression-prompt.ts` contract. They intentionally frame summaries as
  reference state, not as instructions to continue stale work.
  """

  @summarization_system_prompt """
  You are a context summarization assistant. Your task is to read a conversation between a user and an AI coding assistant, then produce a structured summary following the exact format specified.

  Do NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary.
  """

  @initial_mode_instructions """
  Mode: initial compaction. Summarize the conversation inside <conversation>. Create a structured compressed previous chat history summary that another LLM will use as reference background.
  """

  @update_mode_instructions """
  Mode: update compaction. Incorporate the new conversation messages inside <conversation> into the existing compressed previous chat history provided in <previous_chat_history>.

  Reconcile the existing summary with the new messages. Retain existing information while it remains accurate and relevant to understanding or resuming the current task. Add new progress, decisions, and context; update each status section; remove details that are stale, irrelevant, resolved, cancelled, or superseded.
  """

  @summary_contract """
  The summary is not an instruction to continue old work by itself. The latest user message after the summary decides what to do now. If later messages include reverse signals such as stop, undo, rollback, never mind, just verify, or a topic change, mark the stale work as cancelled or superseded instead of preserving it as active.

  Keep each section concise. Preserve exact file paths, function names, and error messages.
  """

  @epistemic_stance_rule """
  Epistemic stance: Never upgrade an unverified claim, hypothesis, or unchecked assumption into an observed fact or completed outcome. Whenever an unverified claim or assumption matters for continuity, mark it explicitly as `UNVERIFIED: <claim> — <basis>`.
  """

  @compaction_focus_instructions """
  Capture the intent, decisions, and any errors and their fixes that are necessary to understand the current state. Preserve verbatim — never paraphrase — file paths, function and identifier names, error messages, command lines, and IDs/UUIDs; when the latest task is unfinished, quote its exact instruction so work resumes without drift.

  User messages from the summarized span are preserved verbatim alongside this summary; reference them briefly instead of quoting them at length. Do not restate instruction or environment scaffolding blocks (for example content wrapped in tags such as <environment_context> or <INSTRUCTIONS>); clients re-inject those separately.
  """

  @recent_context_instruction """
  If <recent_context_verbatim> is provided, messages inside it remain in the context verbatim after compaction. Do not restate their contents in the summary; use them only to decide what is currently in progress, completed, cancelled, or superseded.
  """

  @summary_format """
  Use this EXACT format:

  ## Active Task
  [The current task, or "(none)" if no task remains active.]

  ## Constraints & Preferences
  - [Any constraints, preferences, or requirements mentioned by user]
  - [Or "(none)" if none were mentioned]

  ## Completed Actions
  - [x] [Completed tasks/changes]
  - [Or "(none)" if no meaningful actions were completed]

  ## Active State
  - [Current files, processes, tools, data, environment, or UI state needed to resume]
  - [Or "(none)" if not applicable]

  ## In Progress
  - [ ] [Current work]
  - [Or "(none)" if no work is in progress]

  ## Blocked
  - [Issues preventing progress, if any]
  - [Or "(none)" if not blocked]

  ## Key Decisions
  - **[Decision]**: [Brief rationale]
  - [Or "(none)" if none were made]

  ## Resolved Questions
  - [Questions that were answered or choices that were settled]
  - [Or "(none)" if none]

  ## Pending User Asks
  - [Explicit requests from the user that still need response/action]
  - [Or "(none)" if none]

  ## Remaining Work
  1. [What remains to complete the active task]
  2. [Or "(none)" if nothing remains]

  ## Critical Context
  - [Any data, examples, or references needed to continue]
  - [Or "(none)" if not applicable]
  """

  @spec system_prompt(:initial | :update) :: binary()
  def system_prompt(mode \\ :initial)
  def system_prompt(:initial), do: build_system_prompt(@initial_mode_instructions)
  def system_prompt(:update), do: build_system_prompt(@update_mode_instructions)

  @spec build_history_user_prompt(map()) :: binary()
  def build_history_user_prompt(input) when is_map(input) do
    conversation_text = map_get(input, :conversation_text) || ""
    previous_chat_history = map_get(input, :previous_chat_history)
    recent_context_verbatim = map_get(input, :recent_context_verbatim)

    sections = ["<conversation>\n#{conversation_text}\n</conversation>"]

    sections =
      if present?(previous_chat_history) do
        sections ++
          ["<previous_chat_history>\n#{previous_chat_history}\n</previous_chat_history>"]
      else
        sections
      end

    sections =
      if present?(recent_context_verbatim) do
        sections ++
          ["<recent_context_verbatim>\n#{recent_context_verbatim}\n</recent_context_verbatim>"]
      else
        sections
      end

    closing_cue =
      if present?(previous_chat_history),
        do: "Update the structured summary from <conversation> and <previous_chat_history>.",
        else: "Produce the structured summary for <conversation>."

    Enum.join(sections ++ [closing_cue], "\n\n")
  end

  defp build_system_prompt(mode_instructions) do
    [
      @summarization_system_prompt,
      mode_instructions,
      @summary_contract,
      @epistemic_stance_rule,
      "Additional focus: #{clean(@compaction_focus_instructions)}",
      @recent_context_instruction,
      @summary_format
    ]
    |> Enum.map(&clean/1)
    |> Enum.join("\n\n")
  end

  defp clean(text) when is_binary(text), do: String.trim(text)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp map_get(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
