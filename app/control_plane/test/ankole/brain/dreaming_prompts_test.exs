defmodule Ankole.Brain.DreamingPromptsTest do
  use Ankole.AIGatewayCase

  alias Ankole.AppConfigure
  alias Ankole.Brain.Claims
  alias Ankole.Brain.Dreaming
  alias Ankole.Brain.Objects
  alias Ankole.Brain.SchemaPacks

  setup do
    allow_cache_database_access()
    AppConfigure.Cache.clear_for_test()
    on_exit(fn -> AppConfigure.Cache.clear_for_test() end)

    {:ok, _result} = SchemaPacks.install_packs([])

    test_pid = self()

    base_url =
      start_upstream_server(fn %{path: "chat/completions", body: body} ->
        send(test_pid, {:dreaming_request, body})

        system =
          body["messages"]
          |> Enum.find(&(&1["role"] == "system"))
          |> Map.fetch!("content")

        payload =
          if String.contains?(system, "Extract dated events") do
            %{"items" => []}
          else
            %{
              "verdict" => "no_contradiction",
              "axis" => "Compatible claims.",
              "severity" => "info",
              "confidence" => 0.9
            }
          end

        {:json, 200, chat_completion_body(body["model"], Ankole.JSON.encode!(payload))}
      end)

    {:ok, _provider} =
      ProviderConfigs.create_provider(%{
        provider_id: "brain-dreaming-prompts",
        provider_kind: "openrouter",
        base_url: base_url,
        credential_pool: %{"entries" => [%{"label" => "Default", "api_key" => "sk-test"}]}
      })

    configure_brain_maintainer_profile!("heavy", "brain-dreaming-prompts", "fake-dreaming")

    %{principal: human} = human_fixture()
    %{human: human}
  end

  test "phase_extract_links separates timeline extraction instructions and sets prompt_cache_key",
       %{human: human} do
    {:ok, _object} =
      Objects.create_object(
        %{
          slug: "projects/timeline-cache",
          type: "project",
          title: "Timeline Cache",
          body: "On 2026-04-01 the team froze the v1 API."
        },
        human.uid
      )

    assert %{status: :ok, objects: count} = Dreaming.phase_extract_links()
    assert count >= 1

    assert_receive {:dreaming_request, timeline_request}
    assert timeline_request["prompt_cache_key"] == "brain:dreaming:timelines"

    assert [
             %{"role" => "system", "content" => instructions},
             %{"role" => "user", "content" => user_prompt}
           ] = timeline_request["messages"]

    assert instructions =~ "Extract dated events from one memory page passage."
    refute instructions =~ "Timeline Cache"
    assert user_prompt =~ "Page: Timeline Cache"
    assert user_prompt =~ "2026-04-01"
    refute user_prompt =~ "Extract dated events from one memory page passage."
  end

  test "phase_contradictions separates contradiction instructions and sets prompt_cache_key", %{
    human: human
  } do
    {:ok, _object} =
      Objects.create_object(
        %{
          slug: "companies/contradiction-cache",
          type: "company",
          title: "Contradiction Cache",
          body: "Profile body."
        },
        human.uid
      )

    for claim_text <- ["Headquarters are in Berlin.", "Headquarters are in Munich."] do
      {:ok, _res} =
        Claims.write_fact(
          %{
            object_slug: "companies/contradiction-cache",
            claim: claim_text,
            kind: "fact",
            holder: "world",
            audience_scope: "world",
            notability: "medium",
            confidence: 0.75,
            valid_from: DateTime.utc_now(:microsecond),
            provenance: "test"
          },
          human.uid
        )
    end

    assert %{status: :ok, pairs: 1, written: 1} = Dreaming.phase_contradictions()

    assert_receive {:dreaming_request, request}
    assert request["prompt_cache_key"] == "brain:dreaming:contradictions"

    assert [
             %{"role" => "system", "content" => instructions},
             %{"role" => "user", "content" => user_prompt}
           ] = request["messages"]

    assert instructions =~ "Compare two memory claims about one entity from one holder"
    refute instructions =~ "Berlin"
    assert user_prompt =~ "Claim A"
    assert user_prompt =~ "Claim B"
    refute user_prompt =~ "Compare two memory claims about one entity from one holder"
  end
end
