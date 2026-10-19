-- The lobby menu, laid out like the design page's lobby mockup:
--   left:  "PARTY n/6": one row per pirate (portrait, name, race · class, red role chip, READY / NOT READY),
--          empty slots say "+ INVITE A FRIEND"; under it the Bounty Board
--   right: "YOUR PIRATE": your figure, then RACE / CLASS / HAKI / ROLE rows with REROLL / CHANGE / PICK buttons,
--          FORCE READY (Captain) and the big READY button
-- No walking here: the camera shows your ship while you set up.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local CrewDefs = require(Shared.CrewDefs)
local ClassDefs = require(Shared.ClassDefs)
local Config = require(Shared.Config)
local Kit = require(script.Parent.Kit)
local Style = Kit.Style
local new = Kit.new

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Lobby")

local LobbyUI = {}

local gui = Kit.screen("Lobby", 30, player:WaitForChild("PlayerGui"))
Kit.autoScale(gui, 1200, 720)
gui.Enabled = false
local data = nil
local refs: { [string]: any } = {}
local chooser = nil
local camConn = nil

local RACE_SKIN = {
	Human = Color3.fromRGB(246, 201, 69), Buccaneer = Color3.fromRGB(200, 140, 95), Fishman = Color3.fromRGB(95, 179, 217),
	Merfolk = Color3.fromRGB(120, 200, 200), Dwarf = Color3.fromRGB(240, 180, 150), Skypiean = Color3.fromRGB(250, 225, 190),
	Giant = Color3.fromRGB(201, 154, 107), ThreeEye = Color3.fromRGB(210, 190, 230), Cyborg = Color3.fromRGB(160, 170, 185),
	Lunarian = Color3.fromRGB(245, 245, 250),
}

local function setCamera(on)
	local cam = workspace.CurrentCamera
	if on then
		cam.CameraType = Enum.CameraType.Scriptable
		if camConn then
			camConn:Disconnect()
		end
		local t0 = os.clock()
		camConn = RunService.RenderStepped:Connect(function()
			-- a (re)spawn can swap the camera or set it back to Custom: take it back every frame
			cam = workspace.CurrentCamera
			if not cam then
				return -- the new camera isn't there yet
			end
			if cam.CameraType ~= Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Scriptable
			end
			local t = os.clock() - t0
			-- the ship map can set the shot with a part named LobbyCamera (front face = where it looks);
			-- otherwise slowly swing around the ship
			local ship = workspace:FindFirstChild("Ship")
			local marker = ship and ship:FindFirstChild("LobbyCamera", true)
			if marker and marker:IsA("BasePart") then
				cam.CFrame = marker.CFrame * CFrame.new(math.sin(t * 0.2) * 1.5, math.sin(t * 0.13) * 0.6, 0)
				return
			end
			local center = if ship and ship:IsA("Model") then ship:GetPivot().Position else Vector3.new(0, 10, 0)
			local spot = ship and ship:FindFirstChild("DeckSpot1", true)
			if spot and spot:IsA("BasePart") then
				center = spot.Position
			end
			local a = math.rad(35) + math.sin(t * 0.08) * 0.25
			cam.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(a) * 85, 24, math.sin(a) * 85), center + Vector3.new(0, 4, 0))
		end)
	else
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
		cam.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
end

local function closeChooser()
	if chooser then
		chooser:Destroy()
		chooser = nil
	end
end

