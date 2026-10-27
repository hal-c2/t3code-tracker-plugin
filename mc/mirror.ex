defmodule HalC2Plugins.T3codeTracker.Mirror do
  @moduledoc """
  A bare clone, a mirror, of the upstream repository's main branch in the plugin's data
  directory. It holds commits only (`--filter=tree:0`): who wrote a pull request
  and who co-wrote it is all in its squash commit.

  Upstream merges everything into main, its V2 work included, so main is the one
  branch the tracker follows.
  """

  @branch "main"
  # Commit, date, author, subject and co-authors, split by unit separators so a
  # subject may hold anything.
  @format "%H%x1f%aI%x1f%an%x1f%ae%x1f%s%x1f%(trailers:key=Co-authored-by,valueonly,separator=%x1d)%x1e"

  def branch, do: @branch

  @doc "Clones `repository` into `dir`, or fetches its main branch when it is already there."
  def sync(dir, repository) do
    if File.dir?(Path.join(dir, "objects")) do
      git(dir, [
        "fetch",
        "--quiet",
        "--no-tags",
        "--filter=tree:0",
        "origin",
        "+#{@branch}:refs/heads/#{@branch}"
      ])
    else
      File.mkdir_p!(Path.dirname(dir))

      git(Path.dirname(dir), [
        "clone",
        "--quiet",
        "--bare",
        "--filter=tree:0",
        "--single-branch",
        "--no-tags",
        "--branch",
        @branch,
        "https://github.com/#{repository}.git",
        dir
      ])
    end
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "The first-parent commits of main, newest first, for `Ledger.commits/1`."
  def log(dir) do
    if File.dir?(Path.join(dir, "objects")),
      do: git(dir, ["log", "--first-parent", "--format=#{@format}", @branch], false),
      else: {:error, "There is no copy of upstream yet."}
  end

  @doc "How many commits main has after `cursor`, or nil when the copy does not have it."
  def pending(dir, cursor) do
    case git(dir, ["rev-list", "--first-parent", "--count", "#{cursor}..#{@branch}"]) do
      {:ok, count} -> String.to_integer(String.trim(count))
      _ -> nil
    end
  end

  # git without the machine's config or a prompt for credentials: upstream is public.
  # What it writes to stderr is kept out of output that is parsed.
  defp git(cwd, args, merge_stderr \\ true) do
    env = [
      {"GIT_TERMINAL_PROMPT", "0"},
      {"GIT_CONFIG_GLOBAL", "/dev/null"},
      {"GIT_CONFIG_NOSYSTEM", "1"}
    ]

    case System.cmd("git", args, cd: cwd, env: env, stderr_to_stdout: merge_stderr) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, "git #{hd(args)} failed: #{String.trim(out)}"}
    end
  end
end
