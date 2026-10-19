-- The crew's ship: the only place you can walk. Built from parts at the origin (chunky, readable, wood + rope).
-- Stations (design page "The ship"): Map Table (Ready / chart), Crafting + Crew Chest, Repairs + Lockers,
-- Galley (Cook), Infirmary (Doctor), Crow's Nest (Navigator), Stage (Musician), Study (Archaeologist).
-- Crafting on the ship is always safe. Every action is checked here: you must be in the run and near the station.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ItemDefs = require(Shared.ItemDefs)
local CrewDefs = require(Shared.CrewDefs)
local Remotes = require(script.Parent.Remotes)
local Run = require(script.Parent.Run)

local ShipService = {}

local DECK_Y = 10
local ship
ShipService.Stations = {} -- [name] = { part, label, role? }

local WOOD = Color3.fromRGB(150, 100, 60)
local DARK = Color3.fromRGB(100, 65, 38)
local CREAM = Color3.fromRGB(243, 234, 215)

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.WoodPlanks
	p.Color = WOOD
	for k, v in props do
		p[k] = v
	end
	p.Parent = props.Parent or ship
	return p
end

local function station(name, label, action, pos, size, color, role)
	local p = part({ Name = name, Size = size, Position = Vector3.new(pos.X, DECK_Y + size.Y / 2, pos.Z), Color = color or DARK, Material = Enum.Material.Wood })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ObjectText = label
	prompt.ActionText = action
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	-- floating sign so stations read from far away
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 34)
	bb.StudsOffset = Vector3.new(0, size.Y / 2 + 2.2, 0)
	bb.MaxDistance = 70
	bb.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	t.TextColor3 = CREAM
	t.Font = Enum.Font.Bangers
	t.TextScaled = true
	t.Text = label
	t.Parent = bb
	local st = Instance.new("UIStroke")
	st.Color = CREAM
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = t
	ShipService.Stations[name] = { part = p, label = label, role = role }
	return p
end

