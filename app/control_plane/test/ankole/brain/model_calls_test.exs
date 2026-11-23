defmodule Ankole.Brain.ModelCallsTest do
  use ExUnit.Case, async: true

  alias Ankole.Brain.ModelCalls

  describe "decode_json_object/1" do
    test "decodes a bare object" do
      assert {:ok, %{"facts" => []}} = ModelCalls.decode_json_object(~s({"facts": []}))
    end

    test "decodes analysis prose followed by a bare object" do
      # Models without structured output, for example DeepSeek, put their
      # full analysis in output_text and append the JSON at the end.
      text = """
      Let me analyze this conversation step by step.
      The user mentioned a product called Cobalt-593.
      Here is the extraction result:
      {"facts": [{"claim": "Cobalt-593 launched", "kind": "event"}], "takes": []}
      """

      assert {:ok, %{"facts" => [%{"claim" => "Cobalt-593 launched"}]}} =
               ModelCalls.decode_json_object(text)
    end

    test "decodes the last fenced block after analysis" do
      text = """
      Analysis with an inline example: `{"not": "this"}` is the shape.

      ```json
      {"facts": [], "takes": [{"claim": "prefer weekly summaries"}]}
      ```
      """

      assert {:ok, %{"takes" => [%{"claim" => "prefer weekly summaries"}]}} =
               ModelCalls.decode_json_object(text)
    end

    test "prefers the whole text when it already is the object" do
      text = ~s({"nested": {"a": 1}, "note": "contains } and { in strings"})
      assert {:ok, %{"nested" => %{"a" => 1}}} = ModelCalls.decode_json_object(text)
    end

    test "fails when no candidate is a JSON object" do
      assert {:error, :model_output_not_json} =
               ModelCalls.decode_json_object("I could not produce a result.")

      assert {:error, :model_output_not_json} = ModelCalls.decode_json_object(~s(["array"]))
    end

    test "takes the last balanced object when the output carries several" do
      # A first-to-last brace slice would fuse both objects into invalid
      # JSON; the balanced scan keeps them separate and the final answer
      # comes last.
      text = """
      Draft attempt: {"items": [{"claim": "wrong draft"}]}
      Corrected result:
      {"items": [{"claim": "final answer", "kind": "fact"}]}
      """

      assert {:ok, %{"items" => [%{"claim" => "final answer"}]}} =
               ModelCalls.decode_json_object(text)
    end

    test "balanced scan ignores braces inside strings" do
      text = ~s(prose {"a": "left { and right }", "b": 2} trailing)
      assert {:ok, %{"a" => "left { and right }", "b" => 2}} = ModelCalls.decode_json_object(text)
    end

    test "an unbalanced trailing brace does not break earlier objects" do
      text = ~s(first: {"ok": true} then a dangling { at the end)
      assert {:ok, %{"ok" => true}} = ModelCalls.decode_json_object(text)
    end
  end
end

defmodule Ankole.Brain.ModelCallsRequestTest do
  use Ankole.AIGatewayCase

  alias Ankole.AppConfigure
  alias Ankole.Brain.Config
  alias Ankole.Brain.ModelCalls

  setup do
    allow_cache_database_access()
    AppConfigure.Cache.clear_for_test()
    on_exit(fn -> AppConfigure.Cache.clear_for_test() end)

    test_pid = self()

    base_url =
      start_upstream_server(fn %{path: "chat/completions", body: body} ->
        send(test_pid, {:model_calls_upstream, body})
        {:json, 200, chat_completion_body(body["model"], ~s({"ok":true}))}
      end)

    {:ok, _provider} =
      ProviderConfigs.create_provider(%{
        provider_id: "brain-model-calls-test",
        provider_kind: "openrouter",
        base_url: base_url,
        credential_pool: %{"entries" => [%{"label" => "Default", "api_key" => "sk-test"}]}
      })

    configure_brain_maintainer_profile!("light", "brain-model-calls-test", "fake-model-calls")
    %{model: Config.extraction_model()}
  end

  test "complete_text/3 and complete_json/3 forward non-empty instructions and prompt_cache_key",
       %{
         model: model
       } do
    assert {:ok, ~s({"ok":true})} =
             ModelCalls.complete_text(model, "dynamic data",
               caller: "brain.test",
               instructions: "static rules",
               prompt_cache_key: "brain:test_key"
             )

    assert_receive {:model_calls_upstream, body}
    assert body["prompt_cache_key"] == "brain:test_key"

    assert [
             %{"role" => "system", "content" => "static rules"},
             %{"role" => "user", "content" => "dynamic data"}
           ] = body["messages"]

    assert {:ok, %{"ok" => true}} =
             ModelCalls.complete_json(model, "json data",
               caller: "brain.test",
               instructions: "json rules",
               prompt_cache_key: "brain:json_key"
             )

    assert_receive {:model_calls_upstream, json_body}
    assert json_body["prompt_cache_key"] == "brain:json_key"

    assert [
             %{"role" => "system", "content" => "json rules"},
             %{"role" => "user", "content" => "json data"}
           ] = json_body["messages"]
  end

  test "complete_text/3 omits empty or nil instructions and prompt_cache_key", %{model: model} do
    assert {:ok, ~s({"ok":true})} =
             ModelCalls.complete_text(model, "plain prompt",
               instructions: "   ",
               prompt_cache_key: ""
             )

    assert_receive {:model_calls_upstream, body}
    refute Map.has_key?(body, "prompt_cache_key")
    assert [%{"role" => "user", "content" => "plain prompt"}] = body["messages"]
  end
end
