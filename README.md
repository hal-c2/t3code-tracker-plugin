# T3 Code Tracker

A HAL-C2 MC plugin that shows the HAL-C2 ledger's backlog and who is at work on
it, how far HAL-C2 has carried upstream
[T3 Code](https://github.com/pingdotgg/t3code), and who upstream did the work.

HAL-C2 records every behaviour it has, will have, or dropped as Gherkin scenarios
under `features/`. The **Ledger** page has four views.

**Backlog** lists every feature file with work left, the largest share of
`@priority-high` work first: how many scenarios are still to do, blocked and
finished, the surfaces they are missing on, and the branches at work on the file.
Scenarios count as `mise run features:pick` counts them: a `Scenario Outline` once,
or, when it passes itself, once for each `Examples` table that carries a backlog
tag; `@backlog-<surface>` only on a scenario that has that surface (`@shared` is
the desktop, the phone and the terminal); `@blocked` apart from what can start.

**In progress** lists the branches of the ledger's repository at work on its
feature files, newest first, with their open pull requests: those with an open pull
request, and those with a commit in the last week, at most 40. For each file one
changes, it says how many backlog scenarios the branch edits or removes and how many
of them it makes pass.

**Upstream** lists each upstream pull request the ledger cites:

- **Being worked on** while any scenario citing it is still `@backlog` or
  `@backlog-<surface>`; **blocked** when what is left is `@blocked`; **finished**
  once every scenario that is not `@dropped` passes; **dropped** when all of them
  are.
- **Who wrote it**: the author of its squash commit on upstream's main and every
  `Co-authored-by`, with agents and bots named apart.
- **Where it is cited**: each feature file, with how far its scenarios have got.
- **At work**: the branches editing the backlog scenarios it is cited for.

**Credits** lists everyone whose upstream work the ledger carries, with the pull
requests they are named on. The header shows how many upstream commits came after
the ledger's cursor (`features/UPSTREAM`) and are not read yet.

### Citing upstream

A pull request or commit URL in a file's leading `# Sources:` comment cites it for
the whole file, so every scenario in the file counts toward it. The page marks
those **whole file**. To cite it for the scenarios it covers, put a comment line
starting `# Upstream #<number>` (a pull request) or `# Upstream <sha>` (a commit, by its full 40-character hash)
above them. It goes with the `Feature`, `Rule`, scenario or `Examples` table after
it, as a tag line would, and the rest of the line says what upstream did:

```gherkin
# Upstream #13590: a thread whose worktree is still being checked out is in worktree mode.
@desktop @backlog
Scenario: A thread still preparing its worktree says "New worktree"
```

A reference cited both ways counts only the scenarios its `# Upstream` lines
name. A pull request is exact when every file cites it that way.

The page also moves the ledger on, each time in a thread of its own, on a new
worktree of the ledger's project from `main`:

- **Check upstream** starts the checking agent on the upstream commits after the
  ledger's cursor, with the ledger's `upstream-ledger` skill.
- **Implement**, beside a feature file that still has backlog scenarios that are
  not blocked, starts the implementing agent on that file, whether or not it
  cites upstream.

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
on that MC; to read its pull requests, to show the open ones at work on the ledger
(without it, only branches with a recent commit show); and to start threads, for
the checking and implementing agents.

Each look fetches the ledger's branches into that checkout and reads `features/`
as main has it, whatever branch or edits the checkout itself has. The branches go
to `refs/t3code-tracker/heads/`, a namespace of the plugin's own, pruned as they
go from origin, so the checkout's own branches and `origin/*` refs are left alone.
A look lists the open pull requests once and reads one `git diff` against main for
each branch at work.
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
  starts the agents' threads, `ledger.ex` reads feature files, branch diffs and
  commits (no MC needed), `checkout.ex` reads the ledger's main and branches
  through its checkout, and `mirror.ex` keeps the copy of upstream.
- `ui/TrackerPage.qml`: the **Ledger** page. `ui/TrackerSettings.qml`: its
  settings.
- `test/`: tests for the reader and the page.

## Tests

The reader, and the git log format and branch reading against real repositories:

```bash
elixir -r mc/ledger.ex -r mc/mirror.ex -r mc/checkout.ex test/ledger_test.exs
```

The page and the settings, against a fake MC part, from a hal-c2 checkout's
`apps/desktop-qt`:

```bash
QT_QPA_PLATFORM=offscreen qmltestrunner -import tests/imports -import qml \
  -input <this folder>/test
```
