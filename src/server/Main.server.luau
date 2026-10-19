-- Server entry (step 3): everyone in the server is one crew and sails the sea chart.
-- (Step 5 replaces the auto crew with the lobby menu.)
local Players = game:GetService("Players")
local Run = require(script.Parent.Run)

local CLASSES = { "Warrior", "Assassin" }
local ROLES = { "Captain", "Navigator", "Cook", "Doctor", "Musician", "Archaeologist" }

local function memberFor(player, i)
	return { player = player, userId = player.UserId, name = player.DisplayName, classId = CLASSES[(i - 1) % 2 + 1], race = "Human", haki = "Armament", role = ROLES[math.min(i, 6)] }
end

local function startRun()
	local list = {}
	for i, p in Players:GetPlayers() do
		table.insert(list, memberFor(p, i))
	end
	if #list > 0 then
		Run.start(list)
	end
end

Run.onEnd = function()
	task.wait(2)
	startRun()
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Wait()
	task.wait(1)
	if Run.current and Run.current.active then
		Run.addMember(Run.current, memberFor(player, #Run.members(Run.current) + 1))
	elseif not Run.current then
		startRun()
	end
end)
