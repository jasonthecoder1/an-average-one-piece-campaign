-- Ship screens: Crafting bench, Crew Chest, your Locker, your Bag (gear + items) and Repairs.
-- Opened by walking up to a station and pressing its prompt (E), or B for the bag. All in the owner's UI style.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local ItemDefs = require(Shared.ItemDefs)
local Kit = require(script.Parent.Kit)
local Style = Kit.Style
local new = Kit.new

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ship")
local mapRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Map")

local ShipUI = {}
ShipUI.openChart = nil -- set by Main (MapUI.open)
ShipUI.blocked = nil

local gui = Kit.screen("ShipScreens", 15, player:WaitForChild("PlayerGui"))
Kit.autoScale(gui, 1100, 700)
local inv = nil
local invKey = nil -- the last inv as text: a refresh with nothing new doesn't rebuild the open screen
local open = nil -- { kind, frame }

local function close()
	if open then
		open.frame:Destroy()
		open = nil
	end
end

local function itemTile(parent, id, order, onClick, sub)
	local def = ItemDefs.Items[id]
	local holder = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(74, 84), LayoutOrder = order, ZIndex = 12, Parent = parent })
	Kit.tile({ Glyph = def and def.glyph or "?", Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(14, 2), ZIndex = 12, Parent = holder })
	Kit.label({ Text = def and def.name or id, Font = Style.BodyLight, TextSize = 11, Wrap = true, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 52), ZIndex = 13, Parent = holder })
	if sub then
		Kit.label({ Text = sub, Font = Style.Body, TextSize = 12, Color = Style.Cyan, Size = UDim2.fromOffset(30, 14), Position = UDim2.new(1, -30, 0, 0), ZIndex = 15, Parent = holder, Outline = 1.5 })
	end
	if onClick then
		holder.Activated:Connect(onClick)
	end
	return holder
end

local function grid(parent, name, pos, size)
	local g = new("ScrollingFrame", { Name = name, BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = size, Position = pos, ZIndex = 11, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = parent })
	Kit.stroke(g, Style.Cream, 2)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(74, 86), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = g })
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 6), Parent = g })
	return g
end

local function frame(kind, title, w, h)
	close()
	local f = Kit.panel({ Name = kind, Size = UDim2.fromOffset(w, h), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 10, Parent = gui, Rotation = -0.6 })
	Kit.tab(f, title, 230)
	Kit.button({ Text = "X", TextSize = 22, Size = UDim2.fromOffset(40, 36), Position = UDim2.new(1, -30, 0, -20), ZIndex = 14, Color = Style.Panel2, Parent = f, OnClick = close })
	open = { kind = kind, frame = f }
	return f
end

local function holdText()
	local parts = {}
	for item, n in inv.hold or {} do
		table.insert(parts, n .. "x " .. item)
	end
	table.sort(parts)
	return "SHIP HOLD: " .. (if #parts > 0 then table.concat(parts, "  ·  ") else "empty (win fights to get materials)")
end

-- ===== crafting =====
local function showCraft()
	local f = frame("Craft", "CRAFTING", 760, 520)
	Kit.label({ Text = holdText(), Font = Style.Body, TextSize = 14, Color = Style.Gold, Wrap = true, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 16), ZIndex = 12, Parent = f })
	local list = new("ScrollingFrame", { Name = "Recipes", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -40, 1, -76), Position = UDim2.fromOffset(20, 58), ZIndex = 11, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = f })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(345, 84), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	for i, r in ItemDefs.Recipes do
		local def = ItemDefs.Items[r.out]
		local card = new("Frame", { BackgroundColor3 = Style.Panel2, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 12, Parent = list })
		Kit.stroke(card, Style.Cream, 2)
		Kit.tile({ Glyph = def.glyph, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 14), ZIndex = 13, Parent = card })
		Kit.label({ Text = string.upper(def.name), Font = Style.Display, TextSize = 20, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -170, 0, 22), Position = UDim2.fromOffset(66, 4), ZIndex = 13, Parent = card })
		Kit.label({ Text = def.desc, Font = Style.BodyLight, TextSize = 11, Color = Style.Muted, Wrap = true, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -170, 0, 26), Position = UDim2.fromOffset(66, 26), ZIndex = 13, Parent = card })
		local needs, ok = {}, true
		for item, n in r.needs do
			local have = (inv.hold and inv.hold[item]) or 0
			if have < n then
				ok = false
			end
			table.insert(needs, n .. " " .. item .. " (" .. have .. ")")
		end
		if r.out == "Crew Chest" and inv.chestBuilt then
			ok = false
			needs = { "Already built!" }
		end
		Kit.label({ Text = table.concat(needs, ", "), Font = Style.Body, TextSize = 11, Color = if ok then Style.Cyan else Style.Red2, Wrap = true, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -170, 0, 26), Position = UDim2.fromOffset(66, 54), ZIndex = 13, Parent = card })
		local b = Kit.button({ Text = "CRAFT", TextSize = 20, Size = UDim2.fromOffset(86, 38), Position = UDim2.new(1, -96, 0.5, -19), ZIndex = 14, Parent = card, OnClick = function()
			remote:FireServer("craft", i)
		end })
		if not ok then
			Kit.setDisabled(b, true)
		end
	end
