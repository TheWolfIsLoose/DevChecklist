# Dev Checklist

An in-game list of what to test, for any addon project. Each project keeps its own round of items; ticks are saved per project, so whoever wrote the round can read the results from `WTF\...\SavedVariables\DevChecklist.lua`.

## Adding items

**From your addon's code** (add `## OptionalDeps: DevChecklist` to your toc, and guard with `if DevChecklist then ... end`):

```lua
DevChecklist:Register("MyAddon", "v1.2 round", {
    { "login", "No Lua errors.", "yes / no" },          -- area, what to test, what to send back
    { area = "bags", text = "Bag opens at the bank.", send = "screenshot" },
})
DevChecklist:Add("MyAddon", "bags", "Sort button works.")      -- one more item, this session
DevChecklist:Park("MyAddon", "later", "Retest after the patch.") -- saved until removed
DevChecklist:AddGroup("Raid night")                              -- an empty saved group
```

**In the window:** the **+** in the title bar adds a group; the **+** on a group opens a row to type tasks into (Area, Task, Send; Enter adds, Esc closes). Tasks you add have an **x** to delete them; groups you made have an **x** that deletes on the second click. Everything added in the window is saved.

**Paste markdown:** **Import** in the title bar opens a paste box; paste a list and click **Import**. The tasks are added to what's already there:

- `# Name` picks the group. A round or group with that name gets the tasks; otherwise a new group is made ("Imported" if there's no heading).
- `## Name` (or deeper) sets the area for the tasks below it.
- Only checkbox lines are tasks: `- [ ]`, `* [ ]`, `+ [ ]` or `1. [ ]`. `[x]` comes in already ticked.
- Everything else (plain bullets, paragraphs) is a note and is skipped. Bold and code marks are stripped.
- Tasks already in that group are skipped, so pasting twice adds nothing.

Say in each task how to confirm it (a screenshot, yes / no, a log). Sample:

```markdown
# MyAddon

Round 3: new bag sort. Lines like this one are skipped.

## Login
- [ ] No Lua errors on login. (yes / no)
- [ ] The welcome line prints once, not on every reload.

## Bags
- [ ] Open your bags: a Sort button sits in the title bar. (screenshot)
- [ ] Click Sort twice: items don't move the second time.
- [x] Bags still open at the bank.
- Plain bullets like this one are notes, not tasks.
```

From code: `DevChecklist:Import(markdown)`.

**In chat:** `/dc add [area:] text` adds a task to a "Parked" group.

**As a file:** put `DevChecklist_Rounds["MyAddon"] = { round = "...", items = { ... } }` in `Rounds\MyAddon.lua` and list it in `DevChecklist.toc`.

## Other calls

`DevChecklist:Unpark(id, index)`, `:Clear(id)` (drops the round, parked items and ticks), `:IsDone(id, text)`, `:Progress(id)` → done, total, `:Show()`, `:Hide()`, `:Toggle()`, `:Refresh()`.

## Commands

| Command | |
|---|---|
| `/dc` | show or hide |
| `/dc add [area:] text` | park an item |
| `/dc clear <round>` | drop a round and its ticks |

The window opens at login while anything is unticked. Click an item to tick it, click a round's header to fold it.

## Look

Follows atrocityEssentials: its accent and font when it's loaded (Expressway through LibSharedMedia otherwise), near-black panels, 1px edges.
