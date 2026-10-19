-- The fight arena. The OWNER builds the real island / boss arenas (see MAP_GUIDE.md and MapLoader.luau);
-- this file loads one per fight and reads its marker parts (CrewSpot1-6, EnemySpot1-6, CameraSpot).
-- With no maps yet, a plain block stand-in is used so the game still runs.
-- Enemies are chunky block figures built here (all original looks from BattleDefs.Looks).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local BattleDefs = require(ReplicatedStorage.Shared.BattleDefs)
local MapLoader = require(script.Parent.MapLoader)

local Arena = {}

Arena.Center = Vector3.new(0, 2, 420) -- where the stand-in island goes (away from the ship at the origin)
local C = Arena.Center
Arena.CameraPos = C + Vector3.new(14, 22, 42) -- set again by Arena.load from the map's CameraSpot
Arena.CameraLook = C + Vector3.new(0, 0, -8)

local folder
local current -- the loaded arena model

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end

-- Default spot layout around a center (ground level): crew in two rows of 3 on the near side (+Z),
-- enemies on the far side (-Z), facing each other. Used by the stand-in and for any marker a map is missing.
local function defaultCrew(center, i)
	local row = if i <= 3 then 0 else 1
	local col = ((i - 1) % 3) - 1
	local pos = center + Vector3.new(col * 7 + row * 3.5, 0, 11 + row * 7)
	return CFrame.lookAt(pos, pos - Vector3.new(0, 0, 1))
end

local function defaultEnemy(center, i)
	local row = if i <= 3 then 0 else 1
	local col = ((i - 1) % 3) - 1
	local pos = center + Vector3.new(col * 8 + row * 4, 0, -11 - row * 8)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
end

local function marker(model, name, size, cf)
	local p = part({ Name = name, Size = size, CFrame = cf * CFrame.new(0, size.Y / 2, 0), Transparency = 1, CanCollide = false, CanQuery = false, Parent = model })
	return p
end

-- A plain block stand-in island with all the markers, so fights work before the owner's maps exist.
local function buildStandIn()
	local m = Instance.new("Model")
	m.Name = "StandInIsland"
	part({ Name = "Ground", Size = Vector3.new(90, 2, 80), Position = C - Vector3.new(0, 1, 0), Color = Color3.fromRGB(226, 200, 140), Material = Enum.Material.Sand, Parent = m })
	local center = Vector3.new(C.X, C.Y, C.Z)
	for i = 1, 6 do
		marker(m, "CrewSpot" .. i, Vector3.new(2, 1, 2), defaultCrew(center, i))
		marker(m, "EnemySpot" .. i, Vector3.new(2, 1, 2), defaultEnemy(center, i))
	end
	local camPos = center + Vector3.new(14, 22, 42)
	marker(m, "CameraSpot", Vector3.new(1, 1, 1), CFrame.lookAt(camPos, center + Vector3.new(0, 0, -8)) * CFrame.new(0, -0.5, 0))
	return m
end