end

-- ===== storage (Crew Chest or Locker) =====
local function showStorage(which)
	local isChest = which == "chest"
	local f = frame("Storage" .. which, if isChest then "CREW CHEST" else "YOUR LOCKER", 760, 470)
	if isChest and not inv.chestBuilt then
		Kit.label({ Text = "The Crew Chest isn't built yet.\nCraft one at the CRAFTING bench (4 Driftwood + 1 Iron Plate).", Font = Style.Body, TextSize = 20, Wrap = true, Size = UDim2.new(1, -60, 1, -60), Position = UDim2.fromOffset(30, 30), ZIndex = 12, Parent = f })
		return
	end
	Kit.label({ Text = "Click an item to move it across.", Font = Style.BodyLight, TextSize = 14, Color = Style.Muted, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 14), ZIndex = 12, Parent = f })
	local other = if isChest then inv.chest else inv.locker
	local otherMax = if isChest then ItemDefs.ChestSlots else ItemDefs.LockerSlots
	Kit.label({ Text = "YOUR BAG " .. #inv.bag .. "/" .. ItemDefs.BagSlots, Font = Style.Display, TextSize = 20, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(300, 22), Position = UDim2.fromOffset(20, 40), ZIndex = 12, Parent = f })
	Kit.label({ Text = (if isChest then "CREW CHEST " else "LOCKER ") .. #other .. "/" .. otherMax, Font = Style.Display, TextSize = 20, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(300, 22), Position = UDim2.fromOffset(392, 40), ZIndex = 12, Parent = f })
	local left = grid(f, "Bag", UDim2.fromOffset(20, 66), UDim2.new(0, 348, 1, -88))
	local right = grid(f, "Other", UDim2.fromOffset(392, 66), UDim2.new(0, 348, 1, -88))
	-- the id goes along with the index: the server checks it's still that item
	for i, id in inv.bag do
		itemTile(left, id, i, function()
			remote:FireServer("move", { from = "bag", to = which, index = i, id = id })
		end)
	end
	for i, id in other do
		itemTile(right, id, i, function()
			remote:FireServer("move", { from = which, to = "bag", index = i, id = id })
		end)
	end
end

-- ===== bag + gear =====
local function showBag()
	local f = frame("Bag", "YOUR GEAR", 700, 470)
	local slots = { "Weapon", "Helmet", "Chest", "Legs" }
	Kit.label({ Text = "WEARING (click to take off)", Font = Style.Body, TextSize = 13, Color = Style.Red2, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(300, 18), Position = UDim2.fromOffset(20, 16), ZIndex = 12, Parent = f })
	for i, slot in slots do
		local id = inv.gear[slot]
		local box = new("Frame", { BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = UDim2.fromOffset(150, 96), Position = UDim2.fromOffset(20 + (i - 1) * 164, 38), ZIndex = 11, Parent = f })
		Kit.stroke(box, Style.Cream, 2)
		Kit.label({ Text = string.upper(slot), Font = Style.Body, TextSize = 11, Color = Style.Muted, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 2), ZIndex = 12, Parent = box })
		if id then
			local tile = itemTile(box, id, 1, function()
				remote:FireServer("unequip", slot)
			end)
			tile.Position = UDim2.fromOffset(38, 12)
		else
			Kit.label({ Text = "empty", Font = Style.BodyLight, TextSize = 13, Color = Style.Dim, ZIndex = 12, Parent = box })
		end
	end
	Kit.label({ Text = "BAG " .. #inv.bag .. "/" .. ItemDefs.BagSlots .. "  (click: equip gear / use items)", Font = Style.Body, TextSize = 13, Color = Style.Red2, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(500, 18), Position = UDim2.fromOffset(20, 146), ZIndex = 12, Parent = f })
	local g = grid(f, "Bag", UDim2.fromOffset(20, 168), UDim2.new(1, -40, 1, -214))
	for i, id in inv.bag do
		local def = ItemDefs.Items[id]
		itemTile(g, id, i, function()
			if not def then
				return
			elseif def.kind == "use" then
				remote:FireServer("use", { index = i, id = id })
			elseif def.kind == "weapon" or def.kind == "armor" then
				remote:FireServer("equip", { index = i, id = id })
			end
		end)
	end
	Kit.label({ Text = "Class weapons only help their own class: you're a " .. (inv.classId or "?") .. ".   Health: " .. math.floor((inv.hpFrac or 1) * 100) .. "%", Font = Style.BodyLight, TextSize = 13, Color = Style.Muted, Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 20, 1, -38), ZIndex = 12, Parent = f })
end

-- ===== repairs =====
local function showRepairs()
	local f = frame("Repairs", "REPAIRS", 520, 240)
	Kit.label({ Text = "HULL " .. inv.hull .. " / " .. inv.hullMax, Font = Style.Display, TextSize = 28, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 20), ZIndex = 12, Parent = f })
	local _, set = Kit.bar({ Size = UDim2.new(1, -60, 0, 18), Position = UDim2.fromOffset(30, 58), Color = Style.Red, ZIndex = 12, Parent = f })
	set(inv.hull / inv.hullMax, true)
	Kit.label({ Text = "Your ship is super tanky. Only Marines hurt it. If it ever hits 0, the run is over.", Font = Style.BodyLight, TextSize = 14, Wrap = true, Size = UDim2.new(1, -60, 0, 40), Position = UDim2.fromOffset(30, 84), ZIndex = 12, Parent = f })
	local idx = table.find(inv.bag, "Hull Patch")
	local b = Kit.button({ Text = "USE HULL PATCH", TextSize = 20, Size = UDim2.fromOffset(220, 44), Position = UDim2.new(0.5, -110, 1, -64), ZIndex = 13, Parent = f, OnClick = function()
		if idx then
			remote:FireServer("use", { index = idx, id = "Hull Patch" })
		end
	end })
	if not idx or inv.hull >= inv.hullMax then
		Kit.setDisabled(b, true)
	end
end

local function setScroll(f, scroll)
	for _, d in f:GetDescendants() do
		if d:IsA("ScrollingFrame") and scroll[d.Name] then
			d.CanvasPosition = scroll[d.Name]
		end
	end
end

local function reopen()
	if not open or not inv then
		return
	end
	-- keep the lists where they were scrolled, so a refresh doesn't jump back to the top
	local scroll = {}
	for _, d in open.frame:GetDescendants() do
		if d:IsA("ScrollingFrame") then
			scroll[d.Name] = d.CanvasPosition
		end
	end
	local k = open.kind
	if k == "Craft" then
		showCraft()
	elseif k == "Storagechest" then
		showStorage("chest")
	elseif k == "Storagelocker" then
		showStorage("locker")
	elseif k == "Bag" then
		showBag()
	elseif k == "Repairs" then
		showRepairs()
	end
	if open then
		setScroll(open.frame, scroll)
		task.delay(0, setScroll, open.frame, scroll) -- again once the new list has its size
	end
end

-- HUD: hull + bag button (under the sea chart HUD)
local hud = Kit.panel({ Name = "ShipHud", Size = UDim2.fromOffset(250, 62), Position = UDim2.fromOffset(16, 156), ZIndex = 2, Parent = gui, Rotation = 0.8, NoDots = true })
hud.Visible = false
local hullText = Kit.label({ Text = "", Font = Style.Body, TextSize = 12, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 4), ZIndex = 4, Parent = hud })
local _, setHull = Kit.bar({ Size = UDim2.new(1, -130, 0, 8), Position = UDim2.fromOffset(10, 22), Color = Style.Red, ZIndex = 4, Parent = hud })
Kit.button({ Text = "BAG [B]", TextSize = 18, Size = UDim2.fromOffset(100, 30), Position = UDim2.new(1, -110, 0, 16), ZIndex = 5, Parent = hud, OnClick = function()
	if open and open.kind == "Bag" then
		close()
	elseif inv then
		showBag()
	end
end })

function ShipUI.setHudVisible(v)
	hud.Visible = v and inv ~= nil
	if not v then
		close()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.B or not inv or (ShipUI.blocked and ShipUI.blocked()) then
		return
	end
	if open and open.kind == "Bag" then
		close()
	else
		showBag()
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if not inv or (ShipUI.blocked and ShipUI.blocked()) then
		return
	end
	local n = prompt.Name
	if n == "MapTable" then
		close()
		if ShipUI.openChart then
			ShipUI.openChart()
		end
	elseif n == "CraftBench" then
		showCraft()
	elseif n == "CrewChest" then
		showStorage("chest")
	elseif n == "Lockers" then
		showStorage("locker")
	elseif n == "RepairBench" then
		showRepairs()
	else
		remote:FireServer("station", n)
	end
end)

function ShipUI.init()
	remote.OnClientEvent:Connect(function(msg, data)
		if msg == "inv" then
			local ok, key = pcall(HttpService.JSONEncode, HttpService, data)
			local same = ok and key == invKey
			invKey = if ok then key else nil
			inv = data
			hullText.Text = "HULL " .. data.hull .. "/" .. data.hullMax .. "   ·   HP " .. math.floor((data.hpFrac or 1) * 100) .. "%"
			setHull(data.hull / data.hullMax)
			hud.Visible = not (ShipUI.blocked and ShipUI.blocked())
			if not same then
				reopen()
			end
		end
	end)
	-- the run is over: forget its bag and close its screens (MapUI shows the result)
	mapRemote.OnClientEvent:Connect(function(msg)
		if msg == "runEnd" then
			inv = nil
			invKey = nil
			close()
			hud.Visible = false
		end
	end)
end

return ShipUI
