-- Action commands: the timing minigames on your own attacks. Data + pure graders only, so the client minigame,
-- the server rules (BattleService) and any tests read the same numbers. Engine reused from NextLife (with
-- permission); every name and look here is new.
--
--   STRIKE  a marker sweeps a slanted bar left -> right; ONE press grades it by where the marker is (t = 0..1):
--           CRIT near the notch, GOOD around it, MISS if you press too early (or never), WEAK anywhere else.
--   RINGS   (heavy moves) three rings close on a target, `interval` apart; a press near a ring's meet = a spark.
--           0..3 sparks -> multiplier. 3 sparks = PERFECT. Never misses.
--
-- Client -> server timing: { grade = "crit"|"good"|"weak"|"miss", t = number? } for Strike, { sparks = 0..3 } for
-- Rings. The server never trusts it: sanitizeTiming() keeps the shape, resolve() clamps the values, and
-- BattleService also checks the time the answer took (a "crit" that came back too soon becomes WEAK).
local ActionCommandDefs = {}

ActionCommandDefs.Strike = {
	sweep = 0.9, -- seconds for the marker to go from t = 0 to t = 1
	notch = 0.75, -- CRIT notch position along the bar
	critWindow = 0.05,
	goodWindow = 0.15,
	earlyMiss = 0.15, -- pressing with t < this is a MISS (no mashing)
	lead = 0.35, -- seconds before the marker starts moving
	tail = 0.1, -- seconds the marker rests at the end before it counts as MISS
	mult = { crit = 1.5, good = 1.0, weak = 0.6, miss = 0 },
}

ActionCommandDefs.Rings = {
	rings = 3,
	interval = 0.45,
	approach = 0.7,
	lead = 0.35,
	window = 0.1,
	early = 0.2,
	mult = { [0] = 0.8, [1] = 1.0, [2] = 1.15, [3] = 1.35 },
	grade = { [0] = "weak", [1] = "good", [2] = "strong", [3] = "perfect" },
}

ActionCommandDefs.Labels = {
	crit = "CRIT!",
	good = "GOOD",
	weak = "WEAK",
	miss = "MISS",
	strong = "STRONG",
	perfect = "PERFECT!",
}

local function finite(v)
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
ActionCommandDefs.finite = finite

function ActionCommandDefs.strikeGrade(t)
	local d = ActionCommandDefs.Strike
	if t == nil or not finite(t) or t < d.earlyMiss or t > 1 then
		return "miss"
	end
	local off = math.abs(t - d.notch)
	if off <= d.critWindow + 1e-6 then
		return "crit"
	elseif off <= d.goodWindow + 1e-6 then
		return "good"
	end
	return "weak"
end

function ActionCommandDefs.cleanGrade(grade)
	if grade == "crit" or grade == "good" or grade == "weak" or grade == "miss" then
		return grade
	end
	return "weak"
end

function ActionCommandDefs.cleanSparks(sparks)
	if not finite(sparks) then
		return 0
	end
	return math.clamp(math.floor(sparks), 0, ActionCommandDefs.Rings.rings)
end

-- Shape check for an untrusted timing table. Returns nil when nothing usable is left.
function ActionCommandDefs.sanitizeTiming(tm)
	if typeof(tm) ~= "table" then
		return nil
	end
	local out = {}
	if typeof(tm.grade) == "string" and #tm.grade <= 16 then
		out.grade = tm.grade
	end
	if finite(tm.sparks) and math.abs(tm.sparks) < 1000 then
		out.sparks = tm.sparks
	end
	if finite(tm.t) and math.abs(tm.t) < 1000 then
		out.t = tm.t
	end
	if out.grade == nil and out.sparks == nil then
		return nil
	end
	return out
end

-- Earliest time (seconds after the bar appears) a real press could land in a zone. Anything sooner is a cheat
-- or a broken client, so the server downgrades it.
function ActionCommandDefs.strikeEarliest(grade)
	local d = ActionCommandDefs.Strike
	local zone = if grade == "crit" then d.critWindow else d.goodWindow
	return d.lead + d.sweep * (d.notch - zone) - 0.05
end

function ActionCommandDefs.strikeTimeout()
	local d = ActionCommandDefs.Strike
	return d.lead + d.sweep + d.tail + 2.5 -- + network slack
end

function ActionCommandDefs.ringMeets()
	local d = ActionCommandDefs.Rings
	local meets = {}
	for i = 1, d.rings do
		meets[i] = d.lead + d.approach + (i - 1) * d.interval
	end
	return meets
end

function ActionCommandDefs.ringTimeout()
	local meets = ActionCommandDefs.ringMeets()
	return meets[#meets] + ActionCommandDefs.Rings.window + 2.5
end

-- Server entry point. qte = "strike" | "rings" | nil. elapsed = seconds the answer took (server clock).
--   -> { kind, grade, mult, missed, sparks? }
function ActionCommandDefs.resolve(qte, timing, elapsed)
	local tm = if type(timing) == "table" then timing else {}
	if qte == "strike" then
		local grade = ActionCommandDefs.cleanGrade(tm.grade)
		if elapsed and (grade == "crit" or grade == "good") and elapsed < ActionCommandDefs.strikeEarliest(grade) then
			grade = "weak"
		end
		return { kind = qte, grade = grade, mult = ActionCommandDefs.Strike.mult[grade], missed = grade == "miss" }
	elseif qte == "rings" then
		local sparks = ActionCommandDefs.cleanSparks(tm.sparks)
		if elapsed then
			-- a spark can only be claimed for a ring whose window has already opened
			local d = ActionCommandDefs.Rings
			local possible = 0
			for _, m in ActionCommandDefs.ringMeets() do
				if elapsed >= m - d.window - 0.05 then
					possible += 1
				end
			end
			sparks = math.min(sparks, possible)
		end
		local grade = ActionCommandDefs.Rings.grade[sparks]
		return { kind = qte, sparks = sparks, grade = grade, mult = ActionCommandDefs.Rings.mult[sparks], missed = false }
	end
	return { kind = nil, grade = "good", mult = 1, missed = false }
end

return ActionCommandDefs
