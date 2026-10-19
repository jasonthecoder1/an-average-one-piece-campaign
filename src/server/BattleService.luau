-- Turn-based fights. The server does ALL the math; players only send their move pick, their QTE result and their
-- dodge-box result, and every one of those is checked and clamped here (engine idea reused from NextLife).
--
-- BattleService.fight(run, enemyIds, opts) yields until the fight ends and returns
--   { won = bool, gold = number, loot = { [item] = n }, bounty = { [userId] = gained } }
--
-- run: { members = { member... }, sea = 1..3, buffs = {}, roleHolders = { Captain = member|"npc", ... } }
-- member: { player, userId, name, classId, race, haki, role, hpFrac (0..1), bounty }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BattleDefs = require(Shared.BattleDefs)
local ClassDefs = require(Shared.ClassDefs)
local CrewDefs = require(Shared.CrewDefs)
local ActionCommandDefs = require(Shared.ActionCommandDefs)
local Remotes = require(script.Parent.Remotes)
local Arena = require(script.Parent.Arena)
local ItemDefs = require(Shared.ItemDefs)

local BattleService = {}

local battleOf = {} -- [Player] = battle
local nextId = 0

local function send(battle, ...)
	for _, u in battle.crew do
		if u.player and u.player.Parent and not u.gone then
			Remotes.Battle:FireClient(u.player, ...)
		end
	end
end

local function sendTo(unit, ...)
	if unit.player and unit.player.Parent and not unit.gone then
		Remotes.Battle:FireClient(unit.player, ...)
	end
end

local function log(battle, text)
	send(battle, "log", text)
end

local function alive(u)
	return not u.dead and not u.gone and u.hp > 0
end

local function statusList(u)
	local out = {}
	for key, v in u.statuses do
		if v then
			local def = BattleDefs.Status[key]
			if def then
				local label = def.label
				if key == "poison" and type(v) == "table" then
					label = "POISON " .. v.turns
				end
				table.insert(out, label)
			end
		end
	end
	if u.rage and u.rage >= BattleDefs.RageMax then
		table.insert(out, "ENRAGED")
	end
	table.sort(out)
	return out
end

local function snapshot(battle)
	local crew, enemies = {}, {}
	for _, u in battle.crew do
		table.insert(crew, {
			uid = u.uid, name = u.name, classId = u.classId, role = u.role, userId = u.userId, slot = u.slot,
			hp = u.hp, maxHp = u.maxHp, stamina = u.stamina, maxStamina = BattleDefs.Stamina.max,
			statuses = statusList(u), ko = not alive(u), gone = u.gone, color = u.color,
		})
	end
	for _, e in battle.enemies do
		table.insert(enemies, {
			uid = e.uid, name = e.name, id = e.def.id, rank = e.def.rank, title = e.def.title, look = e.def.look, slot = e.slot,
			hp = e.hp, maxHp = e.maxHp, parts = e.def.parts, weak = e.def.weak,
			statuses = statusList(e), dead = e.dead, rage = e.rage,
		})
	end
	local order = {}
	for _, u in battle.order or {} do
		if alive(u) then
			table.insert(order, { uid = u.uid, side = u.side, acted = u.acted })
		end
	end
	return { id = battle.id, round = battle.round, crew = crew, enemies = enemies, order = order, active = battle.active, sea = battle.sea }
end

local function pushState(battle)
	send(battle, "state", snapshot(battle))
end

-- Ask one player for something and wait (polling) for the matching reply or the deadline.
local function ask(battle, unit, kind, payload, timeout)
	battle.token += 1
	local token = battle.token
	local pending: { [string]: any } = { kind = kind, token = token, at = os.clock(), reply = nil }
	battle.pending[unit.player] = pending
	payload.token = token
	sendTo(unit, kind, payload)
	local deadline = os.clock() + timeout
	while os.clock() < deadline and pending.reply == nil and not unit.gone and not battle.over do
		task.wait(0.05)
	end
	battle.pending[unit.player] = nil
	return pending.reply, (pending.replyAt or os.clock()) - pending.at
end

-- ===== roles and buffs =====

local function roleHolder(battle, roleId)
	local h = battle.run.roleHolders and battle.run.roleHolders[roleId]
	return h
