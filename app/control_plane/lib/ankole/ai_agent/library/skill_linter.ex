defmodule Ankole.AIAgent.Library.SkillLinter do
  @moduledoc """
  Static linter for runtime skills under `app/library`.

  Validates progressive-disclosure budgets, runtime surface declarations,
  skill-scoped markdown links, and hidden control characters or secret literals
  across standalone skills (`skills/*/SKILL.md`) and plugin skills
  (`agent-plugins/*/skills/*/SKILL.md`).
  """

  alias Ankole.AIAgent.Library.SourceReader
  alias Ankole.Kernel, as: NativeKernel

  @max_description_tokens 75
  @min_description_chars 12
  @max_skill_bytes 8_192
  @max_skill_lines 250

  @bidi_control_pattern ~r/[\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/u
  @zero_width_pattern ~r/[\x{200B}-\x{200D}\x{FEFF}]/u

  @secret_patterns [
    {"sk- secret key", ~r/\bsk-[A-Za-z0-9_-]{12,}/},
    {"GitHub token", ~r/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{12,}/},
    {"GitHub fine-grained PAT", ~r/\bgithub_pat_[A-Za-z0-9_]{12,}/},
    {"AWS access key ID", ~r/\bAKIA[0-9A-Z]{16}\b/},
    {"Slack token", ~r/\bxox[baprs]-[A-Za-z0-9-]{10,}/},
    {"Google API key", ~r/\bAIza[0-9A-Za-z_-]{20,}/},
    {"Private key PEM block", ~r/-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/}
  ]

  @type violation :: %{
          file: String.t(),
          relative_path: String.t(),
          errors: [String.t()]
        }

  @type lint_report :: %{
          library_root: String.t(),
          checked_count: non_neg_integer(),
          files: [String.t()]
        }

  @doc """
  Lints every runtime `SKILL.md` file under the configured or given `:library_root`.
  """
  @spec lint(keyword()) :: {:ok, lint_report()} | {:error, [violation()]}
  def lint(opts \\ []) when is_list(opts) do
    library_root =
      opts
      |> Keyword.get_lazy(:library_root, &SourceReader.library_root/0)
      |> Path.expand()

    case discover_skill_files(library_root) do
      [] ->
        {:error,
         [
           %{
             file: library_root,
             relative_path: ".",
             errors: ["no runtime SKILL.md files found under #{library_root}"]
           }
         ]}

      files ->
        violations =
          files
          |> Enum.flat_map(fn file ->
            case lint_file(file) do
              :ok ->
                []

              {:error, errors} ->
                [
                  %{
                    file: file,
                    relative_path: Path.relative_to(file, library_root),
                    errors: errors
                  }
                ]
            end
          end)

        case violations do
          [] ->
            {:ok, %{library_root: library_root, checked_count: length(files), files: files}}

          _errors ->
            {:error, violations}
        end
    end
  end

  @doc """
  Discovers runtime `SKILL.md` files under `library_root`.

  Scans only `skills/*/SKILL.md` and `agent-plugins/*/skills/*/SKILL.md`.
  """
  @spec discover_skill_files(String.t()) :: [String.t()]
  def discover_skill_files(library_root) when is_binary(library_root) do
    expanded = Path.expand(library_root)

    [
      Path.join(expanded, "skills/*/SKILL.md"),
      Path.join(expanded, "agent-plugins/*/skills/*/SKILL.md")
    ]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lints one `SKILL.md` file and any markdown references inside its skill directory.
  """
  @spec lint_file(String.t()) :: :ok | {:error, [String.t()]}
  def lint_file(skill_md_path) when is_binary(skill_md_path) do
    expanded_path = Path.expand(skill_md_path)
    skill_dir = Path.dirname(expanded_path)

    case File.read(expanded_path) do
      {:ok, raw} ->
        errors =
          if String.valid?(raw) do
            validate_skill_contents(raw, skill_dir) ++
              validate_reference_markdown_files(skill_dir)
          else
            ["SKILL.md must be valid UTF-8"]
          end

        case errors do
          [] -> :ok
          list -> {:error, list}
        end

      {:error, reason} ->
        {:error, ["unable to read SKILL.md: #{inspect(reason)}"]}
    end
  end

  defp validate_skill_contents(raw, skill_dir) do
    {frontmatter_errors, body} = validate_frontmatter_section(raw)

    size_errors(raw) ++
      frontmatter_errors ++
      character_and_secret_errors(raw, nil) ++
      relative_link_errors(body, skill_dir, skill_dir, nil)
  end

  defp validate_reference_markdown_files(skill_dir) do
    skill_dir
    |> Path.join("references/**/*.md")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.flat_map(fn ref_path ->
      relative_ref = Path.relative_to(ref_path, skill_dir)

      case File.read(ref_path) do
        {:ok, raw} ->
          if String.valid?(raw) do
            character_and_secret_errors(raw, relative_ref) ++
              relative_link_errors(raw, Path.dirname(ref_path), skill_dir, relative_ref)
          else
            ["#{relative_ref}: file must be valid UTF-8"]
          end

        {:error, reason} ->
          ["#{relative_ref}: unable to read file: #{inspect(reason)}"]
      end
    end)
  end

  defp size_errors(raw) do
    bytes = byte_size(raw)
    lines = count_lines(raw)

    []
    |> maybe_add(
      bytes > @max_skill_bytes,
      "SKILL.md exceeds #{@max_skill_bytes} bytes (#{bytes} bytes)"
    )
    |> maybe_add(
      lines > @max_skill_lines,
      "SKILL.md exceeds #{@max_skill_lines} lines (#{lines} lines)"
    )
  end

  defp validate_frontmatter_section(raw) do
    case split_frontmatter(raw) do
      {:ok, frontmatter_yaml, body} ->
        case YamlElixir.read_from_string(frontmatter_yaml) do
          {:ok, %{} = frontmatter} ->
            errors =
              description_errors(frontmatter, frontmatter_yaml) ++
                ankole_runtime_errors(frontmatter)

            {errors, body}

          _invalid ->
            {["invalid YAML frontmatter"], body}
        end

      :missing ->
        {["missing YAML frontmatter"], raw}
    end
  end

  defp split_frontmatter(raw) do
    cond do
      match = Regex.run(~r/\A---\r?\n([\s\S]*?)\r?\n---(?:\r?\n([\s\S]*))?\z/, raw) ->
        case match do
          [_, yaml, body] -> {:ok, yaml, body}
          [_, yaml] -> {:ok, yaml, ""}
        end

      match = Regex.run(~r/\A---\r?\n---(?:\r?\n([\s\S]*))?\z/, raw) ->
        case match do
          [_, body] -> {:ok, "", body}
          [_] -> {:ok, "", ""}
        end

      true ->
        :missing
    end
  end

  defp description_errors(frontmatter, frontmatter_yaml) do
    multiline_yaml? = Regex.match?(~r/^description:\s*(?:[|>][-+]?|\s*$)/m, frontmatter_yaml)

    case Map.get(frontmatter, "description") do
      nil ->
        ["missing required description frontmatter field"]

      value when not is_binary(value) ->
        ["description must be a single-line string"]

      value ->
        if multiline_yaml? or String.contains?(value, ["\n", "\r"]) do
          ["description must be a single-line string"]
        else
          trimmed = String.trim(value)
          char_count = String.length(trimmed)

          []
          |> maybe_add(
            char_count < @min_description_chars,
            "description must be at least #{@min_description_chars} characters (got #{char_count})"
          )
          |> Kernel.++(description_token_errors(trimmed))
        end
    end
  end

  defp description_token_errors(""), do: []

  defp description_token_errors(description) do
    tokens = NativeKernel.estimate_o200k_base_tokens(description)

    if tokens > @max_description_tokens do
      ["description exceeds #{@max_description_tokens} o200k_base tokens (got #{tokens})"]
    else
      []
    end
  end

  defp ankole_runtime_errors(frontmatter) do
    case Map.get(frontmatter, "ankole-runtime") do
      nil ->
        [
          "missing required ankole-runtime frontmatter field (expected: any, main, or background_job)"
        ]

      value ->
        case SourceReader.normalize_ankole_runtime(value) do
          {:ok, runtime} when runtime in ~w(any main background_job) ->
            []

          {:error, _reason} ->
            [
              "invalid ankole-runtime #{inspect(value)} (expected: any, main, or background_job)"
            ]
        end
    end
  end

  defp character_and_secret_errors(text, prefix) do
    bidi_error =
      if Regex.match?(@bidi_control_pattern, text),
        do: [prefix_error(prefix, "contains disallowed bidirectional control characters")],
        else: []

    zw_error =
      if Regex.match?(@zero_width_pattern, text),
        do: [prefix_error(prefix, "contains disallowed zero-width characters")],
        else: []

    secret_errors =
      @secret_patterns
      |> Enum.filter(fn {_label, pattern} -> Regex.match?(pattern, text) end)
      |> Enum.map(fn {label, _pattern} ->
        prefix_error(prefix, "contains potential secret literal (#{label})")
      end)

    bidi_error ++ zw_error ++ secret_errors
  end

  defp relative_link_errors(markdown, link_base_dir, skill_dir, prefix) do
    markdown
    |> extract_markdown_link_targets()
    |> Enum.flat_map(fn target ->
      validate_link_target(target, link_base_dir, skill_dir, prefix)
    end)
  end

  defp extract_markdown_link_targets(markdown) do
    cleaned =
      markdown
      |> strip_fenced_code_blocks()
      |> strip_inline_code_spans()

    inline_targets =
      Regex.scan(~r/!?\[[^\]]*\]\(([^)\r\n]+)\)/, cleaned)
      |> Enum.map(fn [_, raw_target] -> normalize_link_target(raw_target) end)

    reference_targets =
      Regex.scan(~r/^\s{0,3}\[[^\]]+\]:\s*(\S+)/m, cleaned)
      |> Enum.map(fn [_, raw_target] -> normalize_link_target(raw_target) end)

    inline_targets ++ reference_targets
  end

  defp strip_fenced_code_blocks(markdown) do
    {kept_lines, _fence} =
      markdown
      |> String.split(~r/\r?\n/, trim: false)
      |> Enum.reduce({[], nil}, fn line, {acc, active_fence} ->
        case active_fence do
          nil ->
            case Regex.run(~r/\A[ ]{0,3}(`{3,}|~{3,})/, line) do
              [_, fence] -> {acc, {String.first(fence), String.length(fence)}}
              nil -> {[line | acc], nil}
            end

          {fence_char, fence_len} ->
            closing_pattern = ~r/\A[ ]{0,3}#{Regex.escape(fence_char)}{#{fence_len},}[ ]*\z/

            if Regex.match?(closing_pattern, line) do
              {acc, nil}
            else
              {acc, active_fence}
            end
        end
      end)

    kept_lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp strip_inline_code_spans(markdown) do
    Regex.replace(~r/(``+)([^\r\n]*?)\1|`([^`\r\n]+)`/, markdown, "code")
  end

  defp normalize_link_target(raw_target) do
    trimmed = String.trim(raw_target)

    case Regex.run(~r/\A<([^>]*)>(?:\s+.*)?\z/, trimmed) do
      [_, angle_target] -> String.trim(angle_target)
      nil -> trimmed |> String.split(~r/\s+/, parts: 2) |> hd()
    end
  end

  defp validate_link_target("", _link_base_dir, _skill_dir, prefix) do
    [prefix_error(prefix, "contains empty markdown link target")]
  end

  defp validate_link_target(target, link_base_dir, skill_dir, prefix) do
    lower = String.downcase(target)

    cond do
      String.starts_with?(lower, ["http://", "https://", "mailto:", "#"]) ->
        []

      Regex.match?(~r/\A[a-z][a-z0-9+.-]*:/i, target) ->
        [prefix_error(prefix, "unsupported URI scheme in relative markdown link: #{target}")]

      true ->
        validate_relative_file_link(target, link_base_dir, skill_dir, prefix)
    end
  end

  defp validate_relative_file_link(target, link_base_dir, skill_dir, prefix) do
    file_part =
      target
      |> String.split("#", parts: 2)
      |> hd()
      |> String.split("?", parts: 2)
      |> hd()

    segments = String.split(file_part, ["/", "\\"])

    cond do
      file_part == "" ->
        [prefix_error(prefix, "broken relative markdown link: #{target}")]

      String.starts_with?(file_part, ["/", "\\"]) or Regex.match?(~r/\A[A-Za-z]:/, file_part) ->
        [
          prefix_error(
            prefix,
            "relative markdown link must stay inside skill directory: #{target}"
          )
        ]

      ".." in segments ->
        [
          prefix_error(
            prefix,
            "relative markdown link escapes or traverses with '..': #{target}"
          )
        ]

      true ->
        expanded = Path.expand(file_part, link_base_dir)
        verify_resolved_file(target, expanded, skill_dir, prefix)
    end
  end

  defp verify_resolved_file(target, expanded, skill_dir, prefix) do
    cond do
      expanded == skill_dir or not String.starts_with?(expanded, skill_dir <> "/") ->
        [prefix_error(prefix, "relative markdown link escapes skill directory: #{target}")]

      symlink?(expanded) ->
        [prefix_error(prefix, "relative markdown link must not point to a symlink: #{target}")]

      not File.regular?(expanded) ->
        [prefix_error(prefix, "broken relative markdown link (file not found): #{target}")]

      true ->
        []
    end
  end

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} -> true
      _other -> false
    end
  end

  defp count_lines(""), do: 0

  defp count_lines(raw) do
    raw
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
    |> String.split(~r/\r?\n/, trim: false)
    |> length()
  end

  defp prefix_error(nil, message), do: message
  defp prefix_error(prefix, message), do: "#{prefix}: #{message}"

  defp maybe_add(errors, true, message), do: errors ++ [message]
  defp maybe_add(errors, false, _message), do: errors
end
