-- The sea chart (design page "Sea map"): For The King 2-style hex tiles, islands as stop tiles, sea lanes between them.
-- Ready -> the chart opens for everyone -> vote by clicking a glowing stop. The Captain can Force Ready and breaks ties.
-- The Navigator sees what is at each stop. Also shows story cards (events, ports, allied crews) and the run's end.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local MapDefs = require(Shared.MapDefs)
local Kit = require(script.Parent.Kit)
local Style = Kit.Style
local new = Kit.new

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Map")

local MapUI = {}
MapUI.chart = nil -- last "chart" message
MapUI.blocked = nil -- function() -> true while another screen (a fight) is up

local gui = Kit.screen("SeaChart", 20, player:WaitForChild("PlayerGui"))
Kit.autoScale(gui, 1100, 700)
local root -- the open chart panel
local builtSeed -- the seed the hex grid was built for
local refs: { [string]: any } = {}

local R = 20
local W = math.sqrt(3) * R
local CHART_W = math.floor(18.5 * W + 20)
local CHART_H = 12 * 1.5 * R + R + 20

local function cellXY(c, r)
	return 10 + c * W + (if r % 2 == 1 then W / 2 else 0) + W / 2, 10 + r * 1.5 * R + R
end

local function hex(parent, x, y, rad, color, z)
	-- a pointy-top hexagon = 3 rectangles (width sqrt(3)*rad, height rad) rotated 0 / 60 / 120 degrees
	for i = 0, 2 do
		new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(math.sqrt(3) * rad, rad), Rotation = i * 60, ZIndex = z, Parent = parent })
	end
end

local function line(parent, x1, y1, x2, y2, color, thick, z, transparency)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	return new("Frame", { BackgroundColor3 = color, BackgroundTransparency = transparency or 0, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2), Size = UDim2.fromOffset(len, thick), Rotation = math.deg(math.atan2(dy, dx)), ZIndex = z, Parent = parent })
end

local function closeChart()
	if root then
		root:Destroy()
		root = nil
		builtSeed = nil
	end
end
MapUI.close = closeChart

local function nodeInfo(n)
	local stop = MapDefs.Stops[n.type]
	local lines = { stop.desc }
	if n.info then
		table.insert(lines, (if MapUI.chart.navigator and n.type ~= "Boss" then "NAVIGATOR: " else "") .. n.info)
	elseif not MapUI.chart.navigator and (n.type == "Fight" or n.type == "Elite" or n.type == "Event" or n.type == "Treasure" or n.type == "Camp") then
		table.insert(lines, "Only the Navigator knows what's here.")
	end
	return stop.label, table.concat(lines, "\n")
end

local function showInfo(n)
	if not refs.infoTitle then
		return
	end
	local title, text = nodeInfo(n)
	refs.infoTitle.Text = title
	refs.infoText.Text = text
end

local function buildGrid(chart)
	local view = chart.view
	local area = refs.area
	area:ClearAllChildren()
	local sea = if view.weather == "Night" then Color3.fromRGB(10, 20, 32) elseif view.weather == "Stormy" then Color3.fromRGB(15, 32, 48) else Color3.fromRGB(16, 40, 61)
	for r = 0, MapDefs.Rows - 1 do
		for c = 0, MapDefs.Cols - 1 do
			local x, y = cellXY(c, r)
			local reef = view.reefs[c .. "," .. r]
			hex(area, x, y, R - 1, if reef then Color3.fromRGB(36, 51, 63) else sea, 3)
			if reef then
				new("Frame", { BackgroundColor3 = Color3.fromRGB(138, 153, 171), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(9, 9), Rotation = 45, ZIndex = 4, Parent = area })
			end
		end
	end
	if view.weather == "Stormy" then
		local rng = Random.new(view.seed)
		for _ = 1, 4 do
			local x, y = cellXY(rng:NextInteger(1, 16), rng:NextInteger(1, 10))
			local cl = new("Frame", { BackgroundColor3 = Color3.fromRGB(58, 74, 92), BackgroundTransparency = 0.2, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 16), Position = UDim2.fromOffset(x - 20, y - 8), ZIndex = 9, Parent = area })
			new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = cl })
			Kit.label({ Text = "⚡", TextSize = 14, Color = Style.Gold, Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(12, 12), ZIndex = 10, Parent = cl })
		end
	end
	refs.lanes = new("Frame", { Name = "Lanes", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = area })
	refs.isles = new("Frame", { Name = "Isles", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = area })