end

local function crewDamageMult(battle, attacker)
	local mult = attacker.dmgMult
	-- Captain: +5% while the Captain is standing (NPC captain: half)
	local cap = roleHolder(battle, "Captain")
	if cap == "npc" then
		mult *= 1 + 0.05 * CrewDefs.NpcScale
	elseif cap then
		for _, u in battle.crew do
			if u.role == "Captain" and alive(u) then
				mult *= 1.05
				break
			end
		end
	end
	-- Musician: +5% for the first 2 rounds
	if battle.round <= 2 then
		local mus = roleHolder(battle, "Musician")
		if mus == "npc" then
			mult *= 1 + 0.05 * CrewDefs.NpcScale
		elseif mus then
			mult *= 1.05
		end
	end
	-- Cook's meal from the ship
	if battle.mealBonus then
		mult *= 1 + battle.mealBonus
	end
	return mult
end

-- ===== moves =====

local function movesFor(battle, unit)
	local list = {}
	local function add(id)
		local m = ClassDefs.Moves[id]
		if not m then
			return
		end
		local usable, reason = true, nil
		if unit.stamina < m.cost then
			usable, reason = false, "Needs " .. m.cost .. " stamina"
		end
		if m.requires == "FirstTurn" and unit.turnsTaken > 0 then
			usable, reason = false, "Only on your first turn"
		end
		if m.oncePerFight and battle.usedOnce[unit.uid .. m.id] then
			usable, reason = false, "Already used this fight"
		end
		table.insert(list, { id = m.id, label = m.label, desc = m.desc, cost = m.cost, menu = m.menu, target = m.target, qte = m.qte, usable = usable, reason = reason })
	end
	-- CREW RUSH while every living enemy is DOWN
	local allDown, any = true, false
	for _, e in battle.enemies do
		if alive(e) then
			any = true
			if not e.statuses.down then
				allDown = false
			end
		end
	end
	if any and allDown then
		add("CrewRush")
	end
	for _, id in unit.kit.moves do
		add(id)
	end
	if unit.role == "Captain" then
		add("CaptainsOrders")
	end
	return list
end

local function findMove(list, id)
	for _, m in list do
		if m.id == id then
			return m
		end
	end
	return nil
end

local function firstAliveEnemy(battle)
	for _, e in battle.enemies do
		if alive(e) then
			return e
		end
	end
	return nil
end

local function enemyByUid(battle, uid)
	for _, e in battle.enemies do
		if e.uid == uid then
			return e
		end
	end
	return nil
end

local function rootOf(unit)
	if unit.side == "enemy" then
		return unit.model and unit.model.PrimaryPart
	end
	local ch = unit.player and unit.player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function checkEnd(battle)
	local enemyLeft, crewLeft = false, false
	for _, e in battle.enemies do
		if alive(e) then
			enemyLeft = true
		end
	end
	for _, u in battle.crew do
		if alive(u) then
			crewLeft = true
		end
	end
	if not enemyLeft then
		battle.over, battle.won = true, true
	elseif not crewLeft then
		battle.over, battle.won = true, false
	end
	return battle.over
end

local function killEnemy(battle, e, by)
	e.dead = true
	e.hp = 0
	e.statuses = {}
	if by then
		by.stats.kos += 1
	end
	log(battle, e.name .. " is defeated!")
	Arena.defeat(e.model)
end

