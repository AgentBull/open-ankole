defmodule Mix.Tasks.Ankole.Skills.Lint do
  @moduledoc """
  Validates every runtime skill under `app/library` using `Ankole.AIAgent.Library.SkillLinter`.

      mix ankole.skills.lint
      mix ankole.skills.lint --library-root /path/to/library
  """

  use Mix.Task

  alias Ankole.AIAgent.Library.SkillLinter

  @shortdoc "Lints runtime skills under app/library"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [library_root: :string])

    if invalid != [] or rest != [] do
      Mix.raise("usage: mix ankole.skills.lint [--library-root PATH]")
    end

    {:ok, _apps} = Application.ensure_all_started(:ankole_kernel)
    {:ok, _apps} = Application.ensure_all_started(:yaml_elixir)

    case SkillLinter.lint(opts) do
      {:ok, %{checked_count: count}} ->
        Mix.shell().info("ankole.skills.lint: #{count} skill(s) passed")

      {:error, violations} ->
        Mix.shell().error("ankole.skills.lint failed:")

        Enum.each(violations, fn %{relative_path: path, errors: errors} ->
          Mix.shell().error("  #{path}:")
          Enum.each(errors, &Mix.shell().error("    - #{&1}"))
        end)

        Mix.raise("ankole.skills.lint found violations in #{length(violations)} skill(s)")
    end
  end
end
