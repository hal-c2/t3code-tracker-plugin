defmodule HalC2Plugins.T3codeTracker.Checkout do
  @moduledoc """
  The ledger as it is on its repository's main branch, read through the checkout
  that is a project on this MC, and what the branches pushed to it change there. The
  checkout's own files are not read: it may be behind, on another branch, or
  mid-edit, and the ledger is what main says.

  The branches are fetched into a namespace of the tracker's own,
  `refs/t3code-tracker/heads/`, pruned as origin deletes them, so the checkout's
  own branches and remote-tracking refs are left as they are.
  """

  @branch "main"
  @ref "refs/remotes/origin/#{@branch}"
  @heads "refs/t3code-tracker/heads"

  def branch, do: @branch

  @doc """
  Fetches main and every other branch from the checkout's origin, with the
  machine's own git setup.
  """
  def fetch(root) do
    case git(root, [
           "fetch",
           "--quiet",
           "--no-tags",
           "--prune",
           "origin",
           "+refs/heads/#{@branch}:#{@ref}",
           "+refs/heads/*:#{@heads}/*"
         ]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  The branches origin had at the last fetch, other than main, each
  `%{"branch", "sha", "at"}` with when its last commit was made, in milliseconds.
  """
  def branches(root) do
    format = "%(refname:lstrip=3)%09%(objectname)%09%(committerdate:unix)"

    with {:ok, out} <- git(root, ["for-each-ref", "--format=#{format}", @heads], false) do
      branches =
        for line <- String.split(out, "\n", trim: true),
            [name, sha, at] <- [String.split(line, "\t")],
            name != @branch,
            do: %{"branch" => name, "sha" => sha, "at" => String.to_integer(at) * 1000}

      {:ok, branches}
    end
  end

  @doc """
  What `branch` changes in the feature files since it left main, with each changed
  file whole as context, for `Ledger.work_files/2`. Nothing once main has it all.
  """
  def diff(root, branch) do
    git(
      root,
      [
        "diff",
        "--no-color",
        "--no-ext-diff",
        "--no-renames",
        "--src-prefix=a/",
        "--dst-prefix=b/",
        "--unified=1000000",
        "#{@ref}...#{@heads}/#{branch}",
        "--",
        "features/*.feature"
      ],
      false
    )
  end

  @doc """
  The files under `dir` on main as last fetched, `%{path => text}`, with the
  commit they were read at.
  """
  def files(root, dir) do
    with {:ok, sha} <- head(root),
         {:ok, tar} <- git(root, ["archive", "--format=tar", sha, "--", dir], false) do
      case :erl_tar.extract({:binary, tar}, [:memory]) do
        {:ok, entries} ->
          {:ok, sha, Map.new(entries, fn {path, text} -> {to_string(path), text} end)}

        {:error, reason} ->
          {:error, "The ledger could not be read: #{inspect(reason)}"}
      end
    end
  end

  defp head(root) do
    case git(root, ["rev-parse", "--verify", "--quiet", @ref <> "^{commit}"]) do
      {:ok, sha} -> {:ok, String.trim(sha)}
      _ -> {:error, "The ledger's checkout has not fetched origin/#{@branch} yet."}
    end
  end

  defp git(cwd, args, merge_stderr \\ true) do
    case System.cmd("git", args,
           cd: cwd,
           env: [{"GIT_TERMINAL_PROMPT", "0"}],
           stderr_to_stdout: merge_stderr
         ) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, "git #{hd(args)} failed: #{String.trim(out)}"}
    end
  end
end
