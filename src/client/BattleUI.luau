-- The fight screen, laid out like the design page's fight mockup:
--   top:    black TURN ORDER strip (crew squares cream, enemies red, the active one thick) + a "ROUND N" tab
--           under it, then each enemy's portrait circle, name (BOSS tag), thin red health bar and big red number
--   right:  square command tiles with a red offset shadow: STRIKE / SKILL / HEAVY / ROLE (+ glowing CREW RUSH)
--   bottom: one card per crewmate: colored name strip, portrait, big health number, class, red HP bar, cyan stamina
--   camera: For The King-style 3/4 view from behind the crew
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage.Shared
local BattleDefs = require(Shared.BattleDefs)
local ClassDefs = require(Shared.ClassDefs)
local ActionCommandDefs = require(Shared.ActionCommandDefs)
local Kit = require(script.Parent.Kit)
local Qte = require(script.Parent.Qte)
local DodgeBox = require(script.Parent.DodgeBox)
local Style = Kit.Style
local new = Kit.new

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Battle")

local BattleUI = {}

local gui -- ScreenGui while a fight is on
local state -- last snapshot
local ui: { [string]: any } = {} -- named widgets
local choosing = nil -- { token, moves, deadline }
local camConn
local _myUid

local MENU_INFO = {
	Rush = { label = "CREW RUSH", glyph = "!!" },
	Attack = { label = "STRIKE", glyph = "⚔" },
	Skill = { label = "SKILL", glyph = "★" },
	Heavy = { label = "HEAVY", glyph = "✸" },
	Role = { label = "ROLE", glyph = "♛" },
}

local function lookColor(look, key)
	local l = BattleDefs.Looks[look]
	return l and l[key] or Style.Cream
end

local function findCrew(uid)
	for _, c in state and state.crew or {} do
		if c.uid == uid then
			return c
		end
	end
	return nil
end

local function findEnemy(uid)
	for _, e in state and state.enemies or {} do
		if e.uid == uid then
			return e
		end
	end
	return nil
end

local function modelOf(uid)
	if uid:sub(1, 1) == "e" then
		local arena = workspace:FindFirstChild("Arena")
		return arena and arena:FindFirstChild("Enemies") and arena.Enemies:FindFirstChild(uid)
	end
	local c = findCrew(uid)
	if c then
		local p = Players:GetPlayerByUserId(c.userId)
		return p and p.Character
	end
	return nil
end

-- A floating number / word over a 3D unit.
local function popup(uid, text, color, big)
	local m = modelOf(uid)
	local adornee = m and (m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart"))
	if not adornee then
		return
	end
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(200, 60), StudsOffset = Vector3.new(math.random(-10, 10) / 10, 4.5, 0), AlwaysOnTop = true, Adornee = adornee, Parent = gui })
	local l = Kit.label({ Text = text, Font = Style.Display, TextSize = if big then 46 else 34, Color = color or Style.Cream, Size = UDim2.fromScale(1, 1), Parent = bb, Outline = 3 })
	TweenService:Create(bb, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = bb.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	task.delay(0.6, function()
		TweenService:Create(l, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
	end)
	task.delay(1, function()
		bb:Destroy()
	end)
end

local function logLine(text)
	if not ui.log then
		return
	end
	ui.log.Text = text
	ui.log.TextTransparency = 0
	ui.logTween = TweenService:Create(ui.log, TweenInfo.new(0.4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 4), { TextTransparency = 0.6 })
	ui.logTween:Play()
end

-- ===== build the screen =====

local function buildTop()
	local strip = new("Frame", { Name = "TopStrip", BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44), ZIndex = 5, Parent = gui })
	new("Frame", { BackgroundColor3 = Style.Cream, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, 0), ZIndex = 6, Parent = strip })
	Kit.label({ Text = "TURN ORDER", Font = Style.Body, TextSize = 14, Color = Style.Red2, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(120, 44), Position = UDim2.fromOffset(16, 0), ZIndex = 6, Parent = strip })
	ui.order = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -140, 0, 34), Position = UDim2.fromOffset(130, 5), ZIndex = 6, Parent = strip })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = ui.order })
	-- the ROUND tab hanging under the strip
	local tab = new("Frame", { Name = "RoundTab", BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = UDim2.fromOffset(150, 30), Position = UDim2.new(0.5, 0, 0, 44), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 6, Parent = gui })
	Kit.stroke(tab, Style.Cream, 2.5)
	ui.round = Kit.label({ Text = "ROUND 1", Font = Style.Display, TextSize = 22, ZIndex = 7, Parent = tab })
	-- enemy plates
	ui.enemies = new("Frame", { Name = "EnemyPlates", BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 62), Position = UDim2.fromOffset(20, 80), ZIndex = 5, Parent = gui })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ui.enemies })
	ui.plates = {}