-- list chooser for class / role
local function openChooser(kind)
	closeChooser()
	local options = {}
	if kind == "class" then
		for _, id in ClassDefs.Order do
			local c = ClassDefs.Classes[id]
			table.insert(options, { id = id, name = c.name, desc = c.role .. ". " .. c.hp .. " HP, speed " .. c.speed .. ". Moves: " .. ClassDefs.Moves[c.basic].label .. ", " .. ClassDefs.Moves[c.signature].label .. " + Tier 1 tree.", ok = true })
		end
		for _, name in { "Marksman", "Brawler", "Beast Tamer", "Weather Mage", "Bard" } do
			table.insert(options, { id = name, name = name, desc = "Coming soon.", ok = false })
		end
	else
		local takenBy = {}
		for _, c in data.crew do
			if c.role and c.userId ~= player.UserId then
				takenBy[c.role] = c.name
			end
		end
		for _, r in CrewDefs.Roles do
			table.insert(options, { id = r.id, name = r.name, desc = r.desc .. (if takenBy[r.id] then "  (TAKEN by " .. takenBy[r.id] .. ")" else ""), ok = true, taken = takenBy[r.id] ~= nil })
		end
	end
	chooser = Kit.panel({ Name = "Chooser", Size = UDim2.fromOffset(470, 70 + #options * 58), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 40, Parent = gui, Rotation = 0.6 })
	Kit.tab(chooser, if kind == "class" then "PICK A CLASS" else "PICK A ROLE", 220)
	Kit.button({ Text = "X", TextSize = 22, Size = UDim2.fromOffset(40, 36), Position = UDim2.new(1, -30, 0, -20), ZIndex = 44, Color = Style.Panel2, Parent = chooser, OnClick = closeChooser })
	for i, o in options do
		local row = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if o.ok then Style.Panel2 else Style.Black, BorderSizePixel = 0, Size = UDim2.new(1, -30, 0, 50), Position = UDim2.fromOffset(15, 20 + (i - 1) * 58), ZIndex = 41, Parent = chooser })
		Kit.stroke(row, if o.taken then Style.Red else (if o.ok then Style.Cream else Style.Dim), 2)
		Kit.label({ Text = string.upper(o.name), Font = Style.Display, TextSize = 21, Color = if o.ok then Style.Cream else Style.Muted, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 2), ZIndex = 42, Parent = row })
		Kit.label({ Text = o.desc, Font = Style.BodyLight, TextSize = 11, Color = Style.Muted, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 23), ZIndex = 42, Parent = row })
		row.Activated:Connect(function()
			if o.ok then
				remote:FireServer(kind, o.id)
				closeChooser()
			end
		end)
	end
end

