-- Battle data: weak points, statuses, dodge-box patterns, enemies and encounter building.
-- Server rules and client visuals both read this. Add a new enemy / boss / pattern by adding a table here.
local BattleDefs = {}

BattleDefs.Stamina = { start = 3, perTurn = 2, max = 10 }
BattleDefs.TurnSeconds = 30 -- pick a move within this, or the game does a basic attack for you
BattleDefs.HpPerExtraPlayer = 0.6 -- enemy HP = base x (1 + 0.6 per extra player)
BattleDefs.DownTakenMult = 1.5
BattleDefs.GrazeForStamina = 5 -- this many grazes in one dodge box = +1 stamina next turn

-- Elements of attacks. An enemy's `weak` element, hit on its CORE, knocks it DOWN.
BattleDefs.Elements = { "Slash", "Pierce", "Blunt", "Shot" }

-- Weak points (bosses and elites have several; normal enemies only have a Core).
BattleDefs.Parts = {
	Core = { id = "Core", label = "CORE", mult = 1, weakSpot = true, desc = "Normal damage. Its weakness lands here: knock it DOWN." },
	Eyes = { id = "Eyes", label = "EYES", mult = 0.8, status = "blind", rage = 1, desc = "x0.8. BLIND: its next attack is less accurate. Fills Rage." },
	Arms = { id = "Arms", label = "ARMS", mult = 0.8, status = "stagger", desc = "x0.8. STAGGER: fewer bullets in its next attack." },
	Legs = { id = "Legs", label = "LEGS", mult = 0.8, status = "slow", desc = "x0.8. SLOW: it acts last next round." },
	Weapon = { id = "Weapon", label = "WEAPON", mult = 0.6, status = "break", rage = 2, desc = "x0.6. 30% chance to BREAK its strongest attack. Fills a lot of Rage." },
}
BattleDefs.PartOrder = { "Core", "Eyes", "Arms", "Legs", "Weapon" }
BattleDefs.BreakChance = 0.3
BattleDefs.RageMax = 3 -- full Rage = its next attack hits 1.5x

BattleDefs.Status = {
	stagger = { label = "STAGGERED", keep = 0.65 }, -- keep 65% of the bullets
	blind = { label = "BLINDED", spread = 0.6, telegraph = 1.4 }, -- aimed shots wobble, warnings last longer
	slow = { label = "SLOWED" },
	down = { label = "DOWN" },
	stun = { label = "STUNNED" },
	poison = { label = "POISON" },
	smoke = { label = "HIDDEN" },
	guard = { label = "PARRY" },
	marked = { label = "MARKED" },
	taunt = { label = "TAUNT" },
	bodyguard = { label = "GUARDED" },
}

-- Dodge-box patterns. `gen` names the client generator (DodgeBox.luau). The server only uses the numbers:
-- it clamps the reported hits to maxHits (x stagger keep) and grazes to maxGraze. stunAt = this many hits STUNS you.
BattleDefs.Patterns = {
	CannonBarrage = { id = "CannonBarrage", label = "CANNON BARRAGE", gen = "rain", duration = 6, damagePerHit = 7, maxHits = 8, density = 1.0 },
	SwordWaves = { id = "SwordWaves", label = "SWORD WAVES", gen = "waves", duration = 6.5, damagePerHit = 8, maxHits = 7, density = 1.0 },
	PistolVolley = { id = "PistolVolley", label = "PISTOL VOLLEY", gen = "aimed", duration = 6, damagePerHit = 6, maxHits = 9, density = 1.0 },
	FishmanKarate = { id = "FishmanKarate", label = "FISHMAN KARATE", gen = "burst", duration = 6.5, damagePerHit = 8, maxHits = 8, density = 1.0, stunAt = 3 },
	-- harder versions for elites and bosses
	SharkStorm = { id = "SharkStorm", label = "SHARK STORM", gen = "burst", duration = 7.5, damagePerHit = 10, maxHits = 10, density = 1.6, stunAt = 3 },
	GrandBarrage = { id = "GrandBarrage", label = "GRAND BARRAGE", gen = "rain", duration = 7.5, damagePerHit = 10, maxHits = 10, density = 1.7, stunAt = 3 },
	BlackBlade = { id = "BlackBlade", label = "BLACK BLADE", gen = "waves", duration = 7.5, damagePerHit = 12, maxHits = 9, density = 1.6 },
	HeadHunt = { id = "HeadHunt", label = "HEAD HUNT", gen = "aimed", duration = 7, damagePerHit = 9, maxHits = 11, density = 1.6 },
}
BattleDefs.MaxGraze = 30

