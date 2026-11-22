-- Offline smoke test for DevChecklist with stubbed WoW API.
-- Run from the repo root: luajit dev/smoke.lua .   (must print SMOKE OK; luajit is Lua 5.1, like the game)
-- With a saved file as the second argument (luajit dev/smoke.lua . path/to/SavedVariables/DevChecklist.lua)
-- it only checks that the file loads, logs in and logs out cleanly, and prints SAVED DATA OK. The file is not changed.
local dir = arg[1] or "."
local handlers = {}
local function Dummy()
  local o = {}
  local num = { GetStringHeight=14, GetEffectiveScale=1, GetHeight=600, GetVerticalScroll=0 }
  setmetatable(o, { __index = function(t, k)
    if num[k] then return function() return num[k] end end
    if not k:match("^%u") then return nil end
    if k == "IsShown" then return function(s) return s._shown end end
    if k == "Show" then return function(s) s._shown = true end end
    if k == "Hide" then return function(s) s._shown = false end end
    if k == "SetShown" then return function(s, v) s._shown = v end end
    if k == "SetScript" or k == "HookScript" then return function(s, n, f) s["_"..n] = f; if n=="OnEvent" then handlers[#handlers+1]=f end end end
    if k == "GetText" then return function(s) return s._text end end
    if k == "SetText" then return function(s, v) s._text = v end end
    if k == "GetPoint" then return function() return "TOPLEFT", nil, "TOPLEFT", 1, 2 end end
    if k:match("^Create") then return function(self) local d = Dummy(); d._parent = self; KIDS[#KIDS+1] = d; return d end end
    return function() end
  end })
  return o
end
ALL = {}
KIDS = {}
CreateFrame = function(t, n, parent) local d = Dummy(); d._type, d._name, d._parent = t, n, parent; ALL[#ALL+1] = d; return d end
UIParent = Dummy()
PixelUtil = { GetNearestPixelSize = function() return 1 end }
Mixin = function(o) return o end
BackdropTemplateMixin = {}
STANDARD_TEXT_FONT = "font"
GameTooltip = Dummy()
local now = 100
GetTime = function() return now end
local timers = {}
C_Timer = { After = function(_, f) timers[#timers+1] = f end }
SlashCmdList = {}
date = os.date
local zone, inCombat = "Dornogal", false
GetRealZoneText = function() return zone end
GetInstanceInfo = function() return "Dornogal", "none", 0, "" end
InCombatLockdown = function() return inCombat end
GetSpecialization = function() return 2 end
GetSpecializationInfo = function(i) return 63, "Fire" end
GetNumGroupMembers = function() return 0 end
-- the rest of what a fail or note reads about the surroundings
GetSubZoneText = function() return "The Stalls" end
UnitLevel = function() return 80 end
IsInRaid = function() return false end
IsInGroup = function() return false end
GetPhysicalScreenSize = function() return 3840, 2160 end
GetBuildInfo = function() return "12.0.0", "12345" end
GetFramerate = function() return 59.6 end
GetNetStats = function() return 1, 2, 20, 30 end
local function Named(name, shown, forbidden, strata)
  return { IsForbidden = function() return forbidden end, IsShown = function() return shown end, GetName = function() return name end,
    GetFrameStrata = function() return strata or "MEDIUM" end }
end
GetMouseFoci = function() return { Named("MouseFrameName", true) } end
rawset(UIParent, "GetChildren", function()
  return Named("MinimapCluster", true), Named("ShownOne", true), Named("HiddenOne", false), Named("Locked", true, true), Named(nil, true),
    Named("ShownTwo", true), Named("ShownOne", true), Named("DevChecklistFrame", true), Named("DialogOne", true, false, "DIALOG")
end)
local shiftDown, shots = false, 0
IsShiftKeyDown = function() return shiftDown end
Screenshot = function() shots = shots + 1 end
-- an error catcher that announces errors by id through the game's event registry
local bugCb
EventRegistry = {
  RegisterCallback = function(_, name, fn, owner) if name == "BugGrabber.BugGrabbed" then bugCb = function(id) fn(owner, id) end end end,
  UnregisterCallback = function(_, name) if name == "BugGrabber.BugGrabbed" then bugCb = nil end end,
}
BugGrabber = { GetErrorByID = function(_, id) return id == "table: 1" and { message = "boom in\nFile.lua:1" } or nil end }
local printed = {}
print = function(s) printed[#printed+1] = s end

assert(loadfile(dir.."/DevChecklist.lua"))("DevChecklist")
-- a round file, as one would sit in Rounds/
DevChecklist_Rounds.Demo = { round = "r1", items = { { "login", "No Lua errors.", "yes / no" }, { "bags", "Bag opens.", "screenshot" } } }
local DC = DevChecklist
if arg[2] then
  dofile(arg[2])
  assert(type(DevChecklistDB) == "table", "the file sets DevChecklistDB")
  DevChecklist_Rounds.Demo.items[3] = { kind = "check", text = "Saved data is a table.", run = function() return type(DevChecklistDB) == "table", type(DevChecklistDB) end }
  DevChecklist_Rounds.Demo.items[4] = { kind = "needs", text = "Works in a raid.", needs = "a raid group" }
  handlers[1](nil, "ADDON_LOADED", "DevChecklist")
  handlers[1](nil, "PLAYER_LOGIN")
  handlers[1](nil, "PLAYER_ENTERING_WORLD", false, true)
  assert(DevChecklistDB.check.Demo["Saved data is a table."].ok == true, "check ran after the reload")
  DC:Show()
  DC:Log("Demo", "after login")
  handlers[1](nil, "PLAYER_LOGOUT")
  local sv = DevChecklistDB
  for _, k in ipairs({ "done", "fail", "snap", "notes", "log", "parked", "groups", "collapsed", "report", "check", "needs", "remark", "shots" }) do
    assert(type(sv[k]) == "table", "DevChecklistDB." .. k .. " is a table")
  end
  assert(sv.v == 2 and #sv.log <= 100 and sv.log[#sv.log]:find("[Demo] after login", 1, true), "version, log cap, recording")
  assert(sv.report.Demo and sv.report.Demo.open == 2 and sv.report.Demo.pass == 1 and #sv.report.Demo.needs == 1, "report written for the loaded round")
  io.write("SAVED DATA OK\n")
  return
end
-- before saved data: Park queues
DC:Park("Early", "a", "Queued item")
DC:AddGroup("EarlyGroup")
assert(DC:Import("# EarlyImport\n- [ ] Queued import.") == 0, "import before load reports 0")
-- old v1 saved data
DevChecklistDB = { done = { ["No Lua errors."] = true, ["Not a current item"] = true }, collapsed = {}, point = {"TOPLEFT","TOPLEFT",5,5} }
local fire = handlers[1]
fire(nil, "ADDON_LOADED", "Other")
fire(nil, "ADDON_LOADED", "DevChecklist")
DC:Log("Demo", "sent while loading")
assert(DevChecklistDB.log[1]:find("[Demo] sent while loading", 1, true), "Log is kept before login when a round file is loaded")
fire(nil, "PLAYER_LOGIN")
local db = DevChecklistDB
assert(db.v == 2, "migrated")
assert(db.done.Demo and db.done.Demo["No Lua errors."], "tick moved")
assert(db.done["Not a current item"] == nil, "stale flat tick dropped")
assert(db.parked.Early and #db.parked.Early == 1, "queued park flushed")
assert(db.groups.EarlyGroup and db.parked.EarlyImport and #db.parked.EarlyImport == 1, "queued group and import flushed")
local d, t = DC:Progress("Demo"); assert(d == 1 and t == 2, "progress "..d.."/"..t)
-- API
DC:Register("MyAddon", "r1", { {"login","A","yes / no"}, {area="bags", text="B"}, {"x", ""} })
DC:Add("MyAddon", "bags", "C")
d, t = DC:Progress("MyAddon"); assert(t == 3, "register/add total "..t)
assert(not pcall(DC.Register, DC, nil), "bad id errors")
-- slash
SlashCmdList.DEVCHECKLIST("add login: Check thing")
SlashCmdList.DEVCHECKLIST("add plain text")
assert(#db.parked.Parked == 2 and db.parked.Parked[1][1] == "login" and db.parked.Parked[2][2] == "plain text", "slash add")
DC:Unpark("Parked", 1); assert(#db.parked.Parked == 1 and db.parked.Parked[1][2] == "plain text", "unpark")
SlashCmdList.DEVCHECKLIST("clear MyAddon"); assert(select(2, DC:Progress("MyAddon")) == 0, "clear")
SlashCmdList.DEVCHECKLIST("help")
DC:Toggle(); DC:Toggle(); DC:Show()
assert(DC:IsDone("Demo", "No Lua errors."))
-- click every button built so far once (rows tick, headers fold, x unparks)
DC:Park("P", "a", "parked one")
local snap = {}; for i, f in ipairs(ALL) do snap[i] = f end
for _, f in ipairs(snap) do if f._OnClick then f._OnClick(f) end; if f._OnEnter then f._OnEnter(f); f._OnLeave(f) end end
for _, f in ipairs(snap) do if f._OnMouseWheel then f._OnMouseWheel(f, -1) end; if f._OnDragStop then f._OnDragStop(f) end end
-- GUI editing, through the real handlers
local function Newest(pred) for i = #ALL, 1, -1 do if pred(ALL[i]) then return ALL[i] end end end
DC:Show()
local frameObj = Newest(function(f) return f._name == "DevChecklistFrame" end)
local headObj = Newest(function(f) return f._parent == frameObj and f._type == "Frame" end)
local btns = {}
for _, f in ipairs(ALL) do if f._parent == headObj and f._type == "Button" then btns[#btns+1] = f end end
assert(#btns == 3, "close, + and Import in the title bar")
btns[2]._OnClick(btns[2])                                         -- + New Group
local name = Newest(function(f) return f._type == "EditBox" end)
name._text = "  Raid night "; name._OnEnterPressed(name)          -- Enter
assert(db.groups["Raid night"], "group saved, trimmed")
local task = Newest(function(f) return f._type == "EditBox" and f._OnTabPressed end)
assert(task, "task form opened for the new group")
-- the three boxes: area, task, send (in creation order)
local boxes = {}
for _, f in ipairs(ALL) do if f._type == "EditBox" and f._OnTabPressed then boxes[#boxes+1] = f end end
local area, tbox, send = boxes[#boxes-2], boxes[#boxes-1], boxes[#boxes]
tbox._text = ""; tbox._OnEnterPressed(tbox)
assert(not db.parked["Raid night"], "empty task not added")
area._text = "pull"; tbox._text = "Boss mods load"; send._text = "log"; send._OnEnterPressed(send)
local p = db.parked["Raid night"]
assert(p and #p == 1 and p[1][1] == "pull" and p[1][2] == "Boss mods load" and p[1][3] == "log", "task added from form")
local area2 = Newest(function(f) return f._type == "EditBox" and f._OnTabPressed end)
assert(area2, "form reopened")
-- delete: first click arms, second deletes
send._OnEscapePressed(send)
local function Header(id)
  for i = #KIDS, 1, -1 do local fs = KIDS[i]
    if type(fs._text) == "string" and fs._text:find(id, 1, true) and fs._parent._type == "Button" then return fs._parent end end
end
local function GroupX(id)
  local h = Header(id); local found
  for _, f in ipairs(ALL) do if f._parent == h and f._type == "Button" then found = found or f end end
  return found                                                    -- x is created before +
end
local x = GroupX("Raid night"); x._OnClick(x)
assert(db.groups["Raid night"], "first click only arms")
x = GroupX("Raid night"); x._OnClick(x)
assert(not db.groups["Raid night"] and not db.parked["Raid night"], "second click deletes")
-- arming lapses after 3 s
DC:AddGroup("Temp")
x = GroupX("Temp"); x._OnClick(x); now = now + 5
for _, f in ipairs(timers) do f() end
x = GroupX("Temp"); x._OnClick(x)
assert(db.groups.Temp, "lapsed arm: one click doesn't delete")
-- markdown import
local md = table.concat({
  "Intro line, ignored.", "# Demo", "## login", "- [ ] No Lua errors.", "- [x] **Login** sound plays.",
  "- A plain note, skipped.", "## bags", "* [ ] Bag `opens` fast.", "1. [ ] Sort works.", "  2) [X] Nested numbered.",
  "---", "#", "### deep", "+ [ ] Deep item.", "# Fresh group", "- [ ] First fresh.", "-[ ] not a list", "- [ ]", "1. Numbered note.",
}, "\r\n")
local items = DC.ParseMarkdown(md)
assert(#items == 7, "parsed "..#items)
assert(items[1].id == "Demo" and items[1].area == "login" and items[1].text == "No Lua errors." and not items[1].done, "item 1")
assert(items[2].text == "Login sound plays." and items[2].done, "ticked + bold")
assert(items[3].text == "Bag opens fast." and items[3].area == "bags", "code marks")
assert(items[5].text == "Nested numbered." and items[5].done, "nested numbered, [X]")
assert(items[6].area == "deep" and items[6].id == "Demo", "### sets area, bare # ignored")
assert(items[7].id == "Fresh group" and items[7].area == "", "new group resets area")
assert(DC.ParseMarkdown("- [ ] x")[1].id == "Imported" and #DC.ParseMarkdown("- x") == 0, "default group, plain bullets skipped")
local before = select(2, DC:Progress("Demo"))
local n = DC:Import(md)
assert(n == 6, "imported "..n)                          -- "No Lua errors." already in Demo's round
assert(select(2, DC:Progress("Demo")) == before + 5, "appended to existing round")
assert(DC:IsDone("Demo", "Login sound plays."), "[x] ticked")
assert(db.collapsed.Demo == false and db.collapsed["Fresh group"] == false, "unfolded")
assert(DC:Import(md) == 0, "re-import adds nothing")
-- through the window: Import button, paste, Import
btns[3]._OnClick(btns[3])
local paste = Newest(function(f) return f._type == "EditBox" and not f._OnTabPressed end)
paste._text = "# Window\n- [ ] From the box."; paste._OnTextChanged(paste)
local go
for i = #KIDS, 1, -1 do local fs = KIDS[i]; if fs._text == "Import" and fs._parent._parent == paste._parent then go = fs._parent; break end end
go._OnClick(go)
assert(db.parked.Window and db.parked.Window[1][2] == "From the box.", "window import")
btns[3]._OnClick(btns[3]); paste = Newest(function(f) return f._type == "EditBox" and not f._OnTabPressed end)
paste._OnEscapePressed(paste)
-- pass / fail / note / build / report
do
  DC:Register("PF", "r1", { {"a", "Item A"}, {"a", "Item B"}, {"b", "Item C"} }, "abc1234")
  assert(DevChecklist_Rounds.PF.build == "abc1234", "build kept")
  local function Row(text)
    for i = #KIDS, 1, -1 do local fs = KIDS[i]
      if type(fs._text) == "string" and fs._text:find(text, 1, true) and fs._parent._type == "Button" and fs._parent._OnClick then return fs._parent end end
  end
  DC:Show()
  Row("Item A")._OnClick(Row("Item A"), "LeftButton")
  assert(db.done.PF["Item A"] and not db.fail.PF, "left click passes")
  Row("Item B")._OnClick(Row("Item B"), "RightButton")
  assert(db.fail.PF and db.fail.PF["Item B"] == "", "right click fails")
  local note = Newest(function(f) return f._type == "EditBox" and f._OnEnterPressed and not f._OnTabPressed end)
  note._text = "  bars overlap  "; note._OnEnterPressed(note)
  assert(db.fail.PF["Item B"] == "bars overlap", "note saved, trimmed")
  Row("Item B")._OnClick(Row("Item B"), "LeftButton")
  assert(db.done.PF["Item B"] and not db.fail.PF, "pass clears the fail")
  Row("Item B")._OnClick(Row("Item B"), "RightButton")
  assert(db.fail.PF["Item B"] == "" and not db.done.PF["Item B"], "fail clears the pass")
  Row("Item B")._OnClick(Row("Item B"), "RightButton")
  assert(not db.fail.PF, "right click again clears the fail")
  Row("Item C")._OnClick(Row("Item C"), "RightButton")
  note = Newest(function(f) return f._type == "EditBox" and f._OnEnterPressed and not f._OnTabPressed end)
  note._text = "wrong sound"; note._OnEnterPressed(note)
  -- left click while the note box is still open (no Enter): fail clears, box goes
  Row("Item B")._OnClick(Row("Item B"), "RightButton")
  assert(db.fail.PF["Item B"] == "", "failed again")
  local nAll = #ALL
  Row("Item B")._OnClick(Row("Item B"), "LeftButton")
  assert(db.done.PF["Item B"] and not db.fail.PF["Item B"], "left click with the note box open passes")
  for i = nAll + 1, #ALL do assert(ALL[i]._type ~= "EditBox", "note box closed after the left click") end
  Row("Item B")._OnClick(Row("Item B"), "LeftButton")      -- clear it again; the report below expects Item B open
  -- flight recorder: events and Log lines while a round is open, snapshot on fail
  local recEv = handlers[1] == fire and handlers[2] or handlers[1]
  assert(recEv ~= fire, "recorder has its own event frame")
  recEv(nil, "PLAYER_ENTERING_WORLD", false, true)
  recEv(nil, "PLAYER_REGEN_DISABLED"); inCombat = true
  DC:Log("PF", "bags opened")
  assert(db.log[#db.log]:find("[PF] bags opened", 1, true) and db.log[#db.log - 2]:find("reload: Dornogal", 1, true), "events logged")
  for i = 1, 130 do DC:Log("PF", "spam " .. i) end
  assert(#db.log == 100 and db.log[100]:find("spam 130", 1, true), "log trimmed to 100")
  Row("Item A")._OnClick(Row("Item A"), "RightButton")
  local s = db.snap.PF["Item A"]
  assert(s and s.zone == "Dornogal" and s.combat == "yes" and s.spec == "Fire" and s.group == 0 and s.build == "abc1234", "snapshot fields")
  assert(#s.log == 20 and s.log[20]:find("spam 130", 1, true), "snapshot has the last 20 lines")
  note = Newest(function(f) return f._type == "EditBox" and f._OnEnterPressed and not f._OnTabPressed end)
  DC:Log("PF", "later line"); note._text = "late note"; note._OnEnterPressed(note)
  assert(db.snap.PF["Item A"] == s and db.fail.PF["Item A"] == "late note", "note keeps the first snapshot")
  Row("Item A")._OnClick(Row("Item A"), "LeftButton")
  assert(not db.snap.PF["Item A"] and db.done.PF["Item A"], "pass drops the snapshot")
  assert(db.snap.PF["Item C"], "Item C kept its snapshot")
  zone = ""; local inst = { "Murder Row", "scenario", 0, "" }
  local oldInfo = GetInstanceInfo; GetInstanceInfo = function() return unpack(inst) end
  recEv(nil, "PLAYER_ENTERING_WORLD", true, false)
  assert(db.log[#db.log]:find("login: Murder Row (Murder Row, scenario)", 1, true), "empty zone and difficulty filled: " .. db.log[#db.log])
  GetInstanceInfo, zone = oldInfo, "Dornogal"
  handlers[1](nil, "PLAYER_LOGOUT")
  local rep = db.report.PF
  assert(rep.round == "r1" and rep.build == "abc1234" and rep.pass == 1 and rep.open == 1 and #rep.fail == 1, "report counts")
  assert(rep.fail[1].text == "Item C" and rep.fail[1].note == "wrong sound", "report fail entry")
  assert(select(1, DC:Progress("PF")) == 1, "fails are not passes")
  DC:Clear("PF"); assert(not db.fail.PF and not db.snap.PF, "clear drops fails and snapshots")
  -- no round with an unpassed task: nothing is recorded
  for id in pairs(DevChecklist_Rounds) do DC:Clear(id) end
  local n = #db.log
  DC:Log("PF", "after clear")
  assert(#db.log == n, "log stops when no round is open")
  DC:Register("Again", "r2", { {"a", "One"} })
  DC:Log("Again", "back on")
  assert(db.log[#db.log]:find("back on", 1, true), "recording resumes with a new round")
  -- a round closed from outside leaves its saved ticks behind; the next login drops them, not live ones
  db.done.OLD, db.fail.OLD, db.snap.OLD, db.collapsed.OLD = { ["x"] = true }, { ["y"] = "n" }, { ["y"] = {} }, { x = true }
  db.collapsed.Again = false
  db.log[#db.log + 1] = "09:00:00 [OLD] stale line"; db.log[#db.log + 1] = "09:00:01 [Again] live line"; db.log[#db.log + 1] = "09:00:02 zone: Dornogal"
  handlers[1](nil, "PLAYER_LOGIN")
  assert(not (db.done.OLD or db.fail.OLD or db.snap.OLD or db.collapsed.OLD), "closed round's saved data dropped")
  assert(db.collapsed.Again == false, "live round's saved state kept")
  local joined = table.concat(db.log, "\n")
  assert(not joined:find("[OLD]", 1, true) and joined:find("[Again] live line", 1, true) and joined:find("zone: Dornogal", 1, true), "only the stale round's log lines dropped")
  -- /dc note: lands on the open round, stamped; General when none is open
  SlashCmdList.DEVCHECKLIST("note   bars flicker at the bank ")
  local nt = db.notes.Again and db.notes.Again[1]
  assert(nt and nt.text == "bars flicker at the bank" and nt.zone == "Dornogal" and nt.at and nt.spec == "Fire" and type(nt.log) == "table", "note on the open round")
  assert(printed[#printed]:find("note saved to Again.", 1, true), "note confirm line")
  DC:Register("Second", "r3", { {"a", "S1"} })
  DC:Add("Second", "a", "S2")
  Row("S2")._OnClick(Row("S2"), "LeftButton")   -- last ticked: Second is where a note goes
  SlashCmdList.DEVCHECKLIST("note second round")
  assert(db.notes.Second and db.notes.Second[1].text == "second round" and #db.notes.Again == 1, "note follows the round last ticked")
  SlashCmdList.DEVCHECKLIST("note")
  assert(#db.notes.Again == 1 and #db.notes.Second == 1, "empty note ignored")
  DC:Clear("Again"); assert(not db.notes.Again, "clear drops notes")
  for id in pairs(DevChecklist_Rounds) do DC:Clear(id) end
  SlashCmdList.DEVCHECKLIST("note nothing open")
  assert(db.notes.General and db.notes.General[1].text == "nothing open", "General when no round is open")
  assert(printed[#printed]:find("General (no round open)", 1, true), "general confirm line")
  -- Log joins the values after the id, drops line breaks and cuts long lines
  DC:Register("L", "r", { {"a", "One"} })
  DC:Log("L", "count", 3, nil, true)
  assert(db.log[#db.log]:find("[L] count 3 nil true", 1, true), "log joins values: " .. db.log[#db.log])
  DC:Log("L", ("x"):rep(400) .. "\nnext")
  assert(#db.log[#db.log] == 9 + 4 + 300 and not db.log[#db.log]:find("\n"), "long log line cut to 300")
  -- notes: last 50 per round; login drops a closed round's notes, never General
  for i = 1, 60 do SlashCmdList.DEVCHECKLIST("note n" .. i) end
  assert(#db.notes.L == 50 and db.notes.L[50].text == "n60", "notes capped at 50")
  db.notes.Gone = { { text = "old" } }
  handlers[1](nil, "PLAYER_LOGIN")
  assert(not db.notes.Gone and db.notes.L and db.notes.General, "login drops only a closed round's notes")
  -- Lua errors land in the log while a round is open; the listener goes when the last round closes
  assert(bugCb, "error listener registered while recording")
  bugCb("table: 1")
  assert(db.log[#db.log]:find("error: boom in File.lua:1", 1, true), "error logged: " .. db.log[#db.log])
  for id in pairs(DevChecklist_Rounds) do DC:Clear(id) end
  assert(not bugCb, "error listener removed when no round is open")
end
-- task kinds: look (with setup), check, needs, beside old-format tasks
do
  local db = DevChecklistDB
  local reg = {}                                     -- events our frame watches from here on
  rawset(ALL[1], "RegisterEvent", function(_, e) reg[e] = true end)
  rawset(ALL[1], "UnregisterEvent", function(_, e) reg[e] = nil end)
  local mark = #KIDS
  local function Redraw() mark = #KIDS; DC:Show() end
  local function Seen(text)                          -- a text drawn by the last Redraw
    for i = mark + 1, #KIDS do
      if type(KIDS[i]._text) == "string" and KIDS[i]._text:find(text, 1, true) then return KIDS[i], i end
    end
  end
  local function Btn(label, after)                   -- a button from the last Redraw (the first one after a task's row)
    local _, from = Seen(after or "")
    for i = from or mark + 1, #KIDS do
      if KIDS[i]._text == label and KIDS[i]._parent._OnClick then return KIDS[i]._parent end
    end
  end
  local function Click(label, after, button) Redraw(); local b = assert(Btn(label, after), "no button " .. label); b._OnClick(b, button) end
  local function NoteBox() for i = #ALL, 1, -1 do if ALL[i]._type == "EditBox" and ALL[i]._OnEnterPressed then return ALL[i] end end end

  for id in pairs(DevChecklist_Rounds) do DC:Clear(id) end
  local setupRan, state, slashArg = 0, 1, nil
  SLASH_SMOKEADDON1 = "/smokeaddon"
  SlashCmdList.SMOKEADDON = function(msg) slashArg = msg end
  DC:Register("K", "kinds", {
    "A plain string task",
    { "area", "Old style task", "yes / no" },
    { kind = "look", text = "Panel looks right", setup = function() setupRan = setupRan + 1 end },
    { kind = "look", text = "Slash look", setup = "/SmokeAddon open now" },
    { kind = "look", text = "Bad setup", setup = "/nosuchcommand" },
    { kind = "check", text = "State is one", run = function() return state == 1, state end },
    { kind = "check", text = "Errors out", run = function() error("kaboom") end },
    { kind = "check", text = "Long value", run = function() return true, ("v"):rep(500) end },
    { kind = "needs", text = "Works in a group", needs = "a group of five" },
    { kind = "needs", text = "Works on a keypress", needs = "a hardware key press" },
  }, "b1")
  local p, n = DC:Progress("K"); assert(p == 0 and n == 8, "needs tasks are not counted: " .. p .. "/" .. n)

  -- checks never run in combat: they wait, the window says so, and they run when it ends
  inCombat = true
  assert(DC:RunChecks() == nil and not db.check.K and reg.PLAYER_REGEN_ENABLED, "checks wait in combat")
  Redraw(); assert(Seen("In combat: the checks run when it ends."), "window says the checks wait")
  inCombat = false
  fire(nil, "PLAYER_REGEN_ENABLED")
  assert(not reg.PLAYER_REGEN_ENABLED, "combat end is no longer watched")
  local c = db.check.K
  assert(c["State is one"].ok == true and c["State is one"].value == "1" and c["State is one"].at:match("^%d+%-%d+%-%d+ %d+:%d+:%d+$"), "check pass, value, time")
  assert(db.done.K["State is one"] and db.done.K["Long value"] and #c["Long value"].value == 200, "passes ticked, value capped")
  assert(c["Errors out"].ok == false and c["Errors out"].value:find("kaboom", 1, true), "an error is a fail with the error text")
  assert(db.fail.K["Errors out"]:find("kaboom", 1, true) and not db.snap.K, "check fail saved, no surroundings for a check")

  -- the window: looks, then Checked by code (only the failure listed), then Needs a situation
  Redraw()
  local _, iLook = Seen("A plain string task")
  local sec, iCheck = Seen("Checked by code")
  local _, iNeeds = Seen("Needs a situation")
  assert(iLook and iCheck and iNeeds and iLook < iCheck and iCheck < iNeeds, "section order")
  assert(sec._text:find("2/3 pass", 1, true) and Seen("Errors out") and not Seen("State is one"), "only failed checks are listed")
  assert(Seen("needs: a group of five") and Seen("the addon cannot test these"), "needs say what they need")
  assert(Seen("Nothing leaves the game until you /reload"), "limits shown up front")
  Click("?"); Redraw()
  assert(db.limits == false and not Seen("Nothing leaves the game"), "? folds the limits")
  Click("?"); Redraw(); assert(Seen("Nothing leaves the game"), "? shows them again")

  -- Run Checks button and /dc run
  state = 2; Click("Run Checks")
  assert(c["State is one"].ok == false and c["State is one"].value == "2" and db.fail.K["State is one"] == "2" and not db.done.K["State is one"], "a check can turn to fail")
  state = 1; SlashCmdList.DEVCHECKLIST("run")
  assert(db.check.K["State is one"].ok and db.done.K["State is one"] and db.fail.K["State is one"] == nil, "and back to pass")
  assert(printed[#printed]:find("3 checks ran, 1 failed", 1, true), "run line: " .. printed[#printed])

  -- once after a login or reload, when a round has checks
  db.check.K = nil
  fire(nil, "PLAYER_LOGIN")
  assert(reg.PLAYER_ENTERING_WORLD and not db.check.K, "checks wait for the world after a reload")
  fire(nil, "PLAYER_ENTERING_WORLD", false, true)
  assert(db.check.K["State is one"].ok and not reg.PLAYER_ENTERING_WORLD, "ran once, no longer watched")

  -- Set Up: refused in combat, a function, an addon slash command, a bad command
  inCombat = true; Click("Set Up", "Panel looks right")
  assert(setupRan == 0 and printed[#printed]:find("Set Up waits for combat to end", 1, true), "setup refused in combat")
  inCombat = false; Click("Set Up", "Panel looks right"); assert(setupRan == 1, "setup function ran")
  Click("Set Up", "Slash look"); assert(slashArg == "open now", "setup slash command ran: " .. tostring(slashArg))
  Click("Set Up", "Bad setup"); assert(printed[#printed]:find("Set Up failed: no addon command /nosuchcommand", 1, true), "bad setup says so")

  -- Looks Right, with text of any length (capped at 4000)
  Click("Looks Right", "Panel looks right")
  local box = NoteBox(); box._text = ("y"):rep(5000); box._OnEnterPressed(box)
  assert(db.done.K["Panel looks right"] and #db.remark.K["Panel looks right"] == 4000, "pass with text")
  Redraw(); assert(Seen(("y"):rep(117) .. "..."), "the row shows the start of the text")

  -- Something's Off: the surroundings are saved, the text can have several lines
  Click("Something's Off", "Slash look")
  local s = db.snap.K["Slash look"]
  assert(db.fail.K["Slash look"] == "" and s.round == "K" and s.task == "Slash look" and s.build == "b1", "fail with round and task")
  assert(s.zone == "Dornogal" and s.subzone == "The Stalls" and s.combat == "no" and s.spec == "Fire" and s.level == 80, "place and character")
  assert(s.group == 0 and s.groupType == "solo" and s.screen == "3840x2160" and s.uiScale == "1.000", "group and screen")
  assert(s.client == "12.0.0 (12345)" and s.fps == 60 and s.latency == "20 / 30 ms" and s.mouse == "MouseFrameName", "client, fps, latency, mouse")
  assert(#s.frames == 3 and s.frames[1] == "DialogOne" and s.frames[2] == "ShownOne" and s.frames[3] == "ShownTwo",
    "frames: dialogs first; no always-shown game containers, hidden, forbidden, unnamed or repeated ones: " .. table.concat(s.frames, ","))
  assert(s.error and s.error:find("boom in File.lua:1", 1, true) and #s.log <= 20 and not s.instance, "last error and log lines")
  box = NoteBox()
  shiftDown = true; box._text = "line one"; box._OnEnterPressed(box)
  assert(db.fail.K["Slash look"] == "", "Shift+Enter does not save")
  shiftDown = false; box._text = " line one\nline two "; box._OnEnterPressed(box)
  assert(db.fail.K["Slash look"] == "line one\nline two" and db.snap.K["Slash look"] == s, "several lines saved, surroundings kept")
  Redraw(); assert(Seen("line one line two"), "the row shows it on one line")

  -- a failing or missing game function leaves its field out, nothing breaks
  local oldNet, oldLevel, oldKids = GetNetStats, UnitLevel, rawget(UIParent, "GetChildren")
  GetNetStats = function() error("no net") end; UnitLevel = nil
  rawset(UIParent, "GetChildren", function() error("no children") end)
  SlashCmdList.DEVCHECKLIST("note still works")
  local nt = db.notes.K[#db.notes.K]
  assert(nt.text == "still works" and nt.latency == nil and nt.level == nil and nt.frames == nil and nt.zone == "Dornogal", "guarded reads")
  GetNetStats, UnitLevel = oldNet, oldLevel; rawset(UIParent, "GetChildren", oldKids)

  -- the frame list is capped at 40
  rawset(UIParent, "GetChildren", function()
    local t = {}; for i = 1, 60 do t[i] = Named("Many" .. i, true, false, i == 60 and "TOOLTIP" or nil) end; return unpack(t)
  end)
  SlashCmdList.DEVCHECKLIST("note many frames"); nt = db.notes.K[#db.notes.K]
  assert(#nt.frames == 40 and nt.frames[1] == "Many60" and nt.frames[2] == "Many1", "frame list capped, high strata first")
  rawset(UIParent, "GetChildren", oldKids)

  -- log lines in a snapshot: this round's and untagged ones first, others only to fill up
  local oldLog = db.log
  db.log = { "10:00:00 [K] first", "10:00:01 login: Dornogal" }
  for i = 1, 25 do db.log[#db.log + 1] = "10:01:00 [Other] spam " .. i end
  db.log[#db.log + 1] = "10:02:00 zone: Dornogal"
  SlashCmdList.DEVCHECKLIST("note log pick"); nt = db.notes.K[#db.notes.K]
  local others = 0; for _, l in ipairs(nt.log) do if l:find("[Other]", 1, true) then others = others + 1 end end
  assert(#nt.log == 20 and nt.log[1] == "10:00:00 [K] first" and nt.log[2] == "10:00:01 login: Dornogal" and nt.log[20] == "10:02:00 zone: Dornogal"
    and others == 17 and nt.log[3] == "10:01:00 [Other] spam 9", "own and untagged lines kept, newest others fill the rest, oldest first")
  for i = 1, 30 do db.log[#db.log + 1] = "10:03:00 [K] mine " .. i end
  SlashCmdList.DEVCHECKLIST("note log full"); nt = db.notes.K[#db.notes.K]
  others = 0; for _, l in ipairs(nt.log) do if l:find("[Other]", 1, true) then others = others + 1 end end
  assert(#nt.log == 20 and others == 0 and nt.log[20] == "10:03:00 [K] mine 30", "enough own lines: no other round's lines")
  db.log = oldLog

  -- /dc scale: saved, clamped, applied to the window
  local scaled
  rawset(frameObj, "SetScale", function(_, v) scaled = v end)
  assert(db.scale == nil, "no size saved by default")
  SlashCmdList.DEVCHECKLIST("scale 1.5"); assert(db.scale == 1.5 and scaled == 1.5, "scale set")
  SlashCmdList.DEVCHECKLIST("scale 9"); assert(db.scale == 2 and scaled == 2, "scale clamped high")
  SlashCmdList.DEVCHECKLIST("scale 0.1"); assert(db.scale == 0.8 and scaled == 0.8, "scale clamped low")
  SlashCmdList.DEVCHECKLIST("scale big"); assert(db.scale == 0.8 and printed[#printed]:find("window size 0.80", 1, true), "bad number changes nothing")
  SlashCmdList.DEVCHECKLIST("scale 1"); assert(db.scale == 1 and scaled == 1, "back to 1")

  -- the tool row says what each button does
  Redraw(); assert(Btn("Add Note") and Btn("Capture Screen") and Btn("Run Checks") and Btn("?"), "tool row labels")

  -- an instance shows in the surroundings
  local oldInfo = GetInstanceInfo; GetInstanceInfo = function() return "The Depths", "party", 23, "Mythic" end
  -- the Note box in the window: any length up to 4000, with the surroundings
  Click("Add Note"); box = NoteBox(); box._text = ("n"):rep(5000); box._OnEnterPressed(box)
  nt = db.notes.K[#db.notes.K]
  assert(#nt.text == 4000 and nt.round == "K" and nt.instance == "The Depths / party / Mythic" and #nt.frames == 3 and type(nt.log) == "table", "window note with surroundings")
  GetInstanceInfo = oldInfo

  -- needs: Couldn't, Skip, Did It, and a right click for tried-and-failed
  Click("Couldn't", "Works in a group"); Click("Skip", "Works on a keypress")
  assert(db.needs.K["Works in a group"] == "couldnt" and db.needs.K["Works on a keypress"] == "skip", "needs answers")
  Redraw(); assert(Seen("(couldn't)") and Seen("(skipped)"), "answers shown")
  Click("Did It", "Works in a group")
  assert(db.done.K["Works in a group"] and db.needs.K["Works in a group"] == nil, "Did It passes and replaces the answer")
  Redraw(); local row = Seen("Works on a keypress")._parent; row._OnClick(row, "RightButton")
  assert(db.fail.K["Works on a keypress"] == "" and not db.needs.K, "right click fails a needs task")
  p, n = DC:Progress("K"); assert(n == 8, "still 8 counted")

  -- report: needs listed apart, never holding the round back
  fire(nil, "PLAYER_LOGOUT")
  local rep = db.report.K
  assert(rep.pass + rep.open + #rep.fail == 8 and rep.passed == false and #rep.needs == 2, "report counts looks and checks")
  assert(rep.needs[1].answer == "pass" and rep.needs[1].needs == "a group of five" and rep.needs[2].answer == "fail", "report needs list")
  local kinds = {}; for _, e in ipairs(rep.fail) do kinds[e.text] = e.kind end
  assert(kinds["Errors out"] == "check" and kinds["Slash look"] == "look", "report fails carry the kind")
  DC:Register("N", "r", { "Only look", { kind = "needs", text = "Edge", needs = "a raid" } })
  Redraw(); row = Seen("Only look")._parent; row._OnClick(row, "LeftButton")
  fire(nil, "PLAYER_LOGOUT")
  assert(db.report.N.passed == true and db.report.N.needs[1].answer == "open" and db.report.N.open == 0, "an open needs task does not hold the round back")

  -- capture: asked, then the game's answer; matched by time
  local s0 = shots
  local id, at = DC:Capture()
  local list = db.shots[id]
  assert(shots == s0 + 1 and list[#list].result == "asked" and list[#list].at == at and reg.SCREENSHOT_SUCCEEDED and reg.SCREENSHOT_FAILED, "capture asked")
  fire(nil, "SCREENSHOT_SUCCEEDED")
  assert(list[#list].result == "saved" and not reg.SCREENSHOT_SUCCEEDED and not reg.SCREENSHOT_FAILED, "capture saved, events dropped")
  assert(list[#list].file:match("^WoWScrnShot_%d%d%d%d%d%d_%d%d%d%d%d%d$") and printed[#printed]:find("Look for " .. list[#list].file, 1, true), "capture names the file to look for")
  Click("Capture", "Bad setup")
  assert(shots == s0 + 2 and db.shots.K[#db.shots.K].task == "Bad setup", "capture from a task")
  fire(nil, "SCREENSHOT_FAILED"); assert(db.shots.K[#db.shots.K].result == "failed", "capture failed")
  SlashCmdList.DEVCHECKLIST("shot"); assert(shots == s0 + 3, "/dc shot")
  local oldShot = Screenshot; Screenshot = nil
  id = DC:Capture("K", "no function")
  assert(db.shots.K[#db.shots.K].result == "failed" and not reg.SCREENSHOT_SUCCEEDED, "no screenshot function: failed, nothing watched")
  Screenshot = oldShot
  for i = 1, 40 do DC:Capture("K", "many " .. i) end
  assert(#db.shots.K == 30 and db.shots.K[30].task == "many 40", "captures capped at 30")

  -- tools/results.lua prints all of it (run on a copy of what the game would save)
  do
    local function ser(v, out)
      if type(v) == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
          out[#out + 1] = "[" .. (type(k) == "number" and k or ("%q"):format(k)) .. "]="
          ser(x, out); out[#out + 1] = ","
        end
        out[#out + 1] = "}"
      else
        out[#out + 1] = type(v) == "string" and ("%q"):format(v) or tostring(v)
      end
    end
    local out = { "DevChecklistDB = " }; ser(db, out)
    local saved = os.tmpname()
    local fh = assert(io.open(saved, "w")); fh:write(table.concat(out)); fh:close()
    local outFile = os.tmpname()
    local oldArg, oldPrint = arg, print
    local got = {}
    arg = { saved, "K" }; print = function(line) got[#got + 1] = line end
    local ok, err = pcall(dofile, dir .. "/tools/results.lua")
    arg, print = oldArg, oldPrint
    os.remove(saved); os.remove(outFile)
    assert(ok, "results.lua runs: " .. tostring(err))
    local text = table.concat(got, "\n")
    for _, want in ipairs({
      "round passed: no", "[x] Panel looks right  -- yyy", "[FAIL] Slash look  -- line one", "subzone The Stalls",
      "frames shown: DialogOne, ShownOne, ShownTwo", "WoWScrnShot_", "== Checked by code", "[ok] State is one = 1", "[FAIL] Errors out = ",
      "== Needs a situation", "[pass] Works in a group  (needs: a group of five)", "[fail] Works on a keypress",
      "== Notes", "still works", "instance The Depths / party / Mythic", "== Captures", "| asked | many 11", "| asked | many 40",
    }) do
      assert(text:find(want, 1, true), "results.lua prints: " .. want)
    end
    assert(not text:find("[x] State is one", 1, true), "checks are not repeated under Passed")
  end

  -- closing: /dc clear drops everything; login drops a closed round's data, General stays
  DC:Clear("K")
  assert(not (db.check.K or db.needs.K or db.remark.K or db.shots.K or db.notes.K or db.fail.K or db.snap.K), "clear drops the new data too")
  db.check.Gone, db.needs.Gone, db.remark.Gone, db.shots.Gone, db.shots.General = { x = { ok = true } }, { x = "skip" }, { x = "t" }, { {} }, { {} }
  fire(nil, "PLAYER_LOGIN")
  assert(not (db.check.Gone or db.needs.Gone or db.remark.Gone or db.shots.Gone) and db.shots.General, "login prunes closed rounds")

  -- no round open: nothing watched, nothing recorded
  for rid in pairs(DevChecklist_Rounds) do DC:Clear(rid) end
  reg = {}
  fire(nil, "PLAYER_LOGIN")
  assert(not next(reg) and not bugCb, "no round: no events")
  local before = #db.log; DC:Log("K", "nobody listening"); assert(#db.log == before, "no round: no log")
end
print = io.write
io.write("SMOKE OK\n")
