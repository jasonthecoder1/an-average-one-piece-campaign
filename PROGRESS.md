# Average One Piece Campaign — progress

Roblox game, built as Rojo source files. Studio place: **An Average Campaign** (placeId 122707308332469).
GitHub: https://github.com/jasonthecoder1/an-average-one-piece-campaign

## How to try it in Studio (short version)

1. Open a terminal in this folder and type: `rojo serve`
2. In Roblox Studio, open **An Average Campaign**. Click the **Rojo** plugin, then **Connect**.
   (No Rojo plugin? Run `rojo plugin install` once. Or skip Rojo: open `build.rbxl` from this folder instead.)
3. In Game Settings, set the server size to **6** (the whole server is one crew).
4. Press **Play**.
5. You see the **lobby**. Pick a **role** (you need one). Pick a **class** if you want. Click **READY**.
6. You are on your **ship**. Walk around. Press **E** at a station.
7. Go to the **MAP TABLE**, press E, click **READY**. The sea chart opens.
8. Click a glowing stop to **vote**. Then you go there.
9. In a fight: click **STRIKE / SKILL / HEAVY**, pick a move, click an enemy.
   - **Strike bar**: press SPACE (or click) when the marker is on the red notch.
   - **Power rings**: press SPACE as each ring touches the red dot.
   - **Dodge box**: move the red heart with WASD / arrows. SPACE = dash.
10. Win fights to get **materials**. Craft at the **CRAFTING** bench. Press **B** for your bag and gear.
11. Beat the boss at the top of the chart to reach the next sea. Beat Sea 3 = **PIRATE KING**.

Tip: to test with friends in Studio, use **Test > Clients and Servers** with 2-3 players.
Your own maps: read **MAP_GUIDE.md** (where to put them and which parts to name).
Rerolls for race and Haki are free in Studio (until Robux products are set in `src/shared/Config.luau`).

## Done (each step builds with `rojo build` and passes the luau-lsp type check)

1. **Single fight** — turn-based, STRIKE bar QTE (crit/good/weak/miss), POWER RINGS QTE for heavy moves,
   Undertale dodge box (red heart, cannonballs / sword waves / pistol shots / fishman water, graze chain,
   dash), red HP / cyan stamina, win/lose. The server checks every answer (too-fast crits become WEAK,
   hits clamped, early dodge answers rejected).
2. **Full fight screen** — up to 6 crew vs up to 6 enemies, turn order by Speed, For The King 3/4 camera
   from behind the crew, TURN ORDER strip + ROUND tab, enemy plates on top, crew cards on the bottom,
   command tiles on the right (like the design page). Weak points (CORE/EYES/ARMS/LEGS/WEAPON) on elites
   and bosses, DOWN + ONE MORE!, CREW RUSH when all enemies are down, Rage, BREAK. Screen shrinks on phones.
3. **Sea map** — a new hex chart per sea (same generator as the design page: shapes, weather, reefs),
   4 rows + boss. Ready -> chart opens -> everyone votes (30 s). Captain: Force Ready + breaks ties.
   Navigator sees what waits at each stop. Stops: Fight, Elite, Port Town, Camp (rest, maybe ambush),
   Event (6 story cards), Treasure Isle, Allied Crew, Boss -> huge power-up -> next sea. Cook's meal after
   every stop.
4. **Ship** — walkable deck with mast, sail, cabin, props. Stations with signs: Map Table, Crafting,
   Crew Chest (craft it first), Repairs (hull), Lockers (personal), Galley (Cook), Infirmary (Doctor),
   Crow's Nest (Navigator), Stage (Musician), Study (Archaeologist). 10 recipes (weapons, armor set,
   bandages, hull patch). Gear: class weapons give damage only to their class; armor gives HP.
