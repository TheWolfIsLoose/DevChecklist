# Dev Checklist

An in-game checklist of what to test, and a helper for the person testing.
The list a tester sees holds only what needs a person's eyes and feel. What
code can read, the addon checks by itself. Edge cases that need a certain
situation stay on the list, set apart, so nobody wonders why they cannot be
tested right now. Whatever the tester notices is saved together with where
they were, so whoever wrote the tasks can read it afterwards. Any number of
addons can use it at once without touching each other's lists.

- [Using the checklist](#using-the-checklist)
- [What it cannot do](#what-it-cannot-do)
- [For addon authors](#for-addon-authors)
- [The test loop, start to finish](docs/workflow.md)

## Using the checklist

Type `/dc` to show or hide the window. It also opens by itself at login
while anything is unticked.

Each round shows its tasks in three parts:

1. **Your part** (no heading): things to look at and judge.
   - **Set Up** (when the task has one) puts the game in the right state for
     you, for example by opening a panel. It does not run in combat.
   - **Looks Right** passes the task. A box opens in case you want to add
     something; Esc skips it.
   - **Something's Off** fails it and opens a box: say what is off, as long
     as you like (Enter saves, Shift+Enter starts a new line). Where you
     were is saved with it.
   - **Capture** takes a screenshot and notes the time next to the task.
   - Shortcuts: left click the task to pass it (again to clear), right click
     to fail it (again to clear). A pass and a fail replace each other.
2. **Checked by code**: tests the addon runs by itself, after every reload
   and when you click **Run Checks**. One line when they all pass; otherwise
   the ones that do not, with what was found. Nothing to click.
3. **Needs a situation**: things the addon cannot test because they need a
   certain state, such as a full group or a key press. Each says what it
   needs. Answer **Did It** when you got to try it and it worked, right click
   it when you tried and it failed, **Couldn't** when you had no way to get
   there, or **Skip**. These never keep a round from counting as passed.

Above the rounds: **Run Checks**, **Note** (free text about anything, saved
with where you were), **Capture**, and **?** (shows or hides the limits
below).

- **Fold a group:** click its header. The header shows how many tasks are
  passed (`3/8`, plus a red count of fails). A group folds by itself once
  nothing in it is waiting for an answer.
- **Move the window:** drag the title bar. It remembers where you left it.

## What it cannot do

The window says this too (the **?** button folds it away).

- **Nothing leaves the game until you `/reload` or log out.** That is when
  the game writes saved data. Whoever reads your results sees nothing
  before that.
- **It cannot press protected buttons.** Casting, targeting, using items
  and anything else the game reserves for a real key press or click stay
  yours to do. Set Up can run a function or an addon's own slash command,
  nothing more.
- **Checks and Set Up wait out combat.** Checks asked for in combat run when
  it ends; Set Up asks you to try again after the fight.
- **A check proves state, never how something looks.** "The frame is shown
  and 300 wide" can be checked. "It looks right" needs you.

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
| `/dc note text` | Save free text, with where you were, on the open round. With no round open it goes to a "General" list and says so |
| `/dc shot` | Take a screenshot and note the time on the open round |
| `/dc run` | Run the checks now |
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
- Each task is a string, `{ area, text, send }` or `{ area =, text =, send = }`.
  `area` groups tasks under a small heading, `text` is the task, and `send`
  (optional) is shown in grey after it: what you want back.
- `Register` replaces your whole round. The list itself isn't saved (your
  code registers it again every load), but **ticks are**, and they follow the
  task text. Change a task's text and it comes back unticked.

#### Three kinds of task

A task written as above is a **look**. A table task can say what kind it is:

```lua
DevChecklist:Register("MyAddon", "v1.2: bag sort", {
    -- look: a person judges it. setup is optional: a function, or an addon's own slash command.
    { kind = "look", text = "The Sort button lines up with the title.", setup = "/myaddon bags" },

    -- check: code decides it. run returns ok and, if you like, the value it found.
    { kind = "check", text = "Sort button exists and is shown.",
      run = function() local b = MyAddonSortButton; return b ~= nil and b:IsShown(), b and b:GetWidth() end },

    -- needs: it takes a situation the addon cannot make. needs says which.
    { kind = "needs", text = "Sort is greyed out during a boss fight.", needs = "a boss encounter" },
}, "a1b2c3d")
```

Which kind?

- **If code can read it, it is a check.** A setting's value, whether a frame
  exists, is shown, where it is anchored, how many rows a list has.
- **If it needs a person's judgment, it is a look.** Whether it lines up,
  reads well, feels right, is the right color.
- **If it needs a situation, it is a needs.** A group, a raid, a boss, a
  certain zone, an item you may not own, a real key press.

How each one behaves:

- **check:** `run` is called with no arguments, guarded: an error is a fail
  whose value is the error text. The first return value decides pass or
  fail; the second is saved as text (cut to 200 characters). Checks run once
  after each login or reload when the world has loaded, and when the tester
  clicks **Run Checks** or types `/dc run`. Never in combat, never on a
  timer. Keep `run` to reading state: it must not change anything.
- **look:** `setup` runs only when the tester clicks **Set Up**, guarded, and
  not in combat. A string is looked up among addon slash commands and called
  with the rest of the line; the game's own secure commands (`/cast`,
  `/target` and so on) cannot be run this way. With no `setup` there is no
  button.
- **needs:** shown under "Needs a situation" with the `needs` text. It is
  left out of the round's pass count and never keeps the round from reading
  as passed.

Functions cannot be saved, so `check` and `setup` tasks come from `Register`
or a round file, not from `Park`, `Import` or the window.

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
    remark = { ["MyAddon"] = { ["No Lua errors on login."] = "clean on two characters" } },   -- text added to a pass
    check = { ["MyAddon"] = { ["Sort button exists and is shown."] = {      -- every check task, each run replaces it
        ok = true, value = "24", at = "2026-11-17 21:02:41" } },
    },
    needs = { ["MyAddon"] = { ["Sort is greyed out during a boss fight."] = "couldnt" } },   -- "couldnt" or "skip"
    report = { ["MyAddon"] = {            -- summary, rewritten on every reload and logout
        round = "v1.2: bag sort", build = "a1b2c3d",
        pass = 2, open = 0,               -- looks and checks only
        fail = { { text = "Open your bags: a Sort button shows.", note = "button missing at 1080p", kind = "look" } },
        needs = { { text = "Sort is greyed out during a boss fight.", needs = "a boss encounter",
            answer = "couldnt" } },       -- "pass", "fail" (with note), "couldnt", "skip" or "open"
        passed = false,                   -- true when every look and check passed; needs tasks do not count
    } },
    snap = { ["MyAddon"] = { ["Open your bags: a Sort button shows."] = {   -- surroundings, taken when the task failed
        at = "2026-11-17 21:04:12", round = "MyAddon", task = "Open your bags: a Sort button shows.",
        zone = "Dornogal", subzone = "The Stalls", combat = "no", spec = "Fire", level = 80,
        group = 0, groupType = "solo", screen = "3840x2160", uiScale = "0.533", client = "12.0.0 (12345)",
        fps = 60, latency = "20 / 30 ms", mouse = "ContainerFrame1", build = "a1b2c3d",
        frames = { "ChatFrame1", "ContainerFrame1" },                       -- shown, named top-level frames (first 40)
        error = "21:03:58 MyAddon/Bags.lua:12: attempt to index a nil value",   -- last Lua error heard, if any
        log = { "21:02:40 reload: Dornogal", "21:03:55 [MyAddon] bags opened" },   -- last 20 log lines
        -- instance = "name / type / difficulty" when inside one
    } } },
    notes = { ["MyAddon"] = { {           -- from /dc note and the Note box: the same surroundings plus text
        text = "bars flicker at the bank", at = "2026-11-17 21:05:30", round = "MyAddon", zone = "Dornogal", ... } } },
    shots = { ["MyAddon"] = { {           -- from Capture and /dc shot
        at = "2026-11-17 21:06:02", task = "Open your bags: a Sort button shows.", result = "saved" } } },
    log = { "21:02:40 reload: Dornogal", "21:03:10 combat in", ... },   -- flight recorder, last 100 lines
    parked = { ... }, groups = { ... },   -- tasks and groups added in game
}
```

A check that passes is also in `done`; one that fails is also in `fail`,
with its value as the note (and no entry in `snap`). A needs task answered
Did It is in `done`, and one that was tried and failed is in `fail`. A
surroundings field is left out when the game could not supply it.

A capture's `result` is `saved` or `failed` as the game reported it, or
`asked` if the game never answered. The picture itself is a file in the
game's `Screenshots` folder; match it by `at`.

The file is plain Lua, so a script can load it instead of searching the
text. `tools/results.lua` in this repo prints one round (looks with their
answers, text and surroundings, checks with their values, the needs list,
notes, captures, and the round's log lines):

```
luajit tools/results.lua "<path>/SavedVariables/DevChecklist.lua" MyAddon
```

The game writes the file only on `/reload` and logout, so reload before
reading. `report` is rewritten at the same moment and lists only rounds that
were loaded then. Passes and fails are keyed by task text; results for a
task that is no longer in the round are old.

### 5. Flight recorder

While a round from `Register`, `Add` or a round file has a task still
waiting (not passed, and not a needs task answered Couldn't or Skip), Dev
Checklist keeps a short log: login and reload, zone changes,
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

When the tester fails a look or a needs task, the surroundings are saved
with it in `snap`: round and task, time, zone and subzone, instance,
combat, spec, level, group size and type, screen size and UI scale, client
build, fps and latency, the named frame under the mouse, the shown named
top-level frames, the last Lua error heard, your build label and the last
20 log lines. Every read is guarded and capped, only reads are made, and
frames the game forbids are skipped. Passing or clearing the task drops it.
With no round open, nothing is recorded and no events are watched.

A note (`/dc note` or the Note box) saves the same surroundings plus the
text in `notes`, on the open round: the one last ticked or failed when
several are open, or a list called "General" when none is. A note can be up
to 4000 characters, and the last 50 notes per round are kept. A capture is
saved the same way in `shots` (last 30 per round).

Saved data stays small: when a round is closed (its file removed, or
`/dc clear`), its ticks, fails, check results, snapshots, notes, captures
and tagged log lines are dropped at the next login. Read the results before
closing the round.

### API

| Call | What it does | Saved? |
|---|---|---|
| `:Register(id, round, tasks[, build])` | Set your round (replaces it) | Ticks and fails only |
| `:Add(id, area, text[, send])` | Add one task to your round | Ticks only |
| `:Park(id, area, text[, send])` | Add one task that stays until deleted | Yes |
| `:Import(markdown[, id])` | Add tasks from a markdown list (format above); `id` is the group when there's no `#` line. Returns how many were added | Yes |
| `:AddGroup(id)` | Add an empty group | Yes |
| `:Unpark(id, index)` | Delete a saved task (`index` within that id's saved tasks) and its tick | Yes |
| `:Clear(id)` | Delete everything for this id: round, saved tasks, passes, fails, check results, snapshots, notes, captures and its log lines | Yes |
| `:IsDone(id, text)` | Is this task ticked? | |
| `:Progress(id)` | Returns `passed, total` (needs tasks are not counted) | |
| `:RunChecks()` | Run every check task now. Returns how many ran and how many failed, or nothing in combat (they run when it ends) | Latest result per check |
| `:Capture([id[, task]])` | Take a screenshot and save the time (and task) under `id`, or the open round. Returns the id and the time | Last 30 per round |
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
        "The welcome line reads well.",
        { kind = "check", text = "The saved setting is on.", run = function() return MyAddonDB and MyAddonDB.sort == true end },
        { kind = "needs", text = "Sort works at a guild bank.", needs = "guild bank access" },
    },
    build = "a1b2c3d",   -- optional
}
```

A round file is Lua, so it can hold the same task kinds as `Register`,
functions included.

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
