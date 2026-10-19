-- The Undertale-style dodge box (design page "Dodge box"): a black box with a cream border, a red heart you move
-- with WASD / arrows (or drag on a phone), cannonballs, sword waves, pistol shots and fishman karate water.
-- Pass close to a bullet without getting hit = a GRAZE (chain shown above the box; 5+ = +1 stamina next turn).
-- SPACE / SHIFT = dash (short, can't be hit while dashing).
-- Bullets are built from the server's seed, so everyone would see the same pattern. The server clamps what we
-- report (hits 0..maxHits, grazes 0..30) and won't accept an answer that comes back before the box could end.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleDefs = require(ReplicatedStorage.Shared.BattleDefs)
local Kit = require(script.Parent.Kit)
local Style = Kit.Style
local new = Kit.new

local DodgeBox = {}

local HEART_R = 0.022 -- in box units (box = 0..1)
local SPEED = 0.62 -- box units per second
local DASH_TIME = 0.16
local DASH_SPEED = 2.6
local DASH_COOLDOWN = 0.9
local HIT_IFRAMES = 0.6
local GRAZE_PAD = 0.045
local TELEGRAPH = 0.45

-- ===== pattern generators: return a list of bullets { t, x, y, vx, vy, r, kind, warnX?, warnY? } =====
-- `aim` bullets get their velocity when they spawn (they aim at the heart).
local Gen = {}

function Gen.rain(rng, dur, density)
	local list = {}
	local t = 0.5
	while t < dur - 0.6 do
		local x = rng:NextNumber(0.05, 0.95)
		local big = rng:NextNumber() < 0.2
		table.insert(list, { t = t, x = x, y = -0.06, vx = rng:NextNumber(-0.05, 0.05), vy = rng:NextNumber(0.5, 0.75), r = if big then 0.05 else 0.032, kind = "ball", warnX = x, warnY = 0.03 })
		t += rng:NextNumber(0.22, 0.4) / density
	end
	return list
end

function Gen.waves(rng, dur, density)
	local list = {}
	local t = 0.6
	local dir = 1
	while t < dur - 1.2 do
		local n = 11
		local gap = rng:NextInteger(1, n - 3)
		local horizontal = rng:NextNumber() < 0.5
		for i = 0, n - 1 do
			if i ~= gap and i ~= gap + 1 and (density < 1.3 or i ~= gap + 2 or rng:NextNumber() < 0.5) then
				local p = (i + 0.5) / n
				local b = { t = t, r = 0.028, kind = "slash" }
				if horizontal then
					b.x, b.y, b.vx, b.vy = (if dir > 0 then -0.05 else 1.05), p, 0.48 * dir, 0
					b.warnX, b.warnY = (if dir > 0 then 0.03 else 0.97), p
				else
					b.x, b.y, b.vx, b.vy = p, (if dir > 0 then -0.05 else 1.05), 0, 0.48 * dir
					b.warnX, b.warnY = p, (if dir > 0 then 0.03 else 0.97)
				end
				table.insert(list, b)
			end
		end
		dir = -dir
		t += rng:NextNumber(0.9, 1.25) / density
	end
	return list
end

function Gen.aimed(rng, dur, density)
	local list = {}
	local t = 0.5
	while t < dur - 0.5 do
		local side = rng:NextInteger(1, 4)
		local s = rng:NextNumber(0.05, 0.95)
		local x, y
		if side == 1 then
			x, y = s, -0.04
		elseif side == 2 then
			x, y = s, 1.04
		elseif side == 3 then
			x, y = -0.04, s
		else
			x, y = 1.04, s
		end
		table.insert(list, { t = t, x = x, y = y, aim = 0.72, r = 0.022, kind = "shot", warnX = math.clamp(x, 0.03, 0.97), warnY = math.clamp(y, 0.03, 0.97), spread = rng:NextNumber(-1, 1) })
		t += rng:NextNumber(0.28, 0.45) / density
	end
	return list
end

function Gen.burst(rng, dur, density)
	local list = {}
	local t = 0.6
	while t < dur - 1 do
		local cx, cy = rng:NextNumber(0.15, 0.85), rng:NextNumber(0.15, 0.85)
		local n = math.floor(10 + 4 * density)
		local off = rng:NextNumber(0, math.pi * 2)
		for i = 1, n do
			local a = off + (i / n) * math.pi * 2
			table.insert(list, { t = t, x = cx, y = cy, vx = math.cos(a) * 0.42, vy = math.sin(a) * 0.42, r = 0.026, kind = "drop", warnX = cx, warnY = cy })
		end
		t += rng:NextNumber(0.85, 1.2) / density
	end
	return list
end

local KIND_COLOR = {
	ball = Color3.fromRGB(25, 25, 25),
	slash = Style.Cream,
	shot = Style.Gold,
	drop = Style.Cyan,
}

-- Runs the box. payload = the server's "dodge" message. Returns { hits, grazes }.
function DodgeBox.run(gui, payload)
	local pattern = BattleDefs.Patterns[payload.pattern] or BattleDefs.Patterns.CannonBarrage
	local mods = payload.mods or {}
	local rng = Random.new(payload.seed or 1)
	local dur = pattern.duration
	local bullets = (Gen[pattern.gen] or Gen.rain)(rng, dur, payload.density or pattern.density or 1)
	-- STAGGER: the enemy only gets some of its bullets out
	if mods.stagger then
		local keep = {}
		for _, b in bullets do
			if rng:NextNumber() < BattleDefs.Status.stagger.keep then
				table.insert(keep, b)
			end
		end
		bullets = keep
	end
	local tele = TELEGRAPH * (if payload.observation then 1.75 else 1) * (if mods.blind then BattleDefs.Status.blind.telegraph else 1)

	local cam = workspace.CurrentCamera
	local px = math.floor(math.clamp(cam.ViewportSize.Y * 0.46, 220, 380))
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

	local hx, hy = 0.5, 0.75
	local hits, grazes, chain = 0, 0, 0
	local iframes, dashT, dashCd = 0, 0, 0
	local dashLen = DASH_TIME * (payload.dashMult or 1)
	local speed = SPEED * (payload.heartSpeed or 1)
	local touchPos = nil

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
	table.insert(conns, UserInputService.TouchMoved:Connect(function(touch)
		touchPos = touch.Position
	end))
	table.insert(conns, UserInputService.TouchStarted:Connect(function(touch)
		touchPos = touch.Position
	end))
	table.insert(conns, UserInputService.TouchEnded:Connect(function()
		touchPos = nil
	end))
	if dashBtn then
		dashBtn.Activated:Connect(tryDash)
	end

	-- live bullets
	local live = {}
	local nextIdx = 1
	table.sort(bullets, function(a, b)
		return a.t < b.t
	end)
	local warnings = {}

	local function makeDot(r, color, z)
		local f = new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(r * 2, r * 2), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z, Parent = box })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = f })
		return f
	end

	local t0 = os.clock()
	local last = t0
	while true do
		local now = os.clock()
		local el = now - t0
		local dt = math.min(now - last, 1 / 20)
		last = now
		if el >= dur then
			break
		end
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
		while nextIdx <= #bullets and bullets[nextIdx].t <= el do
			local b = bullets[nextIdx]
			nextIdx += 1
			if b.aim then
				local dx, dy = hx - b.x, hy - b.y
				local a = math.atan2(dy, dx) + (if mods.blind then (b.spread or 0) * BattleDefs.Status.blind.spread else 0)
				b.vx, b.vy = math.cos(a) * b.aim, math.sin(a) * b.aim
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

		-- move bullets, check hits and grazes
		for i = #live, 1, -1 do
			local b = live[i]
			b.x += b.vx * dt
			b.y += b.vy * dt
			if b.x < -0.15 or b.x > 1.15 or b.y < -0.15 or b.y > 1.15 then
				b.f:Destroy()
				table.remove(live, i)
				continue
			end
			b.f.Position = UDim2.fromScale(b.x, b.y)
			local dx, dy = b.x - hx, b.y - hy
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist < b.r + HEART_R then
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
				b.grazed = true
			elseif not b.grazed and dist < b.r + HEART_R + GRAZE_PAD then
				b.grazed = true
				grazes += 1
				chain += 1
				chainLabel.Text = "GRAZE  CHAIN x" .. chain
				local s = makeDot(0.012, Style.Cream, 57)
				s.Position = UDim2.fromScale((b.x + hx) / 2, (b.y + hy) / 2)
				task.delay(0.2, function()
					s:Destroy()
				end)
			end
		end
		RunService.RenderStepped:Wait()
	end
	for _, c in conns do
		c:Disconnect()
	end
	holder:Destroy()
	return { hits = hits, grazes = grazes }
end

return DodgeBox