end

local function buildBottom()
	ui.crew = new("Frame", { Name = "CrewCards", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 104), Position = UDim2.new(0, 12, 1, -114), ZIndex = 5, Parent = gui })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ui.crew })
	ui.cards = {}
	-- log line above the cards
	ui.log = Kit.label({ Text = "", Font = Style.Body, TextSize = 18, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -146), ZIndex = 6, Parent = gui, Outline = 2 })
	-- whose turn / timer banner
	ui.banner = Kit.label({ Text = "", Font = Style.Display, TextSize = 30, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 148), ZIndex = 6, Parent = gui, Outline = 2 })
end

local function buildCommands()
	ui.cmd = new("Frame", { Name = "Commands", BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 330), Position = UDim2.new(1, -24, 0.5, -10), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 8, Visible = false, Parent = gui })
	ui.cmdButtons = {}
	ui.list = Kit.panel({ Name = "MoveList", Size = UDim2.fromOffset(330, 300), Position = UDim2.new(1, -290, 0.5, -10), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 9, Parent = gui, Tilt = 1 })
	ui.list.Visible = false
	ui.listTab = Kit.tab(ui.list, "STRIKE", 170)
	ui.listItems = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, -22), Position = UDim2.fromOffset(10, 14), ZIndex = 10, Parent = ui.list })
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ui.listItems })
	-- target / part picker hint
	ui.pick = Kit.label({ Text = "", Font = Style.Display, TextSize = 26, Color = Style.Cyan, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 184), ZIndex = 9, Parent = gui, Outline = 2 })
	ui.parts = new("Frame", { Name = "Parts", BackgroundTransparency = 1, Size = UDim2.new(0, 640, 0, 92), Position = UDim2.new(0.5, 0, 0, 222), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 9, Visible = false, Parent = gui })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), Parent = ui.parts })
	ui.back = Kit.button({ Text = "BACK", Size = UDim2.fromOffset(110, 38), Position = UDim2.new(1, -24, 0.5, 190), AnchorPoint = Vector2.new(1, 0), ZIndex = 9, Color = Style.Panel2, Parent = gui, OnClick = function()
		BattleUI.cancelPick()
	end })
	ui.back.Visible = false
end

local function buildScreen()
	if gui then
		gui:Destroy()
	end
	gui = Kit.screen("BattleScreen", 10, player:WaitForChild("PlayerGui"))
	Kit.autoScale(gui, 1280, 720)
	ui = {} :: { [string]: any }
	buildTop()
	buildBottom()
	buildCommands()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
end

-- ===== refresh from a snapshot =====

local function orderSquare(entry, i)
	local isEnemy = entry.side == "enemy"
	local active = state.active == entry.uid
	local sq = new("Frame", { BackgroundColor3 = Style.Panel, BorderSizePixel = 0, Size = UDim2.fromOffset(30, 30), LayoutOrder = i, ZIndex = 7, BackgroundTransparency = if entry.acted then 0.5 else 0 })
	Kit.stroke(sq, if active then Style.Cream elseif isEnemy then Style.Red else Style.Cream, if active then 3.5 else 1.5)
	local head, body
	if isEnemy then
		local e = findEnemy(entry.uid)
		head = lookColor(e and e.look, "skin")
		body = lookColor(e and e.look, "shirt")
	else
		local c = findCrew(entry.uid)
		head = Color3.fromRGB(246, 201, 69)
		body = c and c.color or Style.Cream
	end
	new("Frame", { BackgroundColor3 = head, BorderSizePixel = 0, Size = UDim2.fromOffset(14, 10), Position = UDim2.fromOffset(8, 4), ZIndex = 8, Parent = sq })
	new("Frame", { BackgroundColor3 = body, BorderSizePixel = 0, Size = UDim2.fromOffset(20, 11), Position = UDim2.fromOffset(5, 15), ZIndex = 8, Parent = sq })
	if active then
		sq.Size = UDim2.fromOffset(34, 34)
	end
	return sq
