-- Print one round's results from a saved DevChecklist file, outside the game.
-- Usage: luajit tools/results.lua <path to SavedVariables/DevChecklist.lua> <round id>
-- Any Lua 5.1 works. The file is only read. The game writes it on /reload and
-- logout, so reload before running this.
local path, id = arg[1], arg[2]
if not path or not id then
    io.write("usage: results.lua <SavedVariables/DevChecklist.lua> <round id>\n")
    os.exit(2)
end
local chunk = assert(loadfile(path))
local env = {}
setfenv(chunk, env)()
local db = assert(env.DevChecklistDB, "no DevChecklistDB in " .. path)

local function sorted(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end
local function of(name) return db[name] and db[name][id] or {} end
-- Text that may hold several lines, with the later lines indented.
local function lines(text, pad) return (tostring(text):gsub("\n", "\n" .. pad)) end

local function stamp(s)
    return ("%s | %s | combat %s | spec %s | group %s%s"):format(tostring(s.at), tostring(s.zone),
        tostring(s.combat), tostring(s.spec), tostring(s.group), s.build and (" | build " .. s.build) or "")
end
-- The surroundings saved with a fail or a note: the stamp, then whatever else was read.
local MORE = { "subzone", "instance", "level", "groupType", "screen", "uiScale", "client", "fps", "latency", "mouse", "error" }
local function around(s, pad, withLog)
    print(pad .. stamp(s))
    local parts = {}
    for _, k in ipairs(MORE) do
        if s[k] ~= nil then parts[#parts + 1] = k .. " " .. tostring(s[k]) end
    end
    if #parts > 0 then print(pad .. table.concat(parts, " | ")) end
    if s.frames and #s.frames > 0 then print(pad .. "frames shown: " .. table.concat(s.frames, ", ")) end
    if withLog then
        for _, line in ipairs(s.log or {}) do print(pad .. "  " .. line) end
    end
end

local rep = db.report and db.report[id]
if rep then
    print(("== %s: %s%s (as of the last reload)"):format(id, tostring(rep.round),
        rep.build and (", build " .. rep.build) or ""))
    print(("   %d passed, %d failed, %d not ticked"):format(rep.pass, #rep.fail, rep.open))
    if rep.passed ~= nil then
        print("   round passed: " .. (rep.passed and "yes" or "no") .. " (looks and checks; needs tasks are listed apart)")
    end
else
    print("== " .. id .. ": no report (round not loaded at the last reload)")
end

-- Checks and needs tasks get their own sections; everything else is a look.
local checks, needs, apart = of("check"), rep and rep.needs or {}, {}
for text in pairs(checks) do apart[text] = true end
for _, n in ipairs(needs) do apart[n.text] = true end
local snaps, remarks = of("snap"), of("remark")

print("== Passed")
for _, text in ipairs(sorted(of("done"))) do
    if not apart[text] then
        print("  [x] " .. text .. (remarks[text] and ("  -- " .. lines(remarks[text], "        ")) or ""))
    end
end

print("== Failed")
local fails = of("fail")
for _, text in ipairs(sorted(fails)) do
    if not apart[text] then
        print("  [FAIL] " .. text .. (fails[text] ~= "" and ("  -- " .. lines(fails[text], "        ")) or ""))
        if snaps[text] then around(snaps[text], "      ", true) end
    end
end

if next(checks) then
    print("== Checked by code")
    for _, text in ipairs(sorted(checks)) do
        local c = checks[text]
        print(("  [%s] %s%s  (%s)"):format(c.ok and "ok" or "FAIL", text,
            c.value ~= nil and (" = " .. tostring(c.value)) or "", tostring(c.at)))
    end
end

if #needs > 0 then
    print("== Needs a situation (the addon cannot test these)")
    for _, n in ipairs(needs) do
        print(("  [%s] %s  (needs: %s)%s"):format(tostring(n.answer), n.text, tostring(n.needs or "?"),
            (n.note and n.note ~= "") and ("  -- " .. lines(n.note, "        ")) or ""))
        if snaps[n.text] then around(snaps[n.text], "      ", true) end
    end
end

print("== Notes")
for _, n in ipairs(of("notes")) do
    if n.round then                       -- saved with the full surroundings
        print("  " .. lines(n.text, "  "))
        around(n, "      ", true)
    else
        print("  " .. stamp(n) .. " | " .. tostring(n.text))
    end
end

local shots = of("shots")
if #shots > 0 then
    print("== Captures (match the file in the game's Screenshots folder by time)")
    for _, c in ipairs(shots) do
        print(("  %s | %s | %s%s"):format(tostring(c.at), tostring(c.result), tostring(c.task or "(no task)"),
            c.file and (" | " .. c.file) or ""))
    end
end

print("== Flight recorder lines for this round")
local tag = "[" .. id .. "]"
for _, line in ipairs(db.log or {}) do
    if line:find(tag, 1, true) then print("  " .. line) end
end
