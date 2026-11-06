defmodule HalC2Plugins.T3codeTracker.Ledger do
  @moduledoc """
  What the tracker reads, apart from the MC: the scenarios of a HAL-C2 ledger's
  feature files and how far each has got, the upstream pull requests and commits
  they cite and who wrote each one upstream, and what a branch changes in them.

  A scenario is `finished` when it carries no status tag (it passes on all its
  surfaces), `working` when it is `@backlog`, or `@backlog-<surface>` for a surface
  it has, `blocked` when it is `@blocked`, and `dropped` when it is `@dropped`. A
  `Scenario Outline` counts once, unless it is finished itself and its `Examples`
  tables carry statuses of their own: then each table counts as a scenario. That is
  how `mise run features:pick` counts work.

  A comment line starting `# Upstream #<number>` (a pull request) or `# Upstream
  <sha>` (a commit, by its full 40-character hash) cites it for the `Feature`, `Rule`, scenario or `Examples` table
  after it, as its tags would apply. A URL in the file's leading `# Sources:`
  comment cites for every scenario of the file, an attribution marked `"file"`: it
  does not say which scenarios carry it. A reference cited both ways is scoped.
  """

  @statuses ~w(working blocked finished dropped)
  @surfaces ~w(mc desktop mobile tui)
  @keywords [
    {"Feature:", :feature},
    {"Rule:", :rule},
    {"Background:", :background},
    {"Scenario Outline:", :outline},
    {"Scenario Template:", :outline},
    {"Scenario:", :scenario},
    {"Example:", :scenario},
    {"Examples:", :examples},
    {"Scenarios:", :examples}
  ]
  # Co-authors that are agents and bots rather than people. GitHub's own bots end
  # in `[bot]`; these are the agents that sign commits with an address of their own,
  # and an address on a domain reserved for tests (RFC 2606) is nobody's.
  @agents ~w(noreply@anthropic.com noreply@openai.com codex@openai.com cursoragent@cursor.com)
  # Agents GitHub gives an account, known by their login.
  @agent_logins ~w(codex copilot)
  @reserved ~w(.test .example .invalid .localhost)

  @doc "The status counts of nothing, the start of every sum."
  def none, do: Map.new(@statuses, &{&1, 0})

  @doc """
  One feature file: the upstream pull requests and commits it cites, each
  `%{"kind", "ref", "note", "scope"}` with `"scope"` `"file"` or `"scoped"`; its
  scenarios counted by status; the `working` ones counted by each surface they are
  still missing on (`surfaces`) and by priority (`priority`); and the scenarios
  themselves (`units`), which stay in the MC.
  """
  def feature(text, upstream) do
    blocks = blocks(text)
    units = blocks |> units(nil) |> dedupe()
    headed = text |> header() |> Enum.flat_map(&cite(&1, upstream)) |> Enum.uniq_by(&key/1)
    notes = Map.new(headed, &{key(&1), &1["note"]})

    # A scoped citation keeps the header's note when the header names it too.
    scoped =
      blocks
      |> Enum.flat_map(& &1.cites)
      |> Enum.uniq_by(&key/1)
      |> Enum.map(fn cite ->
        if notes[key(cite)] in [nil, ""], do: cite, else: %{cite | "note" => notes[key(cite)]}
      end)

    keys = MapSet.new(scoped, &key/1)
    file_wide = Enum.reject(headed, &MapSet.member?(keys, key(&1)))

    working = Enum.filter(units, &(&1.status == "working"))

    %{
      citations:
        Enum.map(file_wide, &Map.put(&1, "scope", "file")) ++
          Enum.map(scoped, &Map.put(&1, "scope", "scoped")),
      scenarios: counts(units),
      surfaces:
        Map.merge(
          Map.new(@surfaces, &{&1, 0}),
          working |> Enum.flat_map(& &1.missing) |> Enum.frequencies()
        ),
      priority: %{
        "high" => Enum.count(working, &(&1.priority == "high")),
        "low" => Enum.count(working, &(&1.priority == "low"))
      },
      units: units
    }
  end

  defp key(citation), do: {citation["kind"], citation["ref"]}

  defp counts(units), do: Map.merge(none(), units |> Enum.map(& &1.status) |> Enum.frequencies())

  # The leading comment, without its `# Upstream` lines, which cite for the
  # Feature they stand above.
  defp header(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.take_while(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.reject(&upstream_line?/1)
  end

  @upstream_line ~r/^#\s*Upstream\s+(?:#(\d+)|([0-9a-f]{40}))\b[\s:.,;-]*(.*)$/i

  defp upstream_line?(line), do: Regex.match?(@upstream_line, line)

  # The pull request or commit a `# Upstream` comment line cites, and what it says.
  defp scoped_cite(line) do
    case Regex.run(@upstream_line, line) do
      [_, number, "", note] when number != "" ->
        [%{"kind" => "pull", "ref" => number, "note" => note}]

      [_, "", sha, note] when byte_size(sha) in 7..40 ->
        [%{"kind" => "commit", "ref" => String.downcase(sha), "note" => note}]

      _ ->
        []
    end
  end

  defp cite(line, upstream) do
    pattern =
      ~r"https://github\.com/#{Regex.escape(upstream)}/(pull|commit)/([0-9]+|[0-9a-f]{7,40})\b(?:\s*\(([^)]*)\))?"i

    for [_, kind, ref | note] <- Regex.scan(pattern, line) do
      %{
        "kind" => if(String.downcase(kind) == "pull", do: "pull", else: "commit"),
        "ref" => String.downcase(ref),
        "note" => List.first(note, "")
      }
    end
  end

  # Each keyword of the file in order, `%{kind, name, line, tags, cites, body}`: the
  # tags and `# Upstream` citations above it, and the lines under it up to the next
  # one. Doc strings are body, whatever they hold.
  defp blocks(text) do
    {blocks, _} =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{tags: [], cites: [], doc: nil}}, fn {raw, number}, {blocks, at} ->
        line = String.trim(raw)

        cond do
          at.doc ->
            doc = if String.starts_with?(line, at.doc), do: nil, else: at.doc
            {body(blocks, line), %{at | doc: doc}}

          String.starts_with?(line, ~w(""" ```)) ->
            {body(blocks, line), %{at | doc: String.slice(line, 0, 3)}}

          String.starts_with?(line, "#") ->
            {blocks, %{at | cites: at.cites ++ scoped_cite(line)}}

          String.starts_with?(line, "@") ->
            {blocks, %{at | tags: at.tags ++ tags_of(line)}}

          line == "" ->
            {blocks, at}

          found = keyword(line) ->
            {name, kind} = found

            block = %{
              kind: kind,
              name: name,
              line: number,
              tags: at.tags,
              cites: at.cites,
              body: []
            }

            {[block | blocks], %{at | tags: [], cites: []}}

          true ->
            {body(blocks, line), at}
        end
      end)

    blocks |> Enum.map(&%{&1 | body: Enum.reverse(&1.body)}) |> Enum.reverse()
  end

  defp body([block | blocks], line), do: [%{block | body: [line | block.body]} | blocks]
  defp body([], _line), do: []

  defp keyword(line) do
    Enum.find_value(@keywords, fn {word, kind} ->
      if String.starts_with?(line, word),
        do: {line |> String.replace_prefix(word, "") |> String.trim(), kind}
    end)
  end

  defp tags_of(line) do
    line
    |> String.split("#", parts: 2)
    |> hd()
    |> String.split()
    |> Enum.filter(&String.starts_with?(&1, "@"))
  end

  # The scenarios under each Feature and Rule, with what those carry.
  defp units([], _scope), do: []

  defp units([%{kind: :feature} = block | rest], _scope),
    do: units(rest, %{feature: block, rule: nil})

  defp units([%{kind: :rule} = block | rest], scope) when scope != nil,
    do: units(rest, %{scope | rule: block})

  defp units([%{kind: :scenario} = block | rest], scope) when scope != nil do
    tags = inherited(scope, :tags) ++ block.tags
    [unit(scope, block.name, block.line, tags, block.cites, block.body) | units(rest, scope)]
  end

  defp units([%{kind: :outline} = block | rest], scope) when scope != nil do
    {tables, rest} = Enum.split_while(rest, &(&1.kind == :examples))
    outline(scope, block, tables) ++ units(rest, scope)
  end

  defp units([_ | rest], scope), do: units(rest, scope)

  # An outline is one scenario, or one per Examples table when the outline passes
  # and its tables say otherwise.
  defp outline(scope, block, tables) do
    own = inherited(scope, :tags) ++ block.tags

    if status(own) == "finished" and Enum.any?(tables, &(status(own ++ &1.tags) != "finished")) do
      for {table, index} <- Enum.with_index(tables, 1) do
        unit(
          scope,
          {block.name, index},
          table.line,
          own ++ table.tags,
          block.cites ++ table.cites,
          {block.body, table.body}
        )
      end
    else
      cites = block.cites ++ Enum.flat_map(tables, & &1.cites)
      text = {block.body, Enum.map(tables, &{&1.tags, &1.body})}
      [unit(scope, block.name, block.line, own, cites, text)]
    end
  end

  defp inherited(%{feature: feature, rule: rule}, field),
    do: Map.fetch!(feature, field) ++ if(rule, do: Map.fetch!(rule, field), else: [])

  defp unit(scope, name, line, tags, cites, text) do
    %{
      key: {scope.rule && scope.rule.name, name},
      line: line,
      status: status(tags),
      missing: missing(tags),
      priority:
        cond do
          "@priority-high" in tags -> "high"
          "@priority-low" in tags -> "low"
          true -> nil
        end,
      cites: (inherited(scope, :cites) ++ cites) |> Enum.map(&key/1) |> Enum.uniq(),
      hash: :erlang.phash2({tags, text})
    }
  end

  # Two scenarios of one name under one rule are told apart by their order.
  defp dedupe(units) do
    {units, _} =
      Enum.map_reduce(units, %{}, fn unit, seen ->
        n = Map.get(seen, unit.key, 0)
        {%{unit | key: {unit.key, n}}, Map.put(seen, unit.key, n + 1)}
      end)

    units
  end

  defp status(tags) do
    cond do
      "@dropped" in tags -> "dropped"
      "@blocked" in tags -> "blocked"
      "@backlog" in tags or missing(tags) != [] -> "working"
      true -> "finished"
    end
  end

  # The surfaces a scenario has (`@shared` is each client) that it does not pass on yet.
  defp missing(tags) do
    has =
      Enum.filter(@surfaces, &(("@" <> &1) in tags or (&1 != "mc" and "@shared" in tags)))

    if "@backlog" in tags, do: has, else: Enum.filter(has, &(("@backlog-" <> &1) in tags))
  end

  @doc """
  The feature files with backlog work, `%{"path", "scenarios", "surfaces",
  "priority"}`: the largest share of `@priority-high` work first, then the least
  `@priority-low`, then the most work, and last those whose work is all blocked.
  """
  def backlog(features) do
    for {path, feature} <- features,
        feature.scenarios["working"] + feature.scenarios["blocked"] > 0 do
      %{
        "path" => path,
        "scenarios" => feature.scenarios,
        "surfaces" => feature.surfaces,
        "priority" => feature.priority
      }
    end
    |> Enum.sort_by(fn file ->
      working = file["scenarios"]["working"]
      share = fn n -> if working > 0, do: n / working, else: 0 end

      {working == 0, -share.(file["priority"]["high"]), share.(file["priority"]["low"]), -working,
       file["path"]}
    end)
  end

  @doc """
  What a branch does to the ledger, from `git diff` with the whole of each file as
  context (`Checkout.diff/2`): `%{"path", "scenarios", "finishes", keys}` for each
  feature file it changes, where `"scenarios"` counts the backlog scenarios it edits
  or removes, `"finishes"` those of them it makes pass, and `keys` names them.
  """
  def work_files(diff, upstream) do
    for {path, old, new} <- files_of(diff), String.ends_with?(path, ".feature") do
      before = if old, do: feature(old, upstream).units, else: []
      later = if new, do: Map.new(feature(new, upstream).units, &{&1.key, &1}), else: %{}

      touched =
        for unit <- before,
            unit.status in ~w(working blocked),
            later[unit.key] == nil or later[unit.key].hash != unit.hash,
            do: unit

      %{
        "path" => path,
        "scenarios" => length(touched),
        "finishes" => Enum.count(touched, &(later[&1.key][:status] == "finished")),
        keys: MapSet.new(touched, & &1.key)
      }
    end
  end

  # Each file of a whole-context diff, `{path, before, after}`, nil where it is added
  # or deleted. Context lines are in both, `-` lines only before, `+` only after.
  defp files_of(diff) do
    diff
    |> String.split(~r/^diff --git /m, trim: true)
    |> Enum.flat_map(fn chunk ->
      lines = String.split(chunk, "\n")
      {head, hunks} = Enum.split_while(lines, &(not String.starts_with?(&1, "@@")))
      old = Enum.find_value(head, &side(&1, "--- "))
      new = Enum.find_value(head, &side(&1, "+++ "))

      text = fn mark ->
        hunks
        |> Enum.flat_map(fn
          <<^mark::binary-size(1), rest::binary>> -> [rest]
          " " <> rest -> [rest]
          _ -> []
        end)
        |> Enum.join("\n")
      end

      case {old, new} do
        {nil, nil} -> []
        {old, new} -> [{elem(new || old, 1), old && text.("-"), new && text.("+")}]
      end
    end)
  end

  # The path on one side of a file's diff header, nil for /dev/null.
  defp side(line, prefix) do
    case String.split_at(line, String.length(prefix)) do
      {^prefix, "a/" <> path} -> {:path, path}
      {^prefix, "b/" <> path} -> {:path, path}
      _ -> nil
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
          String.downcase(login || "") in @agent_logins or String.ends_with?(email, @reserved)
    }
  end

  @doc """
  Each upstream pull request or commit the ledger cites, from `features` (`{path,
  feature/2}` pairs), the upstream `commits`, and the branches in `work`
  (`%{"branch", "files" => work_files/2}`). Those not on the branch the commits came
  from have no title or authors and are `onBranch: false`. An entry is `exact` when
  every file cites it for its scenarios rather than the whole file, and names in
  `work` the branches that edit the backlog scenarios it is cited for (any change
  to the file, for a file-wide citation).
  """
  def entries(features, commits, upstream, work \\ []) do
    by_number =
      for commit <- commits,
          [_, number] <- [Regex.run(~r/\(#(\d+)\)$/, commit["subject"])],
          into: %{},
          do: {number, commit}

    features
    |> Enum.flat_map(fn {path, feature} ->
      for citation <- feature.citations do
        covered =
          if citation["scope"] == "file",
            do: feature.units,
            else: Enum.filter(feature.units, &(key(citation) in &1.cites))

        file = %{
          "path" => path,
          "note" => citation["note"],
          "scope" => citation["scope"],
          "scenarios" => counts(covered)
        }

        {citation, file, working_on(work, path, citation["scope"], covered)}
      end
    end)
    |> Enum.group_by(fn {citation, _, _} -> key(citation) end)
    |> Enum.map(fn {{kind, ref}, cited} ->
      files = Enum.map(cited, &elem(&1, 1))

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
        "exact" => Enum.all?(files, &(&1["scope"] == "scoped")),
        "work" => cited |> Enum.flat_map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort(),
        "scenarios" => scenarios,
        "status" => overall(scenarios)
      }
    end)
    |> Enum.sort_by(&{&1["mergedAt"] || "", &1["key"]}, :desc)
  end

  defp working_on(work, path, scope, covered) do
    keys = MapSet.new(covered, & &1.key)

    for branch <- work,
        file <- branch["files"],
        file["path"] == path,
        scope == "file" or not MapSet.disjoint?(file.keys, keys),
        do: branch["branch"]
  end

  @doc "`work` as it is published: what `work_files/2` keeps for the MC left out."
  def public(work) do
    for branch <- work,
        do: Map.update!(branch, "files", fn files -> Enum.map(files, &Map.delete(&1, :keys)) end)
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