end

local function enemyPlate(e)
	local boss = e.rank == "boss"
	local f = new("TextButton", { Name = e.uid, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(boss and 250 or 200, 60), ZIndex = 6, LayoutOrder = e.slot })
	local portrait = new("Frame", { BackgroundColor3 = Style.Panel, Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(0, 4), ZIndex = 7, Parent = f })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = portrait })
	Kit.stroke(portrait, if boss then Style.Red else Style.Cream, 2.5)
	new("Frame", { BackgroundColor3 = lookColor(e.look, "skin"), BorderSizePixel = 0, Size = UDim2.fromOffset(16, 14), Position = UDim2.fromOffset(9, 10), ZIndex = 8, Parent = portrait })
	local nameText = string.upper(e.name) .. (if boss then " · BOSS" elseif e.rank == "elite" then " · ELITE" else "")
	Kit.label({ Name = "Name", Text = nameText, Font = Style.Display, TextSize = 21, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -44, 0, 22), Position = UDim2.fromOffset(44, 0), ZIndex = 7, Parent = f, Outline = 2 })
	local _bar, setBar = Kit.bar({ Size = UDim2.new(1, -100, 0, 10), Position = UDim2.fromOffset(44, 25), Color = Style.Red, ZIndex = 7, Parent = f })
	local num = Kit.label({ Name = "Hp", Text = "", Font = Style.Display, TextSize = 28, Color = Style.Red2, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(60, 28), Position = UDim2.new(1, -52, 0, 14), ZIndex = 7, Parent = f, Outline = 2 })
	local status = Kit.label({ Name = "Status", Text = "", Font = Style.Body, TextSize = 12, Color = Style.Cyan, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(44, 40), ZIndex = 7, Parent = f, Outline = 1.5 })
	f.Activated:Connect(function()
		BattleUI.pickTarget(e.uid)
	end)
	return { frame = f, setBar = setBar, num = num, status = status, portraitStroke = portrait:FindFirstChildOfClass("UIStroke") }
end

local function crewCard(c)
	local me = c.userId == player.UserId
	local f = new("Frame", { Name = c.uid, BackgroundColor3 = Color3.fromRGB(13, 13, 13), BorderSizePixel = 0, Size = UDim2.fromOffset(160, 96), ZIndex = 6, LayoutOrder = c.slot })
	local st = Kit.stroke(f, Style.Cream, 2)
	new("Frame", { Name = "Strip", BackgroundColor3 = c.color or Style.Cream, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 20), ZIndex = 7, Parent = f })
	Kit.label({ Text = string.upper(if me then "YOU" else c.name), Font = Style.Body, TextSize = 13, Color = Style.Black, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -10, 0, 20), Position = UDim2.fromOffset(6, 0), ZIndex = 8, Parent = f })
	if c.role then
		Kit.label({ Text = string.upper(c.role), Font = Style.Body, TextSize = 10, Color = Style.Black, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, -8, 0, 20), ZIndex = 8, Parent = f })
	end
	local portrait = new("Frame", { BackgroundColor3 = Style.Panel, BorderSizePixel = 0, Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(6, 26), ZIndex = 7, Parent = f })
	Kit.stroke(portrait, Style.Cream, 1.5)
	new("Frame", { BackgroundColor3 = Color3.fromRGB(246, 201, 69), BorderSizePixel = 0, Size = UDim2.fromOffset(16, 12), Position = UDim2.fromOffset(9, 4), ZIndex = 8, Parent = portrait })
	new("Frame", { BackgroundColor3 = c.color or Style.Cream, BorderSizePixel = 0, Size = UDim2.fromOffset(22, 13), Position = UDim2.fromOffset(6, 17), ZIndex = 8, Parent = portrait })
	local num = Kit.label({ Text = "", Font = Style.Display, TextSize = 34, XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(70, 34), Position = UDim2.fromOffset(46, 26), ZIndex = 7, Parent = f })
	Kit.label({ Text = string.upper(c.classId), Font = Style.Body, TextSize = 10, Color = Style.Muted, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(60, 14), Position = UDim2.new(1, -66, 0, 28), ZIndex = 7, Parent = f })
	local stam = Kit.label({ Text = "", Font = Style.Body, TextSize = 11, Color = Style.Cyan, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(60, 14), Position = UDim2.new(1, -66, 0, 44), ZIndex = 7, Parent = f })
	local _, setHp = Kit.bar({ Size = UDim2.new(1, -12, 0, 8), Position = UDim2.fromOffset(6, 66), Color = Style.Red, ZIndex = 7, Parent = f })
	local _, setSt = Kit.bar({ Size = UDim2.new(1, -12, 0, 6), Position = UDim2.fromOffset(6, 78), Color = Style.Cyan, ZIndex = 7, Parent = f, Thickness = 1 })
	local status = Kit.label({ Text = "", Font = Style.Body, TextSize = 10, Color = Style.Cyan, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, -16), ZIndex = 7, Parent = f, Outline = 1.5 })
	return { frame = f, stroke = st, num = num, setHp = setHp, setSt = setSt, stam = stam, status = status }
