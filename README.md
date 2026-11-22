# Dev Checklist

An in-game checklist of what to test. A tester ticks tasks off as they play,
and the ticks are saved, so whoever wrote the tasks can read the results
afterwards (passes, fails with a short note, and where the tester was when a task failed). Any number of addons can use it at once without touching each
other's lists.

- [Using the checklist](#using-the-checklist)
- [For addon authors](#for-addon-authors)
- [The test loop, start to finish](docs/workflow.md)

## Using the checklist

Type `/dc` to show or hide the window. It also opens by itself at login
while anything is unticked.

- **Pass a task:** left click it. Click again to clear.
- **Fail a task:** right click it, type a one-line note, press Enter (Esc keeps
  the fail with no note). Right click again to clear. A pass and a fail
  replace each other.
- **Fold a group:** click its header. The header shows how many tasks are
  passed (`3/8`, plus a red count of fails). A group folds by itself once everything in it is ticked.
- **Move the window:** drag the title bar. It remembers where you left it.

### Add your own tasks

Everything you add here is saved until you delete it.

- **New group:** click **+** in the title bar, type a name, press Enter.
- **New task:** click **+** on a group's header. Fill in Area (optional, a
  heading such as "bags"), Task, and Send (optional: what to report back,
  such as "screenshot"). Enter adds the task and keeps the form open for the
  next one; Tab moves between boxes; Esc closes.
- **Delete:** the **x** on a task you added deletes it. The **x** on a group
  you made deletes the group and its tasks: click it twice.
- **Quick add from chat:** `/dc add bags: Sort button works.` adds a task to
  a group called "Parked" (the `bags:` part is optional).

### Import a markdown list

Click **Import** in the title bar, paste a list, click **Import**. The tasks
are added to what's already there.

```markdown
# MyAddon

Round 3: new bag sort. Lines like this one are notes and are skipped.

## Login
- [ ] No Lua errors on login. (yes / no)
- [ ] The welcome line prints once, not on every reload.

## Bags
- [ ] Open your bags: a Sort button sits in the title bar. (screenshot)
- [ ] Click Sort twice: items don't move the second time.
- [x] Bags still open at the bank.
- Plain bullets like this one are notes, not tasks.
```

- `# MyAddon` is the group. If a group with that name already exists, the
  tasks join it. No `#` line: they go to a group called "Imported".
- `## Login` is the area for the tasks under it (`###` and deeper work too).
- **Only checkbox lines are tasks:** `- [ ]`, `* [ ]`, `+ [ ]` or `1. [ ]`.
  `- [x]` arrives already ticked. Everything else is skipped.
- Put how to confirm each test in the task itself, e.g. "(screenshot)".
- Tasks already in the group are skipped, so pasting twice adds nothing.
- The box counts the tasks it found as you paste. Esc closes it.

### Commands

| Command | What it does |
|---|---|
| `/dc` | Show or hide the window |
| `/dc add [area:] task` | Add a task to the "Parked" group |
| `/dc note text` | Save a quick observation (time, zone, combat, spec, group, build) on the open round. With no round open it goes to a "General" list and says so |
| `/dc clear <group>` | Delete a group, its tasks and its ticks |

## For addon authors

### 1. Hook it up

Add Dev Checklist as an optional dependency, so it loads first when it's
installed and your addon still works when it isn't:

```toc
## OptionalDeps: DevChecklist
```

Then guard every call:

```lua
if DevChecklist then
    -- calls go here
end
```

Every call can be made at any time, including at file load, before Dev
Checklist's saved data is ready. One thing to know: call `Register` while
your addon loads (at file load or on `ADDON_LOADED`), not later. At login,
saved ticks, fails and notes of ids that have no round or saved tasks are
treated as left over from a closed round and dropped.

### 2. Give the tester a round of tasks

```lua
if DevChecklist then
    DevChecklist:Register("MyAddon", "v1.2: bag sort", {
        { "login", "No Lua errors on login.", "yes / no" },
        { "bags",  "Open your bags: a Sort button shows.", "screenshot" },
        { area = "bags", text = "Click Sort twice: nothing moves the second time." },
    }, "a1b2c3d")
end
```

- The first argument is your **id**: one group in the window, and the key for
  your ticks. Use your addon's name. Ids are case-sensitive.
- The second is the **round name**, shown next to the id.
- The optional fourth is a **build** label (such as a short commit hash). It is
  shown in grey in the header and saved in the report.
- Each task is `{ area, text, send }` or `{ area =, text =, send = }`.
  `area` groups tasks under a small heading, `text` is the task, and `send`
  (optional) is shown in grey after it: what you want back.
- `Register` replaces your whole round. The list itself isn't saved (your
  code registers it again every load), but **ticks are**, and they follow the
  task text. Change a task's text and it comes back unticked.

### 3. Or save tasks instead

When you want tasks to stay until the tester deletes them, rather than
being sent every load:

```lua
DevChecklist:Park("MyAddon", "later", "Retest after the patch.", "yes / no")
DevChecklist:Import("# MyAddon\n## bags\n- [ ] Sort still works.")
```

### 4. Read the results

In game:

```lua
local done, total = DevChecklist:Progress("MyAddon")
if DevChecklist:IsDone("MyAddon", "No Lua errors on login.") then ... end
```

Outside the game, after the tester reloads or logs out, ticks are in
`WTF\Account\<account>\SavedVariables\DevChecklist.lua`:

