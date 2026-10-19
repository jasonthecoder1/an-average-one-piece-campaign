-- The two QTE minigames (design page "QTEs"): the sword's slanted STRIKE BAR (stop the marker on the red notch) and
-- the CLOSING RINGS for heavy moves (press as each ring closes on the red target). Timing numbers come from
-- Shared.ActionCommandDefs so the server grades with the same rules. Press Space, click, tap or gamepad A.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActionCommandDefs = require(ReplicatedStorage.Shared.ActionCommandDefs)
local Kit = require(script.Parent.Kit)
local Style = Kit.Style
local new = Kit.new

local Qte = {}

local function isPress(input)
	local t = input.UserInputType
	return (t == Enum.UserInputType.Keyboard and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E))
		or t == Enum.UserInputType.MouseButton1
		or t == Enum.UserInputType.Touch
		or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA)
end

local function hint(parent, text, z)
	Kit.label({ Text = text, Font = Style.Body, TextSize = 16, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, 14), ZIndex = z, Parent = parent, Outline = true })
end

-- STRIKE BAR. Returns { grade, t }.
function Qte.strike(gui)
	local d = ActionCommandDefs.Strike
	local root = Kit.panel({ Name = "StrikeQte", Size = UDim2.fromOffset(460, 70), Position = UDim2.fromScale(0.5, 0.62), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 60, Parent = gui, Rotation = -2 })
	Kit.label({ Text = "STRIKE!", Font = Style.Display, TextSize = 30, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, -38), ZIndex = 62, Parent = root, Outline = 2 })
	-- the slanted trough
	local trough = new("Frame", { BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 22), ZIndex = 61, ClipsDescendants = true, Parent = root })
	Kit.stroke(trough, Style.Cream, 2)
	-- wide good zone (cream) and the red crit notch
	local gw = d.goodWindow * 2
	new("Frame", { BackgroundColor3 = Style.Cream, BackgroundTransparency = 0.25, BorderSizePixel = 0, Size = UDim2.fromScale(gw, 1), Position = UDim2.fromScale(d.notch - d.goodWindow, 0), ZIndex = 62, Parent = trough })
	new("Frame", { BackgroundColor3 = Style.Red, BorderSizePixel = 0, Size = UDim2.fromScale(d.critWindow * 2, 1), Position = UDim2.fromScale(d.notch - d.critWindow, 0), ZIndex = 63, Parent = trough })
	-- early miss zone (dark)
	new("Frame", { BackgroundColor3 = Style.Dim, BorderSizePixel = 0, Size = UDim2.fromScale(d.earlyMiss, 1), ZIndex = 62, Parent = trough })
	local marker = new("Frame", { BackgroundColor3 = Style.Cyan, BorderSizePixel = 0, Size = UDim2.new(0, 6, 1, 8), Position = UDim2.new(0, 0, 0, -4), AnchorPoint = Vector2.new(0.5, 0), Rotation = 14, ZIndex = 65, Parent = trough })
	Kit.stroke(marker, Style.Black, 1.5)
	hint(root, "Press SPACE / click / tap on the red notch!  CRIT x1.5 · GOOD x1 · WEAK x0.6 · MISS 0", 62)

	local t0 = os.clock()
	local pressedT = nil
	local done = false
	local conn = UserInputService.InputBegan:Connect(function(input)
		if done or not isPress(input) then
			return
		end
		local el = os.clock() - t0
		if el < d.lead then
			return -- presses during the intro don't count
		end
		pressedT = math.clamp((el - d.lead) / d.sweep, 0, 1.2)
		done = true
	end)
	while not done do
		local el = os.clock() - t0
		local t = math.clamp((el - d.lead) / d.sweep, 0, 1)
		marker.Position = UDim2.new(t, 0, 0, -4)
		if el > d.lead + d.sweep + d.tail then
			done = true
		end
		RunService.RenderStepped:Wait()
	end
	conn:Disconnect()
	local grade = ActionCommandDefs.strikeGrade(pressedT)
	task.delay(0.35, function()
		root:Destroy()
	end)
	return { grade = grade, t = pressedT }
end

-- CLOSING RINGS. Returns { sparks }.
function Qte.rings(gui)
	local d = ActionCommandDefs.Rings
	local meets = ActionCommandDefs.ringMeets()
	local size = 220
	local root = Kit.panel({ Name = "RingQte", Size = UDim2.fromOffset(size + 40, size + 40), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 60, Parent = gui, Rotation = 1.5 })
	Kit.label({ Text = "POWER RINGS!", Font = Style.Display, TextSize = 30, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, -38), ZIndex = 62, Parent = root, Outline = 2 })
	local center = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 61, Parent = root })
	local target = new("Frame", { BackgroundColor3 = Style.Red, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 63, Parent = center })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = target })
	Kit.stroke(target, Style.Cream, 3)
	local sparkLabel = Kit.label({ Text = "0 / 3", Font = Style.Display, TextSize = 22, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -30), ZIndex = 64, Parent = root, Outline = true })
	hint(root, "Press as each ring closes on the red target. 3 of 3 = PERFECT", 62)

	local rings = {}
	for i, m in meets do
		local ring = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 62, Parent = center })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
		local st = Kit.stroke(ring, Style.Cyan, 4)
		rings[i] = { meet = m, frame = ring, stroke = st, state = nil } -- state: "spark" | "miss"
	end

	local t0 = os.clock()
	local sparks = 0
	local conn = UserInputService.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		local el = os.clock() - t0
		for _, r in rings do
			if r.state == nil then
				if math.abs(el - r.meet) <= d.window then
					r.state = "spark"
					sparks += 1
					r.stroke.Color = Style.Cream
					target.BackgroundColor3 = Style.Cream
					task.delay(0.1, function()
						target.BackgroundColor3 = Style.Red
					end)
				elseif el >= r.meet - d.window - d.early and el < r.meet - d.window then
					r.state = "miss" -- pressed too early: this ring fizzles
					r.stroke.Color = Style.Dim
				end
				break -- only the next unresolved ring counts
			end
		end
		sparkLabel.Text = sparks .. " / 3"
	end)
	local last = meets[#meets] + d.window + 0.15
	while os.clock() - t0 < last do
		local el = os.clock() - t0
		for _, r in rings do
			local startT = r.meet - d.approach
			if el >= startT and el <= r.meet + d.window then
				r.frame.Visible = true
				local k = math.clamp((el - startT) / d.approach, 0, 1)
				local s = size - (size - 44) * k
				r.frame.Size = UDim2.fromOffset(s, s)
			elseif el > r.meet + d.window then
				if r.state == nil then
					r.state = "miss"
				end
				r.frame.Visible = false
			end
		end
		RunService.RenderStepped:Wait()
	end
	conn:Disconnect()
	task.delay(0.35, function()
		root:Destroy()
	end)
	return { sparks = sparks }
end

return Qte
