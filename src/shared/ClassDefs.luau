-- Classes and their moves. Tier 1 only for now (Warrior, Assassin). Later tiers / paths and the Bonus Tree slot in
-- as more entries in `tree` and more moves in `Moves`.
--
-- Move fields:
--   id, label, desc, cost (stamina), menu ("Attack" | "Skill" | "Heavy" | "Role" | "Rush")
--   kind: "attack" | "guard" | "smoke" | "orders" | "rush"
--   qte: "strike" | "rings" | nil      power = {min, max}, hits = number of hits, element
--   target: "enemy" | "self" | "allEnemies"
--   requires: "FirstTurn" | "AllDown" | nil
--   notActedMult: damage x this if the target hasn't acted yet this round (Backstab)
--   applies: status put on the target's next attack ("stagger"); poison = { turns, dmg }
--   free: true = doesn't end your turn; oncePerFight: true
local ClassDefs = {}

ClassDefs.Moves = {
	-- Warrior (swords, greatswords, spears, axes, clubs)
	Slash = { id = "Slash", label = "Slash", menu = "Attack", desc = "A basic sword swing. Costs nothing.", cost = 0, kind = "attack", qte = "strike", power = { 10, 14 }, hits = 1, element = "Slash", target = "enemy" },
	WeaponArt = { id = "WeaponArt", label = "Weapon Art", menu = "Skill", desc = "Your sword hits twice.", cost = 2, kind = "attack", qte = "strike", power = { 9, 12 }, hits = 2, element = "Slash", target = "enemy" },
	Parry = { id = "Parry", label = "Parry", menu = "Skill", desc = "Brace. The next attack on you hits much softer, and you strike back.", cost = 2, kind = "guard", target = "self", guardMult = 0.4, counter = { 8, 12 } },
	RisingStrike = { id = "RisingStrike", label = "Rising Strike", menu = "Heavy", desc = "A big upward blow. STAGGERs: fewer bullets in its next attack.", cost = 4, kind = "attack", qte = "rings", power = { 24, 30 }, hits = 1, element = "Blunt", target = "enemy", applies = "stagger" },
	-- Assassin (daggers, pistols)
	Stab = { id = "Stab", label = "Stab", menu = "Attack", desc = "A quick dagger stab. Costs nothing.", cost = 0, kind = "attack", qte = "strike", power = { 9, 13 }, hits = 1, element = "Pierce", target = "enemy" },
	Backstab = { id = "Backstab", label = "Backstab", menu = "Skill", desc = "Huge damage on an enemy that hasn't acted yet this round.", cost = 2, kind = "attack", qte = "strike", power = { 13, 17 }, hits = 1, element = "Pierce", target = "enemy", notActedMult = 2 },
	SmokeBomb = { id = "SmokeBomb", label = "Smoke Bomb", menu = "Skill", desc = "Nobody can target you until your next turn.", cost = 2, kind = "smoke", target = "self" },
	PoisonBlade = { id = "PoisonBlade", label = "Poison Blade", menu = "Skill", desc = "A cut that poisons for 3 turns.", cost = 2, kind = "attack", qte = "strike", power = { 6, 8 }, hits = 1, element = "Pierce", target = "enemy", poison = { turns = 3, dmg = 7 } },
	Ambush = { id = "Ambush", label = "Ambush", menu = "Heavy", desc = "Only on your first turn of a fight: a massive hit.", cost = 4, kind = "attack", qte = "rings", power = { 40, 48 }, hits = 1, element = "Pierce", target = "enemy", requires = "FirstTurn" },
	-- shared
	CaptainsOrders = { id = "CaptainsOrders", label = "Captain's Orders", menu = "Role", desc = "Once per fight: every crewmate gets +1 stamina. Doesn't end your turn.", cost = 0, kind = "orders", target = "self", free = true, oncePerFight = true, role = "Captain" },
	CrewRush = { id = "CrewRush", label = "CREW RUSH!", menu = "Rush", desc = "Every enemy is DOWN! One big team finisher on all of them.", cost = 0, kind = "rush", qte = "strike", power = { 30, 36 }, hits = 1, element = "Blunt", target = "allEnemies", requires = "AllDown" },
}

ClassDefs.MenuOrder = { "Rush", "Attack", "Skill", "Heavy", "Role" }

-- Tier 1 Skill Tree nodes (owner's Class Book). kind: "P" passive, "S" skill (move), "H" heavy (move).
-- `move` links a node to a move above; passives carry their numbers in `mods`.
ClassDefs.Classes = {
	Warrior = {
		id = "Warrior",
		name = "Warrior",
		role = "Frontline fighter",
		weapon = "Sword",
		hp = 110,
		speed = 10,
		color = Color3.fromRGB(200, 60, 50),
		basic = "Slash",
		signature = "WeaponArt",
		tree = {
			{ kind = "P", name = "Weapon Art+", desc = "Weapon Art does +10% damage.", mods = { moveMult = { WeaponArt = 1.1 } } },
			{ kind = "S", name = "Parry", desc = "Block the next hit. If it was a melee hit, strike back.", move = "Parry" },
			{ kind = "P", name = "Battle Hardened", desc = "+10% Health.", mods = { hpMult = 1.1 } },
			{ kind = "H", name = "Rising Strike", desc = "A big upward strike that STAGGERs.", move = "RisingStrike" },
			{ kind = "P", name = "Weapon Master", desc = "Carry 2 class weapons and swap for free. (coming with weapons)", mods = {} },
		},
	},
	Assassin = {
		id = "Assassin",
		name = "Assassin",
		role = "Burst and dodge",
		weapon = "Dagger",
		hp = 85,
		speed = 14,
		color = Color3.fromRGB(110, 70, 160),
		basic = "Stab",
		signature = "Backstab",
		tree = {
			{ kind = "P", name = "Sneak", desc = "Backstab does +10% damage.", mods = { moveMult = { Backstab = 1.1 } } },
			{ kind = "S", name = "Smoke Bomb", desc = "Nobody can target you for 1 turn.", move = "SmokeBomb" },
			{ kind = "S", name = "Poison Blade", desc = "Poison an enemy for 3 turns.", move = "PoisonBlade" },
			{ kind = "H", name = "Ambush", desc = "Only on your first turn of a fight: a massive hit.", move = "Ambush" },
			{ kind = "P", name = "Light Step", desc = "Your dash goes farther in the dodge box.", mods = { dashMult = 1.35 } },
		},
	},
}
ClassDefs.Order = { "Warrior", "Assassin" }

-- Everything a class has at Tier 1: its move list and summed passive mods.
function ClassDefs.kit(classId)
	local c = ClassDefs.Classes[classId] or ClassDefs.Classes.Warrior
	local moves = { c.basic, c.signature }
	local mods = { hpMult = 1, dashMult = 1, moveMult = {} }
	for _, node in c.tree do
		if node.move then
			table.insert(moves, node.move)
		end
		local m = node.mods
		if m then
			if m.hpMult then
				mods.hpMult *= m.hpMult
			end
			if m.dashMult then
				mods.dashMult *= m.dashMult
			end
			if m.moveMult then
				for k, v in m.moveMult do
					mods.moveMult[k] = (mods.moveMult[k] or 1) * v
				end
			end
		end
	end
	return { class = c, moves = moves, mods = mods }
end

return ClassDefs
