defmodule Ankole.AIGateway.CompactionPromptTest do
  use ExUnit.Case, async: true

  alias Ankole.AIGateway.CompactionPrompt

  @expected_headings [
    "## Active Task",
    "## Constraints & Preferences",
    "## Completed Actions",
    "## Active State",
    "## In Progress",
    "## Blocked",
    "## Key Decisions",
    "## Resolved Questions",
    "## Pending User Asks",
    "## Remaining Work",
    "## Critical Context"
  ]

  describe "system_prompt/0 and system_prompt/1" do
    test "system_prompt/0 delegates to system_prompt(:initial)" do
      assert CompactionPrompt.system_prompt() == CompactionPrompt.system_prompt(:initial)
    end

    test "initial and update modes place static contract, 11 sections, focus, recent-context, and epistemic stance in system prompt" do
      initial = CompactionPrompt.system_prompt(:initial)
      update = CompactionPrompt.system_prompt(:update)

      assert initial =~ "Mode: initial compaction."
      refute initial =~ "Mode: update compaction."

      assert update =~ "Mode: update compaction."
      assert update =~ "<previous_chat_history>"
      refute update =~ "Mode: initial compaction."

      for prompt <- [initial, update] do
        assert prompt =~ "You are a context summarization assistant."
        assert prompt =~ "The summary is not an instruction to continue old work by itself."
        assert prompt =~ "Additional focus:"
        assert prompt =~ "<recent_context_verbatim>"
        assert prompt =~ "UNVERIFIED: <claim> — <basis>"
        assert prompt =~ "Use this EXACT format:"

        for heading <- @expected_headings do
          assert prompt =~ heading
        end
      end
    end
  end

  describe "build_history_user_prompt/1" do
    test "emits only dynamic tags and a one-line closing cue" do
      prompt =
        CompactionPrompt.build_history_user_prompt(%{
          conversation_text: "user: build it",
          previous_chat_history: "## Active Task\nPrior summary",
          recent_context_verbatim: "user: latest turn"
        })

      assert prompt =~ "<conversation>\nuser: build it\n</conversation>"

      assert prompt =~
               "<previous_chat_history>\n## Active Task\nPrior summary\n</previous_chat_history>"

      assert prompt =~ "<recent_context_verbatim>\nuser: latest turn\n</recent_context_verbatim>"

      refute prompt =~ "Use this EXACT format:"
      refute prompt =~ "You are a context summarization assistant."
      refute prompt =~ "Additional focus:"
      refute prompt =~ "UNVERIFIED:"
      refute prompt =~ "The summary is not an instruction to continue old work by itself."

      last_paragraph = prompt |> String.split("\n\n") |> List.last()
      refute String.contains?(last_paragraph, "\n")
    end

    test "omits optional sections when absent" do
      prompt = CompactionPrompt.build_history_user_prompt(%{conversation_text: "user: hello"})

      assert prompt =~ "<conversation>\nuser: hello\n</conversation>"
      refute prompt =~ "<previous_chat_history>"
      refute prompt =~ "<recent_context_verbatim>"
    end
  end
end