end

local function drawNodes(chart)
	local view = chart.view
	refs.lanes:ClearAllChildren()
	refs.isles:ClearAllChildren()
	local visited = {}
	for _, id in chart.visited or {} do
		visited[id] = true
	end
	local options = {}
	for _, id in chart.options or {} do
		options[id] = true
	end
	local voting = chart.state == "vote"
	-- votes per node
	local voteCount, myVote = {}, nil
	for uid, nodeId in chart.votes or {} do
		voteCount[nodeId] = (voteCount[nodeId] or 0) + 1
		if tonumber(uid) == player.UserId then
			myVote = nodeId
		end
	end
	-- lanes
	for _, n in view.nodes do
		local x1, y1 = cellXY(n.c, n.r)
		for _, nid in n.next do
			local m = view.nodes[tostring(nid)]
			if m then
				local x2, y2 = cellXY(m.c, m.r)
				local walked = visited[n.id] and visited[nid]
				local open = n.id == chart.at and options[nid]
				line(refs.lanes, x1, y1, x2, y2, if walked then Style.Red elseif open then Style.Cyan else Style.Cream, if walked or open then 4 else 2, 5, if walked or open then 0 else 0.55)
			end
		end
	end
	-- islands
	for _, n in view.nodes do
		local x, y = cellXY(n.c, n.r)
		local stop = MapDefs.Stops[n.type]
		local isOption = options[n.id]
		local here = n.id == chart.at
		local size = if n.type == "Boss" then 46 else 36
		-- a sandy island under the tile
		local isle = new("Frame", { BackgroundColor3 = Color3.fromRGB(214, 190, 130), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y + 4), Size = UDim2.fromOffset(size + 16, size * 0.7), ZIndex = 6, Parent = refs.isles })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = isle })
		local _, face, glyph, st = Kit.tile({ Glyph = stop.glyph, GlyphSize = if n.type == "Boss" then 30 else 22, Size = UDim2.fromOffset(size, size), Position = UDim2.fromOffset(x, y), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 7, Parent = refs.isles, StrokeColor = if n.type == "Boss" then Style.Red else Style.Cream })
		if visited[n.id] and not here then
			face.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
			glyph.TextColor3 = Style.Muted
		end
		if isOption and voting then
			st.Color = Style.Cyan
			TweenService:Create(st, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 }):Play()
		end
		if here then
			local ring = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size + 18, size + 18), ZIndex = 9, Parent = refs.isles })
			new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
			Kit.stroke(ring, Style.Red, 3)
			Kit.label({ Text = "YOU", Font = Style.Display, TextSize = 16, Size = UDim2.fromOffset(60, 16), Position = UDim2.fromOffset(x - 30, y - size / 2 - 26), ZIndex = 10, Parent = refs.isles, Outline = 2 })
		end
		if voteCount[n.id] then
			local badge = new("Frame", { BackgroundColor3 = Style.Red, BorderSizePixel = 0, Size = UDim2.fromOffset(26, 22), Position = UDim2.fromOffset(x + size / 2 - 6, y - size / 2 - 14), ZIndex = 11, Rotation = -6, Parent = refs.isles })
			Kit.stroke(badge, Style.Cream, 2)
			Kit.label({ Text = tostring(voteCount[n.id]), Font = Style.Display, TextSize = 18, ZIndex = 12, Parent = badge })
		end
		if myVote == n.id then
			Kit.label({ Text = "YOUR VOTE", Font = Style.Body, TextSize = 11, Color = Style.Cyan, Size = UDim2.fromOffset(80, 14), Position = UDim2.fromOffset(x - 40, y + size / 2 + 4), ZIndex = 10, Parent = refs.isles, Outline = 1.5 })
		end
		local hit = new("TextButton", { Text = "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size + 10, size + 10), ZIndex = 13, Parent = refs.isles })
		hit.MouseEnter:Connect(function()
			showInfo(n)
		end)
		hit.Activated:Connect(function()
			showInfo(n)
			if voting and isOption then
				remote:FireServer("vote", n.id)
			end
		end)
	end
end

local function drawSide(chart)
	local list = refs.crewList
	for _, ch in list:GetChildren() do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	local ready = {}
	for _, uid in chart.ready or {} do
		ready[uid] = true
	end
	for i, c in chart.crew do
		local row = new("Frame", { BackgroundColor3 = Style.Panel2, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = i, ZIndex = 12, Parent = list })
		Kit.label({ Text = (if c.userId == player.UserId then "YOU" else c.name), Font = Style.Body, TextSize = 13, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -90, 0, 18), Position = UDim2.fromOffset(6, 1), ZIndex = 13, Parent = row })
		Kit.label({ Text = string.upper(c.role or "") .. " · HP " .. math.floor((c.hpFrac or 1) * 100) .. "%", Font = Style.BodyLight, TextSize = 10, Color = Style.Muted, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -90, 0, 14), Position = UDim2.fromOffset(6, 19), ZIndex = 13, Parent = row })
		local status
		if chart.state == "vote" then
			local v = chart.votes and chart.votes[tostring(c.userId)]
			status = if v then "VOTED" else "..."
		else
			status = if ready[c.userId] then "READY ✓" else "NOT READY"
		end
		Kit.label({ Text = status, Font = Style.Body, TextSize = 11, Color = if status == "READY ✓" or status == "VOTED" then Style.Cyan else Style.Muted, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(0, 84, 1, 0), Position = UDim2.new(1, -90, 0, 0), ZIndex = 13, Parent = row })
	end
	-- buttons
	local isCaptain = chart.captainId == player.UserId
	local amReady = ready[player.UserId]
	refs.readyBtn.Visible = chart.state == "ship"
	refs.readyText.Text = if amReady then "READY ✓" else "READY"
	refs.forceBtn.Visible = chart.state == "ship" and isCaptain
	refs.closeBtn.Visible = chart.state ~= "vote"
	refs.status.Text = if chart.state == "vote" then "VOTE ON THE NEXT STOP!" elseif chart.state == "ship" then (#(chart.ready or {}) .. "/" .. #chart.crew .. " READY") else "SAILING..."
	refs.sub.Text = "GOLD " .. chart.gold .. "   ·   " .. chart.view.shape .. "   ·   " .. chart.view.weather .. (if chart.navigator then "   ·   NAVIGATOR VIEW" else "")
end

local function openChart()
	local chart = MapUI.chart
	if not chart or (MapUI.blocked and MapUI.blocked()) then
		return
	end
	if not root then
		refs = {} :: { [string]: any }
		root = new("Frame", { Name = "Backdrop", BackgroundColor3 = Style.Black, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = gui })
		local panel = Kit.panel({ Name = "Chart", Size = UDim2.fromOffset(CHART_W + 290, CHART_H + 120), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2, Parent = root, Tilt = 0.8 })
		refs.tab = Kit.tab(panel, "", 330)
		refs.sub = Kit.label({ Text = "", Font = Style.Body, TextSize = 14, Color = Style.Muted, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 16), ZIndex = 4, Parent = panel })
		refs.area = new("Frame", { Name = "Area", BackgroundColor3 = Color3.fromRGB(31, 61, 89), BorderSizePixel = 0, Size = UDim2.fromOffset(CHART_W, CHART_H), Position = UDim2.fromOffset(16, 44), ZIndex = 3, ClipsDescendants = true, Parent = panel })
		Kit.stroke(refs.area, Style.Cream, 3)
		-- sidebar
		local side = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 250, 1, -60), Position = UDim2.new(1, -266, 0, 44), ZIndex = 10, Parent = panel })
		refs.status = Kit.label({ Text = "", Font = Style.Display, TextSize = 26, Size = UDim2.new(1, 0, 0, 30), ZIndex = 11, Parent = side })
		local info = new("Frame", { BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 120), Position = UDim2.fromOffset(0, 36), ZIndex = 11, Parent = side })
		Kit.stroke(info, Style.Cream, 2)
		refs.infoTitle = Kit.label({ Text = "HOVER A STOP", Font = Style.Display, TextSize = 22, Color = Style.Red2, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(8, 4), ZIndex = 12, Parent = info })
		refs.infoText = Kit.label({ Text = "Paths split and join. The boss waits at the top.", Font = Style.BodyLight, TextSize = 13, Wrap = true, XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -14, 1, -32), Position = UDim2.fromOffset(8, 30), ZIndex = 12, Parent = info })
		refs.crewList = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 250), Position = UDim2.fromOffset(0, 166), ZIndex = 11, Parent = side })
		new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = refs.crewList })
		local readyBtn, readyText = Kit.button({ Text = "READY", Size = UDim2.fromOffset(150, 44), Position = UDim2.new(0, 0, 1, -50), ZIndex = 12, Parent = side, OnClick = function()
			remote:FireServer("ready")
		end })
		refs.readyBtn, refs.readyText = readyBtn, readyText
		refs.forceBtn = Kit.button({ Text = "FORCE ♛", TextSize = 20, Size = UDim2.fromOffset(96, 44), Position = UDim2.new(1, -96, 1, -50), ZIndex = 12, Color = Style.Panel2, Parent = side, OnClick = function()
			remote:FireServer("force")
		end })
		refs.closeBtn = Kit.button({ Text = "X", TextSize = 22, Size = UDim2.fromOffset(40, 36), Position = UDim2.new(1, -30, 0, -20), ZIndex = 12, Color = Style.Panel2, Parent = panel, OnClick = closeChart })
		refs.timer = Kit.label({ Text = "", Font = Style.Display, TextSize = 22, Color = Style.Cyan, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -82), ZIndex = 11, Parent = side, Outline = true })
	end
	local tabLabel = refs.tab:FindFirstChildWhichIsA("TextLabel")
	if tabLabel then
		tabLabel.Text = "SEA " .. chart.sea .. " · " .. string.upper(chart.seaName)
	end
	if builtSeed ~= chart.view.seed then
		buildGrid(chart)
		builtSeed = chart.view.seed
	end
	drawNodes(chart)
	drawSide(chart)
