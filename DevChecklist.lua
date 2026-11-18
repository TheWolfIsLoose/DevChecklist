--[[
    Dev Checklist: a small in-game list of what to test, for any addon project.

    Every task belongs to a group id (usually an addon name). Tasks come
    from code (DevChecklist:Register / :Add for this session, :Park / :Import
    saved), round files in Rounds/, or the window (+, Import, /dc add). One
    id never touches another id's tasks or ticks. Passes are saved in
    DevChecklistDB.done[id][task text], fails (with a one-line note) in
    DevChecklistDB.fail[id][task text], and a per-round summary is written to
    DevChecklistDB.report on reload and logout. README.md has the full guide
    and API.

    Look: near-black panels, 1px black edges, Expressway. When
    atrocityEssentials is loaded it follows the player's accent and font;
    otherwise it uses a default blue accent.
--]]

local ADDON = ...
local DC = {}
DevChecklist = DC
DevChecklist_Rounds = DevChecklist_Rounds or {}

local W, PAD, HEAD = 360, 10, 26
local NOTE = { 0.604, 0.604, 0.604 }   -- note grey #9A9A9A
local MUTED = { 0.5, 0.5, 0.5 }        -- muted text
local FAIL = { 0.9, 0.3, 0.3 }         -- failed item
local db, frame, Layout
local editing                          -- open inline form: { kind = "group" } or { kind = "task", id =, area = }
local armed = {}                       -- group id -> time its delete was armed
local pending = {}                     -- Park / AddGroup / Import calls made before our saved data loaded

-- Look --------------------------------------------------------------------

local function AE() return atrocityEssentials and atrocityEssentials.NS end

-- Read every time: AES lets the player switch the accent (Custom / Class).
local function Brand()
    local S = AE() and AE().Skins
    local b = S and S.palette and S.palette.brand
    if type(b) == "table" then
        local r, g, bl = b.r or b[1], b.g or b[2], b.b or b[3]
        if type(r) == "number" and type(g) == "number" and type(bl) == "number" then return r, g, bl end
    end
    return 0.451, 0.506, 1.0                -- default accent #7381FF
end

local function FontPath()
    local ae = AE()
    if ae and type(ae.FONT) == "string" then return ae.FONT end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return (LSM and LSM:Fetch("font", "Expressway", true)) or STANDARD_TEXT_FONT
end

local function Text(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FontPath(), size, "OUTLINE")
    fs:SetJustifyH("LEFT")
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    return fs
end

local function Px(f) return PixelUtil.GetNearestPixelSize(1, f:GetEffectiveScale(), 1) end

-- Near-black fill + exactly 1 physical px black edge.
local function Panel(f, shade, alpha)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = Px(f) })
    f:SetBackdropColor(shade, shade, shade, alpha)
    f:SetBackdropBorderColor(0, 0, 0, 1)
end

-- Hover: grey wash on ARTWORK 7, never the HIGHLIGHT layer.
local function Hover(btn)
    local t = btn:CreateTexture(nil, "ARTWORK", nil, 7)
    t:SetAllPoints()
    t:SetColorTexture(0.851, 0.851, 0.851, 0.15)
    t:Hide()
    btn:HookScript("OnEnter", function() t:Show() end)
    btn:HookScript("OnLeave", function() t:Hide() end)
end

-- Drawn X (close / remove) or + (add); white at rest, accent on hover.
local function Glyph(parent, size, plus, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size + 6, size + 6)
    local lines = {}
    for i, rot in ipairs(plus and { 0, math.pi / 2 } or { math.pi / 4, -math.pi / 4 }) do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSize(plus and size or size * 1.3, Px(b) * 2)
        t:SetPoint("CENTER")
        t:SetRotation(rot)
        lines[i] = t
    end
    function b:Tint(r, g, bl) for _, t in ipairs(lines) do t:SetVertexColor(r, g, bl) end end
    b:SetScript("OnEnter", function(self)
        self:Tint(Brand())
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self) self:Tint(1, 1, 1); GameTooltip:Hide() end)
    return b
end
local function XButton(parent, size, tip) return Glyph(parent, size, false, tip) end