end

function BattleUI.refresh(snap)
	state = snap
	if not gui then
		return
	end
	ui.round.Text = "ROUND " .. (snap.round or 1)
	-- turn order
	for _, ch in ui.order:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	for i, entry in snap.order or {} do
		orderSquare(entry, i).Parent = ui.order
	end
	-- enemies
	for _, e in snap.enemies do
		local p = ui.plates[e.uid]
		if not p then
			p = enemyPlate(e)
			p.frame.Parent = ui.enemies
			ui.plates[e.uid] = p
		end
		p.setBar(e.hp / e.maxHp)
		p.num.Text = tostring(math.max(0, e.hp))
		p.status.Text = table.concat(e.statuses or {}, " · ")
		p.frame.Visible = not e.dead
		if p.portraitStroke then
			p.portraitStroke.Color = if snap.active == e.uid then Style.Cyan elseif e.rank == "boss" then Style.Red else Style.Cream
		end
	end
	-- crew
	for _, c in snap.crew do
		if c.userId == player.UserId then
			_myUid = c.uid
		end
		local card = ui.cards[c.uid]
		if not card then
			card = crewCard(c)
			card.frame.Parent = ui.crew
			ui.cards[c.uid] = card
		end
		card.num.Text = tostring(c.hp)
		card.setHp(c.hp / c.maxHp)
		card.setSt(c.stamina / c.maxStamina)
		card.stam.Text = "ST " .. c.stamina .. "/" .. c.maxStamina
		card.status.Text = table.concat(c.statuses or {}, " · ")
		local active = snap.active == c.uid
		card.stroke.Color = if active then Style.Red else Style.Cream
		card.stroke.Thickness = if active then 4 else 2
		card.frame.BackgroundColor3 = if c.ko or c.gone then Color3.fromRGB(40, 40, 40) else Color3.fromRGB(13, 13, 13)
		if c.ko then
			card.status.Text = "KNOCKED OUT"
		end
	end
end

-- ===== choosing a move =====

local pick = nil -- { move, targetUid }

local function clearList()
	for _, ch in ui.listItems:GetChildren() do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
end

local function sendAction(moveId, targetUid, part)
	if not choosing then
		return
	end
	remote:FireServer("action", { token = choosing.token, moveId = moveId, targetUid = targetUid, part = part })
	choosing = nil
	pick = nil
	ui.cmd.Visible = false
	ui.list.Visible = false
	ui.parts.Visible = false
	ui.back.Visible = false
	ui.pick.Text = ""
	for _, p in ui.plates do
		p.frame.BackgroundTransparency = 1
	end
	local hl = workspace:FindFirstChild("TargetHighlight")
	if hl then
		hl:Destroy()
	end
end

local function highlight(uid)
	local old = workspace:FindFirstChild("TargetHighlight")
	if old then
		old:Destroy()
	end
	local m = modelOf(uid)
	if m then
		new("Highlight", { Name = "TargetHighlight", Adornee = m, FillColor = Style.Red, FillTransparency = 0.6, OutlineColor = Style.Cream, Parent = workspace })
	end
end