end
MapUI.open = openChart

-- ===== cards =====

local cardFrame
local function showCard(data)
	if cardFrame then
		cardFrame:Destroy()
	end
	closeChart()
	local mine = data.deciderId == player.UserId
	cardFrame = Kit.panel({ Name = "Card", Size = UDim2.fromOffset(520, 150 + #data.choices * 56), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Parent = gui, Rotation = -0.8 })
	Kit.tab(cardFrame, data.title, 260)
	Kit.label({ Text = data.text, Font = Style.Body, TextSize = 18, Wrap = true, Size = UDim2.new(1, -40, 0, 60), Position = UDim2.fromOffset(20, 18), ZIndex = 32, Parent = cardFrame })
	Kit.label({ Text = if mine then "You decide (you're the Captain)." else data.deciderName .. " is choosing...", Font = Style.BodyLight, TextSize = 13, Color = Style.Cyan, Size = UDim2.new(1, -40, 0, 18), Position = UDim2.fromOffset(20, 80), ZIndex = 32, Parent = cardFrame })
	for i, c in data.choices do
		local b = Kit.button({ Text = c.label, TextSize = 20, Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 104 + (i - 1) * 56), ZIndex = 33, Parent = cardFrame, OnClick = function()
			remote:FireServer("card", { token = data.token, index = i })
		end })
		if not mine or not c.ok then
			Kit.setDisabled(b, true)
		end
	end
end

local function showCardResult(data)
	if cardFrame then
		cardFrame:Destroy()
	end
	cardFrame = Kit.panel({ Name = "CardResult", Size = UDim2.fromOffset(500, 140), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Parent = gui, Rotation = 0.8 })
	Kit.tab(cardFrame, string.upper(data.by) .. " CHOSE", 260)
	Kit.label({ Text = data.choice .. "\n\n" .. data.text, Font = Style.Body, TextSize = 18, Wrap = true, Size = UDim2.new(1, -40, 1, -30), Position = UDim2.fromOffset(20, 18), ZIndex = 32, Parent = cardFrame })
	local f = cardFrame
	task.delay(2.6, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

local function showRunEnd(data)
	closeChart()
	Kit.stamp(gui, if data.won then "PIRATE KING!" else "RUN OVER", if data.won then Style.Red else Style.Dim, UDim2.fromScale(0.5, 0.3))
	local p = Kit.panel({ Size = UDim2.fromOffset(460, 150), Position = UDim2.fromScale(0.5, 0.55), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Parent = gui })
	Kit.label({ Text = (if data.won then "You beat an Emperor of the Sea!" else "Your crew fell in Sea " .. data.sea .. ".") .. "\nYour bounty: " .. Kit.commas(data.bounty or 0) .. " berries\nBack to the lobby...", Font = Style.Body, TextSize = 19, Wrap = true, Size = UDim2.new(1, -30, 1, -20), Position = UDim2.fromOffset(15, 10), ZIndex = 32, Parent = p })
	task.delay(6, function()
		p:Destroy()
	end)
end

-- ===== HUD: sea + gold + the chart button =====

local hud = Kit.panel({ Name = "Hud", Size = UDim2.fromOffset(250, 84), Position = UDim2.fromOffset(16, 60), ZIndex = 2, Parent = gui, Rotation = -1, NoDots = true })
hud.Visible = false
local hudSea = Kit.label({ Text = "", Font = Style.Display, TextSize = 22, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(10, 4), ZIndex = 4, Parent = hud })
local hudGold = Kit.label({ Text = "", Font = Style.Body, TextSize = 14, Color = Style.Gold, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(10, 28), ZIndex = 4, Parent = hud })
Kit.button({ Text = "SEA CHART [M]", TextSize = 18, Size = UDim2.fromOffset(150, 30), Position = UDim2.fromOffset(10, 48), ZIndex = 5, Parent = hud, OnClick = function()
	if root then
		if MapUI.chart and MapUI.chart.state ~= "vote" then
			closeChart()
		end
	else
		openChart()
	end
end })

function MapUI.setHudVisible(v)
	hud.Visible = v and MapUI.chart ~= nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.M or not MapUI.chart then
		return
	end
	if root then
		if MapUI.chart.state ~= "vote" then
			closeChart()
		end
	else
		openChart()
	end
end)

-- vote timer
task.spawn(function()
	while true do
		task.wait(0.25)
		local c = MapUI.chart
		if root and refs.timer then
			if c and c.state == "vote" and c.deadlineAt then
				refs.timer.Text = "VOTE ENDS IN " .. math.max(0, math.ceil(c.deadlineAt - os.clock()))
			else
				refs.timer.Text = ""
			end
		end
	end
end)

function MapUI.init()
	remote.OnClientEvent:Connect(function(msg, data)
		if msg == "chart" then
			local wasVote = MapUI.chart and MapUI.chart.state == "vote"
			MapUI.chart = data
			if data.deadline then
				data.deadlineAt = os.clock() + data.deadline
			end
			hudSea.Text = "SEA " .. data.sea .. " · " .. string.upper(data.seaName)
			hudGold.Text = "GOLD " .. data.gold .. "   ·   POWER " .. data.power
			hud.Visible = not (MapUI.blocked and MapUI.blocked())
			if data.state == "vote" and not wasVote then
				openChart()
			elseif root then
				openChart() -- refresh
			end
			if data.state == "stop" then
				closeChart()
			end
		elseif msg == "card" then
			showCard(data)
		elseif msg == "cardResult" then
			showCardResult(data)
		elseif msg == "runEnd" then
			showRunEnd(data)
			MapUI.chart = nil
			hud.Visible = false
		elseif msg == "close" then
			closeChart()
			hud.Visible = false
		end
	end)
	remote:FireServer("view")
end

return MapUI
