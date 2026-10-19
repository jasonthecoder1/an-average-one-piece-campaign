-- Makes the RemoteEvents in ReplicatedStorage.Remotes. One remote per system; the first argument is the message name.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}
local NAMES = { "Battle", "Map", "Lobby", "Ship", "Toast" }

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end
for _, name in NAMES do
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	Remotes[name] = r
end

-- Small helper: a short message box on one player's screen (or everyone's when player is nil).
function Remotes.toast(player, text)
	if player then
		Remotes.Toast:FireClient(player, text)
	else
		Remotes.Toast:FireAllClients(text)
	end
end

return Remotes
