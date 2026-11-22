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
local function stamp(s)
    return ("%s | %s | combat %s | spec %s | group %s%s"):format(tostring(s.at), tostring(s.zone),
        tostring(s.combat), tostring(s.spec), tostring(s.group), s.build and (" | build " .. s.build) or "")
end

local rep = db.report and db.report[id]
if rep then
    print(("== %s: %s%s (as of the last reload)"):format(id, tostring(rep.round),
        rep.build and (", build " .. rep.build) or ""))
    print(("   %d passed, %d failed, %d not ticked"):format(rep.pass, #rep.fail, rep.open))
else
    print("== " .. id .. ": no report (round not loaded at the last reload)")
end

print("== Passed")
for _, text in ipairs(sorted(db.done and db.done[id])) do print("  [x] " .. text) end

print("== Failed")
local snaps = db.snap and db.snap[id] or {}
for _, text in ipairs(sorted(db.fail and db.fail[id])) do
    local note = db.fail[id][text]
    print("  [FAIL] " .. text .. (note ~= "" and ("  -- " .. note) or ""))
    local s = snaps[text]
    if s then
        print("      " .. stamp(s))
        for _, line in ipairs(s.log or {}) do print("        " .. line) end
    end
end

print("== Notes")
for _, n in ipairs(db.notes and db.notes[id] or {}) do print("  " .. stamp(n) .. " | " .. tostring(n.text)) end

print("== Flight recorder lines for this round")
local tag = "[" .. id .. "]"
for _, line in ipairs(db.log or {}) do
    if line:find(tag, 1, true) then print("  " .. line) end
end