-- Text box: window fill, 1px edge (accent while typing), grey placeholder.
local function Field(parent, width, placeholder)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, 20)
    Panel(e, 0.031, 1)
    e:SetAutoFocus(false)
    e:SetFont(FontPath(), 11, "OUTLINE")
    e:SetTextInsets(5, 5, 0, 0)
    e:SetMaxLetters(200)
    local ph = Text(e, 11, MUTED)
    ph:SetPoint("LEFT", 5, 0)
    ph:SetText(placeholder)
    e:HookScript("OnTextChanged", function(self) ph:SetShown(self:GetText() == "") end)
    e:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(Brand()) end)
    e:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); editing = nil; Layout() end)
    return e
end

-- Text button: control fill, 1px edge, grey hover wash.
local function Button(parent, label, width)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 20)
    Panel(b, 0.055, 0.95)
    Hover(b)
    local fs = Text(b, 11)
    fs:SetPoint("CENTER")
    fs:SetText(label)
    return b
end

local function Trim(t) return (t or ""):match("^%s*(.-)%s*$") end

-- Markdown to tasks: "# Name" starts a group (default "Imported"), "## Name"
-- (or deeper) sets the area, and only checkbox lines are tasks ("- [ ]",
-- "* [ ]", "1. [ ]"; "[x]" comes in ticked). Plain bullets and other lines are
-- notes and skipped. Bold and code marks are stripped (the game shows them
-- literally).
local function ParseMarkdown(md, id)
    local out, area = {}, ""
    id = id or "Imported"
    for line in (md or ""):gmatch("[^\r\n]+") do
        local h, title = line:match("^%s*(#+)%s+(.-)[%s#]*$")
        if h then
            if #h == 1 then
                if title ~= "" then id, area = title, "" end
            else
                area = title
            end
        else
            local text = line:match("^%s*[-*+]%s+(.+)$") or line:match("^%s*%d+[.)]%s+(.+)$")
            if text then
                local box, rest = text:match("^%[([ xX]?)%]%s*(.*)$")
                text = Trim((rest or ""):gsub("%*%*", ""):gsub("__", ""):gsub("`", ""))
                if box and text ~= "" then
                    out[#out + 1] = { id = id, area = area, text = text, done = box == "x" or box == "X" }
                end
            end
        end
    end
    return out
end

-- Data --------------------------------------------------------------------

local function Item(it)
    if type(it) ~= "table" then return end
    local text = it.text or it[2]
    if type(text) ~= "string" or text == "" then return end
    return { area = tostring(it.area or it[1] or ""), text = text, send = it.send or it[3] }
end

-- Every round with items: code / file rounds, then parked items under the same id. Sorted by id.
local function Rounds()
    local byId = {}
    for id, r in pairs(DevChecklist_Rounds) do
        if type(id) == "string" and type(r) == "table" and type(r.items) == "table" then
            local t = { id = id, round = r.round, build = r.build, items = {} }
            for _, it in ipairs(r.items) do t.items[#t.items + 1] = Item(it) end
            byId[id] = t
        end
    end
    for id in pairs(db and db.groups or {}) do
        byId[id] = byId[id] or { id = id, items = {}, mine = true }
    end
    for id, list in pairs(db and db.parked or {}) do
        local t = byId[id] or { id = id, items = {}, mine = true }
        for i, it in ipairs(list) do
            local x = Item(it)
            if x then x.parked = i; t.items[#t.items + 1] = x end
        end
        byId[id] = t
    end
    local out = {}
    for _, t in pairs(byId) do if #t.items > 0 or t.mine then out[#out + 1] = t end end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function Done(id, text) return db and db.done[id] and db.done[id][text] == true end

-- A failed item's note (may be ""), or nil when it hasn't failed.
local function Failed(id, text) return db and db.fail[id] and db.fail[id][text] end

local function Drop(t, id) if t[id] and not next(t[id]) then t[id] = nil end end

-- Flight recorder ---------------------------------------------------------
-- While a code or file round has an unpassed task, a few events (login and
-- reload, zone change, combat in/out, Lua errors when BugGrabber is loaded)
-- and DevChecklist:Log lines go into DevChecklistDB.log (last LOG_MAX lines).
-- Each fail saves a snapshot of where the tester was in DevChecklistDB.snap.
-- No round open: no events registered, nothing recorded.

local LOG_MAX, SNAP_LINES = 100, 20
local rec                              -- event frame, made the first time a round opens
local recording = false

local function AddLog(msg)
    local log = db.log
    log[#log + 1] = date("%H:%M:%S") .. " " .. msg
    while #log > LOG_MAX do table.remove(log, 1) end
end

local function Nz(s) if s ~= "" then return s end end    -- "" to nil (the game returns "" for some fields)

-- "zone" or "zone (instance, difficulty)". The zone can be "" at first login.
local function ZoneLine()
    local name, kind, _, diff = GetInstanceInfo()
    local zone = Nz(GetRealZoneText()) or Nz(name) or "?"
    if kind and kind ~= "none" then return zone .. " (" .. (Nz(name) or "?") .. ", " .. (Nz(diff) or kind) .. ")" end
    return zone
end

local function OnBug(_, err)
    local m = type(err) == "table" and err.message or err
    AddLog("error: " .. tostring(m):gsub("[\r\n]+", " "):sub(1, 160))
end

local function OnRecEvent(_, event, a, b)
    if event == "PLAYER_ENTERING_WORLD" then
        AddLog((a and "login" or b and "reload" or "loading screen") .. ": " .. ZoneLine())
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        AddLog("zone: " .. ZoneLine())
    elseif event == "PLAYER_REGEN_DISABLED" then
        AddLog("combat in")
    else
        AddLog("combat out")
    end
end

local function SetRecording(on)
    if on == recording then return end
    recording = on
    local BG = BugGrabber
    if on then
        if not rec then rec = CreateFrame("Frame"); rec:SetScript("OnEvent", OnRecEvent) end
        rec:RegisterEvent("PLAYER_ENTERING_WORLD")
        rec:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        rec:RegisterEvent("PLAYER_REGEN_DISABLED")
        rec:RegisterEvent("PLAYER_REGEN_ENABLED")
        if BG and BG.RegisterCallback then BG.RegisterCallback(rec, "BugGrabber_BugGrabbed", OnBug) end
    else
        rec:UnregisterAllEvents()
        if BG and BG.UnregisterCallback then BG.UnregisterCallback(rec, "BugGrabber_BugGrabbed") end
    end
end

-- Record while any code or file round has a task not yet passed.
local function Arm()
    if not db then return end
    for id, r in pairs(DevChecklist_Rounds) do
        if type(r) == "table" and type(r.items) == "table" then
            for _, it in ipairs(r.items) do
                local text = type(it) == "table" and (it.text or it[2])
                if type(text) == "string" and text ~= "" and not Done(id, text) then SetRecording(true) return end
            end
        end
    end
    SetRecording(false)
end

local function Snapshot(id)
    local spec = GetSpecialization()
    if spec then spec = select(2, GetSpecializationInfo(spec)) end
    local r = DevChecklist_Rounds[id]
    local s = {
        at = date("%Y-%m-%d %H:%M:%S"),
        zone = ZoneLine(),                    -- includes the instance and difficulty when inside one
        combat = InCombatLockdown() and "yes" or "no",
        spec = spec or "none",
        group = GetNumGroupMembers(),
        build = type(r) == "table" and r.build or nil,
        log = {},
    }
    for i = math.max(1, #db.log - SNAP_LINES + 1), #db.log do s.log[#s.log + 1] = db.log[i] end
    return s
end

local function DropSnap(id, text)
    if db.snap[id] then db.snap[id][text] = nil; Drop(db.snap, id) end
end

-- Pass and fail exclude each other: setting one clears the other.
local function SetDone(id, text, on)
    db.done[id] = db.done[id] or {}
    db.done[id][text] = on or nil
    Drop(db.done, id)
    if on and db.fail[id] then db.fail[id][text] = nil; Drop(db.fail, id) end
    if on then DropSnap(id, text) end
    Arm()
end

-- note = nil clears the fail; a string (even "") marks it failed. The first
-- fail takes a snapshot; adding the note later keeps it.
local function SetFail(id, text, note)
    if note == nil then
        if db.fail[id] then db.fail[id][text] = nil; Drop(db.fail, id) end
        DropSnap(id, text)
        return
    end
    db.fail[id] = db.fail[id] or {}
    if db.fail[id][text] == nil then
        db.snap[id] = db.snap[id] or {}
        db.snap[id][text] = Snapshot(id)
    end
    db.fail[id][text] = note
    if db.done[id] then db.done[id][text] = nil; Drop(db.done, id) end
    Arm()
end

-- passed, failed counts for one round.
local function Tally(r)
    local p, f = 0, 0
    for _, it in ipairs(r.items) do
        if Done(r.id, it.text) then p = p + 1 elseif Failed(r.id, it.text) then f = f + 1 end
    end
    return p, f
end

local function CountText(p, n, f)
    return ("%d/%d"):format(p, n) .. (f > 0 and ("  |cffe64d4d" .. f .. " failed|r") or "")
end

-- "|cffRRGGBB" for the current accent.
local function Accent()
    local r, g, b = Brand()
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function Print(msg) print(Accent() .. "Dev|r Checklist: " .. msg) end

-- API ---------------------------------------------------------------------

local function CheckId(id, fn)
    if type(id) ~= "string" or id == "" then error(("DevChecklist:%s: id must be a non-empty string"):format(fn), 3) end
end

function DC:Refresh()
    Arm()
    if frame and frame:IsShown() then Layout() end
end

-- One line in the flight recorder, e.g. DevChecklist:Log("MyAddon", "bags opened").
-- Kept only while a round is open; otherwise does nothing.
function DC:Log(id, msg)
    if not recording then return end
    AddLog("[" .. tostring(id) .. "] " .. tostring(msg))
end

-- Replace this id's round (this session). Ticks for items with the same text carry over.
-- build (optional, e.g. a short commit hash) is shown in the header and saved in the report.
function DC:Register(id, round, items, build)
    CheckId(id, "Register")
    DevChecklist_Rounds[id] = { round = round, build = build, items = type(items) == "table" and items or {} }
    DC:Refresh()
end

-- Append one item to this id's round (this session).
function DC:Add(id, area, text, send)
    CheckId(id, "Add")
    local r = DevChecklist_Rounds[id]
    if type(r) ~= "table" or type(r.items) ~= "table" then
        r = { round = type(r) == "table" and r.round or nil, build = type(r) == "table" and r.build or nil, items = {} }
        DevChecklist_Rounds[id] = r
    end
    r.items[#r.items + 1] = { area, text, send }
    DC:Refresh()
end

-- Save one item for later (kept across sessions until removed).
function DC:Park(id, area, text, send)
    CheckId(id, "Park")
    if not db then pending[#pending + 1] = function() DC:Park(id, area, text, send) end return end
    db.parked[id] = db.parked[id] or {}
    table.insert(db.parked[id], { area, text, send })
    DC:Refresh()
end

-- Add a markdown list (see ParseMarkdown) to the saved checklist. A "# Name"
-- matching an existing round or group adds to it. Tasks already there (same
-- text in the same group) are skipped, so pasting twice adds nothing.
-- Returns how many were added (0 when called before saved data loads; it
-- still runs then).
function DC:Import(md, id)
    if not db then pending[#pending + 1] = function() DC:Import(md, id) end return 0 end
    local have, touched, n = {}, {}, 0
    for _, r in ipairs(Rounds()) do
        have[r.id] = {}
        for _, x in ipairs(r.items) do have[r.id][x.text] = true end
    end
    for _, it in ipairs(ParseMarkdown(md, id)) do
        have[it.id] = have[it.id] or {}
        if not have[it.id][it.text] then
            have[it.id][it.text] = true
            db.parked[it.id] = db.parked[it.id] or {}
            table.insert(db.parked[it.id], { it.area, it.text })
            if it.done then SetDone(it.id, it.text, true) end
            touched[it.id] = true
            n = n + 1
        end
    end
    for k in pairs(touched) do db.collapsed[k] = false end
    DC:Refresh()
    return n
end
DC.ParseMarkdown = ParseMarkdown

-- A saved group with no items yet (kept until deleted).
function DC:AddGroup(id)
    CheckId(id, "AddGroup")
    if not db then pending[#pending + 1] = function() DC:AddGroup(id) end return end
    db.groups[id] = true
    DC:Refresh()
end

function DC:Unpark(id, index)
    local list = db and db.parked[id]
    if not list or not list[index] then return end
    local text = list[index][2]
    table.remove(list, index)
    if #list == 0 then db.parked[id] = nil end
    if text then SetDone(id, text, false) end
    DC:Refresh()
end

-- Drop this id's round, parked items and ticks.
function DC:Clear(id)
    CheckId(id, "Clear")
    DevChecklist_Rounds[id] = nil
    if db then db.parked[id], db.done[id], db.fail[id], db.snap[id], db.collapsed[id], db.groups[id] = nil, nil, nil, nil, nil, nil end
    DC:Refresh()
end

function DC:IsDone(id, text) return Done(id, text) end

-- done, total for one id.
function DC:Progress(id)
    for _, r in ipairs(Rounds()) do
        if r.id == id then
            local n = 0
            for _, it in ipairs(r.items) do if Done(id, it.text) then n = n + 1 end end
            return n, #r.items
        end
    end
    return 0, 0
end

-- Window ------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "DevChecklistFrame", UIParent, "BackdropTemplate")
    frame:SetWidth(W)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Panel(frame, 0.031, 0.8)
    local pt = db.point or { "TOPLEFT", "TOPLEFT", 40, -200 }
    frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])

    local head = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD)
    Panel(head, 0.055, 0.95)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() frame:StartMoving() end)
    head:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        db.point = { p, rp, x, y }
    end)
    frame.title = Text(head, 12)
    frame.title:SetPoint("LEFT", PAD, 0)
    local close = XButton(head, 9)
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() DC:Hide() end)
    local add = Glyph(head, 9, true, "New Group")
    add:SetPoint("RIGHT", close, "LEFT", -2, 0)
    add:SetScript("OnClick", function() editing = { kind = "group" }; Layout() end)
    local imp = Button(head, "Import", 48)
    imp:SetHeight(18)
    imp:SetPoint("RIGHT", add, "LEFT", -4, 0)
    imp:SetScript("OnClick", function()
        if editing and editing.kind == "import" then editing = nil else editing = { kind = "import" } end
        Layout()
    end)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 0, -HEAD)
    scroll:SetPoint("BOTTOMRIGHT", 0, PAD / 2)
    scroll:EnableMouseWheel(true)
    frame.scroll = scroll
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    frame.thumb = thumb
    function frame:PlaceThumb()
        local h, view = self.contentH or 0, scroll:GetHeight()
        thumb:SetShown(h > view + 1)
        if h <= view + 1 then return end
        local r, g, b = Brand()
        thumb:SetColorTexture(r, g, b, 0.35)
        local th = math.max(20, view * view / h)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -(view - th) * scroll:GetVerticalScroll() / (h - view))
    end
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local max = math.max(0, (frame.contentH or 0) - s:GetHeight())
        s:SetVerticalScroll(math.min(max, math.max(0, s:GetVerticalScroll() - delta * 40)))
        frame:PlaceThumb()
    end)
