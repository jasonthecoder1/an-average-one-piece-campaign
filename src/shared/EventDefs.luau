-- Story cards for Event stops (and the choices at Port Towns / Allied Crews).
-- A choice's outcome: gold (+/-), heal (fraction of max HP for everyone), hurt (fraction), loot = { item = n },
-- fight = { enemy ids } (with `chance`, 0..1, default 1), cost = gold needed to pick it.
local EventDefs = {}

EventDefs.Events = {
	{ title = "FLOATING CRATE", text = "A crate bobs on the waves, stamped with a Marine seal.", choices = {
		{ label = "Pull it aboard", result = { loot = { ["Iron Plate"] = 1, ["Cloth Strip"] = 2 }, say = "Marine supplies! +1 Iron Plate, +2 Cloth Strip." } },
		{ label = "Leave it", result = { say = "You sail past." } },
	} },
	{ title = "LOST SAILOR", text = "A sailor clings to a broken mast. He says he was a ship's doctor.", choices = {
		{ label = "Pull him up (-15 gold for supplies)", cost = 15, result = { gold = -15, heal = 0.2, say = "He patches the crew up before leaving. Everyone heals 20%." } },
		{ label = "Throw him a rope and go", result = { say = "He waves goodbye." } },
	} },
	{ title = "STRANGE SHRINE", text = "A tiny shrine on a rock, covered in old coins.", choices = {
		{ label = "Pray", result = { chance = 0.5, heal = 0.3, say = "Warm light! Everyone heals 30%.", fail = { hurt = 0.1, say = "A curse! Everyone loses 10% health." } } },
		{ label = "Take the coins", result = { gold = 25, fight = { "PirateThug", "PirateThug" }, chance = 0.5, say = "+25 gold... and the shrine's guards attack!", failSay = "+25 gold. Nobody saw." } },
		{ label = "Leave", result = { say = "Better safe than sorry." } },
	} },
	{ title = "BOTTLE MESSAGE", text = "A message in a bottle: an X marks a beach close by.", choices = {
		{ label = "Dig it up", result = { gold = 35, say = "A small chest! +35 gold." } },
		{ label = "Keep sailing", result = { say = "Maybe next time." } },
	} },
	{ title = "MERMAID SONG", text = "Soft singing drifts over the water.", choices = {
		{ label = "Listen", result = { heal = 0.2, say = "The song calms everyone. Heal 20%." } },
		{ label = "Cover your ears", result = { say = "Nothing happens." } },
	} },
	{ title = "OLD WRECK", text = "A sunken pirate ship sticks out of the reef.", choices = {
		{ label = "Search it", result = { loot = { ["Iron Plate"] = 2, Driftwood = 2 }, fight = { "PirateThug", "FishmanThug" }, chance = 0.4, say = "+2 Iron Plate, +2 Driftwood... and somebody lives here!", failSay = "+2 Iron Plate, +2 Driftwood." } },
		{ label = "Sail on", result = { say = "You leave the wreck alone." } },
	} },
}

EventDefs.Port = { title = "PORT TOWN", text = "A busy harbor. Merchants shout prices at you.", choices = {
	{ label = "Medicine (-30 gold): heal 40%", cost = 30, result = { gold = -30, heal = 0.4, say = "The crew feels much better." } },
	{ label = "Supplies (-20 gold): 2 Iron Plate, 2 Driftwood", cost = 20, result = { gold = -20, loot = { ["Iron Plate"] = 2, Driftwood = 2 }, say = "Supplies loaded." } },
	{ label = "Cloth (-10 gold): 3 Cloth Strip", cost = 10, result = { gold = -10, loot = { ["Cloth Strip"] = 3 }, say = "Cloth loaded." } },
	{ label = "Leave", result = { say = "Back to the ship." } },
} }

EventDefs.Allied = { title = "ALLIED CREW", text = "A friendly pirate crew waves you over.", choices = {
	{ label = "Trade 2 Driftwood for 1 Iron Plate", needs = { Driftwood = 2 }, result = { loot = { Driftwood = -2, ["Iron Plate"] = 1 }, say = "Fair trade!" } },
	{ label = "Rest with them (heal 15%)", result = { heal = 0.15, say = "A good meal and a few stories." } },
	{ label = "Share a drink (+15 gold)", result = { gold = 15, say = "They pay for the round. +15 gold." } },
} }

return EventDefs