local function showParts(enemy)
	for _, ch in ui.parts:GetChildren() do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	ui.parts.Visible = true
	ui.pick.Text = "AIM AT A WEAK POINT"
	for i, pid in enemy.parts do
		local part = BattleDefs.Parts[pid]
		local b = Kit.button({ Text = part.label, Size = UDim2.fromOffset(110, 44), ZIndex = 10, Color = if pid == "Core" then Style.Red else Style.Panel2, Parent = ui.parts, OnClick = function()
			sendAction(pick.move.id, enemy.uid, pid)
		end })
		b.LayoutOrder = i
		Kit.label({ Text = part.desc .. (if pid == "Core" and enemy.weak then " Weak to " .. string.upper(enemy.weak) .. "." else ""), Font = Style.BodyLight, TextSize = 11, Wrap = true, Size = UDim2.new(1, 10, 0, 40), Position = UDim2.new(0, -5, 1, 6), ZIndex = 10, Parent = b, Outline = 1.5 })
	end
end

function BattleUI.pickTarget(uid)
	if not pick or not choosing then
		return
	end
	local e = findEnemy(uid)
	if not e or e.dead then
		return
	end
	pick.targetUid = uid
	highlight(uid)
	if #e.parts > 1 then
		showParts(e)
	else
		sendAction(pick.move.id, uid, "Core")
	end
end

function BattleUI.cancelPick()
	pick = nil
	ui.parts.Visible = false
	ui.back.Visible = false
	ui.pick.Text = ""
	ui.cmd.Visible = choosing ~= nil
	local hl = workspace:FindFirstChild("TargetHighlight")
	if hl then
		hl:Destroy()
	end
end

local function chooseMove(m)
	if not m.usable then
		return
	end
	ui.list.Visible = false
	if m.target == "enemy" then
		pick = { move = m }
		ui.cmd.Visible = false
		ui.back.Visible = true
		-- weakness hint: which enemies this move knocks DOWN
		local el = ClassDefs.Moves[m.id] and ClassDefs.Moves[m.id].element
		ui.pick.Text = "PICK A TARGET" .. (if el then "  (" .. string.upper(el) .. ")" else "")
		local alive = {}
		for _, e in state.enemies do
			if not e.dead then
				table.insert(alive, e)
			end
		end
		if #alive == 1 then
			BattleUI.pickTarget(alive[1].uid)
		end
	else
		sendAction(m.id, nil, nil)
	end
end

local function openMenu(menu)
	if not choosing then
		return
	end
	clearList()
	ui.list.Visible = true
	local t = ui.listTab:FindFirstChildWhichIsA("TextLabel")
	if t then
		t.Text = MENU_INFO[menu].label
	end
	local i = 0
	for _, m in choosing.moves do
		if m.menu == menu then
			i += 1
			local row = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if m.usable then Style.Panel2 else Style.Black, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = i, ZIndex = 11, Parent = ui.listItems })
			Kit.stroke(row, if m.usable then Style.Cream else Style.Dim, 2)
			Kit.label({ Text = string.upper(m.label), Font = Style.Display, TextSize = 22, Color = if m.usable then Style.Cream else Style.Muted, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -80, 0, 24), Position = UDim2.fromOffset(8, 2), ZIndex = 12, Parent = row })
			-- cost pips (cyan)
			local pips = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(80, 14), Position = UDim2.new(1, -86, 0, 7), ZIndex = 12, Parent = row })
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 3), Parent = pips })
			if m.cost == 0 then
				Kit.label({ Text = "FREE", Font = Style.Body, TextSize = 11, Color = Style.Cyan, Size = UDim2.fromOffset(40, 14), ZIndex = 12, Parent = pips })
			end
			for _ = 1, m.cost do
				new("Frame", { BackgroundColor3 = Style.Cyan, BorderSizePixel = 0, Size = UDim2.fromOffset(9, 12), Rotation = 12, ZIndex = 12, Parent = pips })
			end
			local qte = if m.qte == "strike" then "  [STRIKE BAR]" elseif m.qte == "rings" then "  [POWER RINGS]" else ""
			Kit.label({ Text = (if m.usable then m.desc else (m.reason or "")) .. qte, Font = Style.BodyLight, TextSize = 12, Color = if m.usable then Style.Muted else Style.Red2, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -14, 0, 32), Position = UDim2.fromOffset(8, 27), ZIndex = 12, Parent = row })
			row.Activated:Connect(function()
				chooseMove(m)
			end)
		end
	end
	ui.list.Size = UDim2.fromOffset(330, math.max(90, i * 70 + 26))