-- One hit on one enemy. Returns damage dealt, knockedDown.
local function hitEnemy(battle, attacker, move, target, partId, qteMult, missed)
	local part = BattleDefs.Parts[partId] or BattleDefs.Parts.Core
	local rng = battle.rng
	local base = rng:NextInteger(move.power[1], move.power[2])
	local mult = qteMult * part.mult * crewDamageMult(battle, attacker) * (attacker.kit.mods.moveMult[move.id] or 1)
	if move.notActedMult and not target.acted then
		mult *= move.notActedMult
	end
	if target.statuses.down then
		mult *= BattleDefs.DownTakenMult
	end
	local dmg = if missed then 0 else math.max(1, math.floor(base * mult + 0.5))
	local knocked = false
	if not missed then
		target.hp -= dmg
		attacker.stats.damage += dmg
		-- weakness on the CORE = DOWN
		if part.weakSpot and move.element == target.def.weak and not target.statuses.down and target.hp > 0 then
			target.statuses.down = true
			knocked = true
			attacker.stats.downs += 1
		end
		if part.status == "break" then
			if rng:NextNumber() < BattleDefs.BreakChance then
				-- break its strongest attack (if it has another one left)
				local best, bestScore, left = nil, -1, 0
				for _, pid in target.def.patterns do
					if not target.broken[pid] then
						left += 1
						local p = BattleDefs.Patterns[pid]
						local score = p.damagePerHit * p.maxHits
						if score > bestScore then
							best, bestScore = pid, score
						end
					end
				end
				if best and left > 1 then
					target.broken[best] = true
					log(battle, target.name .. "'s " .. BattleDefs.Patterns[best].label .. " is BROKEN!")
				end
			end
		elseif part.status then
			target.statuses[part.status] = true
		end
		if part.rage then
			target.rage = math.min(BattleDefs.RageMax, (target.rage or 0) + part.rage)
		end
		if move.applies then
			target.statuses[move.applies] = true
		end
		if move.poison then
			target.statuses.poison = { turns = move.poison.turns, dmg = move.poison.dmg }
		end
	end
	send(battle, "fx", { kind = "hit", src = attacker.uid, dst = target.uid, amount = dmg, missed = missed, down = knocked, part = partId })
	if target.hp <= 0 and not target.dead then
		killEnemy(battle, target, attacker)
	end
	return dmg, knocked
end

local function runQte(battle, unit, qte)
	if not qte then
		return ActionCommandDefs.resolve(nil)
	end
	local timeout = if qte == "rings" then ActionCommandDefs.ringTimeout() else ActionCommandDefs.strikeTimeout()
	send(battle, "watchQte", { uid = unit.uid, kind = qte })
	local reply, elapsed = ask(battle, unit, "qte", { kind = qte }, timeout)
	local timing = reply and ActionCommandDefs.sanitizeTiming(reply.timing)
	if timing == nil then
		timing = if qte == "rings" then { sparks = 0 } else { grade = "miss" }
	end
	local res = ActionCommandDefs.resolve(qte, timing, elapsed)
	send(battle, "fx", { kind = "grade", uid = unit.uid, grade = res.grade })
	return res
end

-- Do one chosen move. Returns "free" (turn continues), "onemore" (bonus action), or "done".
local function doMove(battle, unit, move, targetUid, partId, auto)
	unit.stamina -= move.cost
	if move.oncePerFight then
		battle.usedOnce[unit.uid .. move.id] = true
	end
	log(battle, unit.name .. " uses " .. move.label .. "!")
	if move.kind == "orders" then
		for _, u in battle.crew do
			if alive(u) then
				u.stamina = math.min(BattleDefs.Stamina.max, u.stamina + 1)
			end
		end
		send(battle, "fx", { kind = "stamp", text = "CAPTAIN'S ORDERS!" })
		return "free"
	elseif move.kind == "guard" then
		local mult = move.guardMult
		if unit.haki == "Armament" then
			mult *= 0.8
		end
		unit.statuses.guard = { mult = mult, counter = move.counter }
		unit.stats.blocks += 1
		send(battle, "fx", { kind = "buff", uid = unit.uid, text = "PARRY" })
		return "done"
	elseif move.kind == "smoke" then
		unit.statuses.smoke = true
		send(battle, "fx", { kind = "buff", uid = unit.uid, text = "SMOKE!" })
		return "done"
	end

	-- attacks
	local targets = {}
	if move.target == "allEnemies" then
		for _, e in battle.enemies do
			if alive(e) then
				table.insert(targets, e)
			end
		end
	else
		local t = enemyByUid(battle, targetUid)
		if not t or not alive(t) then
			t = firstAliveEnemy(battle)
		end
		table.insert(targets, t)
	end
	if #targets == 0 then
		return "done"
	end
	local first = targets[1]
	if not table.find(first.def.parts, partId) then
		partId = "Core"
	end
	local res
	if auto then
		res = { grade = "weak", mult = ActionCommandDefs.Strike.mult.weak, missed = false }
	else
		res = runQte(battle, unit, move.qte)
	end
	local root = rootOf(unit)
	if root and first.model and first.model.PrimaryPart then
		task.spawn(Arena.lunge, root, first.model.PrimaryPart.Position)
	end
	task.wait(0.2)
	local gotDown = false
	for hit = 1, move.hits or 1 do
		for _, t in targets do
			if alive(t) then
				local _, down = hitEnemy(battle, unit, move, t, if move.target == "allEnemies" then "Core" else partId, res.mult, res.missed)
				gotDown = gotDown or down
			end
		end
		if hit < (move.hits or 1) then
			task.wait(0.25)
		end
	end
	if move.kind == "rush" then
		send(battle, "fx", { kind = "stamp", text = "CREW RUSH!" })
		for _, e in battle.enemies do
			e.statuses.down = nil -- they get back up after the rush
		end
	end
	pushState(battle)
	if gotDown and move.kind ~= "rush" then
		return "onemore"
	end
	return "done"
