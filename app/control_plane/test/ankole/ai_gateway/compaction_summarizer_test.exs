defmodule Ankole.AIGateway.CompactionSummarizerTest do
  use Ankole.AIGatewayCase

  alias Ankole.AppConfigure
  alias Ankole.AIGateway.CompactionPrompt
  alias Ankole.AIGateway.CompactionSummarizer

  setup do
    allow_cache_database_access()
    AppConfigure.Cache.clear_for_test()
    on_exit(fn -> AppConfigure.Cache.clear_for_test() end)

    test_pid = self()

    base_url =
      start_upstream_server(fn %{path: "v1/responses", body: body} ->
        send(test_pid, {:summarizer_upstream_request, body})

        {:sse, 200,
         openai_response_stream_events(
           "resp_compaction_summary",
           body["model"],
           "## Active Task\nSummarized cleanly."
         )}
      end)

    agent = agent_fixture().principal

    {:ok, _provider} =
      ProviderConfigs.create_provider(%{
        provider_id: "openai-compaction-summarizer-test",
        provider_kind: "openai",
        base_url: "#{base_url}/v1",
        credential_pool: %{
          "entries" => [%{"label" => "Default", "api_key" => "sk-openai"}]
        },
        connection_options: %{
          "transport" => %{"http_versions" => ["h1"], "compression" => ["gzip"]}
        }
      })

    {:ok, _profile} =
      ModelProfiles.put_model_profile(agent.uid, "light", %{
        provider_id: "openai-compaction-summarizer-test",
        model: "gpt-compact-light",
        context_length: 131_072
      })

    items = [%{"type" => "message", "role" => "user", "content" => "summarize this work"}]
    %{agent: agent, items: items}
  end

  test "initial compaction without affinity_key uses :initial system prompt and fallback cache key",
       %{agent: agent, items: items} do
    assert {:ok, summary} = CompactionSummarizer.summarize(agent.uid, items, nil)
    assert summary.text == "## Active Task\nSummarized cleanly."

    assert_receive {:summarizer_upstream_request, body}
    assert body["instructions"] == CompactionPrompt.system_prompt(:initial)
    assert body["reasoning"] == %{"effort" => "low"}
    assert body["prompt_cache_key"] == "compaction:summary:initial"
    assert body["input"] =~ "<conversation>"
    refute body["input"] =~ "Use this EXACT format:"
  end

  test "update compaction without affinity_key uses :update system prompt and fallback cache key",
       %{agent: agent, items: items} do
    assert {:ok, _summary} =
             CompactionSummarizer.summarize(agent.uid, items, "## Active Task\nEarlier task")

    assert_receive {:summarizer_upstream_request, body}
    assert body["instructions"] == CompactionPrompt.system_prompt(:update)
    assert body["reasoning"] == %{"effort" => "low"}
    assert body["prompt_cache_key"] == "compaction:summary:update"

    assert body["input"] =~
             "<previous_chat_history>\n## Active Task\nEarlier task\n</previous_chat_history>"
  end

  test "preserves explicit affinity_key as prompt_cache_key when provided in request_context",
       %{agent: agent, items: items} do
    request_context = %{"headers" => %{"session-id" => "session-affinity-42"}}

    assert {:ok, _summary} =
             CompactionSummarizer.summarize(agent.uid, items, nil,
               request_context: request_context
             )

    assert_receive {:summarizer_upstream_request, body}
    assert body["instructions"] == CompactionPrompt.system_prompt(:initial)
    assert body["prompt_cache_key"] == "session-affinity-42"
  end
end