end

local function showCommands(moves)
	for _, ch in ui.cmd:GetChildren() do
		ch:Destroy()
	end
	local menus = {}
	for _, m in moves do
		menus[m.menu] = true
	end
	local y = 0
	for _, menu in ClassDefs.MenuOrder do
		if menus[menu] then
			local info = MENU_INFO[menu]
			local isRush = menu == "Rush"
			local _, face, _, st = Kit.tile({ Glyph = info.glyph, Size = UDim2.fromOffset(isRush and 60 or 52, isRush and 60 or 52), Position = UDim2.new(1, -60, 0, y), ZIndex = 9, Parent = ui.cmd, StrokeColor = if isRush then Style.Red else Style.Cream })
			if isRush then
				face.BackgroundColor3 = Style.Red
				TweenService:Create(st, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 }):Play()
			end
			Kit.label({ Text = info.label, Font = Style.Body, TextSize = 16, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(150, 52), Position = UDim2.new(1, -224, 0, y), ZIndex = 9, Parent = ui.cmd, Outline = 2 })
			local hit = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(230, 56), Position = UDim2.new(1, -230, 0, y - 2), ZIndex = 12, Parent = ui.cmd })
			hit.MouseEnter:Connect(function()
				st.Color = Style.Red
			end)
			hit.MouseLeave:Connect(function()
				st.Color = if isRush then Style.Red else Style.Cream
			end)
			hit.Activated:Connect(function()
				openMenu(menu)
			end)
			y += 66
		end
	end
	ui.cmd.Visible = true
end

-- ===== camera =====

local function setCamera(camPos, camLook)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local base = CFrame.lookAt(camPos, camLook)
	if camConn then
		camConn:Disconnect()
	end
	local t0 = os.clock()
	camConn = RunService.RenderStepped:Connect(function()
		-- a slow gentle sway so the scene feels alive
		local t = os.clock() - t0
		cam.CFrame = base * CFrame.new(math.sin(t * 0.3) * 0.6, math.sin(t * 0.21) * 0.3, 0)
		cam.FieldOfView = 55
	end)
end

local function restoreCamera()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local ch = player.Character
	if ch and ch:FindFirstChildOfClass("Humanoid") then
		cam.CameraSubject = ch:FindFirstChildOfClass("Humanoid")
	end
end

-- clicking the 3D enemies picks them too
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not pick or not gui then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { arena.Enemies }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit then
		local m = hit.Instance:FindFirstAncestorOfClass("Model")
		if m and m:GetAttribute("Uid") then
			BattleUI.pickTarget(m:GetAttribute("Uid"))
		end
	end
end)

-- ===== end screen =====

local function showEnd(data)
	local panel = Kit.panel({ Name = "EndPanel", Size = UDim2.fromOffset(420, 250), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 70, Parent = gui, Rotation = -1 })
	Kit.tab(panel, if data.won then "VICTORY!" else "DEFEATED...", 200)
	local lines = {}
	if data.won then
		table.insert(lines, "+" .. data.gold .. " gold")
		local loot = {}
		for item, n in data.loot or {} do
			table.insert(loot, n .. "x " .. item)
		end
		if #loot > 0 then
			table.insert(lines, "Loot: " .. table.concat(loot, ", "))
		end
	else
		table.insert(lines, "Your crew was knocked out.")
	end
	local gain = data.bounty and data.bounty[player.UserId] or 0
	table.insert(lines, "Your bounty: +" .. Kit.commas(gain) .. " berries")
	Kit.label({ Text = table.concat(lines, "\n"), Font = Style.Body, TextSize = 20, Wrap = true, Size = UDim2.new(1, -40, 1, -50), Position = UDim2.fromOffset(20, 30), ZIndex = 72, Parent = panel })
	Kit.stamp(gui, if data.won then "VICTORY" else "DEFEAT", if data.won then Style.Red else Style.Dim, UDim2.fromScale(0.5, 0.18))
end

-- ===== messages =====

