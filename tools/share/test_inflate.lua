-- Offline test for E:Inflate, the size check before unpacking (review F08).
-- Run from the repository root (needs python3 for the cases):
--   lua5.1 tools/share/test_inflate.lua
-- It cuts the size walk and E:Inflate out of EldoUI/Core/Share.lua (between
-- fixed markers, so a renamed part makes the test fail instead of testing a
-- stale copy) and checks them with the streams tools/share/deflate_cases.py
-- makes with zlib:
--   * zlib streams of every kind (stored, fixed and dynamic blocks, all
--     strategies and levels, flushes), cut short and with a bit flipped:
--     the walk gives zlib's size, or "damaged" where zlib fails;
--   * hand-made streams for each rule (block type 3, a copy from before the
--     start, codes 286 and 30, bad code sets) and for the block limit;
--   * strings that unpack past the limit stop early with "long", and
--     E:Inflate never hands them (or damaged ones) to the game;
--   * how long the slowest kinds of stream take.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/share/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local share = ReadFile("EldoUI/Core/Share.lua")
local source = table.concat({
	"local E = ...",
	Between(share, "local Inflate = {", "-- prefix: \"!EUI1!\" for settings", "Share.lua"),
	"return Inflate",
}, "\n")
local E = {}
local Inflate = assert(loadstring(source, "=Share.lua (Inflate)"))(E)
assert(type(Inflate.Size) == "function" and type(E.Inflate) == "function", "Share.lua: Inflate.Size or E:Inflate missing")

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

local function Walk(data, limit)
	local ok, result = pcall(Inflate.Size, data, limit)
	if ok then return result end
	-- Anything but "long" and "damaged" is a mistake in the walk itself.
	return (result == "long" or result == "damaged") and result or "error", result
end

local HEX = {}
for value = 0, 255 do HEX[("%02x"):format(value)] = string.char(value) end
local function FromHex(hex) return (hex:gsub("%x%x", HEX)) end

-- The cases
local cases, byName, ended = {}, {}, nil
local pipe = assert(io.popen("python3 " .. ROOT .. "tools/share/deflate_cases.py"))
for line in pipe:lines() do
	local count = line:match("^#end\t(%d+)$")
	if count then
		ended = tonumber(count)
	else
		local name, expect, limit, hex = line:match("^([^\t]*)\t([^\t]*)\t(%d+)\t(%x*)$")
		assert(name, "deflate_cases.py: a line I can't read: " .. line:sub(1, 80))
		local case = { name = name, expect = tonumber(expect) or expect, limit = tonumber(limit), data = FromHex(hex) }
		cases[#cases + 1] = case
		byName[name] = case
	end
end
pipe:close()
assert(ended and ended == #cases, "deflate_cases.py stopped early (is python3 there?)")

local times = {}
for _, case in ipairs(cases) do
	local started = os.clock()
	local got, message = Walk(case.data, case.limit)
	local took = os.clock() - started
	Check(got == case.expect, ("%s: expected %s, got %s%s"):format(case.name, tostring(case.expect), tostring(got),
		got == "error" and (" (" .. tostring(message) .. ")") or ""))
	if case.name:match("^fast:") then
		Check(took < 0.5, ("%s: took %.2f s"):format(case.name, took))
	elseif case.name:match("^slow:") then
		times[#times + 1] = ("  %s: %d KB in %.2f s"):format(case.name, math.floor(#case.data / 1024), took)
	end
end

-- E:Inflate: the game's DecompressString only sees strings that passed.
local calls, answer = 0, nil
local function Game(present)
	if not present then
		C_EncodingUtil, Enum = nil, nil
		return
	end
	C_EncodingUtil = {
		DecompressString = function(bytes, method)
			calls = calls + 1
			assert(method == "deflate", "E:Inflate: not the Deflate method")
			return answer(bytes)
		end,
	}
	Enum = { CompressionMethod = { Deflate = "deflate" } }
end

local function Inflated(case, limit, reply)
	calls, answer = 0, reply or function() return string.rep("x", case.expect) end
	return E:Inflate(case.data, limit or case.limit)
end

Game(true)
local atLimit = assert(byName["zeros at the limit"])
local text, problem = Inflated(atLimit)
Check(type(text) == "string" and #text == atLimit.expect and problem == nil and calls == 1,
	"E:Inflate: a string at the limit is unpacked once")
local bomb = assert(byName["fast: 64 MB of zeros"])
text, problem = Inflated(bomb, nil, function() error("unpacked a bomb") end)
Check(text == nil and problem == "long" and calls == 0, "E:Inflate: a string past the limit is never unpacked")
local damaged = assert(byName["crafted: copy from before the start"])
text, problem = Inflated(damaged, nil, function() return "x" end)
Check(text == nil and problem == "damaged" and calls == 0, "E:Inflate: a damaged string is never unpacked")
local good = assert(byName["crafted: dynamic block"])
text, problem = Inflated(good, nil, function() error("the game failed") end)
Check(text == nil and problem == "damaged" and calls == 1, "E:Inflate: the game failing counts as damaged")
text, problem = Inflated(good, nil, function() return nil end)
Check(text == nil and problem == "damaged", "E:Inflate: no text from the game counts as damaged")
text, problem = Inflated(good, good.expect, function() return string.rep("x", good.expect + 1) end)
Check(text == nil and problem == "long", "E:Inflate: the game's length has the last word")
text, problem = E:Inflate(nil, 100)
Check(text == nil and problem == "damaged", "E:Inflate: no bytes")
Game(false)
text, problem = Inflated(good)
Check(text == nil and problem == "client" and calls == 0, "E:Inflate: a client without DecompressString")

-- Share.lua and Import.lua unpack through E:Inflate only.
local import = ReadFile("EldoUI/Core/Import.lua")
-- Calls look like util.DecompressString(...) or pcall(util.DecompressString, ...).
local function Unpacks(text)
	local count = 0
	for _ in text:gmatch("DecompressString%s*%(") do count = count + 1 end
	for _ in text:gmatch("pcall%(%s*[%w_.]*DecompressString%s*,") do count = count + 1 end
	return count
end
Check(Unpacks(share) == 1, "Share.lua: DecompressString is called only in E:Inflate")
Check(Unpacks(import) == 0, "Import.lua: DecompressString is called only through E:Inflate")

print("Timings:")
for _, line in ipairs(times) do print(line) end
print(("%d checks passed, %d failed (%d streams)"):format(passed, failed, #cases))
if failed > 0 then os.exit(1) end
