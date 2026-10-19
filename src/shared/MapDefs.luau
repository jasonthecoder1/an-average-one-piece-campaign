-- Sea charts (design page "Sea map"): a For The King 2-style hex chart per sea, Slay the Spire 2-style paths.
-- 4 rows of stops then the boss. Paths split and join. No fog: everyone sees every stop; the Navigator also sees
-- what is AT each stop (enemies, event, loot). Same generator as the design page's "Roll a new sea" button.
local BattleDefs = require(script.Parent.BattleDefs)

local MapDefs = {}

MapDefs.Cols = 18
MapDefs.Rows = 12
MapDefs.LayerRows = { 9, 7, 5, 3 } -- grid rows of the 4 stop layers (start is row 11, boss row 1)
MapDefs.VoteSeconds = 30

MapDefs.Shapes = { "Archipelago", "Narrow Strait", "Reef Maze", "Current Lanes", "Marine Waters", "Scattered Isles" }
MapDefs.Weathers = { "Sunny", "Windy", "Stormy", "Night" }

-- Stop types. glyph = what the map tile shows. weight = how often it rolls.
MapDefs.Stops = {
	Fight = { id = "Fight", label = "FIGHT", glyph = "⚔", weight = 30, desc = "A turn-based fight." },
	Elite = { id = "Elite", label = "ELITE", glyph = "☠", weight = 8, desc = "One tough enemy, maybe with helpers. Better loot." },
	Port = { id = "Port", label = "PORT TOWN", glyph = "⚓", weight = 12, desc = "Shop: medicine and supplies." },
	Camp = { id = "Camp", label = "CAMP", glyph = "▲", weight = 15, desc = "Full rest in a cove: heal. A Marine ship might find you." },
	Event = { id = "Event", label = "EVENT", glyph = "?", weight = 16, desc = "A story card with choices." },
	Treasure = { id = "Treasure", label = "TREASURE ISLE", glyph = "$", weight = 10, desc = "Scavenge for gold and materials." },
	Allied = { id = "Allied", label = "ALLIED CREW", glyph = "⚑", weight = 9, desc = "A friendly crew: trade or rest with them." },
	Boss = { id = "Boss", label = "BOSS", glyph = "♛", weight = 0, desc = "The boss of this sea." },
	Start = { id = "Start", label = "YOUR SHIP", glyph = "⛵", weight = 0, desc = "Where the crew starts." },
}
MapDefs.RollOrder = { "Fight", "Elite", "Port", "Camp", "Event", "Treasure", "Allied" }

local function key(c, r)
	return c .. "," .. r
end