```lua
DevChecklistDB = {
    done = { ["MyAddon"] = { ["No Lua errors on login."] = true } },
    fail = { ["MyAddon"] = { ["Open your bags: a Sort button shows."] = "button missing at 1080p" } },
    report = { ["MyAddon"] = {            -- summary, rewritten on every reload and logout
        round = "v1.2: bag sort", build = "a1b2c3d", pass = 1, open = 1,
        fail = { { text = "Open your bags: a Sort button shows.", note = "button missing at 1080p" } },
    } },
    snap = { ["MyAddon"] = { ["Open your bags: a Sort button shows."] = {   -- taken when the task failed
        at = "2026-11-17 21:04:12", zone = "Dornogal", combat = "no",
        spec = "Fire", group = 0, build = "a1b2c3d",
        log = { "21:02:40 reload: Dornogal", "21:03:55 [MyAddon] bags opened" },   -- last 20 log lines
    } } },
    notes = { ["MyAddon"] = { { at = "2026-11-17 21:05:30", zone = "Dornogal", combat = "no",
        spec = "Fire", group = 0, build = "a1b2c3d", text = "bars flicker at the bank" } } },   -- from /dc note
    log = { "21:02:40 reload: Dornogal", "21:03:10 combat in", ... },   -- flight recorder, last 100 lines
    parked = { ... }, groups = { ... },   -- tasks and groups added in game
}
```

The file is plain Lua, so a script can load it instead of searching the
text. `tools/results.lua` in this repo prints one round (passes, fails with
their notes and snapshots, quick notes, and the round's log lines):

```
luajit tools/results.lua "<path>/SavedVariables/DevChecklist.lua" MyAddon
```

The game writes the file only on `/reload` and logout, so reload before
reading. `report` is rewritten at the same moment and lists only rounds that
were loaded then. Passes and fails are keyed by task text; results for a
task that is no longer in the round are old.

### 5. Flight recorder

While a round from `Register`, `Add` or a round file has a task not yet
passed, Dev Checklist keeps a short log: login and reload, zone changes,
combat in and out, and Lua errors when BugGrabber is loaded. Add your own
lines from any addon:

```lua
if DevChecklist then DevChecklist:Log("MyAddon", "bags opened", count) end
```

The first argument is the round id; it becomes the line's `[MyAddon]` tag.
Everything after it is turned into text and joined with spaces. Each line
gets the time (`21:03:55 [MyAddon] bags opened 4`), is cut to 300
characters, and only the last 100 lines are kept, shared by all rounds, so
log at decision points, not every frame. The call is safe in combat and
does nothing when no round is open.

When the tester fails a task, a snapshot is saved with it in `snap`: time,
zone (with instance and difficulty), combat, spec, group size, your build
label and the last 20 log lines. Passing or clearing the task drops it. With
no round open, nothing is recorded and no events are watched.

`/dc note` saves the same stamp (without the log lines) plus the typed text
in `notes`, on the open round: the one last ticked or failed when several
are open, or a list called "General" when none is. The last 50 notes per
round are kept.

Saved data stays small: when a round is closed (its file removed, or
`/dc clear`), its ticks, fails, snapshots, notes and tagged log lines are
dropped at the next login. Read the results before closing the round.

### API

| Call | What it does | Saved? |
|---|---|---|
| `:Register(id, round, tasks[, build])` | Set your round (replaces it) | Ticks and fails only |
| `:Add(id, area, text[, send])` | Add one task to your round | Ticks only |
| `:Park(id, area, text[, send])` | Add one task that stays until deleted | Yes |
| `:Import(markdown[, id])` | Add tasks from a markdown list (format above); `id` is the group when there's no `#` line. Returns how many were added | Yes |
| `:AddGroup(id)` | Add an empty group | Yes |
| `:Unpark(id, index)` | Delete a saved task (`index` within that id's saved tasks) and its tick | Yes |
| `:Clear(id)` | Delete everything for this id: round, saved tasks, passes, fails, snapshots, notes and its log lines | Yes |
| `:IsDone(id, text)` | Is this task ticked? | |
| `:Progress(id)` | Returns `passed, total` | |
| `:Log(id, ...)` | Add a line to the flight recorder (only while a round is open); values after the id are joined with spaces | Last 100 lines |
| `:Note(text)` | Same as `/dc note`. Returns the id it was saved under | Last 50 per round |
| `:Show()` / `:Hide()` / `:Toggle()` | The window | |
| `:Refresh()` | Redraw the window if it's open | |

A bad `id` (not a string, or empty) raises an error naming the call.

### Round files (no code)

You can also ship a round as a file instead of calling `Register`. Make
`Rounds\MyAddon.lua` inside the DevChecklist folder:

```lua
DevChecklist_Rounds = DevChecklist_Rounds or {}
DevChecklist_Rounds["MyAddon"] = {
    round = "v1.2: bag sort",
    items = {
        { "login", "No Lua errors on login.", "yes / no" },
    },
    build = "a1b2c3d",   -- optional
}
```

Then add `Rounds\MyAddon.lua` on its own line at the end of
`DevChecklist.toc`. Round files are local to your copy: this repo doesn't
ship any. A `/reload` picks up a new or changed round file and the `.toc`
line.

One file can hold several rounds (one `DevChecklist_Rounds["id"] = { ... }`
block each). If a script writes your rounds, have it keep a single file in
the `.toc` and rewrite that file, so a closed round leaves no line behind.
To close a round, remove its block and reload. [docs/workflow.md](docs/workflow.md)
walks through the whole loop.

## Look

Near-black panels, 1px black edges, the Expressway font. When
atrocityEssentials is loaded, the checklist uses its accent color and font.
