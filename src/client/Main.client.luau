-- Client entry: hooks up every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Kit = require(script.Parent.Kit)
local BattleUI = require(script.Parent.BattleUI)
local MapUI = require(script.Parent.MapUI)
local ShipUI = require(script.Parent.ShipUI)
local LobbyUI = require(script.Parent.LobbyUI)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function blocked()
	return BattleUI.active() or LobbyUI.active()
end

BattleUI.init()
MapUI.blocked = blocked
ShipUI.blocked = blocked
ShipUI.openChart = MapUI.open
MapUI.init()
ShipUI.init()
LobbyUI.init()

-- hide the ship HUDs while a fight (or another full screen) is up
task.spawn(function()
	local last = nil
	while true do
		local b = blocked()
		if b ~= last then
			last = b
			MapUI.setHudVisible(not b)
			ShipUI.setHudVisible(not b)
			if b then
				MapUI.close()
			end
		end
		task.wait(0.25)
	end
end)

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