end

-- Fold state is saved per id; unset, a round folds once all of it is ticked.
local function Folded(r, done)
    local c = db.collapsed[r.id]
    if c == nil then return done == #r.items end
    return c
end

-- Tick box: window fill, 1px black edge, accent fill when ticked.
local function Box(parent)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(14, 14)
    Panel(b, 0.031, 1)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", 3, -3)
    b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    return b
end

-- Inline form for new tasks in one group: Area | Task | Send. Enter adds and
-- keeps the form open (area kept) for the next one; Esc closes.
local function TaskForm(body, y, id)
    local form = CreateFrame("Frame", nil, body)
    form:SetPoint("TOPLEFT", 0, y)
    form:SetSize(W, 40)
    local wide = W - 2 * PAD - 2 * 70 - 8
    local area = Field(form, 70, "Area")
    area:SetPoint("TOPLEFT", PAD, -2)
    local task = Field(form, wide, "Task")
    task:SetPoint("LEFT", area, "RIGHT", 4, 0)
    local send = Field(form, 70, "Send")
    send:SetPoint("LEFT", task, "RIGHT", 4, 0)
    area:SetText(editing.area or "")
    local hint = Text(form, 10, NOTE)
    hint:SetPoint("TOPLEFT", PAD, -25)
    hint:SetText("Enter adds the task, Esc closes. Send: what to report back (optional).")
    local function Save()
        local text = Trim(task:GetText())
        if text == "" then task:SetFocus() return end
        editing.area = Trim(area:GetText())
        local s = Trim(send:GetText())
        DC:Park(id, editing.area, text, s ~= "" and s or nil)   -- relayouts; the new form takes focus
    end
    local order = { area, task, send }
    for i, e in ipairs(order) do
        e:SetScript("OnEnterPressed", Save)
        e:SetScript("OnTabPressed", function() order[i % 3 + 1]:SetFocus() end)
    end
    task:SetFocus()
    return 44
