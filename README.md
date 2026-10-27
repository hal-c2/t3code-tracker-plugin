# T3 Code Tracker

A HAL-C2 MC plugin that shows how far HAL-C2 has carried upstream
[T3 Code](https://github.com/pingdotgg/t3code), and who upstream did the work.

HAL-C2 records every behaviour it has, will have, or dropped as Gherkin scenarios
under `features/`. Each feature file names its sources in a `# Sources:` comment,
including the upstream pull requests the behaviour came from. The **Upstream** page
lists each upstream pull request that is cited:

- **Being worked on** while any scenario citing it is still `@backlog` or
  `@backlog-<surface>`; **blocked** when what is left is `@blocked`; **finished**
  once every scenario that is not `@dropped` passes; **dropped** when all of them
  are.
- **Who wrote it**: the author of its squash commit on upstream's main and every
  `Co-authored-by`, with agents and bots named apart.
- **Where it is cited**: each feature file, with how far its scenarios have got.

**Credits** lists everyone whose upstream work the ledger carries, with the pull
requests they are named on. The header shows how many upstream commits came after
the ledger's cursor (`features/UPSTREAM`) and are not read yet.

A file cites for all of its scenarios, so each scenario in the file counts toward
every pull request the file cites.

The page also moves the ledger on, each time in a thread of its own, on a new
worktree of the ledger's project from `main`:

- **Check upstream** starts the checking agent on the upstream commits after the
  ledger's cursor, with the ledger's `upstream-ledger` skill.
- **Implement**, beside a feature file that still has backlog scenarios, starts the
  implementing agent on that file.

The last thread each one started shows beside it, with how its last turn went, and
opens it.

## Install

From this folder:

```bash
mise run plugin:install            # the dev MC (hal-c2-dev) and the installed MC (hal-c2)
mise run plugin:install --dev      # only the dev MC
mise run plugin:install --release  # only the installed MC
```

It copies the package into each MC's `plugins` folder as `t3code-tracker`, the
plugin's id (`~/.local/share/hal-c2/elixir/plugins/t3code-tracker` and its
`hal-c2-dev` sibling, under `$XDG_DATA_HOME` when that is set), and has an MC that
is running look for plugins again; one that is not loads it when it starts. Then
turn it on in **Settings → Plugins**. It asks to read the MC's projects, since a
checkout of the ledger's repository (`hal-c2/hal-c2` by default) must be a project
on that MC, and to start threads, for the checking and implementing agents.

Each look fetches the ledger's main branch into that checkout and reads
`features/` as main has it, whatever branch or edits the checkout itself has.
The first look also clones upstream's main into the plugin's data folder. The clone
holds commits only, not files, and every later look fetches what is new.

## Settings

- **Ledger repository**: `owner/name` of the repository whose `features/` cite
  upstream.
- **Upstream repository**: `owner/name` on GitHub. Only its main branch is
  followed: upstream merges everything there, its V2 work included.
- **Look every (minutes)**: how often it fetches upstream and reads the ledger
  again. **Look now** on the page does it at once.
- **Checking upstream** and **Implementing**: each has its own agent, model, the
  model's options (its effort, for one), access, and prompt, so a cheap model can
  read upstream while a stronger one writes the code. The prompts fill in
  `{{upstream}}`, `{{ledger}}`, `{{cursor}}` and `{{pending}}` when checking, and
  `{{file}}`, `{{working}}`, `{{blocked}}`, `{{upstream}}` and `{{pullRequests}}`
  when implementing. Both ask the agent to commit and push its branch and not to
  open a pull request.

## The package

- `plugin.json`: the manifest.
- `mc/`: the MC part. `t3code_tracker.ex` looks, publishes the `ledger` topic and
  starts the agents' threads, `ledger.ex` reads feature files and commits (no MC
  needed), `checkout.ex` reads the ledger's main through its checkout, and
  `mirror.ex` keeps the copy of upstream.
- `ui/TrackerPage.qml`: the **Upstream** page. `ui/TrackerSettings.qml`: its
  settings.
- `test/`: tests for the reader and the page.

## Tests

The reader, and the git log format against a real repository:

```bash
elixir -r mc/ledger.ex -r mc/mirror.ex -r mc/checkout.ex test/ledger_test.exs
```

The page and the settings, against a fake MC part, from a hal-c2 checkout's
`apps/desktop-qt`:

```bash
QT_QPA_PLATFORM=offscreen qmltestrunner -import tests/imports -import qml \
  -input <this folder>/test
```
