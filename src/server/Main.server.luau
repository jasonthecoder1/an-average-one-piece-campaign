-- Server entry (step 1): every player who joins gets a solo test fight against one enemy.
local Players = game:GetService("Players")
local Remotes = require(script.Parent.Remotes)
local BattleService = require(script.Parent.BattleService)

local function testFight(player)
	local member = { player = player, userId = player.UserId, name = player.DisplayName, classId = "Warrior", race = "Human", haki = "Armament", role = "Captain", hpFrac = 1, bounty = 0 }
	local run = { members = { member }, sea = 1, roleHolders = { Captain = member } }
	local result = BattleService.fight(run, { "MarineRecruit" }, { kind = "Fight" })
	Remotes.toast(player, if result.won then "You won! Respawning a new fight in 5 s." else "You lost! Try again in 5 s.")
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Once(function()
		task.wait(2)
		while player.Parent do
			testFight(player)
			task.wait(5)
		end
	end)
end)