function ShipService.build()
	if ship then
		return ship
	end
	ship = Instance.new("Model")
	ship.Name = "Ship"
	ship.Parent = workspace

	-- sea
	part({ Name = "Sea", Size = Vector3.new(2048, 2, 2048), Position = Vector3.new(0, -1, 0), Color = Color3.fromRGB(35, 115, 185), Material = Enum.Material.Glass, Transparency = 0.1 })
	-- hull (stacked boards that get narrower toward the keel) and a pointed bow
	for i = 0, 4 do
		local w = 28 - i * 4
		part({ Name = "Hull", Size = Vector3.new(80 - i * 6, 2, w), Position = Vector3.new(-2, DECK_Y - 1 - i * 2, 0), Color = if i % 2 == 0 then DARK else WOOD })
	end
	for i = 0, 3 do
		local w = 22 - i * 5
		part({ Name = "Bow", Size = Vector3.new(10, 2, w), Position = Vector3.new(43 + i * 3, DECK_Y - 1, 0), Color = DARK })
	end
	part({ Name = "Deck", Size = Vector3.new(80, 1, 28), Position = Vector3.new(-2, DECK_Y - 0.5, 0), Color = Color3.fromRGB(180, 130, 80) })
	-- rails all around (keeps crew from falling into the sea)
	part({ Name = "RailN", Size = Vector3.new(80, 3, 1), Position = Vector3.new(-2, DECK_Y + 1.5, 14), Color = DARK })
	part({ Name = "RailS", Size = Vector3.new(80, 3, 1), Position = Vector3.new(-2, DECK_Y + 1.5, -14), Color = DARK })
	part({ Name = "RailStern", Size = Vector3.new(1, 3, 28), Position = Vector3.new(-42, DECK_Y + 1.5, 0), Color = DARK })
	part({ Name = "RailBowN", Size = Vector3.new(16, 3, 1), CFrame = CFrame.new(44, DECK_Y + 1.5, 9) * CFrame.Angles(0, math.rad(35), 0), Color = DARK })
	part({ Name = "RailBowS", Size = Vector3.new(16, 3, 1), CFrame = CFrame.new(44, DECK_Y + 1.5, -9) * CFrame.Angles(0, math.rad(-35), 0), Color = DARK })
	part({ Name = "Figurehead", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(52, DECK_Y + 1, 0), Color = Color3.fromRGB(240, 200, 70), Material = Enum.Material.SmoothPlastic })
	-- mast, sail with a jolly roger, crow's nest
	part({ Name = "Mast", Shape = Enum.PartType.Cylinder, Size = Vector3.new(44, 2.2, 2.2), CFrame = CFrame.new(2, DECK_Y + 22, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = DARK, Material = Enum.Material.Wood })
	part({ Name = "Sail", Size = Vector3.new(1, 18, 26), Position = Vector3.new(3.5, DECK_Y + 24, 0), Color = CREAM, Material = Enum.Material.Fabric, CanCollide = false })
	part({ Name = "Skull", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7, 7), CFrame = CFrame.new(4.2, DECK_Y + 25, 0), Color = Color3.fromRGB(20, 20, 20), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	part({ Name = "Bone1", Size = Vector3.new(0.3, 1.2, 12), CFrame = CFrame.new(4.3, DECK_Y + 20.5, 0) * CFrame.Angles(math.rad(30), 0, 0), Color = Color3.fromRGB(20, 20, 20), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	part({ Name = "Bone2", Size = Vector3.new(0.3, 1.2, 12), CFrame = CFrame.new(4.3, DECK_Y + 20.5, 0) * CFrame.Angles(math.rad(-30), 0, 0), Color = Color3.fromRGB(20, 20, 20), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	part({ Name = "CrowsNest", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 7, 7), CFrame = CFrame.new(2, DECK_Y + 38, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = DARK })
	-- stern cabin
	part({ Name = "Cabin", Size = Vector3.new(14, 9, 26), Position = Vector3.new(-35, DECK_Y + 4.5, 0), Color = WOOD })
	part({ Name = "CabinRoof", Size = Vector3.new(15, 1, 27), Position = Vector3.new(-35, DECK_Y + 9.5, 0), Color = DARK })
	part({ Name = "CabinDoor", Size = Vector3.new(0.4, 6, 4), Position = Vector3.new(-27.9, DECK_Y + 3, 0), Color = Color3.fromRGB(70, 45, 25) })
	-- story props: barrels, crates, rope coils
	for i, pos in { Vector3.new(36, 0, -10), Vector3.new(34, 0, 11), Vector3.new(-24, 0, 12), Vector3.new(12, 0, 12), Vector3.new(14, 0, -12) } do
		if i % 2 == 0 then
			part({ Name = "Crate", Size = Vector3.new(3, 3, 3), Position = Vector3.new(pos.X, DECK_Y + 1.5, pos.Z), Color = Color3.fromRGB(165, 115, 60) })
		else
			part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 2.6, 2.6), CFrame = CFrame.new(pos.X, DECK_Y + 1.7, pos.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(120, 75, 40), Material = Enum.Material.Wood })
		end
	end
	-- stations
	local mt = station("MapTable", "MAP TABLE", "Sea Chart / Ready", Vector3.new(10, 0, 0), Vector3.new(6, 3, 4))
	part({ Name = "MapPaper", Size = Vector3.new(5, 0.2, 3.2), Position = mt.Position + Vector3.new(0, 1.6, 0), Color = CREAM, Material = Enum.Material.SmoothPlastic })
	station("Crafting", "CRAFTING", "Craft", Vector3.new(-12, 0, -10), Vector3.new(7, 3.5, 3))
	station("CrewChest", "CREW CHEST", "Open", Vector3.new(-20, 0, -10), Vector3.new(4.5, 3, 3), Color3.fromRGB(120, 80, 40))
	station("Repairs", "REPAIRS", "Repair hull", Vector3.new(-12, 0, 10), Vector3.new(6, 2.5, 3), Color3.fromRGB(110, 110, 120))
	station("Lockers", "LOCKERS", "Open your locker", Vector3.new(-21, 0, 11.5), Vector3.new(7, 6, 2), Color3.fromRGB(90, 95, 105))
	station("Galley", "GALLEY", "Cook", Vector3.new(24, 0, -10), Vector3.new(5, 4, 3), Color3.fromRGB(70, 70, 75), "Cook")
	station("Infirmary", "INFIRMARY", "Treat crew", Vector3.new(24, 0, 10), Vector3.new(6, 2, 3.5), CREAM, "Doctor")
	station("CrowsNestLadder", "CROW'S NEST", "Look out", Vector3.new(4, 0, -3.5), Vector3.new(2, 8, 1), DARK, "Navigator")
	station("Stage", "STAGE", "Play a song", Vector3.new(33, 0, 0), Vector3.new(6, 1, 6), Color3.fromRGB(150, 40, 40), "Musician")
	station("Study", "STUDY", "Study old charts", Vector3.new(-27, 0, -7), Vector3.new(1.5, 7, 6), Color3.fromRGB(90, 60, 40), "Archaeologist")

	-- spawn on the deck
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DeckSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, DECK_Y - 0.4, 6)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = ship
	for _, s in workspace:GetChildren() do
		if s:IsA("SpawnLocation") and s ~= spawn then
			s.Enabled = false
		end
	end
	return ship
end

function ShipService.deckSpot(i)
	local col = (i - 1) % 3
	local row = math.floor((i - 1) / 3)
	return CFrame.new(-2 + col * 5, DECK_Y + 3, -3 + row * 6)
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
	if not near(player, "Crafting") then
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
		if not near(player, "Repairs") then
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
	elseif name == "CrowsNestLadder" then
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
				if root and root.Position.Y < DECK_Y - 4 and math.abs(root.Position.Z - 420) > 200 then
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
