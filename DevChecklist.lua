--[[
    Dev Checklist: a small in-game list of what to test, for any addon project.

    A task is one of three kinds: a look (a person judges it), a check (a
    function decides it) or a needs (it needs a situation the addon cannot
    make). Every task belongs to a group id (usually an addon name). Tasks come
    from code (DevChecklist:Register / :Add for this session, :Park / :Import
    saved), round files in Rounds/, or the window (+, Import, /dc add). One
    id never touches another id's tasks or ticks. Passes are saved in
    DevChecklistDB.done[id][task text], fails (with a one-line note) in
    DevChecklistDB.fail[id][task text], check results in DevChecklistDB.check,
    notes in DevChecklistDB.notes[id], and a per-round summary is written to
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
local lastId                           -- round id last ticked or failed (where /dc note goes if several are open)
local ev                               -- our event frame (made under Load)
local lastError                        -- last Lua error heard while recording
local checksWaiting = false            -- Run Checks was asked for in combat
local pendingShot                      -- capture waiting for the game to say how it went
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

-- A task as written: a string (a look), { area, text, send }, or a table
-- with named fields. kind is "look" (the default: a person judges it, setup
-- is optional), "check" (run() returns ok, value) or "needs" (needs says
-- what situation it takes).
local function Item(it)
    if type(it) == "string" then it = { text = it } end
    if type(it) ~= "table" then return end
    local text = it.text or it[2]
    if type(text) ~= "string" or text == "" then return end
    return {
        area = tostring(it.area or it[1] or ""), text = text, send = it.send or it[3],
        kind = (it.kind == "check" or it.kind == "needs") and it.kind or "look",
        run = it.run, setup = it.setup, needs = it.needs,
    }
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

local function Done(id, text)
    local t = db and db.done[id]
    return type(t) == "table" and t[text] == true    -- not a table: v1 data before its move at login
end

-- A failed item's note (may be ""), or nil when it hasn't failed.
local function Failed(id, text) return db and db.fail[id] and db.fail[id][text] end

-- A needs item's other answer: "couldnt" or "skip" (nil: not answered that way).
local function Needs(id, text) return db and db.needs[id] and db.needs[id][text] end

-- What the tester added to a passed item, or nil.
local function Remark(id, text) return db and db.remark[id] and db.remark[id][text] end

-- Is this task (as written in a round) still waiting for an answer? A fail
-- waits for a retest; a needs item answered "couldnt" or "skip" does not.
local function Waiting(id, it)
    local x = Item(it)
    return x and not Done(id, x.text) and not (x.kind == "needs" and Needs(id, x.text))
end

local function Drop(t, id) if t[id] and not next(t[id]) then t[id] = nil end end

-- Flight recorder ---------------------------------------------------------
-- While a code or file round has an unpassed task, a few events (login and
-- reload, zone change, combat in/out, Lua errors when BugGrabber is loaded)
-- and DevChecklist:Log lines go into DevChecklistDB.log (last LOG_MAX lines,
-- each cut to LINE_MAX characters). Each fail saves a snapshot of where the
-- tester was in DevChecklistDB.snap. No round open: no events registered,
-- nothing recorded.

local LOG_MAX, SNAP_LINES, LINE_MAX, NOTE_MAX = 100, 20, 300, 50
local TEXT_MAX, VALUE_MAX, FIELD_MAX, FRAMES_MAX, SHOT_MAX = 4000, 200, 120, 40, 30
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

-- BugGrabber hands over the error itself (older versions) or its id (newer ones).
local function OnBug(_, err)
    if type(err) == "string" and BugGrabber and BugGrabber.GetErrorByID then
        local ok, e = pcall(BugGrabber.GetErrorByID, BugGrabber, err)
        if ok and e then err = e end
    end
    local m = type(err) == "table" and err.message or err
    m = tostring(m):gsub("[\r\n]+", " ")
    lastError = date("%H:%M:%S") .. " " .. m:sub(1, LINE_MAX)
    AddLog("error: " .. m:sub(1, 160))
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
        if BG and BG.RegisterCallback then
            BG.RegisterCallback(rec, "BugGrabber_BugGrabbed", OnBug)
        elseif BG and EventRegistry then
            EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", OnBug, rec)
        end
    else
        rec:UnregisterAllEvents()
        if BG and BG.UnregisterCallback then
            BG.UnregisterCallback(rec, "BugGrabber_BugGrabbed")
        elseif BG and EventRegistry then
            EventRegistry:UnregisterCallback("BugGrabber.BugGrabbed", rec)
        end
    end
end

-- Record while any code or file round has a task still waiting.
local function Arm()
    if not db then return end
    for id, r in pairs(DevChecklist_Rounds) do
        if type(r) == "table" and type(r.items) == "table" then
            for _, it in ipairs(r.items) do
                if Waiting(id, it) then SetRecording(true) return end
            end
        end
    end
    SetRecording(false)
end

-- Surroundings ------------------------------------------------------------
-- Where the tester was, saved with every fail and every note. Each read is
-- guarded (a missing or failing game function leaves its field out) and
-- capped. Only reads: nothing protected is called, and frames are walked
-- from UIParent's children with IsForbidden checked first.

local function Try(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

-- Any value as one short line, or nil.
local function Cap(v, n)
    if v == nil then return end
    local ok, s = pcall(tostring, v)
    if not ok then return end
    s = s:gsub("[\r\n]+", " ")
    return s:sub(1, n or FIELD_MAX)
end

local function FrameName(f)
    if type(f) ~= "table" or not f.IsForbidden or f:IsForbidden() then return end
    return Cap(f.GetName and f:GetName() or f.GetDebugName and f:GetDebugName())
end

local function MouseFrame()
    local f
    if GetMouseFoci then f = GetMouseFoci()[1] elseif GetMouseFocus then f = GetMouseFocus() end
    return FrameName(f)
end

-- The game's own containers that are shown all the time (and this window):
-- listing them with every snapshot would bury the frames that matter.
local ALWAYS = {}
for name in ([[
    ActionBarController BackpackTokenFrame BagsBar BottomManagedFrameContainer BuffBarCooldownViewer
    BuffFrame BuffIconCooldownViewer ChatFrame1 ContainerFrameContainer DebuffFrame DevChecklistFrame
    EncounterBar EssentialCooldownViewer GeneralDockManager GlobalFXBackgroundModelScene
    GlobalFXDialogModelScene GlobalFXMediumModelScene MainActionBar MainMenuBar
    MainStatusTrackingBarContainer MicroButtonAndBagsBar MicroMenuContainer MinimapCluster
    MirrorTimerContainer MotionSicknessFrame MultiBarBottomLeft MultiBarBottomRight MultiBarLeft
    MultiBarRight ObjectiveTrackerFrame ObjectiveTrackerUIWidgetContainer PetActionBar PlayerFrame
    PrivateRaidBossEmoteFrameAnchor QuestSessionManager RightManagedFrameContainer RoleChangedFrame
    SecondaryStatusTrackingBarContainer SpellActivationOverlayFrame StanceBar StatusTrackingBarManager
    TimerTracker UIErrorsFrame UIPanelLayoutFrame UIWidgetBelowMinimapContainerFrame
    UIWidgetCenterScreenContainerFrame UIWidgetPowerBarContainerFrame UIWidgetTopCenterContainerFrame
    UtilityCooldownViewer VoiceActivityManager
]]):gmatch("%S+") do ALWAYS[name] = true end
local HIGH = { DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

-- Named, shown children of UIParent that are not in ALWAYS: dialogs and
-- anything above them first, then the rest, FRAMES_MAX at most.
local function ShownFrames()
    local out, rest, seen = {}, {}, {}
    local kids = { UIParent:GetChildren() }
    for i = 1, #kids do
        local f = kids[i]
        if not f:IsForbidden() and f:IsShown() then
            local name = f:GetName()
            if name and not ALWAYS[name] and not seen[name] then
                seen[name] = true
                local t = HIGH[f:GetFrameStrata()] and out or rest
                t[#t + 1] = Cap(name, 60)
            end
        end
    end
    for i = 1, #rest do out[#out + 1] = rest[i] end
    for i = #out, FRAMES_MAX + 1, -1 do out[i] = nil end
    return out
end

-- The last SNAP_LINES log lines that matter for this round: its own tagged
-- lines and untagged ones (login, reload, zone, combat, error) first; lines
-- of other rounds only fill what is left. Returned oldest first.
local function LogTail(id)
    local log, pick, n = db.log, {}, 0
    local own = "[" .. tostring(id) .. "]"
    for pass = 1, 2 do
        for i = #log, 1, -1 do
            if n >= SNAP_LINES then break end
            if not pick[i] then
                local tag = log[i]:match("^%S+ (%[[^%]]+%])")
                if pass == 2 or not tag or tag == own then pick[i] = true; n = n + 1 end
            end
        end
    end
    local out = {}
    for i = 1, #log do if pick[i] then out[#out + 1] = log[i] end end
    return out
end

local function Surround(id, text)
    local r = DevChecklist_Rounds[id]
    local s = { at = date("%Y-%m-%d %H:%M:%S"), round = id, task = Cap(text, VALUE_MAX) }
    s.zone = Cap(Try(ZoneLine)) or "?"        -- includes the instance and difficulty when inside one
    s.subzone = Cap(Nz(Try(GetSubZoneText) or ""))
    local name, kind, _, diff = Try(GetInstanceInfo)
    if kind and kind ~= "none" then s.instance = Cap((Nz(name) or "?") .. " / " .. kind .. " / " .. (Nz(diff) or "?")) end
    s.combat = Try(InCombatLockdown) and "yes" or "no"
    s.spec = Cap(Try(function() local i = GetSpecialization(); return i and select(2, GetSpecializationInfo(i)) end)) or "none"
    s.level = tonumber((Try(UnitLevel, "player")))
    s.group = tonumber((Try(GetNumGroupMembers))) or 0
    s.groupType = Try(IsInRaid) and "raid" or Try(IsInGroup) and "party" or "solo"
    local w, h = Try(GetPhysicalScreenSize)
    if tonumber(w) and tonumber(h) then s.screen = ("%dx%d"):format(w, h) end
    local scale = tonumber((Try(function() return UIParent:GetEffectiveScale() end)))
    if scale then s.uiScale = ("%.3f"):format(scale) end
    local version, number = Try(GetBuildInfo)
    if version then s.client = Cap(tostring(version) .. " (" .. tostring(number) .. ")") end
    local fps = tonumber((Try(GetFramerate)))
    if fps then s.fps = math.floor(fps + 0.5) end
    local _, _, home, world = Try(GetNetStats)
    if home then s.latency = Cap(tostring(home) .. " / " .. tostring(world) .. " ms") end
    s.mouse = Try(MouseFrame)
    s.frames = Try(ShownFrames)
    s.error = lastError
    s.build = type(r) == "table" and Cap(r.build, VALUE_MAX) or nil
    s.log = LogTail(id)
    return s
end

local function DropSnap(id, text)
    if db.snap[id] then db.snap[id][text] = nil; Drop(db.snap, id) end
end

-- Pass and fail exclude each other: setting one clears the other.
local function SetDone(id, text, on)
    lastId = id
    db.done[id] = db.done[id] or {}
    db.done[id][text] = on or nil
    Drop(db.done, id)
    if on and db.fail[id] then db.fail[id][text] = nil; Drop(db.fail, id) end
    if on then DropSnap(id, text) end
    if on and db.needs[id] then db.needs[id][text] = nil; Drop(db.needs, id) end
    if not on and db.remark[id] then db.remark[id][text] = nil; Drop(db.remark, id) end
    Arm()
end

-- note = nil clears the fail; a string (even "") marks it failed. The first
-- fail saves the surroundings (not for a check: bare); adding the note later
-- keeps them.
local function SetFail(id, text, note, bare)
    lastId = id
    if note == nil then
        if db.fail[id] then db.fail[id][text] = nil; Drop(db.fail, id) end
        DropSnap(id, text)
        return
    end
    db.fail[id] = db.fail[id] or {}
    if db.fail[id][text] == nil and not bare then
        db.snap[id] = db.snap[id] or {}
        db.snap[id][text] = Surround(id, text)
    end
    db.fail[id][text] = note:sub(1, TEXT_MAX)
    if db.done[id] then db.done[id][text] = nil; Drop(db.done, id) end
    if db.needs[id] then db.needs[id][text] = nil; Drop(db.needs, id) end
    if db.remark[id] then db.remark[id][text] = nil; Drop(db.remark, id) end
    Arm()
end

-- A needs item the tester could not do ("couldnt") or left out ("skip");
-- nil clears it. It replaces a pass or fail, and a pass or fail replaces it.
local function SetNeeds(id, text, answer)
    if answer then SetDone(id, text, false); SetFail(id, text, nil) end
    db.needs[id] = db.needs[id] or {}
    db.needs[id][text] = answer
    Drop(db.needs, id)
    Arm()
end

-- Free text on a passed item ("" or nil clears it).
local function SetRemark(id, text, remark)
    db.remark[id] = db.remark[id] or {}
    db.remark[id][text] = (remark and remark ~= "") and remark:sub(1, TEXT_MAX) or nil
    Drop(db.remark, id)
end

-- Quick notes -------------------------------------------------------------
-- /dc note <text> (or the Note box in the window) saves free text with the
-- surroundings in DevChecklistDB.notes[id], on the open round. Nothing runs
-- until the tester asks.

-- The round a note belongs to: one with a task still waiting (the one last
-- ticked or failed when several are open), or nil.
local function OpenRound()
    local first
    for id, r in pairs(DevChecklist_Rounds) do
        if type(r) == "table" and type(r.items) == "table" then
            for _, it in ipairs(r.items) do
                if Waiting(id, it) then
                    if id == lastId then return id end
                    if not first or id < first then first = id end
                    break
                end
            end
        end
    end
    return first
end

-- No round open: the note goes to the "General" list. Returns the id it landed on.
function DC:Note(text)
    text = Trim(text)
    if text == "" or not db then return end
    local id = OpenRound()
    local s = Surround(id or "General")
    s.text = text:sub(1, TEXT_MAX)
    local list = db.notes[id or "General"] or {}
    db.notes[id or "General"] = list
    list[#list + 1] = s
    while #list > NOTE_MAX do table.remove(list, 1) end
    return id or "General", id == nil
end

-- passed, failed, total for one round. Needs items are left out: they never
-- hold a round back.
local function Tally(r)
    local p, f, n = 0, 0, 0
    for _, it in ipairs(r.items) do
        if it.kind ~= "needs" then
            n = n + 1
            if Done(r.id, it.text) then p = p + 1 elseif Failed(r.id, it.text) then f = f + 1 end
        end
    end
    return p, f, n
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

-- One line in the flight recorder, e.g. DevChecklist:Log("MyAddon", "bags opened", 3).
-- Values after the id are joined with spaces. Kept only while a round is
-- open; otherwise does nothing.
function DC:Log(id, ...)
    if not recording then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    AddLog("[" .. tostring(id) .. "] " .. table.concat(parts, " "):gsub("[\r\n]+", " "):sub(1, LINE_MAX))
end

-- Checks, Set Up, Capture --------------------------------------------------

-- Run every check task: run() is called guarded and returns ok, value. An
-- error is a fail whose value is the error text. Never in combat: asked for
-- in combat, the checks run once when it ends. Returns how many ran and how
-- many failed, or nil while waiting.
local function RunChecks()
    if not db then return end
    if InCombatLockdown() then
        checksWaiting = true
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if checksWaiting then
        checksWaiting = false
        ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    local keep, n, bad = lastId, 0, 0
    for _, r in ipairs(Rounds()) do
        for _, it in ipairs(r.items) do
            if it.kind == "check" then
                local ok, pass, value = pcall(it.run)
                if not ok then pass, value = false, pass end
                value = Cap(value, VALUE_MAX)
                db.check[r.id] = db.check[r.id] or {}
                db.check[r.id][it.text] = { ok = pass and true or false, value = value, at = date("%Y-%m-%d %H:%M:%S") }
                if pass then
                    SetDone(r.id, it.text, true)
                else
                    SetFail(r.id, it.text, value or "", true)
                    bad = bad + 1
                end
                n = n + 1
            end
        end
    end
    lastId = keep
    return n, bad
end

function DC:RunChecks()
    local n, bad = RunChecks()
    DC:Refresh()
    return n, bad
end

-- An addon's own slash command, found in SlashCmdList and called directly.
-- The game's secure commands (/cast, /target, ...) are not there and cannot
-- be run from code.
local function RunSlash(line)
    local cmd, rest = tostring(line):match("^%s*(/%S+)%s*(.-)%s*$")
    if not cmd then error("not a slash command: " .. tostring(line), 0) end
    cmd = cmd:lower()
    for name, fn in pairs(SlashCmdList) do
        local i = 1
        while type(_G["SLASH_" .. name .. i]) == "string" do
            if _G["SLASH_" .. name .. i]:lower() == cmd then fn(rest) return end
            i = i + 1
        end
    end
    error("no addon command " .. cmd, 0)
end

-- Run a look's setup (a function or an addon slash command). Refused in
-- combat. Returns true when it ran without an error.
local function SetUp(it)
    if InCombatLockdown() then
        Print("Set Up waits for combat to end. Try again after the fight.")
        return false
    end
    local ok, err = pcall(type(it.setup) == "function" and it.setup or RunSlash, it.setup)
    if not ok then Print("Set Up failed: " .. (Cap(err, VALUE_MAX) or "?")) end
    return ok
end

local function EndShot(result)
    if pendingShot then
        pendingShot.result = result
        Print(result == "saved"
            and ("capture saved. Look for " .. pendingShot.file .. " in the game's Screenshots folder (the time in the name can be a second later).")
            or "capture failed: the game did not take the screenshot.")
    end
    pendingShot = nil
    ev:UnregisterEvent("SCREENSHOT_SUCCEEDED")
    ev:UnregisterEvent("SCREENSHOT_FAILED")
end

-- Ask the game for a screenshot and save when, for which round and task,
-- how it went ("saved", "failed", or "asked" when the game never said) and
-- the file name the game gives a screenshot taken at that time (without the
-- extension, which follows the game's screenshot format setting).
-- Returns the id it was saved under and the time.
function DC:Capture(id, text)
    if not db then return end
    id = id or OpenRound() or "General"
    local shot = { at = date("%Y-%m-%d %H:%M:%S"), task = Cap(text, VALUE_MAX), result = "asked",
        file = "WoWScrnShot_" .. date("%m%d%y_%H%M%S") }
    local list = db.shots[id] or {}
    db.shots[id] = list
    list[#list + 1] = shot
    while #list > SHOT_MAX do table.remove(list, 1) end
    pendingShot = shot
    ev:RegisterEvent("SCREENSHOT_SUCCEEDED")
    ev:RegisterEvent("SCREENSHOT_FAILED")
    if not pcall(Screenshot) then EndShot("failed") end
    return id, shot.at
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
    if db then
        db.parked[id], db.done[id], db.fail[id], db.snap[id], db.collapsed[id], db.groups[id] = nil, nil, nil, nil, nil, nil
        db.notes[id], db.check[id], db.needs[id], db.remark[id], db.shots[id] = nil, nil, nil, nil, nil
        -- Its log lines too ("[id] ..."), so a cleared round leaves no trail.
        local tag, keep = "[" .. id .. "]", {}
        for _, line in ipairs(db.log or {}) do
            if not line:find(tag, 1, true) then keep[#keep + 1] = line end
        end
        if db.log then db.log = keep end
    end
    DC:Refresh()
end

function DC:IsDone(id, text) return Done(id, text) end

-- passed, total for one id (needs items are not counted).
function DC:Progress(id)
    for _, r in ipairs(Rounds()) do
        if r.id == id then
            local p, _, n = Tally(r)
            return p, n
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
    if db.scale then frame:SetScale(db.scale) end
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

-- Fold state is saved per id; unset, a round folds once nothing in it is waiting.
local function Folded(r, settled)
    local c = db.collapsed[r.id]
    if c == nil then return settled end
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

-- Free text box (under an item, or for a round note). Enter saves, Shift+Enter
-- starts a new line, Esc closes and keeps what was already saved.
-- ponytail: no scroll frame, so a very long text runs past the box while
-- typing (all of it is saved). Add one if that bothers.
local function NoteForm(body, y, indent, placeholder, initial, onSave)
    local e = CreateFrame("EditBox", nil, body, "BackdropTemplate")
    e:SetPoint("TOPLEFT", indent, y - 2)
    e:SetSize(W - PAD - indent, 48)
    Panel(e, 0.031, 1)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFont(FontPath(), 11, "OUTLINE")
    e:SetTextInsets(5, 5, 4, 4)
    e:SetMaxLetters(TEXT_MAX)
    local ph = Text(e, 11, MUTED)
    ph:SetPoint("TOPLEFT", 5, -4)
    ph:SetText(placeholder)
    ph:SetShown((initial or "") == "")
    e:SetText(initial or "")
    e:SetScript("OnTextChanged", function(self)
        ph:SetShown(self:GetText() == "")
        if editing then editing.draft = self:GetText() end
    end)
    e:SetScript("OnEnterPressed", function(self)
        if IsShiftKeyDown() then self:Insert("\n") return end
        onSave(Trim(self:GetText()))
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); editing = nil; Layout() end)
    e:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(Brand()) end)
    e:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
    e:SetFocus()
    return 54
end

-- Saved text as one short line for a row (the full text stays in saved data).
local function Short(t)
    t = t:gsub("[\r\n]+", " "):gsub("|", "||")
    return #t > 120 and (t:sub(1, 117) .. "...") or t
end

local LIMITS = "Nothing leaves the game until you /reload or log out. The addon cannot press protected buttons. "
    .. "Checks and Set Up wait for combat to end. A check proves state, never how something looks. (? hides this.)"

local function SayNote(id, general)
    if id then Print(general and "note saved to General (no round open)." or ("note saved to " .. id .. ".")) end
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
    local rounds = Rounds()

    -- Tools: run the checks, write a note, take a screenshot, show the limits.
    -- Framed and set apart, so they do not read as part of the title bar.
    local hasChecks = false
    for _, r in ipairs(rounds) do
        for _, it in ipairs(r.items) do if it.kind == "check" then hasChecks = true end end
    end
    local tx = PAD
    y = y - 4
    local function Tool(label, width, fn)
        local b = Button(body, label, width)
        b:SetHeight(18)
        b:SetBackdropColor(0.13, 0.13, 0.13, 1)
        b:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        b:SetPoint("TOPLEFT", tx, y)
        b:SetScript("OnClick", fn)
        tx = tx + width + 6
    end
    if hasChecks then
        Tool("Run Checks", 76, function()
            local n, bad = DC:RunChecks()
            if n then Print(n .. (n == 1 and " check ran, " or " checks ran, ") .. bad .. " failed.") end
        end)
    end
    Tool("Add Note", 66, function()
        if editing and editing.kind == "roundnote" then editing = nil else editing = { kind = "roundnote" } end
        Layout()
    end)
    Tool("Capture Screen", 98, function() DC:Capture() end)
    Tool("?", 22, function() db.limits = db.limits == false; Layout() end)
    y = y - 24
    local rule = body:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.12)
    rule:SetPoint("TOPLEFT", PAD, y)
    rule:SetSize(W - 2 * PAD, Px(body))
    y = y - 6
    if checksWaiting then
        local wait = Text(body, 11, FAIL)
        wait:SetPoint("TOPLEFT", PAD, y - 2)
        wait:SetText("In combat: the checks run when it ends.")
        y = y - 18
    end
    if db.limits ~= false then
        local lim = Text(body, 10, NOTE)
        lim:SetPoint("TOPLEFT", PAD, y - 2)
        lim:SetWidth(W - 2 * PAD)
        lim:SetWordWrap(true)
        lim:SetText(LIMITS)
        y = y - (lim:GetStringHeight() + 8)
    end

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
    elseif editing and editing.kind == "roundnote" then
        formTop = -y
        formH = NoteForm(body, y, PAD, "Note for the open round. Enter saves, Shift+Enter starts a new line", editing.draft,
            function(t)
                editing = nil
                SayNote(DC:Note(t))
                Layout()
            end)
        y = y - formH
    end

    for _, r in ipairs(rounds) do
        any = true
        local done, nfail, total = Tally(r)
        open = open + total - done
        local settled = true
        for _, it in ipairs(r.items) do
            if not Done(r.id, it.text) and not (it.kind == "needs" and Needs(r.id, it.text)) then settled = false end
        end
        local adding = editing and editing.kind == "task" and editing.id == r.id
        local folded = not adding and #r.items > 0 and Folded(r, settled)

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
        hc:SetText(CountText(done, total, nfail))
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

        -- A heading inside a round: "Checked by code", "Needs a situation".
        local function Section(title, detail)
            local t = Text(body, 11)
            t:SetPoint("TOPLEFT", PAD, y - 4)
            t:SetWidth(W - 2 * PAD)
            t:SetWordWrap(false)
            t:SetText(title .. "  |cff9a9a9a" .. detail .. "|r")
            y = y - 18
        end

        -- One look or needs task: the row (left click passes, right click
        -- fails and asks what is off; again to clear), the answer buttons
        -- while it is not passed, and the text box when one is open for it.
        local function TaskRow(it)
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
            local on, note, ans = Done(r.id, it.text), Failed(r.id, it.text), Needs(r.id, it.text)
            local c = note and FAIL or ((on or ans) and MUTED) or { 1, 1, 1 }
            box.fill:SetColorTexture(note and FAIL[1] or br, note and FAIL[2] or bg, note and FAIL[3] or bb, 0.8)
            box.fill:SetShown(on or note ~= nil)
            fs:SetTextColor(c[1], c[2], c[3])
            local extra = ""
            if it.kind == "needs" and type(it.needs) == "string" and it.needs ~= "" then
                extra = "  |cff9a9a9aneeds: " .. Short(it.needs) .. "|r"
            end
            if type(it.send) == "string" and it.send ~= "" then extra = extra .. "  |cff9a9a9a" .. it.send .. "|r" end
            if note and note ~= "" then
                extra = extra .. "  |cffe64d4d" .. Short(note) .. "|r"
            elseif on and Remark(r.id, it.text) then
                extra = extra .. "  |cff9a9a9a" .. Short(Remark(r.id, it.text)) .. "|r"
            elseif ans then
                extra = extra .. "  |cff9a9a9a(" .. (ans == "skip" and "skipped" or "couldn't") .. ")|r"
            end
            fs:SetText(it.text .. extra)
            local function Off()
                if Failed(r.id, it.text) == nil then SetFail(r.id, it.text, "") end
                editing = { kind = "note", id = r.id, text = it.text }
                Layout()
            end
            row:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    if Failed(r.id, it.text) ~= nil then
                        SetFail(r.id, it.text, nil)
                        editing = nil
                        Layout()
                    else
                        Off()
                    end
                    return
                end
                -- A left click moves on: close an open text box (this item's or another's).
                if editing and editing.kind == "note" then editing = nil end
                SetDone(r.id, it.text, not Done(r.id, it.text))
                Layout()
            end)
            if it.parked then
                local del = XButton(row, 7, "Delete Task")
                del:SetPoint("TOPRIGHT", -4, -1)
                del:SetScript("OnClick", function() DC:Unpark(r.id, it.parked) end)
            end
            local rh = math.max(20, fs:GetStringHeight() + 8)
            row:SetSize(W, rh)
            y = y - rh
            -- Answer buttons (round tasks only; a task you added yourself is just clicked).
            if not on and not it.parked then
                local sx = PAD + 20
                local function Act(label, width, fn)
                    local b = Button(body, label, width)
                    b:SetHeight(18)
                    b:SetPoint("TOPLEFT", sx, y)
                    b:SetScript("OnClick", fn)
                    sx = sx + width + 4
                end
                if it.kind == "needs" then
                    Act("Did It", 50, function() editing = nil; SetDone(r.id, it.text, true); Layout() end)
                    Act("Couldn't", 60, function() editing = nil; SetNeeds(r.id, it.text, "couldnt"); Layout() end)
                    Act("Skip", 40, function() editing = nil; SetNeeds(r.id, it.text, "skip"); Layout() end)
                else
                    if it.setup then Act("Set Up", 50, function() SetUp(it) end) end
                    Act("Looks Right", 76, function()
                        SetDone(r.id, it.text, true)
                        editing = { kind = "note", id = r.id, text = it.text, remark = true }
                        Layout()
                    end)
                    Act("Something's Off", 100, Off)
                    Act("Capture", 56, function() DC:Capture(r.id, it.text) end)
                end
                y = y - 22
            end
            if editing and editing.kind == "note" and editing.id == r.id and editing.text == it.text then
                local remark = editing.remark
                formTop = -y
                formH = NoteForm(body, y, PAD + 20,
                    remark and "Anything to add? Enter saves, Esc skips" or "What is off? Enter saves",
                    editing.draft or (remark and Remark(r.id, it.text)) or (not remark and Failed(r.id, it.text)) or "",
                    function(t)
                        if remark then SetRemark(r.id, it.text, t) else SetFail(r.id, it.text, t) end
                        editing = nil
                        Layout()
                    end)
                y = y - formH
            end
        end

        if not folded then
            -- The tester's part first: what needs eyes and feel.
            local lastArea
            local nCheck, okCheck, nNeeds = 0, 0, 0
            for _, it in ipairs(r.items) do
                if it.kind == "check" then
                    nCheck = nCheck + 1
                    if Done(r.id, it.text) then okCheck = okCheck + 1 end
                elseif it.kind == "needs" then
                    nNeeds = nNeeds + 1
                else
                    if it.area ~= "" and it.area ~= lastArea then
                        local a = Text(body, 11, NOTE)
                        a:SetPoint("TOPLEFT", PAD, y - 4)
                        a:SetText(it.area)
                        y = y - 18
                    end
                    lastArea = it.area
                    TaskRow(it)
                end
            end

            -- Checked by code: one line when all pass, else the ones that do not.
            if nCheck > 0 then
                Section("Checked by code", okCheck == nCheck and ("all " .. nCheck .. " pass") or (okCheck .. "/" .. nCheck .. " pass"))
                for _, it in ipairs(r.items) do
                    if it.kind == "check" and not Done(r.id, it.text) then
                        local value = Failed(r.id, it.text)
                        local row = CreateFrame("Frame", nil, body)
                        row:SetPoint("TOPLEFT", 0, y)
                        local box = Box(row)
                        box:SetPoint("TOPLEFT", PAD, -3)
                        box.fill:SetColorTexture(FAIL[1], FAIL[2], FAIL[3], 0.8)
                        box.fill:SetShown(value ~= nil)
                        local fs = Text(row, 11, value and FAIL or nil)
                        fs:SetPoint("TOPLEFT", PAD + 20, -4)
                        fs:SetWidth(W - 2 * PAD - 20)
                        fs:SetWordWrap(true)
                        fs:SetText(it.text .. (value and ("  " .. Short(value ~= "" and value or "failed"))
                            or "  |cff9a9a9anot run yet|r"))
                        local rh = math.max(20, fs:GetStringHeight() + 8)
                        row:SetSize(W, rh)
                        y = y - rh
                    end
                end
            end

            -- Needs a situation: said up front that the addon cannot test these.
            if nNeeds > 0 then
                Section("Needs a situation", "the addon cannot test these; right click: tried, failed")
                for _, it in ipairs(r.items) do
                    if it.kind == "needs" then TaskRow(it) end
                end
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
            -- Looks and checks are counted; needs items are listed apart and
            -- never keep the round from reading as passed.
            local pass, open, fails, needs = 0, 0, {}, {}
            for _, it in ipairs(r.items) do
                local note = Failed(r.id, it.text)
                if it.kind == "needs" then
                    needs[#needs + 1] = { text = it.text, needs = Cap(it.needs, VALUE_MAX), note = note,
                        answer = Done(r.id, it.text) and "pass" or note and "fail" or Needs(r.id, it.text) or "open" }
                elseif Done(r.id, it.text) then
                    pass = pass + 1
                elseif note then
                    fails[#fails + 1] = { text = it.text, note = note, kind = it.kind }
                else
                    open = open + 1
                end
            end
            db.report[r.id] = { round = r.round, build = r.build, pass = pass, open = open, fail = fails,
                needs = needs, passed = open == 0 and #fails == 0 }
        end
    end
end

ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGOUT" then WriteReport() return end
    if event == "PLAYER_REGEN_ENABLED" then          -- watched only while checks wait for combat to end
        if checksWaiting then DC:RunChecks() else ev:UnregisterEvent(event) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then         -- once after a login or reload, when a round has checks
        ev:UnregisterEvent(event)
        DC:RunChecks()
        return
    end
    if event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then   -- watched only after a capture
        EndShot(event == "SCREENSHOT_SUCCEEDED" and "saved" or "failed")
        return
    end
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
        db.notes = db.notes or {}
        db.check = db.check or {}
        db.needs = db.needs or {}
        db.remark = db.remark or {}
        db.shots = db.shots or {}
        for _, fn in ipairs(pending) do fn() end
        pending = nil
        ev:UnregisterEvent("ADDON_LOADED")
        Arm()   -- round files are loaded by now: record Log lines other addons send while they load
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
    -- A round closed from outside (its file removed) leaves its ticks, fails,
    -- snapshots and log lines behind; every id still in use is in Rounds()
    -- (loaded rounds, parked items, own lists), so anything else is stale.
    -- Closing happens after the results are read, so nothing wanted goes.
    do
        local live = {}
        for _, r in ipairs(Rounds()) do live[r.id] = true end
        local stale = {}
        for _, t in ipairs({ db.done, db.fail, db.snap, db.collapsed, db.check, db.needs, db.remark }) do
            for id in pairs(t) do if not live[id] then stale[id] = true end end
        end
        if next(stale) then
            for id in pairs(stale) do
                db.done[id], db.fail[id], db.snap[id], db.collapsed[id] = nil, nil, nil, nil
                db.check[id], db.needs[id], db.remark[id] = nil, nil, nil
            end
            local keep = {}
            for _, line in ipairs(db.log) do
                local tagged = line:match("^%S+ %[([^%]]+)%]")
                if not (tagged and stale[tagged]) then keep[#keep + 1] = line end
            end
            db.log = keep
        end
        -- Notes and captures of a closed round go the same way ("General" has no round and stays).
        for _, t in ipairs({ db.notes, db.shots }) do
            for id in pairs(t) do
                if not live[id] and id ~= "General" then t[id] = nil end
            end
        end
    end
    Arm()
    local show
    for _, r in ipairs(Rounds()) do
        for _, it in ipairs(r.items) do
            if it.kind == "check" then ev:RegisterEvent("PLAYER_ENTERING_WORLD") end   -- run them once the world is in
            if it.kind ~= "needs" and not Done(r.id, it.text) then show = true end
        end
    end
    if show then DC:Show() end
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
    elseif cmd == "note" and rest ~= "" then
        SayNote(DC:Note(rest))
    elseif cmd == "shot" then
        DC:Capture()
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n then
            db.scale = math.min(2, math.max(0.8, n))
            if frame then frame:SetScale(db.scale) end
            DC:Refresh()
        end
        Print(("window size %.2f. /dc scale <0.8 to 2.0> changes it."):format(db.scale or 1))
    elseif cmd == "run" then
        local n, bad = DC:RunChecks()
        Print(n and (n .. (n == 1 and " check ran, " or " checks ran, ") .. bad .. " failed.")
            or "in combat: the checks run when it ends.")
    else
        Print("|cffffffff/dc|r show or hide  |cffffffff/dc add [area:] text|r park an item  |cffffffff/dc note text|r note for the open round  |cffffffff/dc shot|r screenshot  |cffffffff/dc run|r run the checks  |cffffffff/dc scale 0.8-2.0|r window size  |cffffffff/dc clear <round>|r drop a round and its ticks")
    end
end