5. **Lobby menu** — no walking (camera shows the ship). Party 1-6, race + Haki rolled and saved
   (DataStore), reroll button (Robux product hook; free in Studio), class + role picks, one-of-each-role
   Ready lock (even Force Ready can't skip it), NPCs fill empty roles, Bounty Board, late joiners can
   "JOIN THE CREW" mid-run.
6. **Classes** — Warrior, Assassin, Tank, Healer with their full Tier 1 trees from the Class Book.
7. **Owner-built maps** — the owner builds the real maps. The code loads them from
   `ServerStorage/Maps/Islands`, `/Bosses` (named after the boss) and `/Ship` and reads named marker parts
   (CrewSpot1-6, EnemySpot1-6, CameraSpot, DeckSpot1-6, MapTable, CraftBench, CrewChest, RepairBench, Lockers,
   Galley, Infirmary, CrowsNest, Stage, Study, LobbyCamera). Plain block stand-ins are used while a folder is
   empty. Plain-words guide: **MAP_GUIDE.md**.

## Reviews (no Studio test runs, so the code was checked by reading)

- Every step: `rojo build` + luau-lsp type check (`tools/check.sh`) is clean.
- Review 1 (one reviewer): 7 bugs fixed (lobby open race, stale move menu, popups, Ambush, SLOW, bounty keys,
  late joiner vote).
- Review 2 (5 area reviewers + 5 skeptics, then 4 fixers + 4 reviewers): 39 confirmed findings fixed, 18 refuted.
  Biggest: the server now rebuilds the dodge-box bullets from the seed (`Shared/DodgePatterns.luau`) and replays
  the heart path the client sends, so a cheater can't claim "0 hits". Also: lobby start/save races, safe DataStore
  loads (a failed load never overwrites a save), Robux receipts handled once, a 60 s "setting sail" countdown so one
  idle player can't stall the crew, rate limits on every remote, item ids checked on ship actions, folder maps.

## File map

| File | What it does |
|---|---|
| `src/shared/ActionCommandDefs.luau` | QTE numbers + graders (strike bar, power rings), server clamps |
| `src/shared/BattleDefs.luau` | weak points, statuses, dodge patterns, enemies, bosses, seas, encounter builder |
| `src/shared/ClassDefs.luau` | classes, moves, Tier 1 trees |
| `src/shared/CrewDefs.luau` | races, Haki, roles (+ roll helper) |
| `src/shared/MapDefs.luau` | sea chart generator + what each player may see |
| `src/shared/EventDefs.luau` | story cards, Port Town, Allied Crew |
| `src/shared/ItemDefs.luau` | materials, gear, recipes, slot sizes, gear bonus |
| `src/shared/Style.luau`, `Config.luau` | UI colors/fonts; Robux product ids, party size |
| `src/server/Main.server.luau` | wires lobby -> run -> ship |
| `src/server/LobbyService.luau` | lobby menu rules, saving, rerolls |
| `src/server/Run.luau` | the run loop: ready, vote, stops, cards, seas, end |
| `src/server/BattleService.luau` | the turn-based fight (all math on the server) |
| `src/server/Arena.luau` | loads the fight arena (owner map or stand-in) + block-figure enemies |
| `src/server/MapLoader.luau` | finds owner maps in ServerStorage/Maps and their marker parts |
| `src/shared/DodgePatterns.luau` | dodge-box bullet generators shared by client and server (anti-cheat replay) |
| `src/server/ShipService.luau` | builds the ship, stations, crafting, storage, gear |
| `src/server/Remotes.luau` | RemoteEvents + toast helper |
| `src/client/Kit.luau` | UI kit in the owner's style (panels, red jagged shadows, halftone, bars, stamps) |
| `src/client/BattleUI.luau`, `Qte.luau`, `DodgeBox.luau` | fight screen, QTEs, dodge box |
| `src/client/MapUI.luau` | sea chart, voting, story cards, run end, HUD |
| `src/client/ShipUI.luau` | crafting, Crew Chest, locker, bag/gear, repairs |
| `src/client/LobbyUI.luau` | lobby menu |
| `tools/check.sh` | build + type check |

NextLife: only its CODE ideas were reused (strike bar / ring QTE grading with server clamps, dodge box,
weak points, graze, DOWN / finisher). Nothing visible was copied.

## Next steps (ideas in order)

- More classes: Marksman, Brawler, Beast Tamer, Weather Mage, Bard (moves are in the design page's Class Book).
- Tier 2 / Tier 3 paths + skill points per level, Class XP, Renown + Bonus Tree in the lobby.
- Power Ups (pick 1 of 3 mid-fight), boss variants / arenas / phase 2, Emperor twists (Sea 3).
- Marine camp attacks on the ship (reflect cannonballs, hull damage), Split Expeditions + Ship Clock.
- Devil fruits + drowning (Dive In / Deep Dive QTE), treasure maps, Admiral ambushes, modifiers.
- Real models / animations / sounds (all One Piece-inspired), Observation's enemy-intent damage numbers.
- Lobby place + TeleportService reserved run servers (now: one server = one party).

For the next chats: the owner asked for **ultracode** (multi-agent workflows) on every new step, plus one
careful review of each step before committing. Put the word "ultracode" in every hand-off brief.

## Open questions for the owner

- Robux prices for race / Haki rerolls (make the Developer Products, paste the ids into `Config.luau`).
- Should Smelling Salts also revive a knocked-out friend? (now: only wakes stunned friends)
- Heavy enemy attacks now STUN on 3+ hits so stun resist / Smelling Salts matter. OK?
- New: once half the crew is Ready at the map table, a 60 s countdown starts and the ship sails without the rest. OK?
- Note: in Studio with API access off, joining waits about 3 s (save retries), then says your save did not load. That is normal in Studio.
