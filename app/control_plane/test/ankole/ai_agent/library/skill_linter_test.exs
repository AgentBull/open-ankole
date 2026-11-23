defmodule Ankole.AIAgent.Library.SkillLinterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Ankole.AIAgent.Library.SkillLinter
  alias Mix.Tasks.Ankole.Skills.Lint, as: LintTask

  @valid_description "Use for validating local reports, reading references, and delivering verified summaries."

  test "lints valid standalone and plugin skills cleanly" do
    root = tmp_library_root!("valid")
    standalone_dir = Path.join([root, "skills", "valid-skill"])
    plugin_dir = Path.join([root, "agent-plugins", "sample", "skills", "plugin-skill"])

    write_file!(Path.join(standalone_dir, "references/guide.md"), "# Guide\n\nDetails.\n")
    write_file!(Path.join(plugin_dir, "references/api.md"), "# API\n\nDetails.\n")

    write_skill!(standalone_dir, """
    ---
    name: valid-skill
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Valid Skill

    Read [the guide](references/guide.md#details) and [docs](https://example.com).
    Skip `#anchor` links, [email](mailto:ops@example.com), and `#section` anchors.
    Code example `[ignored](references/does-not-exist.md)` stays ignored.

    ```markdown
    [also-ignored](../outside.md)
    ```
    """)

    write_skill!(plugin_dir, """
    ---
    name: plugin-skill
    description: "#{@valid_description}"
    ankole-runtime: background_job
    ---

    # Plugin Skill

    See [API reference](references/api.md).
    """)

    # Non-runtime directories next to the library must never be scanned.
    write_file!(Path.join([root, ".agents", "skills", "ignored-bad", "SKILL.md"]), "broken")

    assert {:ok, %{checked_count: 2, files: files}} = SkillLinter.lint(library_root: root)
    assert length(files) == 2
  end

  test "rejects descriptions that are missing, multiline, too short, or over 75 o200k_base tokens" do
    root = tmp_library_root!("descriptions")

    missing_dir = Path.join([root, "skills", "missing-desc"])
    short_dir = Path.join([root, "skills", "short-desc"])
    multiline_dir = Path.join([root, "skills", "multiline-desc"])
    long_dir = Path.join([root, "skills", "long-desc"])

    write_skill!(missing_dir, """
    ---
    name: missing-desc
    ankole-runtime: main
    ---

    # Missing description
    """)

    write_skill!(short_dir, """
    ---
    name: short-desc
    description: "Too short."
    ankole-runtime: main
    ---

    # Short description
    """)

    write_skill!(multiline_dir, """
    ---
    name: multiline-desc
    description: |
      First line description.
      Second line description.
    ankole-runtime: main
    ---

    # Multiline description
    """)

    over_budget =
      Enum.map_join(1..85, " ", fn index -> "workflow#{index}" end)

    write_skill!(long_dir, """
    ---
    name: long-desc
    description: "#{over_budget}"
    ankole-runtime: any
    ---

    # Over budget
    """)

    assert {:error, violations} = SkillLinter.lint(library_root: root)
    by_path = Map.new(violations, &{&1.relative_path, Enum.join(&1.errors, "; ")})

    assert by_path["skills/missing-desc/SKILL.md"] =~ "missing required description"
    assert by_path["skills/short-desc/SKILL.md"] =~ "at least 12 characters"
    assert by_path["skills/multiline-desc/SKILL.md"] =~ "single-line string"
    assert by_path["skills/long-desc/SKILL.md"] =~ "exceeds 75 o200k_base tokens"
  end

  test "rejects missing or invalid ankole-runtime values" do
    root = tmp_library_root!("runtime")
    missing_dir = Path.join([root, "skills", "missing-runtime"])
    invalid_dir = Path.join([root, "skills", "invalid-runtime"])
    bool_dir = Path.join([root, "skills", "bool-runtime"])

    write_skill!(missing_dir, """
    ---
    name: missing-runtime
    description: "#{@valid_description}"
    ---

    # Missing runtime
    """)

    write_skill!(invalid_dir, """
    ---
    name: invalid-runtime
    description: "#{@valid_description}"
    ankole-runtime: worker
    ---

    # Invalid runtime
    """)

    write_skill!(bool_dir, """
    ---
    name: bool-runtime
    description: "#{@valid_description}"
    ankole-runtime: true
    ---

    # Boolean runtime
    """)

    assert {:error, violations} = SkillLinter.lint(library_root: root)
    by_path = Map.new(violations, &{&1.relative_path, Enum.join(&1.errors, "; ")})

    assert by_path["skills/missing-runtime/SKILL.md"] =~ "missing required ankole-runtime"
    assert by_path["skills/invalid-runtime/SKILL.md"] =~ "invalid ankole-runtime"
    assert by_path["skills/bool-runtime/SKILL.md"] =~ "invalid ankole-runtime"
  end

  test "rejects SKILL.md files over 8,192 bytes or 250 lines" do
    root = tmp_library_root!("size")
    heavy_bytes_dir = Path.join([root, "skills", "too-many-bytes"])
    heavy_lines_dir = Path.join([root, "skills", "too-many-lines"])

    write_skill!(heavy_bytes_dir, """
    ---
    name: too-many-bytes
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Heavy Bytes

    #{String.duplicate("a", 8_200)}
    """)

    many_lines = Enum.map_join(1..260, "\n", fn idx -> "Line #{idx}" end)

    write_skill!(heavy_lines_dir, """
    ---
    name: too-many-lines
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Heavy Lines

    #{many_lines}
    """)

    assert {:error, violations} = SkillLinter.lint(library_root: root)
    by_path = Map.new(violations, &{&1.relative_path, Enum.join(&1.errors, "; ")})

    assert by_path["skills/too-many-bytes/SKILL.md"] =~ "exceeds 8192 bytes"
    assert by_path["skills/too-many-lines/SKILL.md"] =~ "exceeds 250 lines"
  end

  test "rejects broken, absolute, and directory-escaping relative markdown links" do
    root = tmp_library_root!("links")
    other_dir = Path.join([root, "skills", "other-skill"])
    broken_dir = Path.join([root, "skills", "broken-links"])

    write_skill!(other_dir, """
    ---
    name: other-skill
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Other
    """)

    write_skill!(broken_dir, """
    ---
    name: broken-links
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Broken Links

    - [missing](references/missing.md)
    - [escaping](../other-skill/SKILL.md)
    - [absolute](/etc/hosts)
    """)

    assert {:error, violations} = SkillLinter.lint(library_root: root)
    broken = Enum.find(violations, &(&1.relative_path == "skills/broken-links/SKILL.md"))
    joined = Enum.join(broken.errors, "\n")

    assert joined =~ "references/missing.md"
    assert joined =~ "../other-skill/SKILL.md"
    assert joined =~ "/etc/hosts"
  end

  test "rejects bidirectional control characters, zero-width characters, and obvious secrets" do
    root = tmp_library_root!("security")
    bidi_dir = Path.join([root, "skills", "bidi-char"])
    zw_dir = Path.join([root, "skills", "zw-char"])
    secret_dir = Path.join([root, "skills", "secret-leak"])

    write_skill!(bidi_dir, """
    ---
    name: bidi-char
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Bidi

    Hidden RLO \u202E text.
    """)

    write_skill!(zw_dir, """
    ---
    name: zw-char
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Zero width

    Hidden ZWSP \u200B and BOM \uFEFF text.
    """)

    write_skill!(secret_dir, """
    ---
    name: secret-leak
    description: "#{@valid_description}"
    ankole-runtime: any
    ---

    # Secrets

    OPENAI=sk-proj-1234567890abcdef123456
    GITHUB=ghp_1234567890abcdef123456
    AWS=AKIAIOSFODNN7EXAMPLE
    """)

    assert {:error, violations} = SkillLinter.lint(library_root: root)
    by_path = Map.new(violations, &{&1.relative_path, Enum.join(&1.errors, "; ")})

    assert by_path["skills/bidi-char/SKILL.md"] =~ "bidirectional control"
    assert by_path["skills/zw-char/SKILL.md"] =~ "zero-width"
    assert by_path["skills/secret-leak/SKILL.md"] =~ "sk- secret key"
    assert by_path["skills/secret-leak/SKILL.md"] =~ "GitHub token"
    assert by_path["skills/secret-leak/SKILL.md"] =~ "AWS access key ID"
  end

  test "mix ankole.skills.lint prints pass count and fails non-zero on violations" do
    root = tmp_library_root!("mix-task")
    skill_dir = Path.join([root, "skills", "demo"])

    write_skill!(skill_dir, """
    ---
    name: demo
    description: "#{@valid_description}"
    ankole-runtime: main
    ---

    # Demo
    """)

    output =
      capture_io(fn ->
        assert :ok = LintTask.run(["--library-root", root])
      end)

    assert output =~ "1 skill(s) passed"

    write_skill!(skill_dir, """
    ---
    name: demo
    description: "#{@valid_description}"
    ---

    # Missing runtime
    """)

    assert_raise Mix.Error, ~r/violations in 1 skill/, fn ->
      capture_io(:stderr, fn ->
        LintTask.run(["--library-root", root])
      end)
    end
  end

  test "real app/library runtime skills pass SkillLinter" do
    library_root = Path.expand("../../../../../library", __DIR__)

    assert {:ok, %{checked_count: 27, files: files}} =
             SkillLinter.lint(library_root: library_root)

    refute Enum.any?(files, &String.contains?(&1, ".agents/skills"))
    assert Enum.any?(files, &String.ends_with?(&1, "/skills/brainstorming/SKILL.md"))
    assert Enum.any?(files, &String.ends_with?(&1, "/agent-plugins/office/skills/docx/SKILL.md"))
  end

  defp tmp_library_root!(label) do
    root =
      Path.join(
        System.tmp_dir!(),
        "ankole-skill-linter-test-#{label}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp write_skill!(dir, content) do
    write_file!(Path.join(dir, "SKILL.md"), content)
  end

  defp write_file!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
