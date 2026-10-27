# Run from the plugin's folder:
#   elixir -r mc/ledger.ex -r mc/mirror.ex test/ledger_test.exs
ExUnit.start()

defmodule HalC2Plugins.T3codeTracker.LedgerTest do
  use ExUnit.Case, async: true

  alias HalC2Plugins.T3codeTracker.{Ledger, Mirror}

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

  test "a feature file cites the upstream pull requests and commits of its leading comment" do
    assert Ledger.feature(@feature, @upstream).citations == [
             %{"kind" => "pull", "ref" => "2829", "note" => ""},
             %{"kind" => "pull", "ref" => "9514", "note" => "the sign-in link on stderr"},
             %{"kind" => "commit", "ref" => "0123456789ab", "note" => "a direct commit"}
           ]
  end

  test "scenarios count by their status, with the tags of their feature and rule" do
    assert Ledger.feature(@feature, @upstream).scenarios ==
             %{"finished" => 1, "working" => 2, "dropped" => 1, "blocked" => 1}
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
    assert status.("@backlog-mobile") == "working"
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
end
