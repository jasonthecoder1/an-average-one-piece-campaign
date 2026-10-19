-- Dodge-box bullets, shared by the client box (DodgeBox.luau) and the server's check (BattleService).
-- Both sides build the SAME bullets from the server's seed (same Random calls in the same order), so the server
-- can replay the heart path the client sends and count the hits and grazes itself.
-- Times are seconds of box time from the start; positions are box units (box = 0..1, y goes down).
local BattleDefs = require(script.Parent.BattleDefs)

local DodgePatterns = {}

DodgePatterns.HEART_R = 0.022 -- in box units
DodgePatterns.SPEED = 0.62 -- box units per second
DodgePatterns.DASH_TIME = 0.16
DodgePatterns.DASH_SPEED = 2.6
DodgePatterns.DASH_COOLDOWN = 0.9
DodgePatterns.HIT_IFRAMES = 0.6
DodgePatterns.GRAZE_PAD = 0.045
DodgePatterns.TELEGRAPH = 0.45
DodgePatterns.START_X, DodgePatterns.START_Y = 0.5, 0.75 -- where the heart starts
DodgePatterns.MAX_STEP = 1 / 20 -- one frame never moves the box clock more than this (a lag spike pauses it)
DodgePatterns.SAMPLE = 0.05 -- the client records the heart path this often
DodgePatterns.MAX_SAMPLES = 400

-- Box times and path numbers are kept to 3 decimals, so both sides work with the exact same values.
function DodgePatterns.round3(v)
	return math.floor(v * 1000 + 0.5) / 1000
end

-- ===== pattern generators: return a list of bullets { t, x, y, vx, vy, r, kind, warnX?, warnY? } =====
-- `aim` bullets get their velocity when they spawn (they aim at the heart, see DodgePatterns.aim).
local Gen = {}

function Gen.rain(rng, dur, density)
	local list = {}
	local t = 0.5
	while t < dur - 0.6 do
		local x = rng:NextNumber(0.05, 0.95)
		local big = rng:NextNumber() < 0.2
		table.insert(list, { t = t, x = x, y = -0.06, vx = rng:NextNumber(-0.05, 0.05), vy = rng:NextNumber(0.5, 0.75), r = if big then 0.05 else 0.032, kind = "ball", warnX = x, warnY = 0.03 })
		t += rng:NextNumber(0.22, 0.4) / density
	end
	return list
end

function Gen.waves(rng, dur, density)
	local list = {}
	local t = 0.6
	local dir = 1
	while t < dur - 1.2 do
		local n = 11
		local gap = rng:NextInteger(1, n - 3)
		local horizontal = rng:NextNumber() < 0.5
		for i = 0, n - 1 do
			if i ~= gap and i ~= gap + 1 and (density < 1.3 or i ~= gap + 2 or rng:NextNumber() < 0.5) then
				local p = (i + 0.5) / n
				local b = { t = t, r = 0.028, kind = "slash" }
				if horizontal then
					b.x, b.y, b.vx, b.vy = (if dir > 0 then -0.05 else 1.05), p, 0.48 * dir, 0
					b.warnX, b.warnY = (if dir > 0 then 0.03 else 0.97), p
				else
					b.x, b.y, b.vx, b.vy = p, (if dir > 0 then -0.05 else 1.05), 0, 0.48 * dir
					b.warnX, b.warnY = p, (if dir > 0 then 0.03 else 0.97)
				end
				table.insert(list, b)
			end
		end
		dir = -dir
		t += rng:NextNumber(0.9, 1.25) / density
	end
	return list
end

function Gen.aimed(rng, dur, density)
	local list = {}
	local t = 0.5
	while t < dur - 0.5 do
		local side = rng:NextInteger(1, 4)
		local s = rng:NextNumber(0.05, 0.95)
		local x, y
		if side == 1 then
			x, y = s, -0.04
		elseif side == 2 then
			x, y = s, 1.04
		elseif side == 3 then
			x, y = -0.04, s
		else
			x, y = 1.04, s
		end
		table.insert(list, { t = t, x = x, y = y, vx = 0, vy = 0, aim = 0.72, r = 0.022, kind = "shot", warnX = math.clamp(x, 0.03, 0.97), warnY = math.clamp(y, 0.03, 0.97), spread = rng:NextNumber(-1, 1) })
		t += rng:NextNumber(0.28, 0.45) / density
	end
	return list
end

function Gen.burst(rng, dur, density)
	local list = {}
	local t = 0.6
	while t < dur - 1 do
		local cx, cy = rng:NextNumber(0.15, 0.85), rng:NextNumber(0.15, 0.85)
		local n = math.floor(10 + 4 * density)
		local off = rng:NextNumber(0, math.pi * 2)
		for i = 1, n do
			local a = off + (i / n) * math.pi * 2
			table.insert(list, { t = t, x = cx, y = cy, vx = math.cos(a) * 0.42, vy = math.sin(a) * 0.42, r = 0.026, kind = "drop", warnX = cx, warnY = cy })
		end
		t += rng:NextNumber(0.85, 1.2) / density
	end
	return list
end

DodgePatterns.Gen = Gen

-- The bullet list for one box, sorted by spawn time. pattern = a BattleDefs.Patterns entry,
-- mods = { stagger?, blind? }. Generator first, then the stagger filter with the same rng (don't change the order:
-- the server rebuilds this list from the seed).
function DodgePatterns.build(pattern, seed, mods, density)
	local rng = Random.new(seed)
	local bullets = (Gen[pattern.gen] or Gen.rain)(rng, pattern.duration, density or pattern.density or 1)
	-- STAGGER: the enemy only gets some of its bullets out
	if mods and mods.stagger then
		local keep = {}
		for _, b in bullets do
			if rng:NextNumber() < BattleDefs.Status.stagger.keep then
				table.insert(keep, b)
			end
		end
		bullets = keep
	end
	-- sort by time; ties keep their built order so both sides get the same list
	for i, b in bullets do
		b.i = i
	end
	table.sort(bullets, function(a, b)
		return a.t < b.t or (a.t == b.t and a.i < b.i)
	end)
	return bullets
end

-- Give an aimed bullet its velocity: it flies at the last recorded heart sample from before it spawns
-- (path = { { t, x, y, dash }... }, oldest first). Client and server pick the same sample.
function DodgePatterns.aim(b, path, blind)
	local hx, hy = DodgePatterns.START_X, DodgePatterns.START_Y
	for i = #path, 1, -1 do
		local s = path[i]
		if s.t < b.t then
			hx, hy = s.x, s.y
			break
		end
	end
	local a = math.atan2(hy - b.y, hx - b.x) + (if blind then (b.spread or 0) * BattleDefs.Status.blind.spread else 0)
	b.vx, b.vy = math.cos(a) * b.aim, math.sin(a) * b.aim
end

return DodgePatterns
