-- UI kit in the owner's style (design page "Look and feel"):
--   black panels with thick cream outlines, a red jagged shadow behind every panel (a little tilted),
--   red halftone dots in the corners, red HP bars, cyan stamina bars, Bangers display font,
--   big comic stamps (CRIT!, PERFECT, ONE MORE!...).
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Style = require(ReplicatedStorage.Shared.Style)

local Kit = {}
Kit.Style = Style

function Kit.new(className, props, children)
	local inst = Instance.new(className)
	for k, v in props or {} do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end
local new = Kit.new

function Kit.stroke(parent, color, thickness)
	return new("UIStroke", { Color = color or Style.Cream, Thickness = thickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter, Parent = parent })
end

function Kit.textStroke(label, thickness)
	new("UIStroke", { Color = Style.Black, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = label })
end

-- A few red halftone dots in a corner of a panel.
function Kit.halftone(parent, corner)
	local holder = new("Frame", {
		Name = "Halftone",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(46, 30),
		AnchorPoint = if corner == "tl" then Vector2.new(0, 0) else Vector2.new(1, 1),
		Position = if corner == "tl" then UDim2.fromOffset(4, 4) else UDim2.new(1, -4, 1, -4),
		ZIndex = (parent.ZIndex or 1) + 1,
		Parent = parent,
	})
	for row = 0, 3 do
		for col = 0, 5 do
			-- fade toward the inside of the panel, like the page's masked dots
			local fade = if corner == "tl" then (row + col) / 8 else ((3 - row) + (5 - col)) / 8
			if fade < 0.85 then
				local d = new("Frame", {
					BackgroundColor3 = Style.Red,
					BackgroundTransparency = math.clamp(fade, 0, 0.8),
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(3, 3),
					Position = UDim2.fromOffset(col * 8, row * 8),
					ZIndex = holder.ZIndex,
					Parent = holder,
				})
				new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = d })
			end
		end
	end
	return holder
end

-- The red jagged shadow: a red frame offset down-right, tilted a touch.
function Kit.shadow(frame, offset, tilt)
	local sh = new("Frame", {
		Name = frame.Name .. "Shadow",
		BackgroundColor3 = Style.Red,
		BorderSizePixel = 0,
		AnchorPoint = frame.AnchorPoint,
		Size = frame.Size,
		Position = frame.Position + UDim2.fromOffset(offset or 6, offset or 6),
		Rotation = (frame.Rotation or 0) + (tilt or 1.2),
		ZIndex = math.max(0, frame.ZIndex - 1),
		Visible = frame.Visible,
		Parent = frame.Parent,
	})
	-- keep the shadow glued to the panel
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		sh.Visible = frame.Visible
	end)
	frame:GetPropertyChangedSignal("Position"):Connect(function()
		sh.Position = frame.Position + UDim2.fromOffset(offset or 6, offset or 6)
	end)
	frame:GetPropertyChangedSignal("Size"):Connect(function()
		sh.Size = frame.Size
	end)
	frame.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			sh:Destroy()
		end
	end)
	return sh
end

-- Black panel + cream outline + red jagged shadow + halftone corner.
--   opts: Name, Size, Position, AnchorPoint, Parent, ZIndex, Rotation, NoShadow, NoDots, Color, StrokeColor
function Kit.panel(opts)
	local f = new("Frame", {
		Name = opts.Name or "Panel",
		BackgroundColor3 = opts.Color or Style.Panel,
		BorderSizePixel = 0,
		Size = opts.Size,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		Rotation = opts.Rotation or 0,
		ZIndex = opts.ZIndex or 2,
		Parent = opts.Parent,
	})
	Kit.stroke(f, opts.StrokeColor or Style.Cream, opts.Thickness or 3)
	if not opts.NoShadow then
		Kit.shadow(f, opts.ShadowOffset or 6, opts.Tilt)
	end
	if not opts.NoDots then
		Kit.halftone(f, "br")
	end
	return f
end

-- A tab title that hangs off the top of a panel ("PARTY 4/6", "YOUR PIRATE"), skewed like the page.
function Kit.tab(parent, text, width)
	local t = new("Frame", {
		Name = "Tab",
		BackgroundColor3 = Style.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width or 180, 34),
		Position = UDim2.fromOffset(10, -26),
		Rotation = -1.5,
		ZIndex = parent.ZIndex + 2,
		Parent = parent,
	})
	Kit.stroke(t)
	Kit.label({ Text = text, Size = UDim2.fromScale(1, 1), Font = Style.Display, TextSize = 24, ZIndex = t.ZIndex + 1, Parent = t })
	return t
end

function Kit.label(opts)
	local l = new("TextLabel", {
		Name = opts.Name or "Label",
		BackgroundTransparency = 1,
		Text = opts.Text or "",
		Font = opts.Font or Style.Body,
		TextSize = opts.TextSize or 16,
		TextColor3 = opts.Color or Style.Cream,
		TextXAlignment = opts.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = opts.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = opts.Wrap or false,
		RichText = opts.Rich or false,
		Size = opts.Size or UDim2.fromScale(1, 1),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		ZIndex = opts.ZIndex or 3,
		Rotation = opts.Rotation or 0,
		Parent = opts.Parent,
	})
	if opts.Outline then
		Kit.textStroke(l, opts.Outline == true and 2 or opts.Outline)
	end
	return l
end