local function build()
	gui:ClearAllChildren()
	Kit.autoScale(gui, 1200, 720)
	refs = {}
	-- a red slash across the screen, like the page's hero
	new("Frame", { BackgroundColor3 = Style.Red, BackgroundTransparency = 0.82, BorderSizePixel = 0, Size = UDim2.new(1.4, 0, 0, 160), Position = UDim2.fromScale(-0.2, 0.62), Rotation = -12, ZIndex = 1, Parent = gui })
	Kit.label({ Text = "AVERAGE ONE PIECE CAMPAIGN", Font = Style.Display, TextSize = 46, Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 18), ZIndex = 3, Parent = gui, Outline = 3 })

	-- PARTY panel
	local partyPanel = Kit.panel({ Name = "Party", Size = UDim2.fromOffset(330, 470), Position = UDim2.fromOffset(40, 120), ZIndex = 4, Parent = gui, Rotation = -0.5 })
	refs.partyTab = Kit.tab(partyPanel, "PARTY 1/6", 200)
	refs.partyList = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 6 * 54), Position = UDim2.fromOffset(12, 16), ZIndex = 5, Parent = partyPanel })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = refs.partyList })
	Kit.label({ Text = "BOUNTY BOARD", Font = Style.Display, TextSize = 20, Color = Style.Red2, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 350), ZIndex = 5, Parent = partyPanel })
	refs.board = Kit.label({ Text = "", Font = Style.BodyLight, TextSize = 13, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -24, 0, 90), Position = UDim2.fromOffset(12, 374), ZIndex = 5, Parent = partyPanel })

	-- YOUR PIRATE panel
	local me = Kit.panel({ Name = "YourPirate", Size = UDim2.fromOffset(560, 470), Position = UDim2.new(1, -40, 0, 120), AnchorPoint = Vector2.new(1, 0), ZIndex = 4, Parent = gui, Rotation = 0.4 })
	Kit.tab(me, "YOUR PIRATE", 220)
	-- figure (block pirate in the race's skin color, straw-hat-ish cap)
	local fig = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 260), Position = UDim2.fromOffset(16, 24), ZIndex = 5, Parent = me })
	for row = 0, 7 do
		for col = 0, 6 do
			local d = new("Frame", { BackgroundColor3 = Style.Red, BackgroundTransparency = 0.45 + (row + col) / 30, BorderSizePixel = 0, Size = UDim2.fromOffset(4, 4), Position = UDim2.fromOffset(20 + col * 16, 30 + row * 16), ZIndex = 5, Parent = fig })
			new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = d })
		end
	end
	refs.head = new("Frame", { BackgroundColor3 = Style.Gold, BorderSizePixel = 0, Size = UDim2.fromOffset(54, 46), Position = UDim2.fromOffset(48, 40), ZIndex = 7, Parent = fig })
	new("Frame", { BackgroundColor3 = Color3.fromRGB(233, 196, 106), BorderSizePixel = 0, Size = UDim2.fromOffset(84, 10), Position = UDim2.fromOffset(33, 32), ZIndex = 8, Parent = fig })
	new("Frame", { BackgroundColor3 = Color3.fromRGB(207, 34, 56), BorderSizePixel = 0, Size = UDim2.fromOffset(54, 6), Position = UDim2.fromOffset(48, 28), ZIndex = 8, Parent = fig })
	refs.body = new("Frame", { BackgroundColor3 = Style.Red, BorderSizePixel = 0, Size = UDim2.fromOffset(66, 70), Position = UDim2.fromOffset(42, 86), ZIndex = 7, Parent = fig })
	refs.armL = new("Frame", { BackgroundColor3 = Style.Gold, BorderSizePixel = 0, Size = UDim2.fromOffset(20, 64), Position = UDim2.fromOffset(20, 86), ZIndex = 7, Parent = fig })
	refs.armR = new("Frame", { BackgroundColor3 = Style.Gold, BorderSizePixel = 0, Size = UDim2.fromOffset(20, 64), Position = UDim2.fromOffset(110, 86), ZIndex = 7, Parent = fig })
	new("Frame", { BackgroundColor3 = Color3.fromRGB(47, 79, 143), BorderSizePixel = 0, Size = UDim2.fromOffset(30, 70), Position = UDim2.fromOffset(42, 156), ZIndex = 7, Parent = fig })
	new("Frame", { BackgroundColor3 = Color3.fromRGB(47, 79, 143), BorderSizePixel = 0, Size = UDim2.fromOffset(30, 70), Position = UDim2.fromOffset(78, 156), ZIndex = 7, Parent = fig })
	Kit.label({ Text = string.upper(player.DisplayName), Font = Style.Display, TextSize = 24, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 232), ZIndex = 7, Parent = fig })

	local function row(i, key, glyph, button, onClick)
		local y = 26 + (i - 1) * 74
		Kit.tile({ Glyph = glyph, Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(186, y), ZIndex = 6, Parent = me })
		Kit.label({ Text = key, Font = Style.Body, TextSize = 11, Color = Style.Red2, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(200, 14), Position = UDim2.fromOffset(246, y - 2), ZIndex = 6, Parent = me })
		local val = Kit.label({ Text = "", Font = Style.Display, TextSize = 24, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(200, 26), Position = UDim2.fromOffset(246, y + 11), ZIndex = 6, Parent = me })
		local desc = Kit.label({ Text = "", Font = Style.BodyLight, TextSize = 11, Color = Style.Muted, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.fromOffset(196, 30), Position = UDim2.fromOffset(246, y + 37), ZIndex = 6, Parent = me })
		local b, bl = Kit.button({ Text = button, TextSize = 17, Size = UDim2.fromOffset(98, 32), Position = UDim2.fromOffset(448, y + 6), ZIndex = 7, Parent = me, OnClick = onClick })
		local sub = Kit.label({ Text = "", Font = Style.Body, TextSize = 10, Color = Style.Muted, Size = UDim2.fromOffset(98, 14), Position = UDim2.fromOffset(448, y + 42), ZIndex = 7, Parent = me })
		return { val = val, desc = desc, btn = b, btnLabel = bl, sub = sub }
	end
	refs.race = row(1, "RACE", "★", "REROLL", function()
		remote:FireServer("reroll", "race")
	end)
	refs.class = row(2, "CLASS", "†", "CHANGE", function()
		openChooser("class")
	end)
	refs.haki = row(3, "HAKI", "◉", "REROLL", function()
		remote:FireServer("reroll", "haki")
	end)
	refs.role = row(4, "ROLE", "♛", "PICK", function()
		openChooser("role")
	end)

	refs.force = Kit.button({ Text = "♛ FORCE READY", TextSize = 18, Size = UDim2.fromOffset(170, 40), Position = UDim2.fromOffset(16, 410), ZIndex = 7, Color = Style.Black, Parent = me, OnClick = function()
		remote:FireServer("force")
	end })
	local readyBtn, readyLabel = Kit.button({ Text = "READY", TextSize = 28, Size = UDim2.fromOffset(330, 50), Position = UDim2.fromOffset(212, 404), ZIndex = 7, Parent = me, OnClick = function()
		if data and data.runActive and not data.inRun then
			remote:FireServer("join")
		else
			remote:FireServer("ready")
		end
	end })
	refs.ready, refs.readyLabel = readyBtn, readyLabel
	refs.warn = Kit.label({ Text = "", Font = Style.Body, TextSize = 13, Color = Style.Red2, Size = UDim2.fromOffset(330, 16), Position = UDim2.fromOffset(212, 384), ZIndex = 7, Parent = me, Outline = 1.5 })
