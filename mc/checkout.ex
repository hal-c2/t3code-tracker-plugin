defmodule HalC2Plugins.T3codeTracker.Checkout do
  @moduledoc """
  The ledger as it is on its repository's main branch, read through the checkout
  that is a project on this MC. The checkout's own files are not read: it may be
  behind, on another branch, or mid-edit, and the ledger is what main says.
  """

  @branch "main"
  @ref "refs/remotes/origin/#{@branch}"

  def branch, do: @branch

  @doc "Fetches main from the checkout's origin, with the machine's own git setup."
  def fetch(root) do
    case git(root, ["fetch", "--quiet", "--no-tags", "origin", @branch]) do
      {:ok, _} -> :ok
      error -> error
    end
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
