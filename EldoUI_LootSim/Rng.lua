-- EldoUI Loot Sim: random numbers.
--
-- Park and Miller's "minimal standard" generator (state = state * 16807 mod
-- 2^31 - 1). Lua 5.1 numbers are doubles: 16807 * (2^31 - 1) is below 2^53,
-- so every step is exact and a seed gives the same numbers on every client.
--
-- Paired dice: a fight asks for named streams ("melee", "spell", "proc" ...)
-- derived from its seed. Two fights with the same seed (your gear and the
-- same gear with one item swapped) roll the same dice for the same kind of
-- event, so the difference between them is mostly the item, not luck.
--
-- This file also opens the addon: S is the private table every file of
-- EldoUI_LootSim shares; it is published as EldoUI.LootSim.
local _, S = ...
local E = EldoUI
S.E = E
if type(E) == "table" then E.LootSim = S end

local Rng = {}
Rng.__index = Rng
S.Rng = Rng

local MODULUS = 2147483647
local MULTIPLIER = 16807
Rng.MODULUS = MODULUS

-- A new generator; seed is any number (folded into 1 .. 2^31 - 2).
function Rng.New(seed)
	seed = math.floor(math.abs(tonumber(seed) or 1)) % MODULUS
	if seed == 0 then seed = 1 end
	return setmetatable({ state = seed, seed = seed }, Rng)
end

-- The next raw value, 1 .. 2^31 - 2.
function Rng:Next()
	self.state = (self.state * MULTIPLIER) % MODULUS
	return self.state
end

-- A number in (0, 1).
function Rng:Random()
	return self:Next() / MODULUS
end

-- A number between low and high.
function Rng:Range(low, high)
	return low + (high - low) * self:Random()
end

-- true with the given percent chance.
function Rng:Chance(percent)
	return self:Random() * 100 < percent
end

-- A small stable hash of a text (for stream seeds).
function Rng.Hash(text)
	local hash = 5381
	text = tostring(text)
	for index = 1, #text do
		hash = (hash * 33 + text:byte(index)) % MODULUS
	end
	return hash
end

-- A child generator for one kind of roll, fixed by this generator's seed
-- and the name (not by how many numbers were drawn before).
function Rng:Stream(name)
	return Rng.New((self.seed * 31 + Rng.Hash(name)) % MODULUS)
end
