-- One run = one trip across the 3 seas. Holds the crew, gold, the crew bag, the sea chart and the loop:
--   SHIP (walk, craft, Ready at the map table) -> VOTE on the chart -> play the STOP -> Cook's meal -> SHIP ...
-- Boss beaten = huge power-up + the next sea's chart. Sea 3 boss (an Emperor) = PIRATE KING. Crew wiped = run over.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MapDefs = require(Shared.MapDefs)
local BattleDefs = require(Shared.BattleDefs)
local CrewDefs = require(Shared.CrewDefs)
local EventDefs = require(Shared.EventDefs)
local Remotes = require(script.Parent.Remotes)
local BattleService = require(script.Parent.BattleService)

local Run = {}
Run.current = nil
Run.onShip = nil -- function(run): put the crew on the ship (set by ShipService)
Run.onEnd = nil -- function(run, won): back to the lobby (set by LobbyService)
Run.onChanged = nil -- function(run): bag / gold changed (ShipService refreshes its screens)
Run.onLeave = nil -- function(run, m): a crewmate is leaving the server (LobbyService keeps their bounty)

local READY_WAIT = 60 -- once half the crew is Ready, the rest get this many seconds

local ROLE_IDS = {}
for _, r in CrewDefs.Roles do
	table.insert(ROLE_IDS, r.id)
end

local function members(run)
	local list = {}
	for _, m in run.members do
		if m.player and m.player.Parent then
			table.insert(list, m)
		end
	end
	return list
end
Run.members = members

local function memberOf(run, player)
	for _, m in run.members do
		if m.player == player then
			return m
		end
	end
	return nil
end
Run.memberOf = memberOf

local function captain(run)
	local h = run.roleHolders.Captain
	if h and h ~= "npc" and h.player and h.player.Parent then
		return h
	end
	return nil
end

local function refreshRoles(run)
	run.roleHolders = {}
	for _, m in members(run) do
		if m.role and not run.roleHolders[m.role] then
			run.roleHolders[m.role] = m
		end
	end
	for _, id in ROLE_IDS do
		run.roleHolders[id] = run.roleHolders[id] or "npc" -- NPCs fill the empty roles
	end
end

-- ===== sending the chart =====

local function chartFor(run, m)
	local nav = run.roleHolders.Navigator
	local isNav = nav ~= "npc" and nav == m
	local readyIds = {}
	for uid in run.ready do
		table.insert(readyIds, uid)
	end
	local votes = {}
	for uid, nodeId in run.votes do
		votes[tostring(uid)] = nodeId
	end
	local crew = {}
	for _, x in members(run) do
		table.insert(crew, { userId = x.userId, name = x.name, role = x.role, classId = x.classId, hpFrac = x.hpFrac, bounty = x.bounty })
	end
	local cap = captain(run)
	return {
		view = MapDefs.publicView(run.map, isNav), at = run.at, visited = run.visited, state = run.state,
		options = run.map.nodes[run.at].next, ready = readyIds, votes = votes, deadline = run.voteDeadline and (run.voteDeadline - os.clock()) or nil,
		readyDeadline = run.readyDeadline and (run.readyDeadline - os.clock()) or nil, -- seconds until the ship sails anyway
		captainId = cap and cap.userId, navigator = isNav, gold = run.gold, sea = run.sea, seaName = BattleDefs.Seas[run.sea].name,
		crew = crew, power = run.power, bag = run.bag,
	}
end

function Run.broadcast(run)
	for _, m in members(run) do
		Remotes.Map:FireClient(m.player, "chart", chartFor(run, m))
	end
	if Run.onChanged then
		Run.onChanged(run)
	end
end

-- ===== bag and gold =====

function Run.addLoot(run, loot)
	for item, n in loot do
		run.bag[item] = math.max(0, (run.bag[item] or 0) + n)
		if run.bag[item] == 0 then
			run.bag[item] = nil
		end
	end
end

local function healAll(run, frac)
	for _, m in members(run) do
		m.hpFrac = math.clamp((m.hpFrac or 1) + frac, 0.05, 1)
	end
end

-- ===== cards (events, ports, allied crews): the Captain decides (or the first player if the Captain is an NPC) =====

local function canAfford(run, choice)
	if choice.cost and run.gold < choice.cost then
		return false
	end
	if choice.needs then
		for item, n in choice.needs do
			if (run.bag[item] or 0) < n then
				return false
			end
		end
	end
	return true
end

