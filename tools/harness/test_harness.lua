-- Does the offline start (tools/harness/load_eldoui.lua) catch a broken
-- module? Run from the repository root:
--   lua5.1 tools/harness/test_harness.lua
-- It runs the harness with tools/harness/fixtures/broken_module.lua as one
-- more EldoUI file: a module whose OnEnable fails. The run must end with
-- exit code 1 and name the module and the line; the module list must count
-- it. Needs io.popen (Linux, as on GitHub).
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/harness/") or "./"

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

local function Run(extra)
	local command = ('lua5.1 "%stools/harness/load_eldoui.lua" %s 2>&1; echo "EXIT:$?"'):format(ROOT, extra or "")
	local pipe = assert(io.popen(command), "io.popen is needed")
	local output = pipe:read("*a")
	pipe:close()
	return output, tonumber(output:match("EXIT:(%d+)")), tonumber(output:match("(%d+) modules"))
end

local plain, plainExit, plainModules = Run()
Check(plainExit == 0, "EldoUI alone starts without errors (exit " .. tostring(plainExit) .. ")")
local output, exit, modules = Run(('--extra "%stools/harness/fixtures/broken_module.lua"'):format(ROOT))
Check(exit == 1, "a broken module makes the run fail (exit " .. tostring(exit) .. ")")
Check(output:find("HarnessBroken:OnEnable failed", 1, true) ~= nil, "the report names the module")
Check(output:find("broken_module.lua:8:", 1, true) ~= nil, "the report names the file and line")
Check(output:find("[PLAYER_LOGIN]", 1, true) ~= nil, "the report names the phase")
Check(plainModules and modules == plainModules + 1, ("the module is counted (%s, then %s)"):format(tostring(plainModules), tostring(modules)))
if failed > 0 then print(plain) print(output) end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