end

-- One-line note under a failed item. Enter saves, Esc closes (the fail stays).
local function NoteForm(body, y, id, text)
    local e = Field(body, W - 2 * PAD - 20, "What went wrong? Enter saves")
    e:SetPoint("TOPLEFT", PAD + 20, y - 2)
    e:SetText(Failed(id, text) or "")
    e:SetScript("OnEnterPressed", function(self)
        SetFail(id, text, Trim(self:GetText()))
        editing = nil
        Layout()
    end)
    e:SetFocus()
    return 26
end

-- Paste box for a markdown list; Import adds it, Esc closes.
-- ponytail: no scroll frame, so a long paste is clipped in the box (all of it
-- still imports; the count below says how much). Add one if that bothers.
local function ImportForm(body, y)
    local box = CreateFrame("EditBox", nil, body, "BackdropTemplate")
    box:SetPoint("TOPLEFT", PAD, y - 2)
    box:SetSize(W - 2 * PAD, 120)
    Panel(box, 0.031, 1)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFont(FontPath(), 11, "OUTLINE")
    box:SetTextInsets(5, 5, 5, 5)
    box:SetMaxLetters(0)
    local ph = Text(box, 11, MUTED)
    ph:SetPoint("TOPLEFT", 5, -5)
    ph:SetText("Paste a markdown list")
    local hint = Text(body, 10, NOTE)
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(W - 2 * PAD - 80)
    hint:SetWordWrap(true)
    local ok = Button(body, "Import", 70)
    ok:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
    local function Update(text)
        ph:SetShown(text == "")
        local n = #ParseMarkdown(text)
        hint:SetText(n > 0 and (n .. (n == 1 and " task" or " tasks") .. " found. Esc closes.")
            or "# starts a group, ## an area; - [ ] lines are tasks. Esc closes.")
    end
    box:SetScript("OnTextChanged", function(self) editing.text = self:GetText(); Update(editing.text) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); editing = nil; Layout() end)
    box:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(Brand()) end)
    box:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
    ok:SetScript("OnClick", function()
        local text = box:GetText()
        editing = nil
        local n = DC:Import(text)
        Print(n == 0 and "nothing new to import." or ("imported " .. n .. (n == 1 and " task." or " tasks.")))
        Layout()
    end)
    box:SetText(editing.text or "")
    Update(editing.text or "")
    box:SetFocus()
    return 152