-- Skewed red button with cream outline and a black offset shadow (page `.btn`).
--   opts: Text, Size, Position, AnchorPoint, Parent, ZIndex, Color, TextSize, OnClick
function Kit.button(opts)
	local b = new("TextButton", {
		Name = opts.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = opts.Color or Style.Red,
		BorderSizePixel = 0,
		Text = "",
		Size = opts.Size or UDim2.fromOffset(160, 40),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		Rotation = opts.Rotation or -1,
		ZIndex = opts.ZIndex or 4,
		Parent = opts.Parent,
	})
	Kit.stroke(b, opts.StrokeColor or Style.Cream, 3)
	local sh = new("Frame", {
		Name = "Drop",
		BackgroundColor3 = Style.Black,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(4, 4),
		ZIndex = b.ZIndex - 1,
		Parent = b,
	})
	local lbl = Kit.label({ Name = "Text", Text = opts.Text or "", Font = Style.Display, TextSize = opts.TextSize or 24, ZIndex = b.ZIndex + 1, Parent = b, Outline = 1.5 })
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Disabled") then
			return
		end
		TweenService:Create(b, TweenInfo.new(0.08), { Size = (opts.Size or UDim2.fromOffset(160, 40)) + UDim2.fromOffset(6, 3) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.08), { Size = opts.Size or UDim2.fromOffset(160, 40) }):Play()
	end)
	if opts.OnClick then
		b.Activated:Connect(function()
			if not b:GetAttribute("Disabled") then
				opts.OnClick()
			end
		end)
	end
	sh.ZIndex = math.max(0, b.ZIndex - 1)
	return b, lbl
end

function Kit.setDisabled(button, disabled, normalColor)
	button:SetAttribute("Disabled", disabled)
	button.BackgroundColor3 = if disabled then Style.Dim else (normalColor or Style.Red)
	local t = button:FindFirstChild("Text")
	if t then
		t.TextColor3 = if disabled then Style.Muted else Style.Cream
	end
end

-- A slanted bar (red HP / cyan stamina): black trough, cream outline, colored fill.
--   returns frame, setter(fraction)
function Kit.bar(opts)
	local trough = new("Frame", {
		Name = opts.Name or "Bar",
		BackgroundColor3 = Style.Black,
		BorderSizePixel = 0,
		Size = opts.Size,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		ZIndex = opts.ZIndex or 3,
		ClipsDescendants = true,
		Parent = opts.Parent,
	})
	Kit.stroke(trough, Style.Cream, opts.Thickness or 1.5)
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundColor3 = opts.Color or Style.Red,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = trough.ZIndex + 1,
		Parent = trough,
	})
	local function set(frac, instant)
		frac = math.clamp(frac or 0, 0, 1)
		if instant then
			fill.Size = UDim2.fromScale(frac, 1)
		else
			TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(frac, 1) }):Play()
		end
	end
	return trough, set, fill
end

-- Square icon tile with red offset shadow (page `#tile`), with a big glyph text inside.
function Kit.tile(opts)
	local holder = new("Frame", {
		Name = opts.Name or "Tile",
		BackgroundTransparency = 1,
		Size = opts.Size or UDim2.fromOffset(44, 44),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		ZIndex = opts.ZIndex or 3,
		Parent = opts.Parent,
	})
	new("Frame", { Name = "Red", BackgroundColor3 = Style.Red, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(4, 4), Rotation = 4, ZIndex = holder.ZIndex, Parent = holder })
	local face = new("Frame", { Name = "Face", BackgroundColor3 = Color3.fromRGB(13, 13, 13), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Rotation = -3, ZIndex = holder.ZIndex + 1, Parent = holder })
	local st = Kit.stroke(face, opts.StrokeColor or Style.Cream, 2.5)
	local glyph = Kit.label({ Name = "Glyph", Text = opts.Glyph or "", Font = Style.Display, TextSize = opts.GlyphSize or 26, Color = opts.GlyphColor or Style.Cream, ZIndex = holder.ZIndex + 2, Parent = face })
	return holder, face, glyph, st
end

-- Big comic stamp in the middle of the screen: "CRIT!", "PERFECT", "ONE MORE!", "VICTORY"...
function Kit.stamp(gui, text, color, pos)
	local f = new("Frame", {
		Name = "Stamp",
		BackgroundColor3 = color or Style.Red,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos or UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(40 + #text * 22, 64),
		Rotation = -6,
		ZIndex = 80,
		Parent = gui,
	})
	Kit.stroke(f, Style.Cream, 4)
	local l = Kit.label({ Text = text, Font = Style.Display, TextSize = 52, ZIndex = 81, Parent = f, Outline = 2 })
	local scale = new("UIScale", { Scale = 2.2, Parent = f })
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.9, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			task.wait(0.27)
			f:Destroy()
		end
	end)
	return f
end

-- A full-screen ScreenGui.
function Kit.screen(name, order, parent)
	return new("ScreenGui", { Name = name, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = order or 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = parent })
end

-- Number formatting for bounties: 1250000 -> "1,250,000"
function Kit.commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- Shrinks a whole screen on small (phone) screens so the 6 crew cards and the command tiles still fit.
function Kit.autoScale(gui, designW, designH)
	local s = Instance.new("UIScale")
	s.Parent = gui
	local cam = workspace.CurrentCamera
	local function update()
		local v = cam.ViewportSize
		s.Scale = math.clamp(math.min(v.X / (designW or 1280), v.Y / (designH or 720)), 0.5, 1.15)
	end
	update()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return s
end

return Kit
