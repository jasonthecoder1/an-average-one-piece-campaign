-- The fight arena: an island clearing near the anchored ship. Crew stands on the near side in two rows of 3
-- (seen from behind by the For The King-style camera), enemies on the far side.
-- Enemies are chunky block figures built here (all original looks from BattleDefs.Looks).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local BattleDefs = require(ReplicatedStorage.Shared.BattleDefs)

local Arena = {}

Arena.Center = Vector3.new(0, 2, 420) -- beside the ship (ship sits around the origin)
local C = Arena.Center

local folder

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

-- Slot positions: index 1..6. Front row 1-3, back row 4-6.
function Arena.crewSlot(i)
	local row = if i <= 3 then 0 else 1
	local col = ((i - 1) % 3) - 1
	local pos = C + Vector3.new(col * 7 + row * 3.5, 1, 11 + row * 7)
	return CFrame.lookAt(pos, Vector3.new(pos.X, pos.Y, C.Z - 20))
end

function Arena.enemySlot(i, n)
	local row = if i <= 3 then 0 else 1
	local col = ((i - 1) % 3) - 1
	if n == 1 then
		col = 0
	end
	local pos = C + Vector3.new(col * 8 + row * 4, 1, -11 - row * 8)
	return CFrame.lookAt(pos, Vector3.new(pos.X, pos.Y, C.Z + 20))
end

-- Camera spot for the client (behind and above the crew, looking at the enemies).
Arena.CameraPos = C + Vector3.new(14, 22, 42)
Arena.CameraLook = C + Vector3.new(0, 0, -8)

function Arena.build()
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace

	-- sand clearing + grass rim
	part({ Name = "Ground", Size = Vector3.new(90, 2, 80), Position = C - Vector3.new(0, 1, 0), Color = Color3.fromRGB(226, 200, 140), Material = Enum.Material.Sand, Parent = folder })
	part({ Name = "Grass", Size = Vector3.new(130, 1.6, 120), Position = C - Vector3.new(0, 1.6, 0), Color = Color3.fromRGB(90, 160, 70), Material = Enum.Material.Grass, Parent = folder })
	part({ Name = "Sea", Size = Vector3.new(600, 1, 600), Position = C - Vector3.new(0, 3, 0), Color = Color3.fromRGB(40, 120, 190), Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false, Parent = folder })

	local rng = Random.new(42)
	-- palm trees around the edge (chunky, readable from far away)
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2
		local r = rng:NextNumber(42, 55)
		local base = C + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r * 0.9)
		if base.Z > C.Z + 30 and math.abs(base.X - C.X) < 30 then
			continue -- keep the camera side open
		end
		local h = rng:NextNumber(12, 18)
		part({ Name = "Trunk", Size = Vector3.new(1.6, h, 1.6), CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))), Color = Color3.fromRGB(130, 90, 55), Material = Enum.Material.Wood, Parent = folder })
		for k = 1, 4 do
			local leaf = part({ Name = "Leaf", Size = Vector3.new(9, 0.6, 2.4), Color = Color3.fromRGB(60, 150, 60), Material = Enum.Material.Grass, CanCollide = false, Parent = folder })
			leaf.CFrame = CFrame.new(base + Vector3.new(0, h, 0)) * CFrame.Angles(0, k * math.pi / 2, math.rad(-18)) * CFrame.new(4, 0, 0)
		end
	end
	-- story props: crates, barrels, rope posts
	for i = 1, 10 do
		local pos = C + Vector3.new(rng:NextNumber(-38, 38), 0, rng:NextNumber(-34, -24))
		if i % 2 == 0 then
			part({ Name = "Crate", Size = Vector3.new(3, 3, 3), Position = pos + Vector3.new(0, 1.5, 0), Orientation = Vector3.new(0, rng:NextNumber(0, 90), 0), Color = Color3.fromRGB(160, 110, 60), Material = Enum.Material.WoodPlanks, Parent = folder })
		else
			local b = part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.2, 2.4, 2.4), Color = Color3.fromRGB(120, 75, 40), Material = Enum.Material.Wood, Parent = folder })
			b.CFrame = CFrame.new(pos + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
	-- warm light
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

	local enemies = Instance.new("Folder")
	enemies.Name = "Enemies"
	enemies.Parent = folder
	return folder
end

-- A block figure for an enemy. Returns the Model (PrimaryPart = root, anchored; the rest welded).
function Arena.spawnEnemy(def, uid, cf)
	local look = BattleDefs.Looks[def.look] or BattleDefs.Looks.Pirate
	local s = (look.scale or 1) * (def.scale or 1)
	local m = Instance.new("Model")
	m.Name = uid
	m:SetAttribute("Uid", uid)
	local root = part({ Name = "Root", Size = Vector3.new(2, 2, 1) * s, Transparency = 1, CanCollide = false, Parent = m })
	root.CFrame = cf * CFrame.new(0, 2 * s, 0)
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
	m.Parent = folder.Enemies
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