end

local function partyRow(c, i)
	local f = new("Frame", { BackgroundColor3 = Style.Panel2, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, ZIndex = 6, Parent = refs.partyList })
	local portrait = new("Frame", { BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 4), ZIndex = 7, Parent = f })
	Kit.stroke(portrait, Style.Cream, 2)
	new("Frame", { BackgroundColor3 = RACE_SKIN[c.race] or Style.Gold, BorderSizePixel = 0, Size = UDim2.fromOffset(18, 15), Position = UDim2.fromOffset(11, 5), ZIndex = 8, Parent = portrait })
	local cls = ClassDefs.Classes[c.classId]
	new("Frame", { BackgroundColor3 = cls and cls.color or Style.Dim, BorderSizePixel = 0, Size = UDim2.fromOffset(28, 15), Position = UDim2.fromOffset(6, 21), ZIndex = 8, Parent = portrait })
	Kit.label({ Text = if c.userId == player.UserId then "You" else c.name, Font = Style.Body, TextSize = 14, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(150, 18), Position = UDim2.fromOffset(52, 5), ZIndex = 7, Parent = f })
	local race = CrewDefs.find(CrewDefs.Races, c.race)
	Kit.label({ Text = (race and race.name or "?") .. " · " .. (cls and cls.name or c.classId), Font = Style.BodyLight, TextSize = 11, Color = Style.Muted, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(52, 25), ZIndex = 7, Parent = f })
	local dup = c.role and table.find(data.dups, c.role)
	local chip = new("Frame", { BackgroundColor3 = if c.role then Style.Red else Style.Dim, BorderSizePixel = 0, Size = UDim2.fromOffset(92, 18), Position = UDim2.new(1, -98, 0, 5), ZIndex = 7, Parent = f })
	if dup then
		Kit.stroke(chip, Style.Cyan, 2)
	end
	Kit.label({ Text = if c.role then string.upper(c.role) else "NO ROLE", Font = Style.Body, TextSize = 10, ZIndex = 8, Parent = chip })
	local status = if c.inRun then "SAILING" elseif c.ready then "READY ✓" else "NOT READY"
	Kit.label({ Text = status, Font = Style.Body, TextSize = 11, Color = if c.ready or c.inRun then Style.Cyan else Style.Muted, Size = UDim2.fromOffset(92, 16), Position = UDim2.new(1, -98, 0, 27), ZIndex = 7, Parent = f })
end

