-- Server entry (step 2): everyone in the server is one crew. A random enemy group is fought, then another.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleDefs = require(ReplicatedStorage.Shared.BattleDefs)
local Remotes = require(script.Parent.Remotes)
local BattleService = require(script.Parent.BattleService)

local CLASSES = { "Warrior", "Assassin" }
local ROLES = { "Captain", "Navigator", "Cook", "Doctor", "Musician", "Archaeologist" }
local members = {}

Players.PlayerAdded:Connect(function(player)
	local i = #members + 1
	members[player] = { player = player, userId = player.UserId, name = player.DisplayName, classId = CLASSES[(i - 1) % 2 + 1], race = "Human", haki = "Armament", role = ROLES[math.min(i, 6)], hpFrac = 1, bounty = 0 }
end)
Players.PlayerRemoving:Connect(function(player)
	members[player] = nil
end)

task.spawn(function()
	local rng = Random.new()
	local fights = 0
	while true do
		task.wait(3)
		local list, holders = {}, {}
		for p, m in members do
			if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				table.insert(list, m)
				holders[m.role] = m
			end
		end
		if #list > 0 then
			for _, r in ROLES do
				holders[r] = holders[r] or "npc"
			end
			fights += 1
			local kind = if fights % 3 == 0 then "Elite" else "Fight"
			local run = { members = list, sea = 1, roleHolders = holders }
			local result = BattleService.fight(run, BattleDefs.buildEncounter(kind, 1, #list, rng), { kind = kind })
			if not result.won then
				for _, m in list do
					m.hpFrac = 1
				end
			end
			Remotes.toast(nil, if result.won then "Victory! Next fight soon." else "Defeated! Healing up for another try.")
		end
	end
end)
