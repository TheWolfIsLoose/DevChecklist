-- Offline smoke test for DevChecklist with stubbed WoW API.
-- Run from the repo root: texlua dev/smoke.lua .   (must print SMOKE OK)
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
local printed = {}
print = function(s) printed[#printed+1] = s end

assert(loadfile(dir.."/DevChecklist.lua"))("DevChecklist")
-- a round file, as one would sit in Rounds/
DevChecklist_Rounds.Demo = { round = "r1", items = { { "login", "No Lua errors.", "yes / no" }, { "bags", "Bag opens.", "screenshot" } } }
local DC = DevChecklist
-- before saved data: Park queues
DC:Park("Early", "a", "Queued item")
-- old v1 saved data
DevChecklistDB = { done = { ["No Lua errors."] = true, ["Not a current item"] = true }, collapsed = {}, point = {"TOPLEFT","TOPLEFT",5,5} }
local fire = handlers[1]
fire(nil, "ADDON_LOADED", "Other")
fire(nil, "ADDON_LOADED", "DevChecklist")
fire(nil, "PLAYER_LOGIN")
local db = DevChecklistDB
assert(db.v == 2, "migrated")
assert(db.done.Demo and db.done.Demo["No Lua errors."], "tick moved")
assert(db.done["Not a current item"] == nil, "stale flat tick dropped")
assert(db.parked.Early and #db.parked.Early == 1, "queued park flushed")
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
  "## bags", "* Bag `opens` fast.", "1. Sort works.", "  2) Nested numbered.", "---", "#", "### deep", "+ Deep item.",
  "# Fresh group", "- First fresh.", "-not a list", "- ", "- [ ]",
}, "\r\n")
local items = DC.ParseMarkdown(md)
assert(#items == 7, "parsed "..#items)
assert(items[1].id == "Demo" and items[1].area == "login" and items[1].text == "No Lua errors." and not items[1].done, "item 1")
assert(items[2].text == "Login sound plays." and items[2].done, "ticked + bold")
assert(items[3].text == "Bag opens fast." and items[3].area == "bags", "code marks")
assert(items[5].text == "Nested numbered.", "nested numbered")
assert(items[6].area == "deep" and items[6].id == "Demo", "### sets area, bare # ignored")
assert(items[7].id == "Fresh group" and items[7].area == "", "new group resets area")
assert(DC.ParseMarkdown("- x")[1].id == "Imported", "default group")
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
paste._text = "# Window\n- From the box."; paste._OnTextChanged(paste)
local go
for i = #KIDS, 1, -1 do local fs = KIDS[i]; if fs._text == "Import" and fs._parent._parent == paste._parent then go = fs._parent; break end end
go._OnClick(go)
assert(db.parked.Window and db.parked.Window[1][2] == "From the box.", "window import")
btns[3]._OnClick(btns[3]); paste = Newest(function(f) return f._type == "EditBox" and not f._OnTabPressed end)
paste._OnEscapePressed(paste)
print = io.write
io.write("SMOKE OK\n")
