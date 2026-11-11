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

**Paste markdown:** **Import** in the title bar opens a paste box. `# Name` starts a group (an existing round or group with that name gets the tasks), `## Name` sets the area, and `-`, `*`, `+` or `1.` lines become tasks. `[x]` comes in ticked. Tasks already in that group are skipped, so pasting twice is harmless. From code: `DevChecklist:Import(markdown)`.

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