end

local function playerTurn(battle, unit)
	local oneMoreUsed = false
	local safety = 0
	while not battle.over and alive(unit) and safety < 6 do
		safety += 1
		local list = movesFor(battle, unit)
		battle.active = unit.uid
		pushState(battle)
		local reply = nil
		if unit.player and unit.player.Parent then
			reply = ask(battle, unit, "choose", { uid = unit.uid, moves = list, seconds = BattleDefs.TurnSeconds }, BattleDefs.TurnSeconds + 1)
		end
		local move, targetUid, partId, auto
		if type(reply) == "table" and type(reply.moveId) == "string" then
			local entry = findMove(list, reply.moveId)
			if entry and entry.usable then
				move = ClassDefs.Moves[entry.id]
				targetUid = if type(reply.targetUid) == "string" then reply.targetUid else nil
				partId = if type(reply.part) == "string" and BattleDefs.Parts[reply.part] then reply.part else "Core"
			end
		end
		if not move then
			-- too slow (or a bad pick): basic attack on the first enemy, no QTE
			move = ClassDefs.Moves[unit.kit.class.basic]
			auto = true
			partId = "Core"
			sendTo(unit, "log", "Too slow! Auto attack.")
		end
		local result = doMove(battle, unit, move, targetUid, partId, auto)
		unit.turnsTaken += 1
		if checkEnd(battle) then
			return
		end
		if result == "free" then
			continue
		elseif result == "onemore" and not oneMoreUsed then
			oneMoreUsed = true
			send(battle, "fx", { kind = "stamp", text = "ONE MORE!" })
			task.wait(0.6)
			continue
		end
		break
	end
end