local function onMessage(msg, data, extra)
	if msg == "start" then
		buildScreen()
		BattleUI.refresh(data)
		setCamera(extra.camPos, extra.camLook)
		Kit.stamp(gui, if extra.kind == "Boss" then "BOSS FIGHT!" else "FIGHT!", Style.Red, UDim2.fromScale(0.5, 0.4))
		return
	end
	if not gui then
		return
	end
	if msg == "state" then
		BattleUI.refresh(data)
		if state.active then
			local c = findCrew(state.active)
			local e = findEnemy(state.active)
			if c then
				ui.banner.Text = if c.userId == player.UserId then "YOUR TURN!" else string.upper(c.name) .. "'S TURN"
			elseif e then
				ui.banner.Text = string.upper(e.name) .. "'S TURN"
			end
		end
	elseif msg == "round" then
		ui.round.Text = "ROUND " .. data
	elseif msg == "choose" then
		choosing = { token = data.token, moves = data.moves, deadline = os.clock() + data.seconds }
		showCommands(data.moves)
		task.spawn(function()
			local tok = data.token
			while choosing and choosing.token == tok do
				local left = math.max(0, math.ceil(choosing.deadline - os.clock()))
				ui.banner.Text = "YOUR TURN!  " .. left
				task.wait(0.25)
			end
		end)
	elseif msg == "qte" then
		local result
		if data.kind == "rings" then
			result = Qte.rings(gui)
		else
			result = Qte.strike(gui)
		end
		remote:FireServer("qte", { token = data.token, timing = result })
	elseif msg == "watchQte" then
		local c = findCrew(data.uid)
		if c and c.userId ~= player.UserId then
			ui.banner.Text = string.upper(c.name) .. " ATTACKS!"
		end
	elseif msg == "dodge" then
		ui.banner.Text = "DODGE!"
		local result = DodgeBox.run(gui, data)
		remote:FireServer("dodge", { token = data.token, hits = result.hits, grazes = result.grazes })
	elseif msg == "watchDodge" then
		local c = findCrew(data.uid)
		local p = BattleDefs.Patterns[data.pattern]
		if c and c.userId ~= player.UserId then
			ui.banner.Text = string.upper(c.name) .. " IS DODGING " .. (p and p.label or "") .. "!"
		end
	elseif msg == "fx" then
		if data.kind == "hit" then
			if data.missed then
				popup(data.dst, "MISS", Style.Muted)
			else
				popup(data.dst, "-" .. data.amount, if data.poison then Color3.fromRGB(150, 230, 90) else Style.Red2, data.amount >= 30)
			end
			if data.down then
				Kit.stamp(gui, "DOWN!", Style.Red, UDim2.fromScale(0.5, 0.32))
			end
			if data.counter then
				popup(data.src, "COUNTER!", Style.Cyan)
			end
		elseif data.kind == "hurt" then
			popup(data.dst, if data.perfect then "PERFECT!" else "-" .. data.amount, if data.perfect then Style.Cyan else Style.Red2, true)
		elseif data.kind == "grade" then
			local label = ActionCommandDefs.Labels[data.grade] or ""
			if data.grade == "crit" or data.grade == "perfect" then
				Kit.stamp(gui, label, Style.Red, UDim2.fromScale(0.5, 0.3))
			elseif label ~= "" then
				popup(data.uid, label, if data.grade == "miss" then Style.Muted else Style.Cream)
			end
		elseif data.kind == "buff" then
			popup(data.uid, data.text, Style.Cyan)
		elseif data.kind == "stamp" then
			Kit.stamp(gui, data.text, Style.Red, UDim2.fromScale(0.5, 0.35))
		end
	elseif msg == "log" then
		logLine(data)
	elseif msg == "end" then
		choosing = nil
		ui.cmd.Visible = false
		ui.list.Visible = false
		showEnd(data)
	elseif msg == "close" then
		restoreCamera()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
		end)
		gui:Destroy()
		gui = nil
		state = nil
	end
end

function BattleUI.init()
	remote.OnClientEvent:Connect(function(msg, data, extra)
		-- QTE and dodge yield; run each message in its own thread so state updates keep flowing
		task.spawn(onMessage, msg, data, extra)
	end)
end

function BattleUI.active()
	return gui ~= nil
end

return BattleUI
