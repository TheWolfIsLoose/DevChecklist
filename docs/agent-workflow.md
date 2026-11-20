# A local Claude Code workflow for addon contributors

Optional. This is one way to work, not a rule of any repo. A project's own
`CLAUDE.md`, contributing guide and checks always win over anything here.

The idea: split each change into five small steps, give every open-ended step
a hard cap, and keep one queue file so nothing gets lost and only one thing is
in progress. Each step is a personal skill in `~/.claude/skills/`.

## The loop

| Step | Skill | Ends with | Cap |
|---|---|---|---|
| Intake | `addon-intake` | One Inbox line or queue row | One question |
| Plan | `addon-plan` | A brief of 10 lines or fewer | 8 grill questions |
| Fix (cause unknown) | `addon-fix` | A fix brief, no code | 2 probe rounds |
| Build | `addon-build` | A branch plus an in-game round that passed | 3 test rounds |
| Ship | `addon-ship` | One PR into the project's target branch | One PR per change |

Every step stops at its own end. Plan never builds, fix never builds, build
never opens a PR. A fresh session per step keeps context small and cheap.

## Why each step has a cap

- **Grill: 8 questions.** Past that, the questions are about things the
  maintainer or a playtest should decide. If the design is still open after 8,
  say what is open and park the row.
- **Diagnosis: 2 probe rounds.** A probe round is: add logging or a read-only
  check, install, play, read the result. Two rounds without a cause means the
  bug is rare; leave the logging in and wait for it to happen in normal play.
  Never ask the tester to reproduce a rare bug on purpose.
- **Testing: 3 rounds.** Three failed rounds means the plan was wrong, not the
  code. Write a handoff and send the row back to plan or fix.

Caps turn "keep going until it works" into a decision point you can see.

## One queue file

Keep a single `state.md` (in a private notes repo or outside the addon repo):

```markdown
## Focus
Row 3: bag search filters

## Queue
| # | Repo | Branch/PR | What | Size | Brief | Blocked by | State |

## Inbox
2026-01-05 | idea | tooltip shows item level | tester report
```

- **One Focus item.** Only one row is in progress.
- **Inbox.** When a new idea, bug or report comes up mid-task, the agent files
  one dated line and goes back to the Focus. No design talk on parked items.
  Triage the Inbox only when Focus is done or you ask.
- **Size** decides how much review a change gets: S = one file, known fix;
  M = a few files or one new setting; L = new module or cross-file design.

## In-game test rounds with DevChecklist

The build step writes the test round as a DevChecklist round file (see
"Round files" in the README) and installs the build. You `/reload`, tick or
fail each item in game (a fail takes a one-line note), and `/reload` again.
The agent then reads the results from the SavedVariables file instead of
asking you to paste them.

### The loop, step by step

1. **Build and check.** The agent branches off the target branch, builds,
   adds the changelog line and runs the project's checks.
2. **Install.** It copies the build into the game's AddOns folder and verifies
   the copy byte for byte against what it staged. Files it can't safely remove
   (stale leftovers) it lists for you instead of deleting.
3. **Publish the round.** One small script (have the agent write it) turns a
   markdown task list into a round file and keeps exactly one round file in
   the DevChecklist `.toc`, for example `Rounds\Active.lua`, built from one
   file per open round. A script also lets you run two rounds at once and
   close one later without leaving files behind.
4. **Test.** `/reload` (a reload picks up new files, `.toc` changes and Lua
   edits; no client restart), then `/dc`, play, tick or fail, `/reload` again.
   SavedVariables are written only on reload or logout, so the agent sees
   nothing until you do.
5. **Read the results.** The agent reads all of these, pass or fail, and
   reports each in one line even when clean:
   - ticks, fails with their notes, and any unticked items;
   - the flight recorder: the snapshot saved with each fail (time, zone,
     combat, spec, group size, build label, last log lines) and the
     `DevChecklist:Log` lines for the round;
   - errors from BugGrabber/BugSack (`!BugGrabber.lua` in SavedVariables).
     An error from a session older than the round's reload is stale; say so
     rather than chasing it.
6. **Close the round, pass or fail.** Remove its file and regenerate the
   joined file so the in-game list shows only open rounds. A follow-up round
   gets a new id.
7. **Next.** Fails and notes feed the next round (cap: 3). A pass sets the row
   to "round passed" and waits for your go before the ship step.

### Round rules

- At most 5 short items per round, one round per area. Each item is an action
  plus the expected result, with what to send back (yes/no, screenshot).
- Group content (dungeons, raids, bosses) is never on the checklist; it is
  tested by playing. Have the addon log by itself and read the log afterwards.
