-- Client entry: hooks up every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Kit = require(script.Parent.Kit)
local BattleUI = require(script.Parent.BattleUI)
local MapUI = require(script.Parent.MapUI)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
BattleUI.init()
MapUI.blocked = BattleUI.active
MapUI.init()

-- toasts: a short message panel at the top of the screen
local toastGui = Kit.screen("Toasts", 50, Players.LocalPlayer:WaitForChild("PlayerGui"))
local stack = 0
remotes:WaitForChild("Toast").OnClientEvent:Connect(function(text)
	stack += 1
	local p = Kit.panel({ Size = UDim2.fromOffset(560, 56), Position = UDim2.new(0.5, 0, 0, 60 + (stack - 1) * 66), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 90, Parent = toastGui, Rotation = -1 })
	Kit.label({ Text = text, Font = Kit.Style.Body, TextSize = 17, Wrap = true, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), ZIndex = 92, Parent = p })
	task.delay(4, function()
		p:Destroy()
		stack -= 1
	end)
end)
