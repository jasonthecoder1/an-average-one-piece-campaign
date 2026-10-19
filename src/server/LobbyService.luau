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

local profiles = {} -- [Player] = { race, haki, classId, role, ready, bestBounty, joinedAt, receipts, noSave }
local rng = Random.new()

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function load(player)
	local data = nil
	local loaded = true
	if store then
		-- try 3 times (wait 1 s, then 2 s): a short DataStore hiccup shouldn't cost anyone their save
		loaded = false
		for attempt = 1, 3 do
			local ok, res = pcall(function()
				return store:GetAsync("u" .. player.UserId)
			end)
			if ok then
				data, loaded = res, true
				break
			end
			if attempt == 3 or not player.Parent then
				break -- out of tries (or they already left)
			end
			task.wait(attempt)
		end
	end
	data = type(data) == "table" and data or {}
	-- purchase ids of rerolls already given (so a repeated receipt never rerolls twice)
	local receipts = {}
	if type(data.receipts) == "table" then
		for _, id in data.receipts do
			if type(id) == "string" then
				table.insert(receipts, id)
			end
		end
	end
	return {
		race = if CrewDefs.find(CrewDefs.Races, data.race) then data.race else CrewDefs.roll(CrewDefs.Races, rng),
		haki = if CrewDefs.find(CrewDefs.Haki, data.haki) then data.haki else CrewDefs.roll(CrewDefs.Haki, rng),
		classId = if ClassDefs.Classes[data.classId] then data.classId else "Warrior",
		bestBounty = tonumber(data.bestBounty) or 0,
		receipts = receipts,
		noSave = not loaded, -- the save couldn't be read: never write these stand-in rolls over it
		role = nil,
		ready = false,
		joinedAt = os.clock(),
	}
end

-- returns true when the record was written
local function save(player)
	local p = profiles[player]
	if not p or not store or p.noSave then
		return false
	end
	local ok = pcall(function()
		store:SetAsync("u" .. player.UserId, { race = p.race, haki = p.haki, classId = p.classId, bestBounty = p.bestBounty, receipts = p.receipts })
	end)
	return ok
end

-- copy a sailing player's run bounty onto their Bounty Board record (m = their run member, if known)
local function keepBounty(player, m)
	local p = profiles[player]
	m = m or (Run.current and Run.memberOf(Run.current, player))
	if p and m then
		p.bestBounty = math.max(p.bestBounty, tonumber(m.bounty) or 0)
	end
end
-- Run calls this before it drops a leaving crewmate (the two PlayerRemoving handlers can run in either order)
Run.onLeave = function(_, m)
	keepBounty(m.player, m)
end

-- spam guard: each player gets at most 10 messages a second, the rest are ignored
local msgCount = {} -- [Player] = { t = when this second started, n = messages in it }
local function spam(player)
	local now = os.clock()
	local c = msgCount[player]
	if not c or now - c.t >= 1 then
		msgCount[player] = { t = now, n = 1 }
		return false
	end
	c.n += 1
	return c.n > 10
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
				-- no rerolls for a player whose save didn't load (the new roll couldn't be kept)
				rerollRace = (Config.RerollRaceProduct ~= 0 or free) and not p.noSave, rerollHaki = (Config.RerollHakiProduct ~= 0 or free) and not p.noSave, freeRerolls = free and Config.RerollRaceProduct == 0,
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

-- force = the Captain's Force Ready (skips "everyone Ready", never the one-of-each-role rule)
local function tryStart(force)
	local list = party()
	-- a run is still going (or on its end screen): nothing starts until it has fully ended
	if #list == 0 or Run.current ~= nil then
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
	if not all and not force then
		return
	end
	-- nothing from the checks to Run.start may wait (a save would let a 2nd click or a role change slip in)
	local members = {}
	for _, e in list do
		e.p.ready = false
		table.insert(members, { player = e.player, userId = e.player.UserId, name = e.player.DisplayName, classId = e.p.classId, race = e.p.race, haki = e.p.haki, role = e.p.role })
		freeze(e.player, false)
	end
	for _, e in list do
		Remotes.Lobby:FireClient(e.player, "close")
	end
	Run.start(members)
	LobbyService.broadcast()
	for _, e in list do
		task.spawn(save, e.player)
	end
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
	LobbyService.broadcast()