- While a round is open, temporary `DevChecklist:Log(id, text)` lines at the
  feature's decision points (guarded by `if DevChecklist`) give a trail when an
  item fails. Remove them before the PR.
- If you suspect the change caused a new problem, back it out first, then
  investigate.

### Traps

- **SavedVariables lag.** Nothing is written until `/reload` or logout. Ask
  for the reload before reading.
- **Windows line endings.** SavedVariables use CRLF and tab indents. Strip `\r`
  and leading whitespace before grepping, or let a small digest script do it.
- **Editing Lua byte for byte.** Some shell tools (`sed -i`, scripting
  languages with escape handling) rewrite line endings or mangle `\r\n`. Edit
  files with the agent's edit tool, run the project's checks, then commit in
  one chain.
- **Stale ticks.** Ticks follow the task text. Results for items no longer in
  the current round file are old; ignore them.
- **One round file in the `.toc`.** Don't add a `.toc` line per round;
  closed rounds would leave stale lines and files behind.
- **Rare bugs.** Don't ask the tester to reproduce one on purpose. Log, play
  normally, read the log later.
- **Verify the install.** An agent that says "installed" has not shown it;
  compare the staged files with the installed ones.

## Template skills

Save each as `~/.claude/skills/<name>/SKILL.md` and edit the paths and branch
names to fit your project.

```markdown
---
name: addon-intake
description: Use when a new bug, idea or report comes in. Classify it and file one Inbox line or queue row. No design talk.
---
1. Read `state.md` and the project's ground rules. Nothing else.
2. Classify: bug (cause known), bug-unknown, feature, question.
3. Already filed or against the rules? Say which row or why, add nothing.
4. Focus set and this does not block it: one Inbox line. Otherwise one queue
   row with every column filled, and the next step in State.
5. Reply in one line: what was filed, its size, the next skill.
```

```markdown
---
name: addon-plan
description: Use for a feature row before building. Max 8 questions, then a brief of 10 lines or fewer. Never builds.
---
1. Read the row, the project's rules and history notes for the feature, and only the code lines needed.
2. Ask at most 8 questions, one round, recommended answer first. Skip anything the
   rules or earlier decisions settle. Ask about what the player sees, not code.
3. Write `drafts/<item>.md`: goal, in/out of scope, design calls with reasons,
   where it lives, performance cost, new setting key (ships off), test round
   (5 items max), screenshots needed.
4. Set the row's State to `briefed`. Stop.
```

```markdown
---
name: addon-fix
description: Use when something is broken and the cause is unknown. Max 2 probe rounds, ends in a fix brief. Never builds the fix.
---
1. Read the error and round results from saved files (SavedVariables: the
   checklist's fails, notes and snapshots, plus BugGrabber errors); never ask
   for pastes. Ignore errors from sessions older than the last reload.
2. Probe: add logging or a read-only check, install, read the result, close
   the round. Max 2 rounds. Suspect a recent change? Back it out first.
3. Grep every caller before naming a fix location; fix at the shared point.
4. Write the brief: root cause and evidence, fix location, one test item.
5. No cause after 2 rounds: say what the logging now catches, set State to
   `waiting on repro`, stop.
```

```markdown
---
name: addon-build
description: Use to build one briefed row or known bug. Branch, checks, install, DevChecklist round, read results. Max 3 test rounds.
---
1. No brief for a feature? Stop and run addon-plan. Unknown cause? addon-fix.
2. Branch off the latest target branch. Read the code end to end first.
3. Build in the project's style, add its changelog line, run its checks.
4. Self-review against the maintainer's usual review notes before installing.
5. Install the build (verify the copy) and publish one DevChecklist round
   (5 items max, temporary `DevChecklist:Log` lines at decision points).
6. When the tester says done, read results from SavedVariables: ticks, fails
   and notes, flight recorder snapshots and log lines, BugGrabber errors.
   Report each source in one line, even when clean. Then close the round.
7. Fails feed the next round (new id). After 3 failed rounds, write a handoff
   and send the row back to plan or fix. Pass: set State to `round passed`.
   Stop. Never open a PR here.
```

```markdown
---
name: addon-ship
description: Use when a round has passed and you say go. Review by size, open one PR, update the queue.
---
1. Confirm the round passed (re-read the results) and you said go.
2. Update the branch the way the project asks (merge or rebase), run checks.
   Confirm no leftover `DevChecklist:Log` lines are in the diff.
3. Review by size: S = the usual-notes list; M = plus a full diff read;
   L = a full code review.
4. Open one PR with the project's title format and template. Drop temporary
   log lines first.
5. Move the row to Open PRs, set the next Focus, stop.
```

A weekly upkeep skill is also worth having: reconcile `state.md` with the
project's open and merged PRs, drop merged rows, and write a short recap.
