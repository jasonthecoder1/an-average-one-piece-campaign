-- Races, Haki and crew roles (owner's rules + the design page's numbers).
local CrewDefs = {}

-- Rolled per player. chance = percent (adds to 100). Boosts are small on purpose.
--   hpMult, dmgMult, speedMult, heartSpeed (dodge box), xpMult, craftExtra, accuracy
CrewDefs.Races = {
	{ id = "Human", name = "Human", chance = 22, desc = "+5% Class XP", mods = { xpMult = 1.05 } },
	{ id = "Buccaneer", name = "Buccaneer", chance = 18, desc = "+5% Strength", mods = { dmgMult = 1.05 } },
	{ id = "Fishman", name = "Fishman", chance = 15, desc = "+8% Health", mods = { hpMult = 1.08 } },
	{ id = "Merfolk", name = "Merfolk", chance = 13, desc = "+5% Speed", mods = { speedMult = 1.05 } },
	{ id = "Dwarf", name = "Dwarf", chance = 12, desc = "10% chance to craft 1 extra", mods = { craftExtra = 0.1 } },
	{ id = "Skypiean", name = "Skypiean", chance = 8, desc = "Heart moves 5% faster in dodge boxes", mods = { heartSpeed = 1.05 } },
	{ id = "Giant", name = "Giant", chance = 6, desc = "+12% Health, -3% Speed", mods = { hpMult = 1.12, speedMult = 0.97 } },
	{ id = "ThreeEye", name = "Three-Eye", chance = 3.5, desc = "+5% Technique (QTE zones a bit wider)", mods = { technique = 1.05 } },
	{ id = "Cyborg", name = "Cyborg", chance = 2, desc = "+5% Endurance (take 5% less damage)", mods = { takenMult = 0.95 } },
	{ id = "Lunarian", name = "Lunarian", chance = 0.5, desc = "SUPER RARE: +5% damage, Burn can't hurt you", mods = { dmgMult = 1.05 }, rare = true },
}

CrewDefs.Haki = {
	{ id = "Observation", name = "Observation", chance = 49.5, desc = "Dodge-box bullets flash before they appear. See the damage enemies will do." },
	{ id = "Armament", name = "Armament", chance = 49.5, desc = "+10% damage, and your Parry blocks more." },
	{ id = "Conquerors", name = "Conqueror's", chance = 1, desc = "REALLY RARE: weaker enemies are stunned for 1 turn when a fight starts (not bosses).", rare = true },
}

-- Exactly one of each per crew. NPCs fill the empty roles with a smaller bonus (npcScale).
CrewDefs.Roles = {
	{ id = "Captain", name = "Captain", desc = "+5% crew damage while standing. Captain's Orders: +1 stamina to all, once per fight. Force Ready + breaks tie votes." },
	{ id = "Navigator", name = "Navigator", desc = "Sees hidden map info: what enemies wait at each stop and what you'll find." },
	{ id = "Cook", name = "Cook", desc = "Cooks a meal after each stop: heals the crew 15% and +5% damage next fight." },
	{ id = "Doctor", name = "Doctor", desc = "Knocked-out crewmates come back with 30% health after a fight (not 1)." },
	{ id = "Musician", name = "Musician", desc = "Plays a song when a fight starts: crew +5% damage for 2 rounds." },
	{ id = "Archaeologist", name = "Archaeologist", desc = "Better scavenging: +25% gold and more materials." },
}
CrewDefs.NpcScale = 0.5 -- NPC role-fillers give half the bonus (Captain's Orders and Force Ready are player-only)

function CrewDefs.find(list, id)
	for _, e in list do
		if e.id == id then
			return e
		end
	end
	return nil
end

function CrewDefs.roll(list, rng)
	local total = 0
	for _, e in list do
		total += e.chance
	end
	local r = rng:NextNumber() * total
	for _, e in list do
		r -= e.chance
		if r <= 0 then
			return e.id
		end
	end
	return list[1].id
end

return CrewDefs
