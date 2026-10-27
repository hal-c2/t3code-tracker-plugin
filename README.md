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

## Install

Copy this folder into the MC's `plugins` folder as `t3code-tracker`, the plugin's
id (`~/.local/share/hal-c2/elixir/plugins/t3code-tracker` on Linux). Click **Look for
plugins** in **Settings → Plugins**, then turn it on. It asks only to read the MC's
projects: a checkout of the ledger's repository (`hal-c2/hal-c2` by default) must
be a project on that MC.

The first look clones upstream's main into the plugin's data folder. The clone
holds commits only, not files, and every later look fetches what is new.

## Settings

- **Ledger repository**: `owner/name` of the repository whose `features/` cite
  upstream.
- **Upstream repository**: `owner/name` on GitHub. Only its main branch is
  followed: upstream merges everything there, its V2 work included.
- **Look every (minutes)**: how often it fetches upstream and reads the ledger
  again. **Look now** on the page does it at once.

## The package

- `plugin.json`: the manifest.
- `mc/`: the MC part. `t3code_tracker.ex` looks and publishes the `ledger` topic,
  `ledger.ex` reads feature files and commits (no MC needed), and `mirror.ex`
  keeps the copy of upstream.
- `ui/TrackerPage.qml`: the **Upstream** page.
- `test/`: tests for the reader and the page.

## Tests

The reader, and the git log format against a real repository:

```bash
elixir -r mc/ledger.ex -r mc/mirror.ex test/ledger_test.exs
```

The page, against a fake MC part, from a hal-c2 checkout's `apps/desktop-qt`:

```bash
QT_QPA_PLATFORM=offscreen qmltestrunner -import tests/imports -import qml \
  -input <this folder>/test/tst_TrackerPage.qml
```