function Run.card(run, card)
	local list = members(run)
	if #list == 0 then
		return
	end
	local decider = captain(run) or list[1]
	run.cardDeciderId = decider.userId -- fixed for this card, even if a late joiner becomes Captain meanwhile
	run.cardToken = (run.cardToken or 0) + 1
	local token = run.cardToken
	local choices = {}
	for i, c in card.choices do
		choices[i] = { label = c.label, ok = canAfford(run, c) }
	end
	run.cardReply = nil
	for _, m in list do
		Remotes.Map:FireClient(m.player, "card", { token = token, title = card.title, text = card.text, choices = choices, deciderId = decider.userId, deciderName = decider.name })
	end
	local deadline = os.clock() + 40
	while os.clock() < deadline and run.cardReply == nil and decider.player.Parent do
		task.wait(0.1)
	end
	local idx = run.cardReply
	if type(idx) ~= "number" or not card.choices[idx] or not canAfford(run, card.choices[idx]) then
		idx = #card.choices -- the last choice is always the safe one
	end
	local choice = card.choices[idx]
	local res = choice.result
	local text = res.say or ""
	local fight = nil
	-- chance: the main result happens with this chance, else `fail` (or nothing)
	local hit = res.chance == nil or Random.new():NextNumber() < res.chance
	if res.fight then
		-- fights with a chance: the gold/loot always comes, the fight only on a hit
		if res.gold then
			run.gold = math.max(0, run.gold + res.gold)
		end
		if res.loot then
			Run.addLoot(run, res.loot)
		end
		if hit then
			fight = res.fight
		else
			text = res.failSay or text
		end
	elseif hit then
		if res.gold then
			run.gold = math.max(0, run.gold + res.gold)
		end
		if res.loot then
			Run.addLoot(run, res.loot)
		end
		if res.heal then
			healAll(run, res.heal)
		end
		if res.hurt then
			healAll(run, -res.hurt)
		end
	elseif res.fail then
		text = res.fail.say or ""
		if res.fail.hurt then
			healAll(run, -res.fail.hurt)
		end
	end
	for _, m in members(run) do
		Remotes.Map:FireClient(m.player, "cardResult", { token = token, choice = choice.label, text = text, by = decider.name })
	end
	Run.broadcast(run)
	task.wait(2.5)
	return fight
end

-- ===== stops =====

local function fight(run, enemies, kind, title)
	-- the Cook's meal + the Musician's shanty, both used up by this fight
	local bonus = (run.cookBonus or 0) + (run.mealBonus or 0)
	local opts = { kind = kind, title = title, mealBonus = if bonus > 0 then bonus else nil, power = run.power }
	run.cookBonus = nil
	run.mealBonus = nil
	for _, m in members(run) do
		Remotes.Map:FireClient(m.player, "close")
	end
	local result = BattleService.fight(run, enemies, opts)
	if result.won then
		run.gold += result.gold
		Run.addLoot(run, result.loot)
	end
	return result.won
end

