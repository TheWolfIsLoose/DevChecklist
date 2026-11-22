# The test loop

One way to run in-game test rounds with Dev Checklist. Every step can be done
by hand or by a script or other automated tool; nothing here needs a
particular setup. `<AddOns>` is the game's `Interface\AddOns` folder and
`<SavedVariables>` is `WTF\Account\<account>\SavedVariables`.

## 1. Write a round

A round is a short named list of tasks under one id. Sort every task into
one of three kinds before writing it down:

- **If code can read it, it is a check.** The addon runs it; the tester
  never sees it unless it fails.
- **If it needs a person's judgment, it is a look.** This is the tester's
  list. Keep it short (about five), one action and its expected result per
  task.
- **If it needs a situation, it is a needs.** A group, a boss, a certain
  zone, a real key press. It stays visible, set apart, with what it needs,
  and never keeps the round from passing.

The aim is a tester's list with nothing on it that code could have answered.

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
        -- look: a plain string, { area, text }, or a table with an optional setup
        "The Sort button sits in the title bar and lines up with the title.",
        { kind = "look", text = "The sorted bag reads top to bottom, best items first.", setup = "/myaddon bags" },

        -- check: run returns ok and, optionally, the value found
        { kind = "check", text = "Sort button exists and is shown.",
          run = function() local b = MyAddonSortButton; return b ~= nil and b:IsShown() end },
        { kind = "check", text = "Sorting twice moves nothing the second time.",
          run = function() return MyAddon.lastSortMoves == 0, MyAddon.lastSortMoves end },

        -- needs: what situation it takes
        { kind = "needs", text = "Sort is greyed out during a boss fight.", needs = "a boss encounter" },
    },
}
```

```
Rounds\Active.lua
```

Notes on the three kinds:

- A check's `run` only reads state and returns. An error inside it is a
  fail with the error text as its value, so a check for something that does
  not exist yet is safe to write.
- A look's `setup` is a function or an addon's own slash command. It runs
  when the tester clicks Set Up, not before, and not in combat. It cannot
  cast, target, use an item or do anything else the game reserves for a real
  key press.
- Old rounds keep working: a task with no `kind` is a look with no setup.

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
The checks run by themselves once the world has loaded.

- **Looks:** Set Up if the task has one, then Looks Right or Something's
  Off. Either answer takes free text of any length; Something's Off also
  saves where the tester was. Capture takes a screenshot and notes the time.
- **Checked by code:** nothing to do. Failures are listed with what was
  found; Run Checks runs them again.
- **Needs a situation:** Did It, Couldn't or Skip (right click: tried it and
  it failed).
- **Add Note** (or `/dc note <text>`) saves anything else the tester
  notices, with the surroundings. **Capture Screen** (or `/dc shot`) takes a
  screenshot and prints the file name to look for.
- `/dc scale 1.4` makes the window larger on a high-resolution screen.

`/reload` once more when done.

### Limits to plan around

- Nothing leaves the game until a `/reload` or logout. That is when the game
  writes saved data, so nothing can be read before it.
- The addon cannot press protected buttons.
- Checks and Set Up wait out combat.
- A check proves state, never how something looks.

## 4. Read the results from three sources

Read all three every time, pass or fail.

1. **The checklist**: `<SavedVariables>\DevChecklist.lua`.
   - `report[id]`: round name, build, counts, the needs list with each
     answer, and `passed` (every look and check passed).
   - `check[id][task]`: `ok`, `value` and `at` for every check.
   - `done[id]` and `fail[id]`: passes, and fails with what the tester
     wrote; `remark[id]`: text added to a pass.
   - `needs[id]`: needs tasks answered `couldnt` or `skip`.
   - `notes[id]` and `shots[id]`: notes with their surroundings, and
     captures with their times. A capture's picture is a file in the game's
     `Screenshots` folder; match it by time.
2. **The flight recorder**, in the same file. `snap[id][task]` holds the
   surroundings saved when a look or needs task failed: place, combat, spec,
   level, group, screen and UI scale, client build, fps and latency, the
   frame under the mouse, the frames shown, the last Lua error and the last
   20 log lines. `log` holds the last 100 lines; the ones from
   `DevChecklist:Log` start with the time and the `[id]` tag.
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
- A check is in `check` and also in `done` or `fail`; a failed check has no
  entry in `snap`.
- Log lines carry a time but no date, and the 100 lines are shared by every
  round. `login:` and `reload:` lines mark where each session starts.
- Nothing is recorded while no round has a task waiting.

## 5. Close the round

After the results are read, pass or fail, remove the round's block from the
round file (or the file, if it was the only one) and reload. At the next
login Dev Checklist drops the closed round's ticks, fails, check results,
snapshots, notes, captures and tagged log lines, so saved data does not
grow. `/dc clear <id>` does the same from inside the game.

Fails feed the next round, under a new id. A needs task nobody could reach
goes on the next round too, or is tested by playing.