-- Looks for the block figures the arena builds (no real models yet; all original).
--   skin, shirt, pants, hat = colors; hatKind = "cap" | "bandana" | "horns" | "straw" | "none"; scale = size
BattleDefs.Looks = {
	Marine = { skin = Color3.fromRGB(240, 196, 150), shirt = Color3.fromRGB(240, 240, 245), pants = Color3.fromRGB(30, 70, 140), hat = Color3.fromRGB(245, 245, 250), hatKind = "cap" },
	Pirate = { skin = Color3.fromRGB(205, 150, 105), shirt = Color3.fromRGB(150, 40, 40), pants = Color3.fromRGB(60, 50, 40), hat = Color3.fromRGB(200, 30, 30), hatKind = "bandana" },
	Fishman = { skin = Color3.fromRGB(80, 150, 200), shirt = Color3.fromRGB(240, 200, 60), pants = Color3.fromRGB(40, 60, 90), hat = Color3.fromRGB(80, 150, 200), hatKind = "none" },
	Officer = { skin = Color3.fromRGB(235, 190, 145), shirt = Color3.fromRGB(250, 250, 250), pants = Color3.fromRGB(20, 40, 90), hat = Color3.fromRGB(20, 40, 90), hatKind = "cap" },
	Arlong = { skin = Color3.fromRGB(70, 120, 190), shirt = Color3.fromRGB(230, 220, 180), pants = Color3.fromRGB(40, 40, 50), hat = Color3.fromRGB(70, 120, 190), hatKind = "none", scale = 1.6 },
	Buggy = { skin = Color3.fromRGB(250, 230, 210), shirt = Color3.fromRGB(200, 40, 40), pants = Color3.fromRGB(240, 200, 60), hat = Color3.fromRGB(40, 90, 200), hatKind = "bandana", scale = 1.4 },
	Mihawk = { skin = Color3.fromRGB(230, 190, 150), shirt = Color3.fromRGB(30, 30, 35), pants = Color3.fromRGB(30, 30, 35), hat = Color3.fromRGB(30, 30, 35), hatKind = "cap", scale = 1.5 },
	Doflamingo = { skin = Color3.fromRGB(235, 190, 145), shirt = Color3.fromRGB(240, 100, 170), pants = Color3.fromRGB(240, 220, 120), hat = Color3.fromRGB(240, 210, 90), hatKind = "none", scale = 1.6 },
	Kaido = { skin = Color3.fromRGB(215, 165, 120), shirt = Color3.fromRGB(110, 60, 140), pants = Color3.fromRGB(40, 40, 40), hat = Color3.fromRGB(230, 230, 230), hatKind = "horns", scale = 2.2 },
	Shanks = { skin = Color3.fromRGB(230, 185, 140), shirt = Color3.fromRGB(240, 240, 240), pants = Color3.fromRGB(50, 40, 30), hat = Color3.fromRGB(190, 30, 30), hatKind = "none", scale = 1.6 },
}