-- Make a new chart. Same seed = same chart. partySize sets the pre-rolled enemy groups (the Navigator sees them).
function MapDefs.generate(seed, sea, partySize)
	local R = Random.new(seed)
	local function ri(a, b)
		return R:NextInteger(a, b)
	end
	local function pick(list)
		return list[ri(1, #list)]
	end
	local shape = pick(MapDefs.Shapes)
	local weather = pick(MapDefs.Weathers)
	local map = { seed = seed, sea = sea, shape = shape, weather = weather, nodes = {}, reefs = {}, whirls = {} }

	local function count()
		if shape == "Narrow Strait" then
			return 2
		elseif shape == "Archipelago" or shape == "Scattered Isles" then
			return ri(3, 4)
		end
		return ri(2, 4)
	end
	local function chooseCols(k)
		for _ = 1, 300 do
			local cs = {}
			for _ = 1, k do
				table.insert(cs, ri(2, 15))
			end
			table.sort(cs)
			local ok = true
			for j = 2, #cs do
				if cs[j] - cs[j - 1] < 3 then
					ok = false
				end
			end
			if shape == "Narrow Strait" and cs[#cs] - cs[1] > 6 then
				ok = false
			end
			if ok then
				return cs
			end
		end
		if k == 2 then
			return { 5, 11 }
		elseif k == 3 then
			return { 3, 8, 13 }
		end
		return { 2, 6, 10, 14 }
	end

	local nextId = 0
	local function addNode(c, r, layer, typ)
		nextId += 1
		local n = { id = nextId, c = c, r = r, layer = layer, type = typ, next = {} }
		map.nodes[nextId] = n
		return n
	end
	local start = addNode(8, 11, 0, "Start")
	map.start = start.id
	local layers = { { start } }
	for li, row in MapDefs.LayerRows do
		local L = {}
		for _, c in chooseCols(count()) do
			table.insert(L, addNode(c, row, li, "Fight"))
		end
		table.insert(layers, L)
	end
	local boss = addNode(ri(6, 10), 1, 5, "Boss")
	map.boss = boss.id
	table.insert(layers, { boss })

	-- edges: every island links to the nearest island(s) in the next layer, and every island has a way forward
	local function link(a, b)
		if not table.find(a.next, b.id) then
			table.insert(a.next, b.id)
		end
	end
	local function nearest(list, c)
		local copy = table.clone(list)
		table.sort(copy, function(x, y)
			return math.abs(x.c - c) < math.abs(y.c - c)
		end)
		return copy
	end
	for li = 1, #layers - 1 do
		local A, B = layers[li], layers[li + 1]
		for _, b in B do
			local n = nearest(A, b.c)
			link(n[1], b)
			if n[2] and R:NextNumber() < 0.45 and math.abs(n[2].c - b.c) <= 6 then
				link(n[2], b)
			end
		end
		for _, a in A do
			if #a.next == 0 then
				link(a, nearest(B, a.c)[1])
			end
		end
	end

	-- stop types
	local total = 0
	for _, id in MapDefs.RollOrder do
		total += MapDefs.Stops[id].weight
	end
	local function wpick()
		local x = R:NextNumber() * total
		for _, id in MapDefs.RollOrder do
			x -= MapDefs.Stops[id].weight
			if x <= 0 then
				return id
			end
		end
		return "Fight"
	end
	for li = 2, 5 do
		local allFight = true
		for _, isl in layers[li] do
			local t = wpick()
			if t == "Elite" and li == 2 then
				t = "Fight" -- no elites on the first row
			end
			isl.type = t
			if t ~= "Fight" then
				allFight = false
			end
		end
		if allFight then
			layers[li][#layers[li]].type = "Camp"
		end
	end

	-- what waits at each stop (the Navigator sees it; everyone finds out when they land)
	for _, n in map.nodes do
		if n.type == "Fight" or n.type == "Elite" or n.type == "Boss" then
			n.enemies = BattleDefs.buildEncounter(n.type, sea, partySize, R)
		elseif n.type == "Event" then
			n.event = R:NextInteger(1, 1000)
		elseif n.type == "Treasure" then
			n.gold = R:NextInteger(25, 60)
		elseif n.type == "Camp" then
			n.ambush = R:NextNumber() < 0.25
		end
	end

	-- decoration: reefs and whirlpools
	local occ = {}
	for _, n in map.nodes do
		occ[key(n.c, n.r)] = true
	end
	local reefN = if shape == "Reef Maze" then 26 else 8
	for _ = 1, reefN do
		local c, r = ri(0, MapDefs.Cols - 1), ri(0, MapDefs.Rows - 1)
		if not occ[key(c, r)] then
			map.reefs[key(c, r)] = true
		end
	end
	return map
end

-- Grid position (0..1 of the chart area) of a hex cell. Odd rows are shifted half a hex (pointy-top hexes).
function MapDefs.cellPos(c, r)
	local w = 1 / (MapDefs.Cols + 0.5)
	local h = 1 / MapDefs.Rows
	return (c + 0.5 + (if r % 2 == 1 then 0.5 else 0)) * w, (r + 0.5) * h
end

-- What a player may see about a stop. Non-Navigators only see the type.
function MapDefs.publicView(map, navigator)
	local out = { seed = map.seed, sea = map.sea, shape = map.shape, weather = map.weather, start = map.start, boss = map.boss, reefs = map.reefs, nodes = {} }
	for id, n in map.nodes do
		local v = { id = id, c = n.c, r = n.r, layer = n.layer, type = n.type, next = n.next }
		if navigator then
			if n.enemies then
				local names = {}
				for _, eid in n.enemies do
					table.insert(names, BattleDefs.Enemies[eid].name)
				end
				v.info = table.concat(names, ", ")
			elseif n.type == "Treasure" then
				v.info = "About " .. n.gold .. " gold + materials"
			elseif n.type == "Camp" then
				v.info = if n.ambush then "Marines nearby! (ambush)" else "Safe cove"
			elseif n.type == "Event" then
				v.info = "Story card #" .. (n.event % 6 + 1)
			end
		elseif n.type == "Boss" and n.enemies then
			v.info = BattleDefs.Enemies[n.enemies[1]].name -- everyone knows who the boss is
		end
		out.nodes[tostring(id)] = v
	end
	return out
end

return MapDefs
