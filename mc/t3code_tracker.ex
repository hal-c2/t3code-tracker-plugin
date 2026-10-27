defmodule HalC2Plugins.T3codeTracker do
  @moduledoc """
  Tracks how far HAL-C2 has carried upstream T3 Code. Every few minutes it reads
  the feature files of the ledger's project on this MC for the upstream pull
  requests and commits their `# Sources:` cite, and fetches upstream's main
  branch for who wrote each one. It publishes all of it on the `ledger` topic:
  each cited pull request with the status of its scenarios and its authors, the
  people credited across them, and how many upstream commits the ledger has not
  read yet (after `features/UPSTREAM`).

  The reads run in a process of their own, so the server only keeps the last
  snapshot and when to look next.
  """
  @behaviour HalC2.Plugins.Extension
  use GenServer

  alias HalC2.Plugins.Host
  alias HalC2Plugins.T3codeTracker.{Ledger, Mirror}

  @id "t3code-tracker"

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

      true ->
        :ok
    end
  end

  @impl HalC2.Plugins.Extension
  def call("ledger", _input, _context), do: {:ok, GenServer.call(__MODULE__, :snapshot)}

  def call("refresh", _input, _context) do
    send(__MODULE__, :poll)
    {:ok, nil}
  end

  def call(method, _input, _context), do: {:error, "t3code-tracker has no method #{method}."}

  defp repository?(value), do: is_binary(value) and Regex.match?(~r{^[\w.-]+/[\w.-]+$}, value)

  # --- server -----------------------------------------------------------------------------

  @impl GenServer
  def init(settings) do
    send(self(), :poll)

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
         "problem" => nil
       }
     }}
  end

  @impl GenServer
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

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