function LobbyUI.refresh(d)
	data = d
	if not gui.Enabled or not refs.partyList then
		return
	end
	refs.partyTab:FindFirstChildWhichIsA("TextLabel").Text = "PARTY " .. #d.crew .. "/" .. Config.PartyMax
	for _, ch in refs.partyList:GetChildren() do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	for i, c in d.crew do
		partyRow(c, i)
	end
	for i = #d.crew + 1, Config.PartyMax do
		local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, ZIndex = 6, Parent = refs.partyList })
		local st = Kit.stroke(f, Style.Cream, 1.5)
		st.Transparency = 0.55
		Kit.label({ Text = "+ INVITE A FRIEND", Font = Style.Body, TextSize = 12, Color = Style.Muted, ZIndex = 7, Parent = f })
	end
	local lines = {}
	for i, b in d.board do
		if i > 5 then
			break
		end
		table.insert(lines, i .. ". " .. b.name .. " — " .. Kit.commas(b.bounty) .. " berries")
	end
	refs.board.Text = if #lines > 0 then table.concat(lines, "\n") else "No bounties yet. Go make a name for yourself!"

	local you = d.you
	local race = CrewDefs.find(CrewDefs.Races, you.race)
	refs.race.val.Text = string.upper(race.name)
	refs.race.desc.Text = race.desc .. " (" .. race.chance .. "%)"
	refs.race.sub.Text = if d.freeRerolls then "FREE IN STUDIO" else "ROBUX"
	Kit.setDisabled(refs.race.btn, not d.rerollRace or d.inRun)
	local cls = ClassDefs.Classes[you.classId]
	refs.class.val.Text = string.upper(cls.name)
	refs.class.desc.Text = cls.role .. " · " .. cls.weapon .. "s"
	Kit.setDisabled(refs.class.btn, d.inRun)
	local haki = CrewDefs.find(CrewDefs.Haki, you.haki)
	refs.haki.val.Text = string.upper(haki.name)
	refs.haki.desc.Text = haki.desc
	refs.haki.sub.Text = refs.race.sub.Text
	Kit.setDisabled(refs.haki.btn, not d.rerollHaki or d.inRun)
	local role = you.role and CrewDefs.find(CrewDefs.Roles, you.role)
	refs.role.val.Text = if role then string.upper(role.name) else "NONE YET"
	refs.role.desc.Text = if role then role.desc else "Pick a crew role. One of each per crew."
	Kit.setDisabled(refs.role.btn, d.inRun)
	refs.head.BackgroundColor3 = RACE_SKIN[you.race] or Style.Gold
	refs.armL.BackgroundColor3 = refs.head.BackgroundColor3
	refs.armR.BackgroundColor3 = refs.head.BackgroundColor3
	refs.body.BackgroundColor3 = cls.color

	refs.force.Visible = d.captainId == player.UserId and not d.runActive
	local readyCount = 0
	for _, c in d.crew do
		if c.ready then
			readyCount += 1
		end
	end
	if d.runActive and not d.inRun then
		refs.readyLabel.Text = "JOIN THE CREW"
		Kit.setDisabled(refs.ready, #d.crew > Config.PartyMax)
		refs.warn.Text = "Your crew is already sailing. Hop on board!"
	else
		refs.readyLabel.Text = (if you.ready then "READY ✓ · " else "READY · ") .. readyCount .. "/" .. #d.crew
		local blocked = #d.dups > 0 or #d.missing > 0
		Kit.setDisabled(refs.ready, blocked and not you.ready)
		if #d.dups > 0 then
			refs.warn.Text = "Two pirates share a role: " .. table.concat(d.dups, ", ")
		elseif #d.missing > 0 then
			refs.warn.Text = "Pick a role first: " .. table.concat(d.missing, ", ")
		else
			refs.warn.Text = ""
		end
	end
end

function LobbyUI.show(on)
	gui.Enabled = on
	setCamera(on)
	closeChooser()
	if on then
		build()
		if data then
			LobbyUI.refresh(data)
		end
	end
end

function LobbyUI.active()
	return gui.Enabled
end

function LobbyUI.init()
	remote.OnClientEvent:Connect(function(msg, d)
		if msg == "lobby" then
			LobbyUI.refresh(d)
		elseif msg == "open" then
			LobbyUI.show(true)
		elseif msg == "close" then
			LobbyUI.show(false)
		elseif msg == "rolled" then
			Kit.stamp(gui, (if d.rare then "RARE! " else "") .. string.upper(d.name), if d.rare then Style.Red else Style.Panel2, UDim2.fromScale(0.5, 0.4))
		end
	end)
	remote:FireServer("hello")
end

return LobbyUI