local function pickTarget(battle)
	local open, all = {}, {}
	for _, u in battle.crew do
		if alive(u) then
			table.insert(all, u)
			if not u.statuses.smoke then
				table.insert(open, u)
			end
		end
	end
	local pool = if #open > 0 then open else all
	if #pool == 0 then
		return nil
	end
	return pool[battle.rng:NextInteger(1, #pool)]
end

local function enemyTurn(battle, e)
	local target = pickTarget(battle)
	if not target then
		return
	end
	local choices = {}
	for _, pid in e.def.patterns do
		if not e.broken[pid] then
			table.insert(choices, pid)
		end
	end
	local pattern = BattleDefs.Patterns[choices[battle.rng:NextInteger(1, #choices)]]
	local mods = { stagger = e.statuses.stagger == true, blind = e.statuses.blind == true }
	e.statuses.stagger, e.statuses.blind = nil, nil
	local enraged = (e.rage or 0) >= BattleDefs.RageMax
	if enraged then
		e.rage = 0
	end
	local dph = pattern.damagePerHit * e.dmgMult * (if enraged then 1.5 else 1)
	local maxHits = pattern.maxHits
	if mods.stagger then
		maxHits = math.ceil(maxHits * BattleDefs.Status.stagger.keep)
	end
	battle.active = e.uid
	pushState(battle)
	log(battle, e.name .. " uses " .. pattern.label .. " on " .. target.name .. "!" .. (if enraged then " (ENRAGED)" else ""))
	local root = rootOf(target)
	if e.model and e.model.PrimaryPart and root then
		task.spawn(Arena.lunge, e.model.PrimaryPart, root.Position)
	end
	send(battle, "watchDodge", { uid = target.uid, pattern = pattern.id, enemy = e.uid })
	local seed = battle.rng:NextInteger(1, 2 ^ 30)
	local reply, elapsed = nil, 0
	if target.player and target.player.Parent then
		reply, elapsed = ask(battle, target, "dodge", {
			pattern = pattern.id, seed = seed, mods = mods, maxHits = maxHits, damagePerHit = math.floor(dph * target.takenMult + 0.5),
			heartSpeed = target.heartSpeed, dashMult = target.kit.mods.dashMult, observation = target.haki == "Observation",
			enemy = e.name, enraged = enraged, density = pattern.density,
		}, pattern.duration + 4)
	end
	-- clamp the client's report
	local fallback = math.ceil(maxHits / 2)
	local hits, grazes = fallback, 0
	if type(reply) == "table" and ActionCommandDefs.finite(reply.hits) then
		hits = math.clamp(math.floor(reply.hits), 0, maxHits)
		if elapsed < pattern.duration - 0.6 then
			hits = math.max(hits, fallback) -- answered before the box could have finished
		end
		if ActionCommandDefs.finite(reply.grazes) then
			grazes = math.clamp(math.floor(reply.grazes), 0, BattleDefs.MaxGraze)
		end
	end
	local guard = target.statuses.guard
	local dmg = hits * dph * target.takenMult
	if guard then
		dmg *= guard.mult
		target.statuses.guard = nil
	end
	dmg = math.floor(dmg + 0.5)
	target.hp = math.max(0, target.hp - dmg)
	target.stats.grazes += grazes
	if grazes >= BattleDefs.GrazeForStamina then
		target.grazeBonus = 1
	end
	send(battle, "fx", { kind = "hurt", dst = target.uid, amount = dmg, hits = hits, maxHits = maxHits, perfect = hits == 0 })
	if hits == 0 then
		send(battle, "fx", { kind = "stamp", text = "PERFECT!" })
	end
	if guard and guard.counter and alive(e) then
		local c = battle.rng:NextInteger(guard.counter[1], guard.counter[2])
		e.hp -= c
		target.stats.damage += c
		send(battle, "fx", { kind = "hit", src = target.uid, dst = e.uid, amount = c, counter = true })
		if e.hp <= 0 then
			killEnemy(battle, e, target)
		end
	end
	if target.hp <= 0 then
		target.statuses = {}
		log(battle, target.name .. " is knocked out!")
		local r = rootOf(target)
		if r then
			r.CFrame = r.CFrame * CFrame.new(0, -2, 0) * CFrame.Angles(math.rad(80), 0, 0)
		end
	end
	pushState(battle)
	checkEnd(battle)
end

-- ===== setup =====

local function makeCrewUnit(battle, member, slot)
	local kit = ClassDefs.kit(member.classId)
	local race = CrewDefs.find(CrewDefs.Races, member.race)
	local rm = race and race.mods or {}
	local power = 1 + 0.15 * (battle.power or 0) -- huge power-up after every sea boss
	local gear = ItemDefs.gearBonus(member) -- armor HP + class-weapon damage
	local maxHp = math.floor((kit.class.hp * kit.mods.hpMult * (rm.hpMult or 1) + gear.hp) * power + 0.5)
	local dmgMult = (rm.dmgMult or 1) * (if member.haki == "Armament" then 1.1 else 1) * power * gear.dmg
	local hp = math.max(1, math.floor(maxHp * (member.hpFrac or 1) + 0.5))
	return {
		uid = "c" .. slot, side = "crew", member = member, player = member.player, userId = member.userId, name = member.name,
		classId = kit.class.id, color = kit.class.color, kit = kit, role = member.role, haki = member.haki, slot = slot,
		maxHp = maxHp, hp = hp, stamina = BattleDefs.Stamina.start, speed = kit.class.speed * (rm.speedMult or 1),
		dmgMult = dmgMult, takenMult = rm.takenMult or 1, heartSpeed = rm.heartSpeed or 1,
		statuses = {}, acted = false, turnsTaken = 0, grazeBonus = 0,
		stats = { damage = 0, downs = 0, kos = 0, grazes = 0, blocks = 0 },
	}
end

local function makeEnemyUnit(battle, id, slot, n, partySize)
	local def = BattleDefs.Enemies[id]
	local sea = BattleDefs.Seas[battle.sea] or BattleDefs.Seas[1]
	local maxHp = math.floor(def.hp * sea.hpMult * (1 + BattleDefs.HpPerExtraPlayer * (partySize - 1)) + 0.5)
	local e = {
		uid = "e" .. slot, side = "enemy", def = def, name = def.name, slot = slot,
		maxHp = maxHp, hp = maxHp, speed = def.speed, dmgMult = sea.dmgMult,
		statuses = {}, acted = false, rage = 0, broken = {},
	}
	e.model = Arena.spawnEnemy(def, e.uid, Arena.enemySlot(slot, n))
	return e
end

local function placeCrew(battle)
	for _, u in battle.crew do
		local ch = u.player and u.player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = true
			root.CFrame = Arena.crewSlot(u.slot) * CFrame.new(0, 2, 0)
		end
	end
end

local function releaseCrew(battle)
	for _, u in battle.crew do
		local ch = u.player and u.player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = Arena.crewSlot(u.slot) * CFrame.new(0, 2, 0) -- stand back up
			root.Anchored = false
		end
	end
end

function BattleService.inBattle(player)
	return battleOf[player] ~= nil
end

function BattleService.fight(run, enemyIds, opts)
	opts = opts or {}
	Arena.build()
	Arena.clearEnemies()
	nextId += 1
	local battle = {
		id = nextId, run = run, sea = run.sea or 1, rng = Random.new(), round = 0, token = 0, pending = {},
		crew = {}, enemies = {}, usedOnce = {}, over = false, won = false, mealBonus = opts.mealBonus, power = opts.power,
	}
	local members = {}
	for _, m in run.members do
		if m.player and m.player.Parent then
			table.insert(members, m)
		end
	end
	for i, m in members do
		local u = makeCrewUnit(battle, m, i)
		table.insert(battle.crew, u)
		battleOf[m.player] = battle
	end
	local n = math.min(#enemyIds, 6)
	for i = 1, n do
		table.insert(battle.enemies, makeEnemyUnit(battle, enemyIds[i], i, n, #members))
	end
	placeCrew(battle)

	-- Conqueror's Haki: weaker enemies (not bosses) are stunned for 1 turn
	for _, u in battle.crew do
		if u.haki == "Conquerors" then
			for _, e in battle.enemies do
				if e.def.rank ~= "boss" then
					e.statuses.stun = true
				end
			end
			battle.conqueror = u.name
		end
	end

	send(battle, "start", snapshot(battle), { camPos = Arena.CameraPos, camLook = Arena.CameraLook, kind = opts.kind or "Fight", title = opts.title })
	task.wait(1.5)
	if battle.conqueror then
		send(battle, "fx", { kind = "stamp", text = "CONQUEROR'S HAKI!" })
		log(battle, battle.conqueror .. "'s Conqueror's Haki stuns the weaker enemies!")
		task.wait(1)
	end
	local musician = roleHolder(battle, "Musician")
	if musician then
		log(battle, "The Musician plays a battle song! Crew +" .. (if musician == "npc" then "2.5" else "5") .. "% damage for 2 rounds.")
	end

	while not battle.over do
		battle.round += 1
		-- turn order by Speed (SLOW = last)
		local order = {}
		for _, u in battle.crew do
			if alive(u) then
				table.insert(order, u)
			end
		end
		for _, e in battle.enemies do
			if alive(e) then
				table.insert(order, e)
			end
		end
		for _, u in order do
			u.acted = false
			u.sortSpeed = if u.statuses.slow then -100 + u.speed else u.speed + battle.rng:NextNumber() * 0.5
		end
		table.sort(order, function(a, b)
			return a.sortSpeed > b.sortSpeed
		end)
		battle.order = order
		send(battle, "round", battle.round)
		pushState(battle)
		task.wait(0.8)

		for _, u in order do
			if battle.over then
				break
			end
			if not alive(u) then
				continue
			end
			battle.active = u.uid
			if u.side == "enemy" then
				u.statuses.slow = nil
			end
			-- poison ticks at the start of its turn
			local poison = u.statuses.poison
			if poison then
				u.hp -= poison.dmg
				poison.turns -= 1
				send(battle, "fx", { kind = "hit", dst = u.uid, amount = poison.dmg, poison = true })
				if poison.turns <= 0 then
					u.statuses.poison = nil
				end
				if u.hp <= 0 then
					if u.side == "enemy" then
						killEnemy(battle, u, nil)
					else
						u.hp = 0
					end
					pushState(battle)
					if checkEnd(battle) then
						break
					end
					continue
				end
			end
			if u.statuses.down or u.statuses.stun then
				log(battle, u.name .. (if u.statuses.down then " is DOWN and loses its turn." else " is stunned!"))
				u.statuses.down, u.statuses.stun = nil, nil
				u.acted = true
				pushState(battle)
				task.wait(0.7)
				continue
			end
			if u.side == "crew" then
				u.statuses.smoke = nil
				if u.turnsTaken > 0 then
					u.stamina = math.min(BattleDefs.Stamina.max, u.stamina + BattleDefs.Stamina.perTurn + u.grazeBonus)
				end
				u.grazeBonus = 0
				playerTurn(battle, u)
			else
				enemyTurn(battle, u)
			end
			u.acted = true
			pushState(battle)
			task.wait(0.4)
			if checkEnd(battle) then
				break
			end
		end
		checkEnd(battle)
	end

	-- rewards
	local result = { won = battle.won, gold = 0, loot = {}, bounty = {} }
	if battle.won then
		for _, e in battle.enemies do
			result.gold += e.def.gold
		end
		local arch = roleHolder(battle, "Archaeologist")
		if arch then
			result.gold = math.floor(result.gold * (if arch == "npc" then 1.125 else 1.25))
		end
		local mats = { "Driftwood", "Iron Plate", "Cloth Strip" }
		for _ = 1, #battle.enemies do
			local item = mats[battle.rng:NextInteger(1, #mats)]
			result.loot[item] = (result.loot[item] or 0) + 1
		end
	end
	local doctor = roleHolder(battle, "Doctor")
	for _, u in battle.crew do
		local s = u.stats
		local gain = s.damage * 1000 + s.downs * 15000 + s.kos * 25000 + s.grazes * 500 + s.blocks * 8000
		if not battle.won then
			gain = math.floor(gain / 4)
		end
		result.bounty[u.userId] = gain
		u.member.bounty = (u.member.bounty or 0) + gain
		-- HP carries over between fights; knocked-out crew get back up after a win
		local hp = u.hp
		if hp <= 0 then
			hp = if doctor == "npc" then u.maxHp * 0.15 elseif doctor then u.maxHp * 0.3 else 1
		end
		u.member.hpFrac = math.clamp(hp / u.maxHp, 0.01, 1)
	end
	send(battle, "end", { won = battle.won, gold = result.gold, loot = result.loot, bounty = result.bounty, kind = opts.kind })
	task.wait(4)
	releaseCrew(battle)
	Arena.clearEnemies()
	for _, u in battle.crew do
		if u.player then
			battleOf[u.player] = nil
		end
	end
	send(battle, "close")
	return result
end

Remotes.Battle.OnServerEvent:Connect(function(player, msg, data)
	local battle = battleOf[player]
	if not battle then
		return
	end
	local pending = battle.pending[player]
	if not pending or type(data) ~= "table" or data.token ~= pending.token then
		return
	end
	if (msg == "action" and pending.kind == "choose") or (msg == "qte" and pending.kind == "qte") or (msg == "dodge" and pending.kind == "dodge") then
		if pending.reply == nil then
			pending.reply = data
			pending.replyAt = os.clock()
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local battle = battleOf[player]
	if battle then
		for _, u in battle.crew do
			if u.player == player then
				u.gone = true
			end
		end
		battleOf[player] = nil
		checkEnd(battle)
	end
end)

return BattleService
