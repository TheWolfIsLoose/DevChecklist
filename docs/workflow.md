# The test loop

One way to run in-game test rounds with Dev Checklist. Every step can be done
by hand or by a script or other automated tool; nothing here needs a
particular setup. `<AddOns>` is the game's `Interface\AddOns` folder and
`<SavedVariables>` is `WTF\Account\<account>\SavedVariables`.

## 1. Write a round

A round is a short named list of tasks under one id. Keep it small (about
five tasks), one action and its expected result per task, and say what you
want back (yes/no, a screenshot).

Pick an id that is new for every round, such as `MyAddon_Bags2` for the
second bag round. Results are saved under the id and follow the task text,
so a new id keeps a follow-up round apart from the last one.

## 2. Publish it

Write the round into a file inside the installed Dev Checklist folder and
list that file in `DevChecklist.toc`:

```lua
-- <AddOns>\DevChecklist\Rounds\Active.lua
DevChecklist_Rounds = DevChecklist_Rounds or {}
DevChecklist_Rounds["MyAddon_Bags2"] = {
    round = "Bag sort, second pass",
    build = "a1b2c3d",   -- optional: what was installed, shown in the header and saved with the results
    items = {
        { "bags", "Open your bags: a Sort button sits in the title bar. (screenshot)" },
        { "bags", "Click Sort twice: nothing moves the second time. (yes/no)" },
    },
}
```

```
Rounds\Active.lua
```

Keep one round file in the `.toc` and put every open round in it. A script
that publishes rounds should rebuild that file from the rounds still open
and check that it loads (`luajit Active.lua` with nothing else is enough)
before the tester reloads. A file that fails to load shows none of its rounds.

If the addon under test has a decision point worth a trail, add a temporary
log line there, using the round id:

```lua
if DevChecklist then DevChecklist:Log("MyAddon_Bags2", "sort clicked", itemCount) end
```

Take these lines out again when the round is closed.

## 3. Play it

`/reload` picks up the round file, the `.toc` line and any changed Lua. The
window opens by itself while a task is unticked (`/dc` shows or hides it).

- Left click a task to pass it.
- Right click to fail it, then type a one-line note and press Enter.
- `/dc note <text>` saves an observation that is not about one task.

`/reload` once more when done. The game writes saved data only on reload and
logout, so nothing can be read before that.

## 4. Read the results from three sources

Read all three every time, pass or fail.

1. **The checklist**: `<SavedVariables>\DevChecklist.lua`. Passes are in
   `done[id]`, fails with their notes in `fail[id]`, quick notes in
   `notes[id]`, and a summary (round name, build, counts) in `report[id]`.
2. **The flight recorder**, in the same file. `snap[id][task]` is the
   snapshot taken when a task failed: time, zone, combat, spec, group size,
   build and the last 20 log lines. `log` holds the last 100 lines; the ones
   from `DevChecklist:Log` start with the time and the `[id]` tag.
3. **Lua errors**, from an error catcher if one is installed. With
   BugGrabber that is `<SavedVariables>\!BugGrabber.lua`; while a round is
   open its errors are also copied into the flight recorder as `error:`
   lines. An error from a session before the round's reload is old.

`tools/results.lua` prints the first two for one round:

```
luajit tools/results.lua "<SavedVariables>/DevChecklist.lua" MyAddon_Bags2
```

Things that trip up a reader:

- The file uses Windows line endings and tab indents. Load it as Lua, or
  strip `\r` and leading whitespace before matching text.
- Passes and fails follow the task text. Entries for a task that is no
  longer in the round are old.
- Log lines carry a time but no date, and the 100 lines are shared by every
  round. `login:` and `reload:` lines mark where each session starts.
- Nothing is recorded while no round has an unpassed task.

## 5. Close the round

After the results are read, pass or fail, remove the round's block from the
round file (or the file, if it was the only one) and reload. At the next
login Dev Checklist drops the closed round's ticks, fails, snapshots, notes
and tagged log lines, so saved data does not grow. `/dc clear <id>` does the
same from inside the game.

Fails feed the next round, under a new id.
