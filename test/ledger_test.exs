# Run from the plugin's folder:
#   elixir -r mc/ledger.ex -r mc/mirror.ex -r mc/checkout.ex test/ledger_test.exs
ExUnit.start()

defmodule HalC2Plugins.T3codeTracker.LedgerTest do
  use ExUnit.Case, async: true

  alias HalC2Plugins.T3codeTracker.{Checkout, Ledger, Mirror}

  @upstream "pingdotgg/t3code"

  @feature """
  # Sources:
  #   https://github.com/pingdotgg/t3code/pull/2829
  #   https://github.com/pingdotgg/t3code/pull/9514 (the sign-in link on stderr)
  #   https://github.com/pingdotgg/t3code/commit/0123456789ab (a direct commit)
  #   https://github.com/someone/else/pull/1
  #   apps/server/src/provider/AntigravityAuth.ts
  @mc @tui
  Feature: Antigravity

    Background:
      Given an MC

    Scenario: It signs in
      Then it is signed in

    @backlog-tui
    Scenario: The terminal client shows the sign-in link
      Then the link shows

    @dropped
    # Dropped: HAL-C2 has no web client.
    Scenario: The web shows the link
      Then nothing

    @backlog
    Rule: Installs
      # https://github.com/pingdotgg/t3code/pull/7777 is not a source here
      Scenario: It installs
        Then it is installed

      @blocked
      Scenario Outline: It updates to <version>
        Then it runs <version>

        @extra
        Examples:
          | version |
          | 1.2     |
  """

  test "a feature file's leading comment cites upstream for the whole file" do
    assert Ledger.feature(@feature, @upstream).citations == [
             %{"kind" => "pull", "ref" => "2829", "note" => "", "scope" => "file"},
             %{
               "kind" => "pull",
               "ref" => "9514",
               "note" => "the sign-in link on stderr",
               "scope" => "file"
             },
             %{
               "kind" => "commit",
               "ref" => "0123456789ab",
               "note" => "a direct commit",
               "scope" => "file"
             }
           ]
  end

  test "scenarios count by their status, with the tags of their feature and rule" do
    assert Ledger.feature(@feature, @upstream).scenarios ==
             %{"finished" => 1, "working" => 2, "dropped" => 1, "blocked" => 1}
  end

  # How a ledger file cites upstream for some of its scenarios: a `# Upstream`
  # comment line goes with the keyword after it, as a tag line would.
  @scoped """
  # Sources:
  #   https://github.com/pingdotgg/t3code/pull/1
  #   https://github.com/pingdotgg/t3code/pull/2 (the header's note)
  #   docs/user/models.md
  # Upstream #3: the whole feature.
  @desktop
  Feature: Models

    # Upstream #2: one scenario, which the header also names.
    @backlog
    Scenario: A model is listed
      Then it is listed

    # Upstream offers more models, which is prose and cites nothing.
    Scenario: A model is picked
      Then it is picked

    # Upstream #4. A rule.
    Rule: Speed

      @backlog
      # Upstream 2 tables differ here, which is prose and cites nothing.
      Scenario: Fast mode shows
        Then it shows

      Scenario Outline: <speed> is priced
        Then it costs <price>

        Examples:
          | speed | price |
          | slow  | 1     |

        # Upstream 0a1b2c3d4e5f60718293a4b5c6d7e8f901234567: a commit for one table.
        @backlog
        Examples:
          | speed | price |
          | fast  | 2     |
  """

  test "a `# Upstream` comment cites for what follows it, a header URL for the whole file" do
    feature = Ledger.feature(@scoped, @upstream)

    assert Enum.map(feature.citations, &{&1["kind"], &1["ref"], &1["scope"], &1["note"]}) == [
             {"pull", "1", "file", ""},
             {"pull", "3", "scoped", "the whole feature."},
             {"pull", "2", "scoped", "the header's note"},
             {"pull", "4", "scoped", "A rule."},
             {"commit", "0a1b2c3d4e5f60718293a4b5c6d7e8f901234567", "scoped", "a commit for one table."}
           ]

    # The outline passes while one of its tables does not: each table counts.
    assert feature.scenarios == %{"finished" => 2, "working" => 3, "blocked" => 0, "dropped" => 0}

    entries = Ledger.entries([{"f", feature}], [], @upstream)

    covered = fn key ->
      entry = Enum.find(entries, &(&1["key"] == key))
      {entry["exact"], entry["scenarios"]["working"], entry["scenarios"]["finished"]}
    end

    assert covered.("#1") == {false, 3, 2}
    assert covered.("#3") == {true, 3, 2}
    assert covered.("#2") == {true, 1, 0}
    assert covered.("#4") == {true, 2, 1}
    assert covered.("0a1b2c3d4e") == {true, 1, 0}
  end

  # model-and-mode.feature as the ledger had it, cut down: three pull requests in the
  # header, two of them also above the scenario each one covers.
  @model_and_mode """
  # Sources:
  #   https://github.com/pingdotgg/t3code/pull/16069
  #   https://github.com/pingdotgg/t3code/pull/13590
  #   https://github.com/pingdotgg/t3code/pull/13555
  @shared
  Feature: Model and mode

    Scenario: The model picker lists the provider's models
      Then they are listed

    # Upstream #13590: a thread whose worktree is still being checked out is in worktree mode.
    @desktop @backlog
    Scenario: A thread still preparing its worktree says "New worktree"
      Then it says "New worktree"

    # Upstream #13555: the collapsed bar's labels must not flip while the user scrolls.
    @desktop @backlog
    Scenario: The collapsed composer bar keeps its labels steady while scrolling
      Then the labels stay

    @backlog
    Scenario: The traits trigger names reasoning and speed in text
      Then it names them
  """

  test "a pull request cited above its scenario counts those, not the whole file" do
    feature = Ledger.feature(@model_and_mode, @upstream)

    entries =
      Ledger.entries([{"features/composer/model-and-mode.feature", feature}], [], @upstream)

    assert Enum.map(entries, &{&1["key"], &1["exact"], &1["scenarios"]["working"]}) == [
             {"#16069", false, 3},
             {"#13590", true, 1},
             {"#13555", true, 1}
           ]
  end

  test "a backlog outline counts once, a passing one by each table that is backlog" do
    count = fn outline_tags, table_tags ->
      Ledger.feature(
        """
        @mc
        Feature: F
          #{outline_tags}
          Scenario Outline: S <n>
            Then <n>

            #{table_tags}
            Examples:
              | n |
              | 1 |

            Examples:
              | n |
              | 2 |
        """,
        @upstream
      ).scenarios
      |> Map.take(~w(working finished))
    end

    assert count.("", "") == %{"working" => 0, "finished" => 1}
    assert count.("", "@backlog") == %{"working" => 1, "finished" => 1}
    assert count.("@backlog", "") == %{"working" => 1, "finished" => 0}
    assert count.("@backlog", "@backlog") == %{"working" => 1, "finished" => 0}
  end

  test "a surface's backlog tag counts only for a scenario on that surface" do
    feature = fn tags ->
      Ledger.feature("Feature: F\n  #{tags}\n  Scenario: S\n    Then it\n", @upstream)
    end

    assert feature.("@desktop @backlog-mobile").scenarios["working"] == 0
    assert feature.("@desktop @mobile @backlog-mobile").scenarios["working"] == 1
    assert feature.("@shared @backlog-mobile").scenarios["working"] == 1
    assert feature.("@shared @backlog-mc").scenarios["working"] == 0
    assert feature.("@mc @shared @backlog-mc").scenarios["working"] == 1

    assert feature.("@mc @shared @backlog").surfaces ==
             %{"mc" => 1, "desktop" => 1, "mobile" => 1, "tui" => 1}

    high = feature.("@shared @backlog-tui @priority-high")
    assert high.surfaces == %{"mc" => 0, "desktop" => 0, "mobile" => 0, "tui" => 1}
    assert high.priority == %{"high" => 1, "low" => 0}
  end

  test "a doc string is part of its step, whatever it holds" do
    feature =
      Ledger.feature(
        ~S'''
        @mc
        Feature: F
          Scenario: S
            Given a file
              """
              @backlog
              Scenario: Not a scenario
              # Upstream #9
              """
            Then it reads
        ''',
        @upstream
      )

    assert feature.scenarios["finished"] == 1
    assert feature.scenarios["working"] == 0
    assert feature.citations == []
  end

  test "the backlog lists every file with work left, the most high priority first" do
    feature = fn tags ->
      Ledger.feature(
        "@mc\nFeature: F\n" <>
          Enum.map_join(tags, fn tags -> "  #{tags}\n  Scenario: S\n    Then it\n" end),
        @upstream
      )
    end

    backlog =
      Ledger.backlog([
        {"features/done.feature", feature.([""])},
        {"features/big.feature", feature.(["@backlog", "@backlog", "@backlog"])},
        {"features/small.feature", feature.(["@backlog"])},
        {"features/urgent.feature", feature.(["@backlog @priority-high", "@backlog"])},
        {"features/later.feature", feature.(["@backlog @priority-low", "@backlog"])},
        {"features/waiting.feature", feature.(["@backlog @blocked"])}
      ])

    assert Enum.map(backlog, & &1["path"]) == [
             "features/urgent.feature",
             "features/big.feature",
             "features/small.feature",
             "features/later.feature",
             "features/waiting.feature"
           ]

    assert hd(backlog)["priority"] == %{"high" => 1, "low" => 0}
    assert hd(backlog)["surfaces"]["mc"] == 2
  end

  # What a branch does to a file, as `git diff --unified=<the whole file>` prints it.
  defp whole_diff(path, before, later) do
    old = String.split(before, "\n")
    new = String.split(later, "\n")
    same = old |> Enum.zip(new) |> Enum.take_while(fn {a, b} -> a == b end) |> length()

    tail =
      old
      |> Enum.reverse()
      |> Enum.zip(Enum.reverse(new))
      |> Enum.take_while(fn {a, b} -> a == b end)
      |> length()
      |> min(min(length(old), length(new)) - same)

    middle = fn lines -> Enum.slice(lines, same, length(lines) - same - tail) end

    Enum.join(
      ["diff --git a/#{path} b/#{path}", "--- a/#{path}", "+++ b/#{path}", "@@ -1 +1 @@"] ++
        Enum.map(Enum.take(old, same), &(" " <> &1)) ++
        Enum.map(middle.(old), &("-" <> &1)) ++
        Enum.map(middle.(new), &("+" <> &1)) ++
        Enum.map(Enum.take(old, -tail), &(" " <> &1)),
      "\n"
    )
  end

  test "a branch that edits backlog scenarios shows on the pull requests cited for them" do
    path = "features/models.feature"

    finished =
      String.replace(
        @scoped,
        "@backlog\n  Scenario: A model is listed",
        "Scenario: A model is listed"
      )

    assert finished != @scoped
    edited = String.replace(@scoped, "Then it shows", "Then it shows the speed")

    work = fn later, label ->
      %{
        "branch" => label,
        "files" => Ledger.work_files(whole_diff(path, @scoped, later), @upstream)
      }
    end

    listed = work.(finished, "list-models")
    speed = work.(edited, "fast-mode")

    assert [%{"path" => ^path, "scenarios" => 1, "finishes" => 1}] = listed["files"]
    assert [%{"path" => ^path, "scenarios" => 1, "finishes" => 0}] = speed["files"]

    entries =
      Ledger.entries([{path, Ledger.feature(@scoped, @upstream)}], [], @upstream, [listed, speed])

    on = fn key -> Enum.find(entries, &(&1["key"] == key))["work"] end

    # A file-wide citation shows every branch that changes the file.
    assert on.("#1") == ["fast-mode", "list-models"]
    assert on.("#2") == ["list-models"]
    assert on.("#4") == ["fast-mode"]
    assert on.("0a1b2c3d4e") == []

    assert Ledger.public([listed]) == [
             %{
               "branch" => "list-models",
               "files" => [%{"path" => path, "scenarios" => 1, "finishes" => 1}]
             }
           ]
  end

  test "a branch that adds a file or edits passing scenarios carries no backlog work" do
    path = "features/new.feature"
    text = "@mc\nFeature: F\n  @backlog\n  Scenario: S\n    Then it\n"

    added =
      Enum.join(
        [
          "diff --git a/#{path} b/#{path}",
          "new file mode 100644",
          "--- /dev/null",
          "+++ b/#{path}",
          "@@ -0,0 +1 @@"
        ] ++ Enum.map(String.split(text, "\n"), &("+" <> &1)),
        "\n"
      )

    assert [%{"path" => ^path, "scenarios" => 0}] = Ledger.work_files(added, @upstream)

    passing = String.replace(@scoped, "Then it is picked", "Then it is chosen")

    assert [%{"scenarios" => 0}] =
             Ledger.work_files(whole_diff("features/f.feature", @scoped, passing), @upstream)
  end

  @log Enum.join(
         [
           Enum.join(
             [
               "de34391427aa",
               "2026-10-02T12:22:22-07:00",
               "Julius Marminge",
               "julius0216@outlook.com",
               "feat(orchestrator): introduce new orchestrator (#2829)",
               Enum.join(
                 [
                   "maria-rcks <maria@kuuro.net>",
                   "Bilal Bakr <62337003+Bil0000@users.noreply.github.com>",
                   "Julius Marminge <Julius0216@outlook.com>",
                   "maria-rcks <maria@kuuro.net>",
                   "Claude Opus 5 (1M context) <noreply@anthropic.com>",
                   "codex <codex@users.noreply.github.com>",
                   "Copilot <175728472+Copilot@users.noreply.github.com>",
                   "GPT-6.1 Sol <noreply@openai.com>",
                   "PR Batch Tester <agent@local.test>",
                   "github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"
                 ],
                 "\x1d"
               )
             ],
             "\x1f"
           ),
           Enum.join(
             [
               "eb334ca574aa",
               "2026-09-03T16:39:17-07:00",
               "Theo Browne",
               "me@t3.gg",
               "fix(antigravity): handle native sign-in URLs on stderr (#9514)",
               ""
             ],
             "\x1f"
           ),
           Enum.join(
             [
               "0123456789ab",
               "2026-09-01T00:00:00Z",
               "Theo Browne",
               "me@t3.gg",
               "chore: a direct commit",
               ""
             ],
             "\x1f"
           )
         ],
         "\x1e\n"
       ) <> "\x1e\n"

  test "a commit names its author and each co-author once, agents and bots marked" do
    [orchestrator | _] = Ledger.commits(@log)

    assert orchestrator["author"] == %{
             "name" => "Julius Marminge",
             "email" => "julius0216@outlook.com",
             "login" => nil,
             "bot" => false
           }

    assert Enum.map(orchestrator["coAuthors"], &{&1["name"], &1["login"], &1["bot"]}) == [
             {"maria-rcks", nil, false},
             {"Bilal Bakr", "Bil0000", false},
             {"Claude Opus 5 (1M context)", nil, true},
             {"codex", "codex", true},
             {"Copilot", "Copilot", true},
             {"GPT-6.1 Sol", nil, true},
             {"PR Batch Tester", nil, true},
             {"github-actions[bot]", "github-actions[bot]", true}
           ]
  end

  test "each cited pull request carries its scenarios, status and authors" do
    other = """
    # Sources:
    #   https://github.com/pingdotgg/t3code/pull/9514
    #   https://github.com/pingdotgg/t3code/pull/1 (not on main)
    Feature: Elsewhere
      Scenario: It works
        Then it works
    """

    features = [
      {"features/a.feature", Ledger.feature(@feature, @upstream)},
      {"features/b.feature", Ledger.feature(other, @upstream)}
    ]

    entries = Ledger.entries(features, Ledger.commits(@log), @upstream)

    assert Enum.map(entries, &{&1["key"], &1["status"], &1["onBranch"]}) == [
             {"#2829", "working", true},
             {"#9514", "working", true},
             {"0123456789", "working", true},
             {"#1", "finished", false}
           ]

    sign_in = Enum.find(entries, &(&1["key"] == "#9514"))
    assert sign_in["title"] == "fix(antigravity): handle native sign-in URLs on stderr"
    assert sign_in["author"]["name"] == "Theo Browne"
    assert sign_in["url"] == "https://github.com/pingdotgg/t3code/pull/9514"

    assert sign_in["scenarios"] == %{
             "finished" => 2,
             "working" => 2,
             "dropped" => 1,
             "blocked" => 1
           }

    assert Enum.map(sign_in["files"], &{&1["path"], &1["note"]}) == [
             {"features/a.feature", "the sign-in link on stderr"},
             {"features/b.feature", ""}
           ]
  end

  test "a pull request is finished once its scenarios pass, and dropped when all are dropped" do
    feature = fn tags ->
      Ledger.feature(
        "# https://github.com/pingdotgg/t3code/pull/5\nFeature: F\n  #{tags}\n  Scenario: S\n",
        @upstream
      )
    end

    status = fn tags -> hd(Ledger.entries([{"f", feature.(tags)}], [], @upstream))["status"] end

    assert status.("") == "finished"
    assert status.("@dropped") == "dropped"
    assert status.("@blocked @backlog") == "blocked"
    assert status.("@mobile @backlog-mobile") == "working"
    assert status.("@desktop @backlog-mobile") == "finished"
  end

  test "credits name the people across the cited pull requests, most first, without agents or bots" do
    entries =
      Ledger.entries(
        [{"f", Ledger.feature(@feature, @upstream)}],
        Ledger.commits(@log),
        @upstream
      )

    assert Enum.map(Ledger.credits(entries), &{&1["name"], &1["entries"]}) == [
             {"Theo Browne", ["#9514", "0123456789"]},
             {"Bilal Bakr", ["#2829"]},
             {"Julius Marminge", ["#2829"]},
             {"maria-rcks", ["#2829"]}
           ]
  end

  test "the cursor is the commit features/UPSTREAM names" do
    assert Ledger.cursor(
             "# The last upstream commit read\nf5ef0ddb90a8c36584e181b1913e7b8a5df30ffc\n"
           ) ==
             "f5ef0ddb90a8c36584e181b1913e7b8a5df30ffc"

    assert Ledger.cursor("# nothing yet\n") == nil
  end

  @tag :git
  test "the upstream copy logs main's first-parent commits with their co-authors" do
    root = Path.join(System.tmp_dir!(), "t3code-tracker-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    work = Path.join(root, "work")
    File.mkdir_p!(work)

    env = [
      {"GIT_CONFIG_GLOBAL", "/dev/null"},
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_AUTHOR_NAME", "Ada"},
      {"GIT_AUTHOR_EMAIL", "ada@example.com"},
      {"GIT_COMMITTER_NAME", "Ada"},
      {"GIT_COMMITTER_EMAIL", "ada@example.com"}
    ]

    git = fn args ->
      {_, 0} = System.cmd("git", args, cd: work, env: env, stderr_to_stdout: true)
    end

    git.(["init", "--quiet", "--initial-branch", "main"])

    git.([
      "commit",
      "--quiet",
      "--allow-empty",
      "-m",
      "feat: a | thing (#12)\n\nBody.\n\nCo-authored-by: Grace <grace@example.com>\nCo-authored-by: Linus <linus@example.com>"
    ])

    git.(["clone", "--quiet", "--bare", work, Path.join(root, "copy.git")])

    assert {:ok, log} = Mirror.log(Path.join(root, "copy.git"))
    assert [commit] = Ledger.commits(log)
    assert commit["subject"] == "feat: a | thing (#12)"
    assert commit["author"]["name"] == "Ada"
    assert Enum.map(commit["coAuthors"], & &1["name"]) == ["Grace", "Linus"]
    assert Mirror.pending(Path.join(root, "copy.git"), commit["sha"]) == 0
  end

  @tag :git
  test "the ledger is what main has on origin, not what the checkout has on disk" do
    root = Path.join(System.tmp_dir!(), "t3code-tracker-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    origin = Path.join(root, "origin")
    checkout = Path.join(root, "checkout")
    File.mkdir_p!(origin)

    env = [
      {"GIT_CONFIG_GLOBAL", "/dev/null"},
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_AUTHOR_NAME", "Ada"},
      {"GIT_AUTHOR_EMAIL", "ada@example.com"},
      {"GIT_COMMITTER_NAME", "Ada"},
      {"GIT_COMMITTER_EMAIL", "ada@example.com"}
    ]

    git = fn cwd, args ->
      {_, 0} = System.cmd("git", args, cd: cwd, env: env, stderr_to_stdout: true)
    end

    commit = fn path, text ->
      File.mkdir_p!(Path.dirname(Path.join(origin, path)))
      File.write!(Path.join(origin, path), text)
      git.(origin, ["add", path])
      git.(origin, ["commit", "--quiet", "-m", "add #{path}"])
    end

    git.(origin, ["init", "--quiet", "--initial-branch", "main"])
    commit.("features/a.feature", "a on main\n")
    git.(root, ["clone", "--quiet", origin, checkout])

    # Main moves on, while the checkout sits on a branch of its own with an edit.
    commit.("features/b.feature", "b on main\n")
    git.(checkout, ["switch", "--quiet", "-c", "other"])
    File.write!(Path.join(checkout, "features/a.feature"), "a edited\n")

    assert :ok = Checkout.fetch(checkout)
    assert {:ok, sha, files} = Checkout.files(checkout, "features")

    assert files == %{
             "features/a.feature" => "a on main\n",
             "features/b.feature" => "b on main\n"
           }

    assert {head, 0} = System.cmd("git", ["rev-parse", "main"], cd: origin)
    assert sha == String.trim(head)
  end

  @tag :git
  test "the branches pushed to origin are read for what they change in the ledger" do
    root = Path.join(System.tmp_dir!(), "t3code-tracker-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    origin = Path.join(root, "origin")
    checkout = Path.join(root, "checkout")
    File.mkdir_p!(Path.join(origin, "features/deep"))

    env = [
      {"GIT_CONFIG_GLOBAL", "/dev/null"},
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_AUTHOR_NAME", "Ada"},
      {"GIT_AUTHOR_EMAIL", "ada@example.com"},
      {"GIT_COMMITTER_NAME", "Ada"},
      {"GIT_COMMITTER_EMAIL", "ada@example.com"}
    ]

    git = fn cwd, args ->
      {_, 0} = System.cmd("git", args, cd: cwd, env: env, stderr_to_stdout: true)
    end

    path = "features/deep/a.feature"
    backlog = "@mc\nFeature: F\n  @backlog\n  Scenario: S\n    Then it\n"
    File.write!(Path.join(origin, path), backlog)
    File.write!(Path.join(origin, "README.md"), "read me\n")
    git.(origin, ["init", "--quiet", "--initial-branch", "main"])
    git.(origin, ["add", "."])
    git.(origin, ["commit", "--quiet", "-m", "main"])
    git.(root, ["clone", "--quiet", origin, checkout])

    # One branch makes the scenario pass, another only touches the README.
    git.(origin, ["switch", "--quiet", "-c", "finish-it"])
    File.write!(Path.join(origin, path), String.replace(backlog, "@backlog\n  ", ""))
    git.(origin, ["commit", "--quiet", "-am", "finish"])
    git.(origin, ["switch", "--quiet", "-c", "docs", "main"])
    File.write!(Path.join(origin, "README.md"), "read me again\n")
    git.(origin, ["commit", "--quiet", "-am", "docs"])

    assert :ok = Checkout.fetch(checkout)
    assert {:ok, branches} = Checkout.branches(checkout)
    assert branches |> Enum.map(& &1["branch"]) |> Enum.sort() == ["docs", "finish-it"]
    assert Enum.all?(branches, &(is_integer(&1["at"]) and &1["at"] > 0))

    assert {:ok, diff} = Checkout.diff(checkout, "finish-it")

    assert [%{"path" => ^path, "scenarios" => 1, "finishes" => 1}] =
             Ledger.work_files(diff, "pingdotgg/t3code")

    assert {:ok, ""} = Checkout.diff(checkout, "docs")

    # A branch deleted on origin goes at the next fetch; the checkout's refs stay.
    git.(origin, ["switch", "--quiet", "main"])
    git.(origin, ["branch", "--quiet", "-D", "docs"])
    assert :ok = Checkout.fetch(checkout)
    assert {:ok, [%{"branch" => "finish-it"}]} = Checkout.branches(checkout)

    assert {_, 0} =
             System.cmd("git", ["rev-parse", "--verify", "--quiet", "origin/main"], cd: checkout)
  end
end