-- Enemies. hp/speed are base numbers (sea scaling and party scaling are added when the fight starts).
--   rank = "minion" | "elite" | "boss"; parts = weak points you can aim at; patterns = its dodge-box attacks
BattleDefs.Enemies = {
	MarineRecruit = { id = "MarineRecruit", name = "Marine Recruit", look = "Marine", rank = "minion", hp = 60, speed = 9, weak = "Slash", parts = { "Core" }, patterns = { "PistolVolley", "SwordWaves" }, gold = 8 },
	MarineGunner = { id = "MarineGunner", name = "Marine Gunner", look = "Marine", rank = "minion", hp = 50, speed = 12, weak = "Blunt", parts = { "Core" }, patterns = { "PistolVolley", "CannonBarrage" }, gold = 9 },
	PirateThug = { id = "PirateThug", name = "Pirate Thug", look = "Pirate", rank = "minion", hp = 70, speed = 8, weak = "Blunt", parts = { "Core" }, patterns = { "SwordWaves", "CannonBarrage" }, gold = 8 },
	FishmanThug = { id = "FishmanThug", name = "Fishman Thug", look = "Fishman", rank = "minion", hp = 80, speed = 11, weak = "Pierce", parts = { "Core" }, patterns = { "FishmanKarate", "SwordWaves" }, gold = 10 },
	-- elites
	MarineLieutenant = { id = "MarineLieutenant", name = "Marine Lieutenant", look = "Officer", rank = "elite", hp = 190, speed = 10, weak = "Slash", parts = { "Core", "Eyes", "Arms", "Legs", "Weapon" }, patterns = { "HeadHunt", "SwordWaves", "PistolVolley" }, gold = 30 },
	FishmanBrute = { id = "FishmanBrute", name = "Fishman Brute", look = "Fishman", rank = "elite", hp = 220, speed = 9, weak = "Pierce", parts = { "Core", "Eyes", "Arms", "Legs" }, patterns = { "SharkStorm", "FishmanKarate" }, gold = 30, scale = 1.3 },
	-- bosses
	Arlong = { id = "Arlong", name = "Arlong", look = "Arlong", rank = "boss", hp = 420, speed = 11, weak = "Pierce", parts = { "Core", "Eyes", "Arms", "Legs", "Weapon" }, patterns = { "SharkStorm", "BlackBlade", "FishmanKarate" }, gold = 120, title = "Saw-Nose Shark" },
	Buggy = { id = "Buggy", name = "Buggy", look = "Buggy", rank = "boss", hp = 380, speed = 12, weak = "Blunt", parts = { "Core", "Eyes", "Arms", "Legs", "Weapon" }, patterns = { "GrandBarrage", "HeadHunt", "CannonBarrage" }, gold = 120, title = "The Clown" },
	Mihawk = { id = "Mihawk", name = "Mihawk", look = "Mihawk", rank = "boss", hp = 420, speed = 15, weak = "Blunt", parts = { "Core", "Eyes", "Arms", "Legs", "Weapon" }, patterns = { "BlackBlade", "SwordWaves", "HeadHunt" }, gold = 200, title = "Hawk Eyes" },
	Doflamingo = { id = "Doflamingo", name = "Doflamingo", look = "Doflamingo", rank = "boss", hp = 430, speed = 13, weak = "Slash", parts = { "Core", "Eyes", "Arms", "Legs", "Weapon" }, patterns = { "BlackBlade", "SharkStorm", "HeadHunt" }, gold = 200, title = "Heavenly Demon" },
	Kaido = { id = "Kaido", name = "Kaido", look = "Kaido", rank = "boss", hp = 480, speed = 9, weak = "Pierce", parts = { "Core", "Eyes", "Arms", "Legs", "Weapon" }, patterns = { "GrandBarrage", "BlackBlade", "SharkStorm" }, gold = 400, title = "Emperor of the Sea", emperor = true },
	Shanks = { id = "Shanks", name = "Shanks", look = "Shanks", rank = "boss", hp = 450, speed = 14, weak = "Blunt", parts = { "Core", "Eyes", "Arms", "Legs", "Weapon" }, patterns = { "BlackBlade", "HeadHunt", "SwordWaves" }, gold = 400, title = "Emperor of the Sea", emperor = true },
}

-- What each sea can throw at you.
BattleDefs.Seas = {
	[1] = { name = "East Blue", hpMult = 1, dmgMult = 1, minions = { "MarineRecruit", "MarineGunner", "PirateThug", "FishmanThug" }, elites = { "MarineLieutenant", "FishmanBrute" }, bosses = { "Arlong", "Buggy" } },
	[2] = { name = "Grand Line", hpMult = 1.7, dmgMult = 1.3, minions = { "MarineRecruit", "MarineGunner", "PirateThug", "FishmanThug" }, elites = { "MarineLieutenant", "FishmanBrute" }, bosses = { "Mihawk", "Doflamingo" } },
	[3] = { name = "New World", hpMult = 2.6, dmgMult = 1.6, minions = { "MarineRecruit", "MarineGunner", "PirateThug", "FishmanThug" }, elites = { "MarineLieutenant", "FishmanBrute" }, bosses = { "Kaido", "Shanks" } },
}

-- Build an encounter: a list of enemy ids. kind = "Fight" | "Elite" | "Boss". rng = Random.
function BattleDefs.buildEncounter(kind, sea, partySize, rng)
	local s = BattleDefs.Seas[sea] or BattleDefs.Seas[1]
	local list = {}
	local function pick(pool)
		return pool[rng:NextInteger(1, #pool)]
	end
	if kind == "Boss" then
		table.insert(list, pick(s.bosses))
		for _ = 1, math.min(2, 1 + math.floor(partySize / 3)) do
			table.insert(list, pick(s.minions))
		end
	elseif kind == "Elite" then
		table.insert(list, pick(s.elites))
		for _ = 1, rng:NextInteger(0, math.min(2, partySize)) do
			table.insert(list, pick(s.minions))
		end
	else
		local n = math.clamp(1 + math.floor((partySize + 1) / 2) + rng:NextInteger(0, 1), 1, 6)
		for _ = 1, n do
			table.insert(list, pick(s.minions))
		end
	end
	return list
end

return BattleDefs