end

Remotes.Lobby.OnServerEvent:Connect(function(player, msg, data)
	if spam(player) then
		return
	end
	local p = profiles[player]
	if not p then
		return
	end
	-- a run member stays locked until their run has fully ended (its end screen counts too)
	local inRun = Run.current and Run.memberOf(Run.current, player)
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
		tryStart(false)
	elseif msg == "force" and not inRun then
		-- ignored while any run exists (tryStart would refuse it anyway)
		if captainOf(party()) == player and Run.current == nil then
			local dups, missing = problems(party())
			if #dups > 0 or #missing > 0 then
				Remotes.toast(player, "Even the Captain can't sail with two of the same role (or someone without a role).")
			else
				tryStart(true)
			end
		end
	elseif msg == "reroll" and (data == "race" or data == "haki") then
		-- their real save never loaded: a paid reroll couldn't be kept, so don't sell one
		if p.noSave then
			Remotes.toast(player, "Your save didn't load, so rerolls are off until you rejoin.")
			return
		end
		local product = if data == "race" then Config.RerollRaceProduct else Config.RerollHakiProduct
		if product ~= 0 then
			MarketplaceService:PromptProductPurchase(player, product)
		elseif RunService:IsStudio() then
			reroll(player, data) -- free while testing in Studio
			save(player)
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
	else
		return -- unknown or bad message: nothing changed, so no broadcast
	end
	LobbyService.broadcast()
end)

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local p = player and profiles[player]
	-- not loaded yet, or their save didn't load (we couldn't keep the reroll): Roblox asks again later
	if not p or p.noSave then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local what = if info.ProductId == Config.RerollRaceProduct then "race" elseif info.ProductId == Config.RerollHakiProduct then "haki" else nil
	if what and not table.find(p.receipts, info.PurchaseId) then
		-- each receipt rerolls once; a retry of the same receipt only tries the save again
		reroll(player, what)
		table.insert(p.receipts, info.PurchaseId)
		while #p.receipts > 50 do
			table.remove(p.receipts, 1)
		end
	end
	if what and not save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- only granted once the reroll is really saved
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- back to the lobby after a run
function LobbyService.open(run)
	-- no waiting in here until the lobby is open (a save would let a new run start halfway through)
	for _, m in run.members do
		local p = profiles[m.player]
		if p then
			p.bestBounty = math.max(p.bestBounty, m.bounty or 0)
			p.ready = false
		end
	end
	local cur = Run.current
	for plr in profiles do
		-- never pull a player out of a run that's sailing
		if plr.Parent and not (cur and cur.active and Run.memberOf(cur, plr)) then
			freeze(plr, true)
			Remotes.Lobby:FireClient(plr, "open")
		end
	end
	LobbyService.broadcast()
	for _, m in run.members do
		if profiles[m.player] then
			task.spawn(save, m.player)
		end
	end
end

local function onCharacter(player, ch)
	local inRun = Run.current and Run.current.active and Run.memberOf(Run.current, player)
	if not inRun then
		local root = ch:WaitForChild("HumanoidRootPart", 5)
		if root then
			task.wait()
			-- check again after the wait: they may have joined the crew meanwhile
			if not (Run.current and Run.current.active and Run.memberOf(Run.current, player)) then
				root.Anchored = true -- the lobby is a menu: no walking
			end
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
	if profile.noSave then
		Remotes.toast(player, "Your save didn't load, so nothing will be saved this time. Rejoin later to get it back.")
	end
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
	msgCount[player] = nil
	keepBounty(player) -- a bounty from a run still going (or on its end screen) counts too
	save(player)
	profiles[player] = nil
	LobbyService.broadcast()
end)

game:BindToClose(function()
	for plr in profiles do
		keepBounty(plr)
		save(plr)
	end
end)

return LobbyService