end

-- ponytail: rebuilds the body on every change (old widgets hidden, not
-- reused). Fine for a dev window; pool rows if it ever feels slow.
Layout = function()
    if frame.body then frame.body:Hide() end
    local body = CreateFrame("Frame", nil, frame.scroll)
    body:SetWidth(W)
    frame.body = body
    local br, bg, bb = Brand()
    local accent = Accent()
    local y, open, any = -6, 0, false
    local formTop, formH

    if editing and editing.kind == "group" then
        local name = Field(body, W - 2 * PAD, "New group name")
        name:SetPoint("TOPLEFT", PAD, y - 2)
        name:SetScript("OnEnterPressed", function(self)
            local id = Trim(self:GetText())
            if id == "" then return end
            editing = { kind = "task", id = id }
            db.collapsed[id] = false
            DC:AddGroup(id)
        end)
        name:SetFocus()
        formTop, formH = -y, 30
        y = y - 30
    elseif editing and editing.kind == "import" then
        formTop = -y
        formH = ImportForm(body, y)
        y = y - formH
    end

    for _, r in ipairs(Rounds()) do
        any = true
        local done, nfail = Tally(r)
        open = open + #r.items - done
        local adding = editing and editing.kind == "task" and editing.id == r.id
        local folded = not adding and #r.items > 0 and Folded(r, done)

        local h = CreateFrame("Button", nil, body)
        h:SetPoint("TOPLEFT", 0, y)
        h:SetSize(W, 22)
        Hover(h)
        local x = r.mine and XButton(h, 7, "Delete Group (click twice)")
        if x then x:SetPoint("RIGHT", -4, 0) end
        local plus = Glyph(h, 8, true, "Add Task")
        plus:SetPoint("RIGHT", x or h, x and "LEFT" or "RIGHT", x and 0 or -4, 0)
        plus:SetScript("OnClick", function()
            editing = { kind = "task", id = r.id }
            Layout()
        end)
        local hc = Text(h, 11, NOTE)
        hc:SetPoint("RIGHT", plus, "LEFT", -4, 0)
        hc:SetText(CountText(done, #r.items, nfail))
        local ht = Text(h, 12)
        ht:SetPoint("LEFT", PAD, 0)
        ht:SetPoint("RIGHT", hc, "LEFT", -6, 0)
        ht:SetWordWrap(false)
        ht:SetText((folded and "+ " or "- ") .. accent .. r.id .. "|r"
            .. ((r.round and r.round ~= "") and ("  " .. r.round) or "")
            .. ((r.build and r.build ~= "") and ("  |cff9a9a9a" .. r.build .. "|r") or ""))
        h:SetScript("OnClick", function() db.collapsed[r.id] = not folded; Layout() end)
        if x then
            if armed[r.id] then
                x:Tint(0.9, 0.3, 0.3)
                hc:SetText("|cffe64d4dClick again to delete|r")
            end
            x:SetScript("OnClick", function()
                if armed[r.id] and GetTime() - armed[r.id] < 3 then
                    armed[r.id] = nil
                    if editing and editing.id == r.id then editing = nil end
                    DC:Clear(r.id)
                    return
                end
                armed[r.id] = GetTime()
                Layout()
                C_Timer.After(3, function()
                    if armed[r.id] then armed[r.id] = nil; DC:Refresh() end
                end)
            end)
        end
        y = y - 24

        local lastArea
        for _, it in ipairs(folded and {} or r.items) do
            if it.area ~= "" and it.area ~= lastArea then
                local a = Text(body, 11, NOTE)
                a:SetPoint("TOPLEFT", PAD, y - 4)
                a:SetText(it.area)
                y = y - 18
            end
            lastArea = it.area

            local row = CreateFrame("Button", nil, body)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetPoint("TOPLEFT", 0, y)
            Hover(row)
            local box = Box(row)
            box:SetPoint("TOPLEFT", PAD, -3)
            local fs = Text(row, 11)
            fs:SetPoint("TOPLEFT", PAD + 20, -4)
            fs:SetWidth(W - 2 * PAD - 20 - (it.parked and 16 or 0))
            fs:SetWordWrap(true)
            local send = (type(it.send) == "string" and it.send ~= "") and ("  |cff9a9a9a" .. it.send .. "|r") or ""
            local function Paint()
                local on, note = Done(r.id, it.text), Failed(r.id, it.text)
                local c = note and FAIL or (on and MUTED) or { 1, 1, 1 }
                box.fill:SetColorTexture(note and FAIL[1] or br, note and FAIL[2] or bg, note and FAIL[3] or bb, 0.8)
                box.fill:SetShown(on or note ~= nil)
                fs:SetTextColor(c[1], c[2], c[3])
                fs:SetText(it.text .. send .. ((note and note ~= "") and ("  |cffe64d4d" .. note .. "|r") or ""))
            end
            Paint()
            -- Left click passes (again to clear); right click fails and asks for a note (again to clear).
            row:SetScript("OnClick", function(_, button)
                local wasFailed = Failed(r.id, it.text) ~= nil
                if button == "RightButton" then
                    if wasFailed then
                        SetFail(r.id, it.text, nil)
                        editing = nil
                    else
                        SetFail(r.id, it.text, "")
                        editing = { kind = "note", id = r.id, text = it.text }
                    end
                    Layout()
                    return
                end
                -- A left click moves on: close an open note box (this item's or another's).
                if editing and editing.kind == "note" then editing = nil; wasFailed = true end
                SetDone(r.id, it.text, not Done(r.id, it.text))
                if wasFailed then Layout() return end
                Paint()
                local p, f = Tally(r)
                hc:SetText(CountText(p, #r.items, f))
            end)
            if it.parked then
                local del = XButton(row, 7, "Delete Task")
                del:SetPoint("TOPRIGHT", -4, -1)
                del:SetScript("OnClick", function() DC:Unpark(r.id, it.parked) end)
            end
            local rh = math.max(20, fs:GetStringHeight() + 8)
            row:SetSize(W, rh)
            y = y - rh
            if editing and editing.kind == "note" and editing.id == r.id and editing.text == it.text then
                formTop = -y
                formH = NoteForm(body, y, r.id, it.text)
                y = y - formH
            end
        end

        if #r.items == 0 and not adding then
            local e = Text(body, 11, NOTE)
            e:SetPoint("TOPLEFT", PAD + 20, y - 3)
            e:SetText("No tasks yet.")
            y = y - 20
        end
        if adding then
            formTop = -y
            formH = TaskForm(body, y, r.id)
            y = y - formH
        end
    end

    if not any and not editing then
        local e = Text(body, 11, NOTE)
        e:SetPoint("TOPLEFT", PAD, y - 4)
        e:SetText("Nothing to test. + adds a group.")
        y = y - 24
    end
    frame.title:SetText(accent .. "Dev|r Checklist  |cff9a9a9a" .. (open > 0 and (open .. " to test") or "all done") .. "|r")

    local contentH = 6 - y
    body:SetHeight(contentH)
    frame.contentH = contentH
    local view = math.min(contentH, math.floor(UIParent:GetHeight() * 0.7))
    frame:SetHeight(HEAD + view + PAD / 2)
    frame.scroll:SetScrollChild(body)
    local cur = math.min(frame.scroll:GetVerticalScroll(), math.max(0, contentH - view))
    if formTop then   -- keep the open form in view
        if formTop + formH > cur + view then cur = formTop + formH - view end
        if formTop < cur then cur = formTop end
    end
    frame.scroll:SetVerticalScroll(cur)
    frame:PlaceThumb()
end

function DC:Show()
    if not db then return end
    if not frame then Build() end
    frame:Show()
    Layout()
end

function DC:Hide()
    if frame then editing = nil; frame:Hide() end
end

function DC:Toggle()
    if frame and frame:IsShown() then DC:Hide() else DC:Show() end
end

-- Load --------------------------------------------------------------------

-- Summary per round for whoever reads the results: written on reload and
-- logout, which is also when the game saves DevChecklistDB.
local function WriteReport()
    if not db then return end
    db.report = {}
    for _, r in ipairs(Rounds()) do
        if #r.items > 0 then
            local pass, fails = 0, {}
            for _, it in ipairs(r.items) do
                if Done(r.id, it.text) then
                    pass = pass + 1
                elseif Failed(r.id, it.text) then
                    fails[#fails + 1] = { text = it.text, note = Failed(r.id, it.text) }
                end
            end
            db.report[r.id] = { round = r.round, build = r.build, pass = pass, open = #r.items - pass - #fails, fail = fails }
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGOUT" then WriteReport() return end
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        DevChecklistDB = DevChecklistDB or {}
        db = DevChecklistDB
        db.done = db.done or {}
        db.fail = db.fail or {}
        db.collapsed = db.collapsed or {}
        db.parked = db.parked or {}
        db.groups = db.groups or {}
        db.log = db.log or {}
        db.snap = db.snap or {}
        for _, fn in ipairs(pending) do fn() end
        pending = nil
        return
    end
    -- v1 saved ticks flat by item text; v2 keys them by id. Move the ones that
    -- match a loaded round's item (every round is registered by now).
    if not db.v then
        local old = db.done
        db.done = {}
        for _, r in ipairs(Rounds()) do
            for _, it in ipairs(r.items) do if old[it.text] == true then SetDone(r.id, it.text, true) end end
        end
        db.v = 2
    end
    Arm()
    for _, r in ipairs(Rounds()) do
        for _, it in ipairs(r.items) do
            if not Done(r.id, it.text) then DC:Show() return end
        end
    end
end)

SLASH_DEVCHECKLIST1 = "/dc"
SLASH_DEVCHECKLIST2 = "/devchecklist"
SlashCmdList.DEVCHECKLIST = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then
        DC:Toggle()
    elseif cmd == "add" and rest ~= "" then
        local area, text = rest:match("^([^:]+):%s*(.+)$")
        DC:Park("Parked", area or "", text or rest)
        Print("parked.")
        DC:Show()
    elseif cmd == "clear" and rest ~= "" then
        DC:Clear(rest)
        Print(rest .. " cleared.")
    else
        Print("|cffffffff/dc|r show or hide  |cffffffff/dc add [area:] text|r park an item  |cffffffff/dc clear <round>|r drop a round and its ticks")
    end
end