function Arena.build()
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace
	local enemies = Instance.new("Folder")
	enemies.Name = "Enemies"
	enemies.Parent = folder
	-- warm light (the owner's maps can bring their own Lighting later)
	local lighting = game:GetService("Lighting")
	lighting.ClockTime = 15.5
	lighting.Brightness = 2.2
	lighting.OutdoorAmbient = Color3.fromRGB(150, 130, 110)
	if not lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.28
		atm.Color = Color3.fromRGB(255, 220, 180)
		atm.Decay = Color3.fromRGB(255, 170, 120)
		atm.Parent = lighting
	end
	return folder
end

-- Load the arena for a fight. kind = "Fight" | "Elite" | "Boss"; bossId = the boss's enemy id (boss fights).
function Arena.load(kind, bossId, sea)
	Arena.build()
	if current then
		current:Destroy()
		current = nil
	end
	local template = nil
	if kind == "Boss" then
		template = (bossId and MapLoader.find("Bosses", bossId)) or nil
		if not template then
			local list = MapLoader.list("Bosses", sea)
			if #list > 0 then
				template = list[math.random(1, #list)]
			end
		end
	end
	if not template then
		local list = MapLoader.list("Islands", sea)
		if #list > 0 then
			template = list[math.random(1, #list)]
		end
	end
	if template then
		current = MapLoader.place(template, folder, "Map")
		-- a Folder map gets wrapped in a Model, so the rest of the code can always use GetPivot
		if current:IsA("Folder") then
			local model = Instance.new("Model")
			model.Name = current.Name
			for _, c in current:GetChildren() do
				c.Parent = model
			end
			current:Destroy()
			if model:FindFirstChildWhichIsA("BasePart", true) then
				model.WorldPivot = model:GetBoundingBox() -- pivot in the middle of the map, not at 0,0,0
			end
			model.Parent = folder
			current = model
		end
	else
		current = buildStandIn()
		current.Name = "Map"
		current.Parent = folder
	end
	-- camera: the CameraSpot's front face looks at the fight
	local cam = MapLoader.marker(current, "CameraSpot")
	local c1 = MapLoader.marker(current, "CrewSpot1")
	local e1 = MapLoader.marker(current, "EnemySpot1")
	if cam then
		Arena.CameraPos = cam.Position
		Arena.CameraLook = cam.Position + cam.CFrame.LookVector * 40
	else
		local a = if c1 then c1.Position else C + Vector3.new(0, 0, 11)
		local b = if e1 then e1.Position else C + Vector3.new(0, 0, -11)
		local away = (a - b)
		away = Vector3.new(away.X, 0, away.Z)
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
		Arena.CameraPos = a + away * 30 + Vector3.new(0, 22, 0)
		Arena.CameraLook = (a + b) / 2
	end
	return current
end

local function center()
	if current then
		local c1 = MapLoader.marker(current, "CrewSpot1")
		local e1 = MapLoader.marker(current, "EnemySpot1")
		if c1 and e1 then
			return (MapLoader.groundCFrame(c1).Position + MapLoader.groundCFrame(e1).Position) / 2
		end
		if current:IsA("PVInstance") then
			return current:GetPivot().Position
		end
		local p = current:FindFirstChildWhichIsA("BasePart", true)
		return if p then p.Position else C
	end
	return C
end

-- Ground CFrame (facing the enemies) for crew slot i (1..6).
function Arena.crewSlot(i)
	local p = current and MapLoader.marker(current, "CrewSpot" .. i)
	if p then
		return MapLoader.groundCFrame(p)
	end
	return defaultCrew(center(), i)
end

-- Ground CFrame (facing the crew) for enemy slot i. A lone enemy stands on the middle spot (2) if it exists.
function Arena.enemySlot(i, n)
	local idx = if n == 1 and current and MapLoader.marker(current, "EnemySpot2") then 2 else i
	local p = current and MapLoader.marker(current, "EnemySpot" .. idx)
	if p then
		return MapLoader.groundCFrame(p)
	end
	return defaultEnemy(center(), i)
end

-- A block figure for an enemy. Returns the Model (PrimaryPart = root, anchored; the rest welded).
function Arena.spawnEnemy(def, uid, cf)
	local look = BattleDefs.Looks[def.look] or BattleDefs.Looks.Pirate
	local s = (look.scale or 1) * (def.scale or 1)
	local m = Instance.new("Model")
	m.Name = uid
	m:SetAttribute("Uid", uid)
	local root = part({ Name = "Root", Size = Vector3.new(2, 2, 1) * s, Transparency = 1, CanCollide = false, Parent = m })
	root.CFrame = cf * CFrame.new(0, 3 * s, 0) -- cf is the ground spot; legs reach the floor
	m.PrimaryPart = root
	local function limb(name, size, offset, color, mat)
		local p = part({ Name = name, Size = size * s, Color = color, Material = mat or Enum.Material.SmoothPlastic, Anchored = false, CanCollide = false, Parent = m })
		p.CFrame = root.CFrame * CFrame.new(offset * s)
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		return p
	end
	limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), look.shirt, Enum.Material.Fabric)
	limb("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.65, 0), look.skin)
	limb("LeftArm", Vector3.new(0.9, 2, 0.9), Vector3.new(-1.45, 0, 0), look.skin)
	limb("RightArm", Vector3.new(0.9, 2, 0.9), Vector3.new(1.45, 0, 0), look.skin)
	limb("LeftLeg", Vector3.new(0.95, 2, 0.95), Vector3.new(-0.5, -2, 0), look.pants, Enum.Material.Fabric)
	limb("RightLeg", Vector3.new(0.95, 2, 0.95), Vector3.new(0.5, -2, 0), look.pants, Enum.Material.Fabric)
	-- eyes (facing the crew, +Z after lookAt is the back, so front = -Z in local space)
	limb("EyeL", Vector3.new(0.22, 0.28, 0.05), Vector3.new(-0.3, 1.75, -0.66), Color3.new(0.05, 0.05, 0.05))
	limb("EyeR", Vector3.new(0.22, 0.28, 0.05), Vector3.new(0.3, 1.75, -0.66), Color3.new(0.05, 0.05, 0.05))
	if look.hatKind == "cap" then
		limb("Cap", Vector3.new(1.45, 0.45, 1.45), Vector3.new(0, 2.45, 0), look.hat)
		limb("Brim", Vector3.new(1.45, 0.12, 0.6), Vector3.new(0, 2.25, -0.9), look.hat)
	elseif look.hatKind == "bandana" then
		limb("Bandana", Vector3.new(1.4, 0.4, 1.4), Vector3.new(0, 2.15, 0), look.hat)
	elseif look.hatKind == "horns" then
		limb("HornL", Vector3.new(0.3, 1.2, 0.3), Vector3.new(-0.5, 2.8, 0), look.hat)
		limb("HornR", Vector3.new(0.3, 1.2, 0.3), Vector3.new(0.5, 2.8, 0), look.hat)
	end
	if def.look == "Arlong" then
		limb("Nose", Vector3.new(0.3, 0.3, 1.6), Vector3.new(0, 1.6, -1.3), Color3.fromRGB(60, 100, 160)) -- saw nose
	end
	-- a weapon in the right hand for elites/bosses
	if def.rank ~= "minion" then
		limb("Weapon", Vector3.new(0.25, 0.25, 4), Vector3.new(1.45, -0.9, -1.8), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
	end
	m.Parent = Arena.build().Enemies
	return m
end

function Arena.clearEnemies()
	if folder then
		folder.Enemies:ClearAllChildren()
	end
end

-- Little lunge toward a point and back (attacks). Works for player roots and enemy roots (both anchored).
function Arena.lunge(rootPart, towards)
	if not rootPart or not rootPart.Parent then
		return
	end
	local start = rootPart.CFrame
	local dir = (towards - start.Position)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		return
	end
	local goal = start + dir.Unit * math.min(6, dir.Magnitude * 0.4)
	local t1 = TweenService:Create(rootPart, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal })
	t1:Play()
	t1.Completed:Wait()
	TweenService:Create(rootPart, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { CFrame = start }):Play()
end

-- Knocked out enemies tip over and fade.
function Arena.defeat(model)
	if not model or not model.PrimaryPart then
		return
	end
	local root = model.PrimaryPart
	TweenService:Create(root, TweenInfo.new(0.5), { CFrame = root.CFrame * CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-80), 0, 0) }):Play()
	task.delay(0.6, function()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p ~= root then
				TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		end
	end)
end

return Arena
