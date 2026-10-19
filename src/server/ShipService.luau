-- The crew's ship: the only place you can walk. The OWNER builds the real ship (see MAP_GUIDE.md): put one model
-- in ServerStorage/Maps/Ship with marker parts named DeckSpot1-6 and one per station. With no ship map yet, a
-- plain block stand-in deck is used so the game still runs.
-- Stations (design page "The ship"): Map Table (Ready / chart), Craft Bench + Crew Chest, Repair Bench + Lockers,
-- Galley (Cook), Infirmary (Doctor), Crow's Nest (Navigator), Stage (Musician), Study (Archaeologist).
-- Crafting on the ship is always safe. Every action is checked here: you must be in the run and near the station.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ItemDefs = require(Shared.ItemDefs)
local CrewDefs = require(Shared.CrewDefs)
local Remotes = require(script.Parent.Remotes)
local Run = require(script.Parent.Run)
local MapLoader = require(script.Parent.MapLoader)

local ShipService = {}

local ship
local deckY = 10 -- floor height of the deck (read from DeckSpot1 once the ship is loaded)
ShipService.Stations = {} -- [name] = { part, label, role? }

-- marker name -> sign text, prompt text, role that may use it (nil = anyone)
ShipService.StationList = {
	{ name = "MapTable", label = "MAP TABLE", action = "Sea Chart / Ready" },
	{ name = "CraftBench", label = "CRAFTING", action = "Craft" },
	{ name = "CrewChest", label = "CREW CHEST", action = "Open" },
	{ name = "RepairBench", label = "REPAIRS", action = "Repair hull" },
	{ name = "Lockers", label = "LOCKERS", action = "Open your locker" },
	{ name = "Galley", label = "GALLEY", action = "Cook", role = "Cook" },
	{ name = "Infirmary", label = "INFIRMARY", action = "Treat crew", role = "Doctor" },
	{ name = "CrowsNest", label = "CROW'S NEST", action = "Look out", role = "Navigator" },
	{ name = "Stage", label = "STAGE", action = "Play a song", role = "Musician" },
	{ name = "Study", label = "STUDY", action = "Study old charts", role = "Archaeologist" },
}

local WOOD = Color3.fromRGB(150, 100, 60)
local DARK = Color3.fromRGB(100, 65, 38)
local CREAM = Color3.fromRGB(243, 234, 215)

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = WOOD
	for k, v in props do
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- Plain block stand-in: a box deck with rails, a mast, and one labeled box per station + all markers.
local function buildStandIn()
	local m = Instance.new("Model")
	m.Name = "StandInShip"
	local y = 10
	part({ Name = "Sea", Size = Vector3.new(2048, 2, 2048), Position = Vector3.new(0, -1, 0), Color = Color3.fromRGB(35, 115, 185), Material = Enum.Material.Glass, Transparency = 0.1, Parent = m })
	part({ Name = "Hull", Size = Vector3.new(80, 10, 28), Position = Vector3.new(0, y - 5, 0), Color = DARK, Parent = m })
	part({ Name = "Deck", Size = Vector3.new(80, 1, 28), Position = Vector3.new(0, y - 0.5, 0), Color = WOOD, Parent = m })
	part({ Name = "RailN", Size = Vector3.new(80, 3, 1), Position = Vector3.new(0, y + 1.5, 14), Color = DARK, Parent = m })
	part({ Name = "RailS", Size = Vector3.new(80, 3, 1), Position = Vector3.new(0, y + 1.5, -14), Color = DARK, Parent = m })
	part({ Name = "RailBack", Size = Vector3.new(1, 3, 28), Position = Vector3.new(-40, y + 1.5, 0), Color = DARK, Parent = m })
	part({ Name = "RailFront", Size = Vector3.new(1, 3, 28), Position = Vector3.new(40, y + 1.5, 0), Color = DARK, Parent = m })
	part({ Name = "Mast", Size = Vector3.new(2, 30, 2), Position = Vector3.new(2, y + 15, 0), Color = DARK, Parent = m })
	part({ Name = "Sail", Size = Vector3.new(1, 14, 22), Position = Vector3.new(3.5, y + 20, 0), Color = CREAM, CanCollide = false, Parent = m })
	local spots = {
		MapTable = { Vector3.new(10, 0, 0), Vector3.new(6, 3, 4) },
		CraftBench = { Vector3.new(-12, 0, -10), Vector3.new(7, 3.5, 3) },
		CrewChest = { Vector3.new(-20, 0, -10), Vector3.new(4.5, 3, 3) },
		RepairBench = { Vector3.new(-12, 0, 10), Vector3.new(6, 2.5, 3) },
		Lockers = { Vector3.new(-21, 0, 11.5), Vector3.new(7, 6, 2) },
		Galley = { Vector3.new(24, 0, -10), Vector3.new(5, 4, 3) },
		Infirmary = { Vector3.new(24, 0, 10), Vector3.new(6, 2, 3.5) },
		CrowsNest = { Vector3.new(4, 0, -3.5), Vector3.new(2, 8, 1) },
		Stage = { Vector3.new(33, 0, 0), Vector3.new(6, 1, 6) },
		Study = { Vector3.new(-30, 0, -7), Vector3.new(1.5, 7, 6) },
	}
	for name, s in spots do
		part({ Name = name, Size = s[2], Position = Vector3.new(s[1].X, y + s[2].Y / 2, s[1].Z), Color = Color3.fromRGB(120, 80, 45), Parent = m })
	end
	for i = 1, 6 do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local pos = Vector3.new(-2 + col * 5, y + 0.5, -3 + row * 6)
		part({ Name = "DeckSpot" .. i, Size = Vector3.new(2, 1, 2), CFrame = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)), Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
	end
	return m
