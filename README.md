# Dev Checklist

An in-game checklist of what to test. A tester ticks tasks off as they play,
and the ticks are saved, so whoever wrote the tasks can read the results
afterwards. Any number of addons can use it at once without touching each
other's lists.

- [Using the checklist](#using-the-checklist)
- [For addon authors](#for-addon-authors)

## Using the checklist

Type `/dc` to show or hide the window. It also opens by itself at login
while anything is unticked.

- **Tick a task:** click it. Click again to untick.
- **Fold a group:** click its header. The header shows how many tasks are
  done (`3/8`). A group folds by itself once everything in it is ticked.
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
Checklist's saved data is ready.

### 2. Give the tester a round of tasks

```lua
if DevChecklist then
    DevChecklist:Register("MyAddon", "v1.2: bag sort", {
        { "login", "No Lua errors on login.", "yes / no" },
        { "bags",  "Open your bags: a Sort button shows.", "screenshot" },
        { area = "bags", text = "Click Sort twice: nothing moves the second time." },
    })
end
```

- The first argument is your **id**: one group in the window, and the key for
  your ticks. Use your addon's name. Ids are case-sensitive.
- The second is the **round name**, shown next to the id.
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
    parked = { ... }, groups = { ... },   -- tasks and groups added in game
}
```

### API

| Call | What it does | Saved? |
|---|---|---|
| `:Register(id, round, tasks)` | Set your round (replaces it) | Ticks only |
| `:Add(id, area, text[, send])` | Add one task to your round | Ticks only |
| `:Park(id, area, text[, send])` | Add one task that stays until deleted | Yes |
| `:Import(markdown[, id])` | Add tasks from a markdown list (format above); `id` is the group when there's no `#` line. Returns how many were added | Yes |
| `:AddGroup(id)` | Add an empty group | Yes |
| `:Unpark(id, index)` | Delete a saved task (`index` within that id's saved tasks) and its tick | Yes |
| `:Clear(id)` | Delete everything for this id: round, saved tasks, ticks | Yes |
| `:IsDone(id, text)` | Is this task ticked? | |
| `:Progress(id)` | Returns `done, total` | |
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
}
```

Then add `Rounds\MyAddon.lua` on its own line at the end of
`DevChecklist.toc`. Round files are local to your copy: this repo doesn't
ship any.

## Look

Near-black panels, 1px black edges, the Expressway font. When
atrocityEssentials is loaded, the checklist uses its accent color and font.
