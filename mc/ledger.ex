defmodule HalC2Plugins.T3codeTracker.Ledger do
  @moduledoc """
  What the tracker reads, apart from the MC: which upstream pull requests and
  commits the feature files of a HAL-C2 ledger cite in their `# Sources:`, how far
  the scenarios of those files have got, and who wrote each one upstream.

  A file cites for all of its scenarios, so every scenario of a file counts for
  each pull request it cites. A scenario is `finished` when it carries no status
  tag (it passes on all its surfaces), `working` when it is `@backlog` or
  `@backlog-<surface>`, `blocked` when it is `@blocked`, and `dropped` when it is
  `@dropped`.
  """

  @statuses ~w(working blocked finished dropped)
  # Co-authors that are agents and bots rather than people. GitHub's own bots end
  # in `[bot]`; these are the agents that sign commits with an address of their own,
  # and an address on a domain reserved for tests (RFC 2606) is nobody's.
  @agents ~w(noreply@anthropic.com cursoragent@cursor.com)
  @reserved ~w(.test .example .invalid .localhost)

  @doc "The status counts of nothing, the start of every sum."
  def none, do: Map.new(@statuses, &{&1, 0})

  @doc """
  One feature file: the upstream pull requests and commits its leading comment
  cites, each `%{"kind", "ref", "note"}`, and its scenarios counted by status.
  """
  def feature(text, upstream) do
    lines = String.split(text, ~r/\r?\n/)

    header =
      Enum.take_while(
        lines,
        &(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "#"))
      )

    citations =
      header |> Enum.flat_map(&cite(&1, upstream)) |> Enum.uniq_by(&{&1["kind"], &1["ref"]})

    %{
      citations: citations,
      scenarios: Map.merge(none(), lines |> statuses() |> Enum.frequencies())
    }
  end

  defp cite(line, upstream) do
    pattern =
      ~r"https://github\.com/#{Regex.escape(upstream)}/(pull|commit)/([0-9]+|[0-9a-f]{7,40})\b(?:\s*\(([^)]*)\))?"i

    for [_, kind, ref | note] <- Regex.scan(pattern, line) do
      %{
        "kind" => if(kind == "pull", do: "pull", else: "commit"),
        "ref" => String.downcase(ref),
        "note" => List.first(note, "")
      }
    end
  end

  # The status of each scenario, with the tags of its feature and rule.
  defp statuses(lines) do
    {statuses, _} =
      Enum.reduce(lines, {[], %{feature: [], rule: [], pending: []}}, fn line, {acc, tags} ->
        line = String.trim(line)

        cond do
          String.starts_with?(line, "@") ->
            {acc, %{tags | pending: tags.pending ++ tags_of(line)}}

          String.starts_with?(line, "Feature:") ->
            {acc, %{tags | feature: tags.pending, pending: []}}

          String.starts_with?(line, "Rule:") ->
            {acc, %{tags | rule: tags.pending, pending: []}}

          Enum.any?(
            ~w(Scenario: Example: Scenario\ Outline: Scenario\ Template:),
            &String.starts_with?(line, &1)
          ) ->
            {[status(tags.feature ++ tags.rule ++ tags.pending) | acc], %{tags | pending: []}}

          # Tags on Examples, or before a Background, belong to no scenario counted here.
          String.starts_with?(line, "Examples:") or String.starts_with?(line, "Background:") ->
            {acc, %{tags | pending: []}}

          true ->
            {acc, tags}
        end
      end)

    statuses
  end

  defp tags_of(line) do
    line
    |> String.split("#", parts: 2)
    |> hd()
    |> String.split()
    |> Enum.filter(&String.starts_with?(&1, "@"))
  end

  defp status(tags) do
    cond do
      "@dropped" in tags -> "dropped"
      "@blocked" in tags -> "blocked"
      Enum.any?(tags, &(&1 == "@backlog" or String.starts_with?(&1, "@backlog-"))) -> "working"
      true -> "finished"
    end
  end

  @doc """
  The commits `git log` printed with `Mirror.log/1`'s format, newest first:
  `%{"sha", "date", "subject", "author", "coAuthors"}`.
  """
  def commits(log) do
    for record <- String.split(log, "\x1e", trim: true),
        [sha, date, name, email, subject, trailers] <- [
          String.split(String.trim_leading(record), "\x1f")
        ] do
      author = person(name, email)

      co_authors =
        for(
          trailer <- String.split(trailers, "\x1d", trim: true),
          [_, name, email] <- [Regex.run(~r/^\s*(.*?)\s*<([^>]+)>\s*$/, trailer)],
          do: person(name, email)
        )
        |> Enum.reject(&(&1["email"] == author["email"]))
        |> Enum.uniq_by(& &1["email"])

      %{
        "sha" => sha,
        "date" => date,
        "subject" => subject,
        "author" => author,
        "coAuthors" => co_authors
      }
    end
  end

  # Who a commit names, with their GitHub login when the address says it.
  defp person(name, email) do
    email = String.trim(email)

    login =
      with [_, login] <- Regex.run(~r/^(?:\d+\+)?([^@]+)@users\.noreply\.github\.com$/i, email),
           do: login

    email = String.downcase(email)

    %{
      "name" => String.trim(name),
      "email" => email,
      "login" => login,
      "bot" =>
        String.contains?(name <> email, "[bot]") or email in @agents or
          String.ends_with?(email, @reserved)
    }
  end

  @doc """
  Each upstream pull request or commit the ledger cites, from `features` (`{path,
  feature/2}` pairs) and the upstream `commits`. Those not on the branch the
  commits came from have no title or authors and are `onBranch: false`.
  """
  def entries(features, commits, upstream) do
    by_number =
      for commit <- commits,
          [_, number] <- [Regex.run(~r/\(#(\d+)\)$/, commit["subject"])],
          into: %{},
          do: {number, commit}

    features
    |> Enum.flat_map(fn {path, feature} ->
      for citation <- feature.citations,
          do:
            {citation,
             %{"path" => path, "note" => citation["note"], "scenarios" => feature.scenarios}}
    end)
    |> Enum.group_by(fn {citation, _} -> {citation["kind"], citation["ref"]} end, fn {_, file} ->
      file
    end)
    |> Enum.map(fn {{kind, ref}, files} ->
      commit =
        if kind == "pull",
          do: by_number[ref],
          else: Enum.find(commits, &String.starts_with?(&1["sha"], ref))

      scenarios =
        Enum.reduce(files, none(), &Map.merge(&2, &1["scenarios"], fn _, a, b -> a + b end))

      %{
        "key" => if(kind == "pull", do: "#" <> ref, else: String.slice(ref, 0, 10)),
        "number" => if(kind == "pull", do: String.to_integer(ref)),
        "url" => "https://github.com/#{upstream}/#{kind}/#{ref}",
        "title" => commit && String.replace(commit["subject"], ~r/\s*\(#\d+\)$/, ""),
        "commit" => commit && commit["sha"],
        "mergedAt" => commit && commit["date"],
        "author" => commit && commit["author"],
        "coAuthors" => if(commit, do: commit["coAuthors"], else: []),
        "onBranch" => commit != nil,
        "files" => Enum.sort_by(files, & &1["path"]),
        "scenarios" => scenarios,
        "status" => overall(scenarios)
      }
    end)
    |> Enum.sort_by(&{&1["mergedAt"] || "", &1["key"]}, :desc)
  end

  # A pull request is being worked on while any scenario it is cited for is still
  # to do, and finished once every one that is not dropped passes.
  defp overall(scenarios) do
    cond do
      scenarios["working"] > 0 -> "working"
      scenarios["blocked"] > 0 -> "blocked"
      scenarios["finished"] > 0 -> "finished"
      scenarios["dropped"] > 0 -> "dropped"
      true -> "cited"
    end
  end

  @doc """
  The people whose upstream work the ledger carries, authors and co-authors
  alike, each with the keys of the entries they are named on, most first. Agents
  and bots are left out; the entries still name them.
  """
  def credits(entries) do
    entries
    |> Enum.flat_map(fn entry ->
      for person <- [entry["author"] | entry["coAuthors"]],
          person,
          not person["bot"],
          do: {person, entry["key"]}
    end)
    |> Enum.group_by(fn {person, _} -> person["login"] || person["email"] end)
    |> Enum.map(fn {_, [{person, _} | _] = named} ->
      Map.put(person, "entries", named |> Enum.map(&elem(&1, 1)) |> Enum.uniq())
    end)
    |> Enum.sort_by(&{-length(&1["entries"]), String.downcase(&1["name"])})
  end

  @doc "The upstream commit a ledger's `features/UPSTREAM` says it has read through, or nil."
  def cursor(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(&String.trim/1)
    |> Enum.find(&Regex.match?(~r/^[0-9a-f]{7,40}$/, &1))
  end
end
