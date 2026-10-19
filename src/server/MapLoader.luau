-- Loads the owner's maps. The owner builds the real 3D maps; the code only needs named MARKER parts.
-- See MAP_GUIDE.md for the plain-words version.
--
--   ServerStorage/Maps/Islands/<any name>   fight arenas (picked at random; optional attribute Sea = 1/2/3)
--   ServerStorage/Maps/Bosses/<boss id>     boss arenas, named after the boss ("Arlong", "Kaido"...), or any name
--                                           (a random one is used when no arena has the boss's name)
--   ServerStorage/Maps/Ship/<any name>      the crew's ship (the first model in there is used)
--
-- Markers are parts found anywhere inside the map model (by exact name). Their FRONT face (LookVector) is where
-- a pirate standing there looks. Spots stand on the ground (the part's bottom is the floor).
--   arenas: CrewSpot1..CrewSpot6, EnemySpot1..EnemySpot6, CameraSpot (front face looks at the fight)
--   ship:   DeckSpot1..DeckSpot6, MapTable, CraftBench, CrewChest, RepairBench, Lockers, Galley, Infirmary,
--           CrowsNest, Stage, Study, LobbyCamera (optional)
local ServerStorage = game:GetService("ServerStorage")

local MapLoader = {}

-- spot markers are always hidden; station markers stay as the builder made them
MapLoader.HiddenPrefixes = { "CrewSpot", "EnemySpot", "CameraSpot", "DeckSpot", "LobbyCamera" }

local function mapsFolder(kind)
	local maps = ServerStorage:FindFirstChild("Maps")
	return maps and maps:FindFirstChild(kind)
end

-- All models in Maps/<kind> (Models or Folders), optionally only those whose Sea attribute matches.
function MapLoader.list(kind, sea)
	local folder = mapsFolder(kind)
	local out = {}
	if not folder then
		return out
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") or m:IsA("Folder") then
			local s = m:GetAttribute("Sea")
			if sea == nil or s == nil or s == sea then
				table.insert(out, m)
			end
		end
	end
	return out
end

function MapLoader.find(kind, name)
	local folder = mapsFolder(kind)
	local m = folder and folder:FindFirstChild(name)
	if m and (m:IsA("Model") or m:IsA("Folder")) then
		return m
	end
	return nil
end

-- Clone a map into a parent, hide its spot markers. Stays where the builder placed it.
function MapLoader.place(template, parent, name)
	local m = template:Clone()
	m.Name = name or template.Name
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			for _, prefix in MapLoader.HiddenPrefixes do
				if d.Name:sub(1, #prefix) == prefix then
					d.Transparency = 1
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					for _, child in d:GetChildren() do
						if child:IsA("Decal") or child:IsA("Texture") then
							child.Transparency = 1
						end
					end
				end
			end
		end
	end
	m.Parent = parent
	return m
end

function MapLoader.marker(model, name)
	local p = model:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- Where a spot marker touches the ground, facing its front face (rotation kept, tilt removed).
function MapLoader.groundCFrame(part)
	local cf = part.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local ground = cf.Position - Vector3.new(0, part.Size.Y / 2, 0)
	return CFrame.lookAt(ground, ground + look.Unit)
end

return MapLoader
