-- Materials, craftable gear and recipes. Gear only lasts for its run (owner rule).
--   kind: "material" | "weapon" | "armor" | "use" | "build"
--   weapon: classWeapon = which class can use its bonus (class abilities only work with your class weapons)
--   armor: slot = "Helmet" | "Chest" | "Legs"; hp = flat max HP bonus
local ItemDefs = {}

ItemDefs.Items = {
	Driftwood = { id = "Driftwood", name = "Driftwood", kind = "material", glyph = "≡", desc = "Wood for hulls, handles and chests." },
	["Iron Plate"] = { id = "Iron Plate", name = "Iron Plate", kind = "material", glyph = "▬", desc = "Metal for blades and armor." },
	["Cloth Strip"] = { id = "Cloth Strip", name = "Cloth Strip", kind = "material", glyph = "≈", desc = "For bandages and padding." },

	["Iron Cutlass"] = { id = "Iron Cutlass", name = "Iron Cutlass", kind = "weapon", glyph = "⚔", classWeapon = "Warrior", dmg = 0.12, desc = "Warrior sword: +12% damage." },
	["Boarding Axe"] = { id = "Boarding Axe", name = "Boarding Axe", kind = "weapon", glyph = "⚒", classWeapon = "Warrior", dmg = 0.18, desc = "Warrior axe: +18% damage." },
	["Steel Dagger"] = { id = "Steel Dagger", name = "Steel Dagger", kind = "weapon", glyph = "†", classWeapon = "Assassin", dmg = 0.12, desc = "Assassin dagger: +12% damage." },
	["Flintlock"] = { id = "Flintlock", name = "Flintlock", kind = "weapon", glyph = "¬", classWeapon = "Assassin", dmg = 0.18, desc = "Assassin pistol: +18% damage." },

	["Iron Helmet"] = { id = "Iron Helmet", name = "Iron Helmet", kind = "armor", slot = "Helmet", glyph = "∩", hp = 10, desc = "+10 max health." },
	["Iron Chestplate"] = { id = "Iron Chestplate", name = "Iron Chestplate", kind = "armor", slot = "Chest", glyph = "▣", hp = 20, desc = "+20 max health." },
	["Iron Leggings"] = { id = "Iron Leggings", name = "Iron Leggings", kind = "armor", slot = "Legs", glyph = "Π", hp = 14, desc = "+14 max health." },

	Bandage = { id = "Bandage", name = "Bandage", kind = "use", glyph = "✚", heal = 0.25, desc = "Use on the ship: heal yourself 25%." },
	["Hull Patch"] = { id = "Hull Patch", name = "Hull Patch", kind = "use", glyph = "▦", hull = 250, desc = "Use on the ship: repair 250 hull." },
	["Crew Chest"] = { id = "Crew Chest", name = "Crew Chest", kind = "build", glyph = "▤", desc = "Builds the Crew Chest: shared storage for the whole crew." },
}

ItemDefs.Recipes = {
	{ out = "Bandage", needs = { ["Cloth Strip"] = 2 } },
	{ out = "Hull Patch", needs = { Driftwood = 2, ["Iron Plate"] = 1 } },
	{ out = "Crew Chest", needs = { Driftwood = 4, ["Iron Plate"] = 1 } },
	{ out = "Iron Cutlass", needs = { ["Iron Plate"] = 2, Driftwood = 1 } },
	{ out = "Boarding Axe", needs = { ["Iron Plate"] = 3, Driftwood = 2 } },
	{ out = "Steel Dagger", needs = { ["Iron Plate"] = 1, Driftwood = 1 } },
	{ out = "Flintlock", needs = { ["Iron Plate"] = 2, Driftwood = 2, ["Cloth Strip"] = 1 } },
	{ out = "Iron Helmet", needs = { ["Iron Plate"] = 2 } },
	{ out = "Iron Chestplate", needs = { ["Iron Plate"] = 3, ["Cloth Strip"] = 1 } },
	{ out = "Iron Leggings", needs = { ["Iron Plate"] = 2, ["Cloth Strip"] = 1 } },
}

ItemDefs.BagSlots = 10
ItemDefs.ChestSlots = 16
ItemDefs.LockerSlots = 6
ItemDefs.HullMax = 1000

-- Gear bonus for a crew member: { hp = flat, dmg = multiplier }
function ItemDefs.gearBonus(member)
	local out = { hp = 0, dmg = 1 }
	for _, id in member.gear or {} do
		local it = ItemDefs.Items[id]
		if it then
			if it.kind == "armor" then
				out.hp += it.hp
			elseif it.kind == "weapon" and it.classWeapon == member.classId then
				out.dmg *= 1 + it.dmg
			end
		end
	end
	return out
end

function ItemDefs.count(list)
	local n = 0
	for _ in list do
		n += 1
	end
	return n
end

return ItemDefs