local function playStop(run, node)
	local t = node.type
	if t == "Fight" or t == "Elite" then
		return fight(run, node.enemies, t)
	elseif t == "Boss" then
		local won = fight(run, node.enemies, "Boss")
		if won then
			run.power += 1
			healAll(run, 1)
			if run.sea >= 3 then
				run.pirateKing = true
			else
				Remotes.toast(nil, "SEA CLEARED! Huge power-up: crew +15% health and damage. Next: " .. BattleDefs.Seas[run.sea + 1].name .. "!")
				run.sea += 1
				run.map = MapDefs.generate(run.rng:NextInteger(1, 2 ^ 30), run.sea, #members(run))
				run.at = run.map.start
				run.visited = { run.at }
			end
		end
		return won
	elseif t == "Camp" then
		if node.ambush then
			Remotes.toast(nil, "A Marine ship found your camp! Fight!")
			if not fight(run, BattleDefs.buildEncounter("Fight", run.sea, #members(run), run.rng), "Fight", "AMBUSH") then
				return false
			end
		end
		healAll(run, 0.4)
		Remotes.toast(nil, "You rest in a quiet cove. Everyone heals 40%.")
		return true
	elseif t == "Treasure" then
		local arch = run.roleHolders.Archaeologist
		local mult = if arch == "npc" then 1.125 else 1.25
		local gold = math.floor((node.gold or 30) * mult)
		run.gold += gold
		local mats = { "Driftwood", "Iron Plate", "Cloth Strip" }
		local loot = { [mats[run.rng:NextInteger(1, 3)]] = 2 }
		Run.addLoot(run, loot)
		Remotes.toast(nil, "Treasure! +" .. gold .. " gold and materials.")
		return true
	end
	local card
	if t == "Port" then
		card = EventDefs.Port
	elseif t == "Allied" then
		card = EventDefs.Allied
	else
		card = EventDefs.Events[(node.event or 1) % #EventDefs.Events + 1]
	end
	local f = Run.card(run, card)
	if f then
		return fight(run, f, "Fight")
	end
	return true
end

-- ===== the loop =====

local function crewToast(run, text)
	for _, m in members(run) do
		Remotes.toast(m.player, text)
	end
end

local function waitReady(run)
	run.state = "ship"
	run.ready = {}
	run.forced = false
	run.votes = {}
	run.voteDeadline = nil
	run.readyDeadline = nil
	Run.broadcast(run)
	local announced, warned = false, false -- the "sails in 60" toast only once per visit (Ready on/off can't spam it)
	while true do
		local list = members(run)
		if #list == 0 then
			run.readyDeadline = nil
			return false
		end
		local n = 0
		for _, m in list do
			if run.ready[m.userId] then
				n += 1
			end
		end
		if n == #list or run.forced then
			run.readyDeadline = nil
			return true
		end
		-- one AFK crewmate (or no player Captain to Force) can't hold the ship forever:
		-- once half the crew is Ready a countdown starts, and when it ends the ship sails anyway
		if n >= math.ceil(#list / 2) and not run.readyDeadline then
			run.readyDeadline = os.clock() + READY_WAIT
			if not announced then
				announced = true
				crewToast(run, "Half the crew is Ready! The ship sails in " .. READY_WAIT .. " seconds.")
			end
			Run.broadcast(run)
		elseif n == 0 and run.readyDeadline then
			run.readyDeadline = nil -- everyone took their Ready back: stop the countdown
			warned = false
			Run.broadcast(run)
		end
		if run.readyDeadline then
			local left = run.readyDeadline - os.clock()
			if left <= 0 then
				run.readyDeadline = nil
				crewToast(run, "Time's up! The ship sets sail.")
				return true
			elseif left <= 10 and not warned then
				warned = true
				crewToast(run, "The ship sails in 10 seconds! Press READY at the map table.")
			end
		end
		task.wait(0.2)
	end
end

local function vote(run)
	run.state = "vote"
	run.votes = {}
	run.voteDeadline = os.clock() + MapDefs.VoteSeconds
	Run.broadcast(run)
	local options = run.map.nodes[run.at].next
	while os.clock() < run.voteDeadline do
		local list = members(run)
		if #list == 0 then
			return nil
		end
		local all = true
		for _, m in list do
			if not run.votes[m.userId] then
				all = false
			end
		end
		if all then
			break
		end
		task.wait(0.2)
	end
	-- most votes wins; a tie goes to the Captain's pick
	local tally = {}
	for _, nodeId in run.votes do
		tally[nodeId] = (tally[nodeId] or 0) + 1
	end
	local best, bestN = {}, 0
	for _, id in options do
		local n = tally[id] or 0
		if n > bestN then
			best, bestN = { id }, n
		elseif n == bestN then
			table.insert(best, id)
		end
	end
	local cap = captain(run)
	local pick = best[run.rng:NextInteger(1, #best)]
	if #best > 1 and cap and run.votes[cap.userId] and table.find(best, run.votes[cap.userId]) then
		pick = run.votes[cap.userId]
		Remotes.toast(nil, "Tie! The Captain breaks it.")
	end
	run.voteDeadline = nil
	return pick
end

local function loop(run)
	while run.active do
		if Run.onShip then
			Run.onShip(run)
		end
		if not waitReady(run) then
			break
		end
		local pick = vote(run)
		if not pick then
			break
		end
		local node = run.map.nodes[pick]
		run.at = pick
		table.insert(run.visited, pick)
		run.state = "stop"
		Run.broadcast(run)
		local stop = MapDefs.Stops[node.type]
		Remotes.toast(nil, "Heading to: " .. stop.label .. "!")
		task.wait(1.5)
		local ok = playStop(run, node)
		if not ok then
			run.active = false
			run.lost = true
			break
		end
		if run.pirateKing then
			run.active = false
			break
		end
		-- the Cook's meal after every stop (its own field, so a Musician's shanty in run.mealBonus isn't wiped)
		local cook = run.roleHolders.Cook
		local s = if cook == "npc" then CrewDefs.NpcScale else 1
		healAll(run, 0.15 * s)
		run.cookBonus = 0.05 * s
		Remotes.toast(nil, (if cook == "npc" then "The NPC cook" else cook.name) .. " cooks a meal: crew heals " .. math.floor(15 * s) .. "% and hits harder next fight.")
	end
	run.active = false
	local won = run.pirateKing == true
	for _, m in members(run) do
		m.bestBounty = math.max(m.bestBounty or 0, m.bounty or 0)
		Remotes.Map:FireClient(m.player, "runEnd", { won = won, sea = run.sea, bounty = m.bounty, gold = run.gold })
	end
	task.wait(6)
	-- only the current run may send everyone back to the lobby (never open it over a newer run)
	if Run.current == run then
		Run.current = nil
		if Run.onEnd then
			Run.onEnd(run, won)
		end
	end
end

-- members: list of { player, userId, name, classId, race, haki, role } (from the lobby)
function Run.start(list)
	local run = {
		active = true, members = {}, sea = 1, gold = 0, bag = {}, power = 0, rng = Random.new(),
		ready = {}, votes = {}, state = "ship",
		departed = {}, -- [userId] = the member table of a crewmate who left (given back if they rejoin)
	}
	for _, m in list do
		m.hpFrac = 1
		m.bounty = 0 -- bounty resets every run (the best one is kept on the Bounty Board)
		table.insert(run.members, m)
	end
	refreshRoles(run)
	run.map = MapDefs.generate(run.rng:NextInteger(1, 2 ^ 30), 1, #run.members)
	run.at = run.map.start
	run.visited = { run.at }
	Run.current = run
	task.spawn(function()
		-- if the loop ever errors, free the lobby instead of leaving a dead run in Run.current forever
		local ok, err = pcall(loop, run)
		if not ok then
			warn("[Run] the run loop crashed: " .. tostring(err))
			run.active = false
			if Run.current == run then
				Run.current = nil
				if Run.onEnd then
					Run.onEnd(run, false)
				end
			end
		end
	end)
	return run
end

function Run.addMember(run, m)
	-- a crewmate who left and came back gets their HP, bounty and gear back (no free heal, no lost gear)
	local back = run.departed[m.userId]
	run.departed[m.userId] = nil
	if back then
		m.hpFrac, m.bounty = back.hpFrac or 1, back.bounty or 0
		m.items, m.gear, m.locker = back.items, back.gear, back.locker
	else
		m.hpFrac = 1
		m.bounty = m.bounty or 0
	end
	-- keep "one of each role": a late joiner whose role is taken gets a free one
	local taken = {}
	for _, x in members(run) do
		taken[x.role or ""] = true
	end
	if back and back.role and not taken[back.role] then
		m.role = back.role -- their old job, if nobody took it meanwhile
	elseif m.role == nil or taken[m.role] then
		m.role = nil
		for _, id in ROLE_IDS do
			if not taken[id] then
				m.role = id
				break
			end
		end
	end
	table.insert(run.members, m)
	refreshRoles(run)
	Run.broadcast(run)
end

-- ===== remote =====

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

Remotes.Map.OnServerEvent:Connect(function(player, msg, data)
	if spam(player) then
		return
	end
	local run = Run.current
	if not run or not run.active then
		return
	end
	local m = memberOf(run, player)
	if not m then
		return
	end
	if msg == "ready" and run.state == "ship" then
		run.ready[m.userId] = if run.ready[m.userId] then nil else true
		Run.broadcast(run)
	elseif msg == "force" and run.state == "ship" then
		local cap = captain(run)
		if cap == m and not run.forced then
			run.forced = true
			Remotes.toast(nil, m.name .. " (Captain) forces everyone to set sail!")
		end
	elseif msg == "vote" and run.state == "vote" and type(data) == "number" then
		-- only a new vote is stored and sent out
		if table.find(run.map.nodes[run.at].next, data) and run.votes[m.userId] ~= data then
			run.votes[m.userId] = data
			Run.broadcast(run)
		end
	elseif msg == "card" and type(data) == "table" and data.token == run.cardToken then
		if m.userId == run.cardDeciderId and type(data.index) == "number" then
			run.cardReply = math.floor(data.index)
		end
	elseif msg == "view" then
		Remotes.Map:FireClient(player, "chart", chartFor(run, m))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	msgCount[player] = nil
	local run = Run.current
	if run then
		for i, m in run.members do
			if m.player == player then
				if Run.onLeave then
					Run.onLeave(run, m)
				end
				run.departed[m.userId] = m -- kept in case they rejoin this run
				table.remove(run.members, i)
				break
			end
		end
		refreshRoles(run)
		run.ready[player.UserId] = nil
		run.votes[player.UserId] = nil
		if run.active then
			Run.broadcast(run)
		end
	end
end)

return Run
