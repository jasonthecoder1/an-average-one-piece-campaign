-- The Undertale-style dodge box (design page "Dodge box"): a black box with a cream border, a red heart you move
-- with WASD / arrows (or drag on a phone), cannonballs, sword waves, pistol shots and fishman karate water.
-- Pass close to a bullet without getting hit = a GRAZE (chain shown above the box; 5+ = +1 stamina next turn).
-- SPACE / SHIFT = dash (short, can't be hit while dashing).
-- Bullets are built from the server's seed (Shared/DodgePatterns). We send back our hits, grazes and the heart
-- path; the server rebuilds the same bullets, replays the path and won't take fewer hits than it counts itself.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleDefs = require(ReplicatedStorage.Shared.BattleDefs)
local DodgePatterns = require(ReplicatedStorage.Shared.DodgePatterns)
local Kit = require(script.Parent.Kit)
local Style = Kit.Style
local new = Kit.new

local DodgeBox = {}

local HEART_R = DodgePatterns.HEART_R
local SPEED = DodgePatterns.SPEED
local DASH_TIME = DodgePatterns.DASH_TIME
local DASH_SPEED = DodgePatterns.DASH_SPEED
local DASH_COOLDOWN = DodgePatterns.DASH_COOLDOWN
local HIT_IFRAMES = DodgePatterns.HIT_IFRAMES
local GRAZE_PAD = DodgePatterns.GRAZE_PAD
local TELEGRAPH = DodgePatterns.TELEGRAPH
local round3 = DodgePatterns.round3

local KIND_COLOR = {
	ball = Color3.fromRGB(25, 25, 25),
	slash = Style.Cream,
	shot = Style.Gold,
	drop = Style.Cyan,
}

-- Runs the box. payload = the server's "dodge" message. Returns { hits, grazes, path }.
-- path = the heart every 0.05 s of box time: { { t, x, y, dash }... } (3 decimals, at most 400 samples).
function DodgeBox.run(gui, payload)
	local pattern = BattleDefs.Patterns[payload.pattern] or BattleDefs.Patterns.CannonBarrage
	local mods = payload.mods or {}
	local dur = pattern.duration
	local bullets = DodgePatterns.build(pattern, payload.seed or 1, mods, payload.density or pattern.density or 1)
	local tele = TELEGRAPH * (if payload.observation then 1.75 else 1) * (if mods.blind then BattleDefs.Status.blind.telegraph else 1)

	local cam = workspace.CurrentCamera
	-- the battle screen already has a UIScale; undo it here so the box keeps its real size on small screens
	local uiScale = gui:FindFirstChildOfClass("UIScale")
	local px = math.floor(math.clamp(cam.ViewportSize.Y * 0.46, 220, 380) / (if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1))
	local holder = new("Frame", { Name = "Dodge", BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px), Position = UDim2.fromScale(0.5, 0.47), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 50, Parent = gui })
	local box = new("Frame", { Name = "Box", BackgroundColor3 = Style.Black, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 51, ClipsDescendants = true, Parent = holder })
	Kit.stroke(box, Style.Cream, 4)
	Kit.shadow(box, 7, 1.5)
	Kit.label({ Text = pattern.label .. (if payload.enraged then "  (ENRAGED!)" else ""), Font = Style.Display, TextSize = 30, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, -70), ZIndex = 55, Parent = holder, Outline = 2 })
	local chainLabel = Kit.label({ Text = "", Font = Style.Display, TextSize = 24, Color = Style.Cyan, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, -38), ZIndex = 55, Parent = holder, Outline = 2 })
	local info = Kit.label({ Text = "WASD / arrows to move · SPACE to dash · " .. (payload.damagePerHit or 0) .. " dmg per hit", Font = Style.Body, TextSize = 14, Size = UDim2.new(1, 60, 0, 20), Position = UDim2.new(0, -30, 1, 12), ZIndex = 55, Parent = holder, Outline = true })
	local hitsLabel = Kit.label({ Text = "HITS 0", Font = Style.Display, TextSize = 22, Color = Style.Red2, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, 34), ZIndex = 55, Parent = holder, Outline = 2 })
	local _timeBar, setTime = Kit.bar({ Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, -8), Color = Style.Cream, Parent = holder, ZIndex = 55 })

	local heart = Kit.label({ Name = "Heart", Text = "♥", Font = Enum.Font.GothamBlack, TextSize = math.floor(px * HEART_R * 2.8), Color = Style.Red, Size = UDim2.fromOffset(px * HEART_R * 3, px * HEART_R * 3), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 58, Parent = box })
	Kit.textStroke(heart, 1.5)

	-- mobile: a dash button
	local dashBtn
	if UserInputService.TouchEnabled then
		dashBtn = Kit.button({ Text = "DASH", Size = UDim2.fromOffset(110, 52), Position = UDim2.new(1, 30, 1, -52), ZIndex = 56, Parent = holder })
		info.Text = "Drag to move · DASH button · " .. (payload.damagePerHit or 0) .. " dmg per hit"
	end

	local hx, hy = DodgePatterns.START_X, DodgePatterns.START_Y
	local hits, grazes, chain = 0, 0, 0
	local iframes, dashT, dashCd = 0, 0, 0
	local dashLen = DASH_TIME * (payload.dashMult or 1)
	local speed = SPEED * (payload.heartSpeed or 1)
	local touchPos = nil
	local dragTouch = nil -- the finger that steers (a tap on DASH with another finger doesn't take over)
	local lastMx, lastMy = 0, 0 -- last steering direction: a dash with no input keeps going that way
	local path = { { t = 0, x = hx, y = hy, dash = false } }
	local nextSample = DodgePatterns.SAMPLE

	local function tryDash()
		if dashCd <= 0 then
			dashT = dashLen
			dashCd = DASH_COOLDOWN
		end
	end
	local conns = {}
	table.insert(conns, UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonB then
			tryDash()
		end
	end))
	table.insert(conns, UserInputService.TouchStarted:Connect(function(touch, processed)
		if processed or dragTouch then
			return
		end
		dragTouch = touch
		touchPos = touch.Position
	end))
	table.insert(conns, UserInputService.TouchMoved:Connect(function(touch, processed)
		if dragTouch == nil and not processed then
			dragTouch = touch -- a finger that was already down when the box opened
		end
		if touch == dragTouch then
			touchPos = touch.Position
		end
	end))
	table.insert(conns, UserInputService.TouchEnded:Connect(function(touch)
		if touch == dragTouch then
			dragTouch, touchPos = nil, nil
		end
	end))
	if dashBtn then
		dashBtn.Activated:Connect(tryDash)
	end

	-- live bullets (the list is already sorted by spawn time)
	local live = {}
	local nextIdx = 1
	local warnings = {}

	local function makeDot(r, color, z)
		local f = new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(r * 2, r * 2), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z, Parent = box })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = f })
		return f
	end

	local function graze(b, bx, by)
		b.grazed = true
		grazes += 1
		chain += 1
		chainLabel.Text = "GRAZE  CHAIN x" .. chain
		local s = makeDot(0.012, Style.Cream, 57)
		s.Position = UDim2.fromScale((bx + hx) / 2, (by + hy) / 2)
		task.delay(0.2, function()
			s:Destroy()
		end)
	end

	-- box time: each frame adds at most 1/20 s, so a lag spike pauses the box instead of skipping ahead
	-- (the server replays the path on the same clock)
	local el = 0
	local last = os.clock()
	while true do
		local now = os.clock()
		local dt = math.min(now - last, DodgePatterns.MAX_STEP)
		last = now
		el += dt
		if el >= dur then
			break
		end
		local elr = round3(el) -- bullets spawn and move on this rounded clock, same as the server's replay
		setTime(1 - el / dur, true)

		-- spawn warnings and bullets
		for i = nextIdx, #bullets do
			local b = bullets[i]
			if b.warned == nil and el >= b.t - tele and b.warnX then
				b.warned = true
				local w = makeDot(b.r * 1.3, Style.Red, 52)
				w.BackgroundTransparency = 0.55
				w.Position = UDim2.fromScale(b.warnX, b.warnY)
				table.insert(warnings, { f = w, untilT = b.t })
			end
			if b.t > el + tele then
				break
			end
		end
		while nextIdx <= #bullets and bullets[nextIdx].t <= elr do
			local b = bullets[nextIdx]
			nextIdx += 1
			if b.aim then
				DodgePatterns.aim(b, path, mods.blind)
			end
			local color = KIND_COLOR[b.kind] or Style.Cream
			b.f = makeDot(b.r, color, 54)
			if b.kind == "ball" then
				Kit.stroke(b.f, Style.Cream, 1.5)
			end
			table.insert(live, b)
		end
		for i = #warnings, 1, -1 do
			if el >= warnings[i].untilT then
				warnings[i].f:Destroy()
				table.remove(warnings, i)
			end
		end

		-- move the heart
		local mx, my = 0, 0
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			my -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
			my += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			mx -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			mx += 1
		end
		for _, st in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if st.KeyCode == Enum.KeyCode.Thumbstick1 and st.Position.Magnitude > 0.2 then
				mx += st.Position.X
				my -= st.Position.Y
			end
		end
		if touchPos then
			local abs = box.AbsolutePosition
			local tx = (touchPos.X - abs.X) / box.AbsoluteSize.X
			local ty = (touchPos.Y - abs.Y) / box.AbsoluteSize.Y
			if tx >= -0.2 and tx <= 1.2 and ty >= -0.2 and ty <= 1.2 then
				local dx, dy = tx - hx, ty - hy
				local m = math.sqrt(dx * dx + dy * dy)
				if m > 0.01 then
					mx, my = dx / m * math.min(1, m * 12), dy / m * math.min(1, m * 12)
				end
			end
		end
		local mag = math.sqrt(mx * mx + my * my)
		if mag > 0.01 then
			lastMx, lastMy = mx / mag, my / mag
		elseif dashT > 0 then
			mx, my = lastMx, lastMy -- a dash always moves the heart
		end
		if mag > 1 then
			mx, my = mx / mag, my / mag
		end
		local sp = speed * (if dashT > 0 then DASH_SPEED else 1)
		hx = math.clamp(hx + mx * sp * dt, HEART_R, 1 - HEART_R)
		hy = math.clamp(hy + my * sp * dt, HEART_R, 1 - HEART_R)
		dashT = math.max(0, dashT - dt)
		dashCd = math.max(0, dashCd - dt)
		iframes = math.max(0, iframes - dt)
		heart.Position = UDim2.fromScale(hx, hy)
		heart.TextTransparency = if iframes > 0 and math.floor(el * 16) % 2 == 0 then 0.7 elseif dashT > 0 then 0.4 else 0

		-- move bullets, check hits and grazes. A graze counts once the bullet leaves the graze band without
		-- touching the heart, and is taken back if that bullet touches you later (the server counts the same way).
		for i = #live, 1, -1 do
			local b = live[i]
			local bx, by = b.x + b.vx * (elr - b.t), b.y + b.vy * (elr - b.t)
			if bx < -0.15 or bx > 1.15 or by < -0.15 or by > 1.15 then
				b.f:Destroy()
				table.remove(live, i)
				continue
			end
			b.f.Position = UDim2.fromScale(bx, by)
			local dx, dy = bx - hx, by - hy
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist < b.r + HEART_R then
				if b.grazed and not b.touched then
					grazes -= 1 -- it got you after all: not a graze
				end
				b.touched = true
				if iframes <= 0 and dashT <= 0 then
					hits += 1
					iframes = HIT_IFRAMES
					chain = 0
					hitsLabel.Text = "HITS " .. hits
					box.BackgroundColor3 = Color3.fromRGB(70, 0, 0)
					task.delay(0.08, function()
						box.BackgroundColor3 = Style.Black
					end)
				end
			elseif dist < b.r + HEART_R + GRAZE_PAD then
				b.near = true
			elseif b.near and not b.touched and not b.grazed then
				graze(b, bx, by)
			end
		end

		-- record the heart (the server replays this path to check our hits and grazes)
		if elr >= nextSample and #path < DodgePatterns.MAX_SAMPLES then
			nextSample = elr + DodgePatterns.SAMPLE
			table.insert(path, { t = elr, x = round3(hx), y = round3(hy), dash = dashT > 0 })
		end
		RunService.RenderStepped:Wait()
	end
	-- bullets still in the graze band when time runs out count too
	for _, b in live do
		if b.near and not b.touched and not b.grazed then
			b.grazed = true
			grazes += 1
		end
	end
	for _, c in conns do
		c:Disconnect()
	end
	holder:Destroy()
	return { hits = hits, grazes = grazes, path = path }
end

return DodgeBox
