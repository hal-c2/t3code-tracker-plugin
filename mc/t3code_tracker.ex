defmodule HalC2Plugins.T3codeTracker do
  @moduledoc """
  Tracks how far HAL-C2 has carried upstream T3 Code. Every few minutes it reads
  the feature files of the ledger's project on this MC for the upstream pull
  requests and commits their `# Sources:` cite, and fetches upstream's main
  branch for who wrote each one. It publishes all of it on the `ledger` topic:
  each cited pull request with the status of its scenarios and its authors, the
  people credited across them, and how many upstream commits the ledger has not
  read yet (after `features/UPSTREAM`).

  It also starts the agents that move the ledger on, each in a new worktree of the
  ledger's project: one that checks upstream (the upstream-ledger skill takes the
  next pull requests after the cursor), and one that implements a feature file's
  backlog scenarios. Each has its own agent, model, access and prompt in the
  settings, and the thread each last started is kept in `threads.json`.

  The reads run in a process of their own, so the server only keeps the last
  snapshot and when to look next.
  """
  @behaviour HalC2.Plugins.Extension
  use GenServer

  alias HalC2.Plugins.Host
  alias HalC2Plugins.T3codeTracker.{Ledger, Mirror}

  @id "t3code-tracker"
  @roles ~w(checking implementing)
  @runtime_modes ~w(approval-required auto-accept-edits auto full-access)

  # --- extension ------------------------------------------------------------------------

  @impl HalC2.Plugins.Extension
  def start_link(settings), do: GenServer.start_link(__MODULE__, settings, name: __MODULE__)

  @impl HalC2.Plugins.Extension
  def validate_settings(settings) do
    cond do
      not repository?(settings["upstream"]) ->
        {:error, "upstream: give it as owner/name."}

      not repository?(settings["ledger"]) ->
        {:error, "ledger: give it as owner/name."}

      not (is_number(settings["pollMinutes"]) and settings["pollMinutes"] >= 1) ->
        {:error, "pollMinutes: look at most once a minute."}

      role = Enum.find(@roles, &(not agent?(settings[&1]))) ->
        {:error,
         "#{role}: give it as {\"provider\": \"claudeAgent\", \"model\": \"\", \"modelOptions\": {}, \"runtimeMode\": \"auto-accept-edits\"}."}

      key = Enum.find(~w(checkPrompt implementPrompt), &(String.trim(settings[&1] || "") == "")) ->
        {:error, "#{key}: the prompt cannot be empty."}

      true ->
        :ok
    end
  end

  defp agent?(%{"provider" => provider} = agent) when is_binary(provider) do
    String.trim(provider) != "" and is_binary(agent["model"] || "") and
      is_map(agent["modelOptions"] || %{}) and
      (agent["runtimeMode"] || "auto-accept-edits") in @runtime_modes
  end

  defp agent?(_agent), do: false

  @impl HalC2.Plugins.Extension
  def call("ledger", _input, _context), do: {:ok, GenServer.call(__MODULE__, :snapshot)}

  def call("refresh", _input, _context) do
    send(__MODULE__, :poll)
    {:ok, nil}
  end

  # What the settings page offers: the agents and their models.
  def call("settings", _input, context) do
    {:ok, providers} = Host.providers(@id)
    {:ok, %{"settings" => context.settings, "providers" => providers}}
  end

  # The checking agent takes the next upstream pull requests after the cursor.
  def call("check", _input, context) do
    snapshot = GenServer.call(__MODULE__, :snapshot)
    cursor = snapshot["cursor"] || %{}

    fill(context.settings["checkPrompt"], %{
      "upstream" => context.settings["upstream"],
      "ledger" => context.settings["ledger"],
      "cursor" => cursor["commit"] || "features/UPSTREAM",
      "pending" => to_string(cursor["pending"] || "an unknown number of")
    })
    |> then(&start(context.settings, "checking", "check", "Check upstream T3 Code", &1))
  end

  # The implementing agent makes one feature file's backlog scenarios pass.
  def call("implement", %{"path" => path}, context) when is_binary(path) do
    snapshot = GenServer.call(__MODULE__, :snapshot)

    cited =
      for entry <- snapshot["pullRequests"],
          file <- entry["files"],
          file["path"] == path,
          do: {entry, file}

    case cited do
      [] ->
        {:error, "No upstream pull request is cited by #{path}."}

      [{_, file} | _] ->
        fill(context.settings["implementPrompt"], %{
          "file" => path,
          "working" => to_string(file["scenarios"]["working"]),
          "blocked" => to_string(file["scenarios"]["blocked"]),
          "upstream" => context.settings["upstream"],
          "pullRequests" =>
            cited |> Enum.map(fn {entry, _} -> entry["url"] end) |> Enum.join(", ")
        })
        |> then(
          &start(
            context.settings,
            "implementing",
            "implement:" <> path,
            "Implement #{Path.basename(path)}",
            &1
          )
        )
    end
  end

  def call(method, _input, _context), do: {:error, "t3code-tracker has no method #{method}."}

  # A thread this plugin started finished a turn: how it went shows beside it.
  @impl HalC2.Plugins.Extension
  def handle_event(
        %{"type" => "turn.finished", "threadId" => thread_id, "status" => status},
        _context
      ),
      do: GenServer.cast(__MODULE__, {:finished, thread_id, status})

  def handle_event(_event, _context), do: :ok

  # Starts `role`'s agent on `prompt` in a new worktree of the ledger's main, and
  # keeps the thread under `key`, replacing the one started before.
  defp start(settings, role, key, title, prompt) do
    thread_id = uuid()

    with {:ok, project} <- ledger_project(settings["ledger"]),
         {:ok, model} <- model(settings[role]),
         {:ok, _} <-
           Host.launch_thread(@id, role, %{
             "threadId" => thread_id,
             "projectId" => project["id"],
             "title" => title,
             "modelSelection" => model,
             "runtimeMode" => settings[role]["runtimeMode"] || "auto-accept-edits",
             "interactionMode" => "default",
             "workspaceStrategy" => %{
               "type" => "worktree",
               "baseRef" => "main",
               "startFromOrigin" => true
             },
             "initialMessage" => %{"text" => prompt, "attachments" => []}
           }) do
      {:ok, GenServer.call(__MODULE__, {:started, key, thread_id})}
    end
  end

  defp uuid do
    <<a::32, b::16, _::4, c::12, _::2, d::62>> = :crypto.strong_rand_bytes(16)
    hex = Base.encode16(<<a::32, b::16, 4::4, c::12, 2::2, d::62>>, case: :lower)

    Enum.map_join([{0, 8}, {8, 4}, {12, 4}, {16, 4}, {20, 12}], "-", fn {at, length} ->
      binary_part(hex, at, length)
    end)
  end

  defp fill(template, values),
    do: Regex.replace(~r/\{\{(\w+)\}\}/, template, fn whole, name -> values[name] || whole end)

  # The model selection for an agent setting: the picked model with the options it
  # offers, else the agent's default model.
  defp model(agent) do
    instance = agent["provider"]
    wanted = String.trim(agent["model"] || "")
    chosen = agent["modelOptions"] || %{}
    {:ok, providers} = Host.providers(@id)

    case Enum.find(providers, &(&1["instanceId"] == instance)) do
      nil ->
        {:error, "There is no agent #{instance} on this MC; pick one in the settings."}

      %{"models" => models} ->
        found = Enum.find(models, &(&1["slug"] == wanted))

        cond do
          # A model the listing does not know (a custom one) keeps the options as picked.
          wanted != "" and found == nil ->
            {:ok,
             selection(
               instance,
               wanted,
               Enum.map(chosen, fn {id, v} -> %{"id" => id, "value" => v} end)
             )}

          model = found || Enum.find(models, & &1["isDefault"]) || List.first(models) ->
            {:ok, selection(instance, model["slug"], options(model["options"] || [], chosen))}

          true ->
            {:error, "#{instance} has no models; pick one in the settings."}
        end
    end
  end

  defp selection(instance, slug, []), do: %{"instanceId" => instance, "model" => slug}

  defp selection(instance, slug, options),
    do: %{"instanceId" => instance, "model" => slug, "options" => options}

  # Only the options the model offers, at values it offers, so a pick left over from
  # another agent cannot fail the run.
  defp options(descriptors, chosen) do
    for descriptor <- descriptors,
        value = chosen[descriptor["id"]],
        value != nil,
        option?(descriptor, value),
        do: %{"id" => descriptor["id"], "value" => value}
  end

  defp option?(%{"type" => "boolean"}, value), do: is_boolean(value)

  defp option?(descriptor, value),
    do: is_binary(value) and Enum.any?(descriptor["options"] || [], &(&1["id"] == value))

  defp repository?(value), do: is_binary(value) and Regex.match?(~r{^[\w.-]+/[\w.-]+$}, value)

  # --- server -----------------------------------------------------------------------------

  @impl GenServer
  def init(settings) do
    send(self(), :poll)
    threads = read_threads()

    {:ok,
     %{
       settings: settings,
       looking: nil,
       timer: nil,
       snapshot: %{
         "upstream" => settings["upstream"],
         "branch" => Mirror.branch(),
         "ledger" => nil,
         "cursor" => nil,
         "pullRequests" => [],
         "credits" => [],
         "checkedAt" => nil,
         "looking" => true,
         "problem" => nil,
         "threads" => threads
       }
     }}
  end

  @impl GenServer
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:started, key, thread_id}, _from, state) do
    thread = %{
      "threadId" => thread_id,
      "startedAt" => System.system_time(:millisecond),
      "status" => "running"
    }

    state = put_threads(state, Map.put(state.snapshot["threads"], key, thread))
    {:reply, thread, state}
  end

  @impl GenServer
  def handle_cast({:finished, thread_id, status}, state) do
    threads =
      Map.new(state.snapshot["threads"], fn
        {key, %{"threadId" => ^thread_id} = thread} -> {key, Map.put(thread, "status", status)}
        other -> other
      end)

    {:noreply, put_threads(state, threads)}
  end

  defp put_threads(state, threads) do
    path = threads_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(threads))
    publish(state, %{"threads" => threads})
  end

  defp threads_path, do: Path.join(Host.data_dir(@id), "threads.json")

  defp read_threads do
    with {:ok, text} <- File.read(threads_path()),
         {:ok, %{} = threads} <- JSON.decode(text),
         do: threads,
         else: (_ -> %{})
  end

  @impl GenServer
  def handle_info(:poll, %{looking: nil} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    server = self()
    settings = state.settings
    # Linked, so turning the plugin off calls off a fetch still running.
    {_pid, ref} =
      Process.spawn(fn -> send(server, {:looked, look(settings)}) end, [:link, :monitor])

    {:noreply, publish(%{state | looking: ref, timer: nil}, %{"looking" => true})}
  end

  def handle_info(:poll, state), do: {:noreply, state}

  def handle_info({:looked, found}, state), do: {:noreply, publish(state, found)}

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{looking: ref} = state) do
    timer = Process.send_after(self(), :poll, trunc(state.settings["pollMinutes"] * 60_000))
    changes = %{"looking" => false}

    changes =
      if reason == :normal,
        do: changes,
        else: Map.put(changes, "problem", "Looking failed: #{inspect(reason)}")

    {:noreply, publish(%{state | looking: nil, timer: timer}, changes)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp publish(state, changes) do
    snapshot = Map.merge(state.snapshot, changes)
    Host.publish(@id, "ledger", snapshot)
    %{state | snapshot: snapshot}
  end

  # --- looking -----------------------------------------------------------------------------

  # The ledger and upstream as they are now. Upstream that cannot be fetched is read
  # from the copy there is, with why in `problem`; a ledger that cannot be found
  # keeps what was published before.
  defp look(settings) do
    upstream = settings["upstream"]
    dir = Path.join([Host.data_dir(@id), "upstream", upstream <> ".git"])

    with {:ok, project} <- ledger_project(settings["ledger"]) do
      synced = Mirror.sync(dir, upstream)

      {commits, logged} =
        case Mirror.log(dir) do
          {:ok, log} -> {Ledger.commits(log), :ok}
          error -> {[], error}
        end

      entries = project["root"] |> features(upstream) |> Ledger.entries(commits, upstream)
      cursor = cursor(project["root"], commits, dir)

      %{
        "upstream" => upstream,
        "ledger" => %{
          "repository" => settings["ledger"],
          "project" => project["title"],
          "root" => project["root"]
        },
        "cursor" => cursor,
        "pullRequests" => entries,
        "credits" => Ledger.credits(entries),
        "checkedAt" => System.system_time(:millisecond),
        "problem" =>
          Enum.find_value([synced, logged], fn
            {:error, message} -> "Upstream could not be read: #{message}"
            :ok -> nil
          end)
      }
    else
      {:error, message} -> %{"problem" => message}
    end
  end

  defp ledger_project(repository) do
    with {:ok, projects} <- Host.projects(@id) do
      case Enum.find(
             projects,
             &(String.downcase(&1["repository"] || "") == String.downcase(repository))
           ) do
        nil ->
          {:error,
           "No project on this MC has #{repository} as its remote. Add a checkout of it as a project."}

        project ->
          {:ok, project}
      end
    end
  end

  defp features(root, upstream) do
    for file <- root |> Path.join("features/**/*.feature") |> Path.wildcard() |> Enum.sort(),
        {:ok, text} <- [File.read(file)],
        do: {Path.relative_to(file, root), Ledger.feature(text, upstream)}
  end

  defp cursor(root, commits, dir) do
    with {:ok, text} <- File.read(Path.join(root, "features/UPSTREAM")),
         sha when is_binary(sha) <- Ledger.cursor(text) do
      commit = Enum.find(commits, &String.starts_with?(&1["sha"], sha))

      %{
        "commit" => sha,
        "date" => commit && commit["date"],
        "pending" => commit && Mirror.pending(dir, sha)
      }
    else
      _ -> nil
    end
  end
end
