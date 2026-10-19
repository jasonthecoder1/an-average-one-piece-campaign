-- The lobby is a MENU (no walking): make a party of 1 to 6, roll race + Haki (kept between runs, rerollable for
-- Robux), pick a class and a role. One of each role per crew: Ready stays locked while two players share a role,
-- and even the Captain's Force Ready can't skip that. NPCs fill the empty roles.
-- The whole server is the party (set the server size to 6 in Game Settings).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage.Shared
local CrewDefs = require(Shared.CrewDefs)
local ClassDefs = require(Shared.ClassDefs)
local Config = require(Shared.Config)
local Remotes = require(script.Parent.Remotes)
local Run = require(script.Parent.Run)

local LobbyService = {}
LobbyService.onJoin = nil -- function(player): a late joiner hopped into a sailing run

local profiles = {} -- [Player] = { race, haki, classId, role, ready, bestBounty, joinedAt }
local rng = Random.new()
local forced = false

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function load(player)
	local data = nil
	if store then
		local ok, res = pcall(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		if ok then
			data = res
		end
	end
	data = type(data) == "table" and data or {}
	return {
		race = if CrewDefs.find(CrewDefs.Races, data.race) then data.race else CrewDefs.roll(CrewDefs.Races, rng),
		haki = if CrewDefs.find(CrewDefs.Haki, data.haki) then data.haki else CrewDefs.roll(CrewDefs.Haki, rng),
		classId = if ClassDefs.Classes[data.classId] then data.classId else "Warrior",
		bestBounty = tonumber(data.bestBounty) or 0,
		role = nil,
		ready = false,
		joinedAt = os.clock(),
	}
end

local function save(player)
	local p = profiles[player]
	if not p or not store then
		return
	end
	pcall(function()
		store:SetAsync("u" .. player.UserId, { race = p.race, haki = p.haki, classId = p.classId, bestBounty = p.bestBounty })
	end)
end

-- party = the first 6 players (by join time)
local function party()
	local list = {}
	for plr, p in profiles do
		if plr.Parent then
			table.insert(list, { player = plr, p = p })
		end
	end
	table.sort(list, function(a, b)
		return a.p.joinedAt < b.p.joinedAt
	end)
	while #list > Config.PartyMax do
		table.remove(list)
	end
	return list
end

local function captainOf(list)
	for _, e in list do
		if e.p.role == "Captain" then
			return e.player
		end
	end
	return nil
end

local function problems(list)
	local seen, dups, missing = {}, {}, {}
	for _, e in list do
		if not e.p.role then
			table.insert(missing, e.player.DisplayName)
		elseif seen[e.p.role] then
			dups[e.p.role] = true
		else
			seen[e.p.role] = true
		end
	end
	local dupList = {}
	for r in dups do
		table.insert(dupList, r)
	end
	return dupList, missing
end

function LobbyService.broadcast()
	local list = party()
	local dups, missing = problems(list)
	local runActive = Run.current ~= nil and Run.current.active
	local crew = {}
	for _, e in list do
		table.insert(crew, {
			userId = e.player.UserId, name = e.player.DisplayName, race = e.p.race, haki = e.p.haki, classId = e.p.classId,
			role = e.p.role, ready = e.p.ready, bestBounty = e.p.bestBounty, inRun = runActive and Run.memberOf(Run.current, e.player) ~= nil,
		})
	end
	local cap = captainOf(list)
	local board = {}
	for plr, p in profiles do
		if plr.Parent then
			table.insert(board, { name = plr.DisplayName, bounty = p.bestBounty })
		end
	end
	table.sort(board, function(a, b)
		return a.bounty > b.bounty
	end)
	local free = RunService:IsStudio()
	for plr, p in profiles do
		if plr.Parent then
			Remotes.Lobby:FireClient(plr, "lobby", {
				crew = crew, you = { race = p.race, haki = p.haki, classId = p.classId, role = p.role, ready = p.ready },
				captainId = cap and cap.UserId, dups = dups, missing = missing, runActive = runActive,
				inRun = runActive and Run.memberOf(Run.current, plr) ~= nil, board = board,
				rerollRace = Config.RerollRaceProduct ~= 0 or free, rerollHaki = Config.RerollHakiProduct ~= 0 or free, freeRerolls = free and Config.RerollRaceProduct == 0,
			})
		end
	end
end

local function freeze(player, on)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = on
	end
end

local function tryStart()
	local list = party()
	if #list == 0 or (Run.current and Run.current.active) then
		return
	end
	local dups, missing = problems(list)
	if #dups > 0 or #missing > 0 then
		return
	end
	local all = true
	for _, e in list do
		if not e.p.ready then
			all = false
		end
	end
	if not all and not forced then
		return
	end
	forced = false
	local members = {}
	for _, e in list do
		e.p.ready = false
		table.insert(members, { player = e.player, userId = e.player.UserId, name = e.player.DisplayName, classId = e.p.classId, race = e.p.race, haki = e.p.haki, role = e.p.role })
		freeze(e.player, false)
		save(e.player)
	end
	for _, e in list do
		Remotes.Lobby:FireClient(e.player, "close")
	end
	Run.start(members)
	LobbyService.broadcast()
end

local function reroll(player, what)
	local p = profiles[player]
	if not p then
		return
	end
	if what == "race" then
		local old = p.race
		for _ = 1, 10 do
			p.race = CrewDefs.roll(CrewDefs.Races, rng)
			if p.race ~= old then
				break
			end
		end
	else
		local old = p.haki
		for _ = 1, 10 do
			p.haki = CrewDefs.roll(CrewDefs.Haki, rng)
			if p.haki ~= old then
				break
			end
		end
	end
	local def = CrewDefs.find(if what == "race" then CrewDefs.Races else CrewDefs.Haki, if what == "race" then p.race else p.haki)
	Remotes.Lobby:FireClient(player, "rolled", { what = what, id = def.id, name = def.name, rare = def.rare })
	save(player)
	LobbyService.broadcast()
end

Remotes.Lobby.OnServerEvent:Connect(function(player, msg, data)
	local p = profiles[player]
	if not p then
		return
	end
	local inRun = Run.current and Run.current.active and Run.memberOf(Run.current, player)
	if msg == "class" and type(data) == "string" and ClassDefs.Classes[data] and not inRun then
		p.classId = data
		p.ready = false
	elseif msg == "role" and type(data) == "string" and CrewDefs.find(CrewDefs.Roles, data) and not inRun then
		p.role = data
		p.ready = false
	elseif msg == "ready" and not inRun then
		local dups, missing = problems(party())
		if p.ready then
			p.ready = false
		elseif #dups == 0 and #missing == 0 then
			p.ready = true
		else
			Remotes.toast(player, "Every crewmate needs a different role before you can Ready.")
		end
		tryStart()
	elseif msg == "force" and not inRun then
		if captainOf(party()) == player then
			local dups, missing = problems(party())
			if #dups > 0 or #missing > 0 then
				Remotes.toast(player, "Even the Captain can't sail with two of the same role (or someone without a role).")
			else
				forced = true
				tryStart()
			end
		end
	elseif msg == "reroll" and (data == "race" or data == "haki") then
		local product = if data == "race" then Config.RerollRaceProduct else Config.RerollHakiProduct
		if product ~= 0 then
			MarketplaceService:PromptProductPurchase(player, product)
		elseif RunService:IsStudio() then
			reroll(player, data) -- free while testing in Studio
		end
		return
	elseif msg == "hello" then
		if not inRun then
			freeze(player, true)
			Remotes.Lobby:FireClient(player, "open")
		end
	elseif msg == "join" and Run.current and Run.current.active and not inRun then
		-- join a run that's already sailing (if the crew has room)
		if #Run.members(Run.current) < Config.PartyMax then
			-- close the lobby first, so the chart that addMember broadcasts isn't blocked by the lobby screen
			Remotes.Lobby:FireClient(player, "close")
			freeze(player, false)
			Run.addMember(Run.current, { player = player, userId = player.UserId, name = player.DisplayName, classId = p.classId, race = p.race, haki = p.haki, role = p.role })
			if LobbyService.onJoin then
				LobbyService.onJoin(player)
			end
		end
	end
	LobbyService.broadcast()
end)

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player or not profiles[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if info.ProductId == Config.RerollRaceProduct then
		reroll(player, "race")
	elseif info.ProductId == Config.RerollHakiProduct then
		reroll(player, "haki")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- back to the lobby after a run
function LobbyService.open(run)
	for _, m in run.members do
		local p = profiles[m.player]
		if p then
			p.bestBounty = math.max(p.bestBounty, m.bounty or 0)
			p.ready = false
			save(m.player)
		end
	end
	for plr in profiles do
		if plr.Parent then
			freeze(plr, true)
			Remotes.Lobby:FireClient(plr, "open")
		end
	end
	LobbyService.broadcast()
end

local function onCharacter(player, ch)
	local inRun = Run.current and Run.current.active and Run.memberOf(Run.current, player)
	if not inRun then
		local root = ch:WaitForChild("HumanoidRootPart", 5)
		if root then
			task.wait()
			root.Anchored = true -- the lobby is a menu: no walking
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	-- connect first: loading the save can take a moment and the character may spawn meanwhile
	player.CharacterAdded:Connect(function(ch)
		onCharacter(player, ch)
	end)
	local profile = load(player)
	if not player.Parent then
		return
	end
	profiles[player] = profile
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	-- the client's "hello" may have come in while we were loading: open the lobby now (a 2nd "open" is harmless)
	local inRun = Run.current and Run.current.active and Run.memberOf(Run.current, player)
	if not inRun then
		freeze(player, true)
		Remotes.Lobby:FireClient(player, "open")
	end
	LobbyService.broadcast()
end)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	profiles[player] = nil
	LobbyService.broadcast()
end)

game:BindToClose(function()
	for plr in profiles do
		save(plr)
	end
end)

return LobbyService