end

-- Put the prompt and a floating sign on a station marker.
local function decorate(p, info)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = info.name
	prompt.ObjectText = info.label
	prompt.ActionText = info.action
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 34)
	bb.StudsOffset = Vector3.new(0, p.Size.Y / 2 + 2.2, 0)
	bb.MaxDistance = 70
	bb.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	t.TextColor3 = CREAM
	t.Font = Enum.Font.Bangers
	t.TextScaled = true
	t.Text = info.label
	t.Parent = bb
	local st = Instance.new("UIStroke")
	st.Color = CREAM
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = t
	ShipService.Stations[info.name] = { part = p, label = info.label, role = info.role }
end

function ShipService.build()
	if ship then
		return ship
	end
	local template = MapLoader.list("Ship")[1]
	if template then
		ship = MapLoader.place(template, workspace, "Ship")
	else
		ship = buildStandIn()
		ship.Name = "Ship"
		ship.Parent = workspace
	end
	for _, info in ShipService.StationList do
		local p = MapLoader.marker(ship, info.name)
		if p then
			decorate(p, info)
		else
			warn("[Ship] the ship map has no part named " .. info.name .. " - that station is missing (see MAP_GUIDE.md)")
		end
	end
	local d1 = MapLoader.marker(ship, "DeckSpot1")
	if d1 then
		deckY = MapLoader.groundCFrame(d1).Position.Y
	else
		warn("[Ship] the ship map has no DeckSpot1 (see MAP_GUIDE.md)")
	end
	-- spawn on the deck (use the map's own SpawnLocation if it has one)
	local spawn = ship:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "DeckSpawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = ShipService.deckSpot(1) * CFrame.new(0, -2.9, 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Duration = 0
		spawn.Neutral = true
		spawn.Parent = ship
	end
	for _, s in workspace:GetDescendants() do
		if s:IsA("SpawnLocation") and s ~= spawn then
			s.Enabled = false
		end
	end
	return ship
end

-- Where crewmate i stands on deck (root height, facing the marker's front face). Missing DeckSpots fall back to
-- standing in a line next to DeckSpot1.
function ShipService.deckSpot(i)
	if ship then
		local own = MapLoader.marker(ship, "DeckSpot" .. i)
		local first = MapLoader.marker(ship, "DeckSpot1")
		if own then
			return MapLoader.groundCFrame(own) * CFrame.new(0, 3, 0)
		elseif first then
			return MapLoader.groundCFrame(first) * CFrame.new((i - 1) * 3, 3, 0)
		end
	end
	local col = (i - 1) % 3
	local row = math.floor((i - 1) / 3)
	return CFrame.new(-2 + col * 5, deckY + 3, -3 + row * 6)
end

-- ===== inventory =====

local function member(player)
	local run = Run.current
	if not run or not run.active then
		return nil, nil
	end
	return Run.memberOf(run, player), run
end

local function near(player, stationName)
	local st = ShipService.Stations[stationName]
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return st and root and (root.Position - st.part.Position).Magnitude < 16
end

local function invFor(run, m)
	return {
		hold = run.bag, bag = m.items or {}, gear = m.gear or {}, chest = run.chest or {}, chestBuilt = run.chestBuilt == true,
		locker = m.locker or {}, hull = run.hull or ItemDefs.HullMax, hullMax = ItemDefs.HullMax, gold = run.gold,
		role = m.role, classId = m.classId, hpFrac = m.hpFrac,
	}
end

function ShipService.push(run)
	for _, m in Run.members(run) do
		Remotes.Ship:FireClient(m.player, "inv", invFor(run, m))
	end
end

local function say(player, text)
	Remotes.toast(player, text)
end

local function onCraft(player, m, run, index)
	if not near(player, "CraftBench") then
		say(player, "Walk to the Crafting bench.")
		return
	end
	local recipe = ItemDefs.Recipes[index]
	if not recipe then
		return
	end
	for item, n in recipe.needs do
		if (run.bag[item] or 0) < n then
			say(player, "Not enough " .. item .. ".")
		return
		end
	end
	local out = ItemDefs.Items[recipe.out]
	if out.kind == "build" then
		if run.chestBuilt then
			say(player, "The Crew Chest is already built.")
		return
		end
	elseif #m.items >= ItemDefs.BagSlots then
		say(player, "Your bag is full. Put something in the Crew Chest or your locker.")
		return
	end
	for item, n in recipe.needs do
		run.bag[item] -= n
		if run.bag[item] <= 0 then
			run.bag[item] = nil
		end
	end
	if out.kind == "build" then
		run.chestBuilt = true
		local st = ShipService.Stations.CrewChest
		if st then
			st.part.Color = Color3.fromRGB(200, 150, 60)
		end
		Remotes.toast(nil, m.name .. " built the CREW CHEST! Everyone can store gear in it now.")
	else
		table.insert(m.items, out.id)
		local race = CrewDefs.find(CrewDefs.Races, m.race)
		local extra = race and race.mods.craftExtra
		if extra and Random.new():NextNumber() < extra and #m.items < ItemDefs.BagSlots then
			table.insert(m.items, out.id)
			say(player, "Dwarf luck! You made an extra " .. out.name .. ".")
		else
			say(player, "Crafted: " .. out.name)
		end
	end
end

local function storage(run, m, name)
	if name == "bag" then
		return m.items, ItemDefs.BagSlots
	elseif name == "chest" then
		if not run.chestBuilt then
			return nil
		end
		run.chest = run.chest or {}
		return run.chest, ItemDefs.ChestSlots
	elseif name == "locker" then
		return m.locker, ItemDefs.LockerSlots
	end
	return nil
end

local function onMove(player, m, run, data)
	if type(data) ~= "table" or type(data.index) ~= "number" then
		return
	end
	local from = storage(run, m, data.from)
	local to, toMax = storage(run, m, data.to)
	if not from or not to or from == to then
		return
	end
	local other = if data.from == "bag" then data.to else data.from
	if other == "chest" and not near(player, "CrewChest") then
		say(player, "Walk to the Crew Chest.")
		return
	elseif other == "locker" and not near(player, "Lockers") then
		say(player, "Walk to the Lockers.")
		return
	end
	local item = from[math.floor(data.index)]
	if not item then
		return
	end
	if #to >= toMax then
		say(player, "That's full.")
		return
	end
	table.remove(from, math.floor(data.index))
	table.insert(to, item)
end

local function onEquip(player, m, index)
	local item = m.items[index]
	local def = item and ItemDefs.Items[item]
	if not def or (def.kind ~= "weapon" and def.kind ~= "armor") then
		return
	end
	local slot = if def.kind == "weapon" then "Weapon" else def.slot
	table.remove(m.items, index)
	if m.gear[slot] then
		table.insert(m.items, m.gear[slot])
	end
	m.gear[slot] = item
	if def.kind == "weapon" and def.classWeapon ~= m.classId then
		say(player, "Equipped " .. def.name .. ". It's not a " .. m.classId .. " weapon, so it gives no bonus.")
	else
		say(player, "Equipped " .. def.name .. ".")
	end
end

local function onUnequip(player, m, slot)
	if type(slot) ~= "string" or not m.gear[slot] then
		return
	end
	if #m.items >= ItemDefs.BagSlots then
		say(player, "Your bag is full.")
		return
	end
	table.insert(m.items, m.gear[slot])
	m.gear[slot] = nil
end

local function onUse(player, m, run, index)
	local item = m.items[index]
	local def = item and ItemDefs.Items[item]
	if not def or def.kind ~= "use" then
		return
	end
	if def.heal then
		if (m.hpFrac or 1) >= 1 then
			say(player, "You're already at full health.")
		return
		end
		m.hpFrac = math.min(1, (m.hpFrac or 1) + def.heal)
	elseif def.hull then
		if not near(player, "RepairBench") then
			say(player, "Use Hull Patches at the Repairs station.")
		return
		end
		run.hull = math.min(ItemDefs.HullMax, (run.hull or ItemDefs.HullMax) + def.hull)
	end
	table.remove(m.items, index)
	say(player, "Used " .. def.name .. ".")
end

-- role stations: once per ship visit each
local function onStation(player, m, run, name)
	local st = ShipService.Stations[name]
	if not st or not near(player, name) then
		return
	end
	if st.role and m.role ~= st.role then
		say(player, "Only the " .. st.role .. " can use the " .. st.label .. ". (NPC crew do their job on their own.)")
		return
	end
	run.stationUsed = run.stationUsed or {}
	if run.stationUsed[name] then
		say(player, "Already done this visit. Try again after the next stop.")
		return
	end
	if name == "Infirmary" then
		for _, x in Run.members(run) do
			x.hpFrac = math.min(1, (x.hpFrac or 1) + 0.2)
		end
		Remotes.toast(nil, m.name .. " (Doctor) treats the crew: everyone heals 20%.")
	elseif name == "Galley" then
		for _, x in Run.members(run) do
			x.hpFrac = math.min(1, (x.hpFrac or 1) + 0.1)
		end
		Remotes.toast(nil, m.name .. " (Cook) hands out snacks: everyone heals 10%.")
	elseif name == "Stage" then
		run.mealBonus = (run.mealBonus or 0) + 0.03
		Remotes.toast(nil, m.name .. " (Musician) plays a sea shanty: +3% crew damage next fight.")
	elseif name == "Study" then
		local mats = { "Driftwood", "Iron Plate", "Cloth Strip" }
		local item = mats[Random.new():NextInteger(1, 3)]
		Run.addLoot(run, { [item] = 1 })
		Remotes.toast(nil, m.name .. " (Archaeologist) finds a note about hidden supplies: +1 " .. item .. ".")
	elseif name == "CrowsNest" then
		say(player, "From up here you can see far. Open the Sea Chart: as Navigator you see what waits at every stop.")
		return
	else
		return
	end
	run.stationUsed[name] = true
	Run.broadcast(run)
end

Remotes.Ship.OnServerEvent:Connect(function(player, msg, data)
	local m, run = member(player)
	if not m then
		return
	end
	m.items = m.items or {}
	m.gear = m.gear or {}
	m.locker = m.locker or {}
	if msg == "craft" and type(data) == "number" then
		onCraft(player, m, run, math.floor(data))
	elseif msg == "move" then
		onMove(player, m, run, data)
	elseif msg == "equip" and type(data) == "number" then
		onEquip(player, m, math.floor(data))
	elseif msg == "unequip" then
		onUnequip(player, m, data)
	elseif msg == "use" and type(data) == "number" then
		onUse(player, m, run, math.floor(data))
	elseif msg == "station" and type(data) == "string" then
		onStation(player, m, run, data)
	end
	ShipService.push(run)
end)

-- put the crew on deck (called by Run before every Ready)
function ShipService.board(run)
	ShipService.build()
	run.stationUsed = {}
	run.hull = run.hull or ItemDefs.HullMax
	for i, m in Run.members(run) do
		m.items = m.items or {}
		m.gear = m.gear or {}
		m.locker = m.locker or {}
		local ch = m.player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = false
			root.CFrame = ShipService.deckSpot(i)
		end
	end
	ShipService.push(run)
end

-- anyone who jumps the rail is fished back out (drowning for fruit users comes with Devil Fruits)
task.spawn(function()
	while true do
		task.wait(0.5)
		local run = Run.current
		if run and run.state == "ship" then
			for i, m in Run.members(run) do
				local ch = m.player.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				if root and root.Position.Y < deckY - 8 then
					root.CFrame = ShipService.deckSpot(i)
					say(m.player, "SPLASH! Your crew fished you out of the sea.")
				end
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(ch)
		local run = Run.current
		if run and run.state == "ship" then
			local root = ch:WaitForChild("HumanoidRootPart", 5)
			if root then
				task.wait()
				root.CFrame = ShipService.deckSpot(1)
			end
		end
	end)
end)

return ShipService
