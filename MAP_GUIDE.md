# Map Guide — how to add your own maps

You build the maps. The game finds them by **folder** and by **part names**.
If a folder is empty, the game uses a plain gray block stand-in, so it always works.

## 1. Where maps go

In Studio, open the **Explorer**. Go to **ServerStorage**. You will see a folder called **Maps**.

```
ServerStorage
└── Maps
    ├── Islands   ← fight islands (normal fights, elites, camps, events)
    ├── Bosses    ← boss arenas
    └── Ship      ← your crew's ship (only ONE model in here)
```

Build your map in the Workspace first. When it's done:

1. Select everything in the map and press **Ctrl+G** to group it into one **Model**.
2. Give the model a name (see below).
3. Drag the model into the right folder in **ServerStorage → Maps**.

The map stays **exactly where you built it**. So build islands **far away from the ship**
(at least 300 studs away). Islands can sit on top of each other, because only one is loaded at a time.

### Names

| Folder | Name the model... | Example |
|---|---|---|
| Islands | anything you like | `PalmBeach`, `MarineFort` |
| Bosses | the boss's name, so that boss always fights there | `Arlong`, `Buggy`, `Mihawk`, `Doflamingo`, `Kaido`, `Shanks` |
| Ship | anything | `GoingMerry` |

- More than one island? The game picks a **random** one for each fight.
- A boss with no arena of its own uses a random boss arena (or an island).
- Want an island only in one sea? Select the model, click **Add Attribute**, name it `Sea`,
  type **Number**, value `1`, `2` or `3`.

## 2. Marker parts

Markers are small parts that tell the game where things go.
Name them **exactly** like below (capital letters matter, no spaces).

How to make a marker:

- Insert a **Part**. Make it about **2 × 1 × 2** studs.
- **Anchored** = on.
- Put it **on the floor** (the bottom of the part touches the ground).
- Turn it so its **Front** face points where the pirate should look.
  Trick to see the front: right-click the part → **Insert Object** → **Decal**. A new Decal always sits on
  the **Front** face, so the side with the decal is the front. (You can delete the decal later, or keep it:
  the game hides it.)
- Spot markers turn **invisible** by themselves when the game loads them, so you can leave them bright red
  while you build.

### Fight islands and boss arenas

| Part name | How many | What it's for | Which way it faces |
|---|---|---|---|
| `CrewSpot1` … `CrewSpot6` | 6 | where your crew stands | toward the enemies |
| `EnemySpot1` … `EnemySpot6` | 6 | where enemies stand | toward the crew |
| `CameraSpot` | 1 | the fight camera | toward the middle of the fight |

Tips:
- Spots **1, 2, 3** are the **front row**. Spots **4, 5, 6** are the **back row**.
- A single enemy (like a boss alone) stands on `EnemySpot2`, so put that one in the middle.
- Put `CameraSpot` **behind and above** the crew, like the For The King camera: about 30 studs back
  and 20 studs up. Its front face looks down at the fight.
- Leave about **7 studs** between spots. Bosses are big, so give `EnemySpot2` extra room in boss arenas.

Picture (seen from above):

```
            E4      E5      E6        ← back row of enemies (face down ↓)
        E1      E2      E3            ← front row of enemies (face down ↓)

                 (open ground)

        C1      C2      C3            ← front row of crew (face up ↑)
            C4      C5      C6        ← back row of crew (face up ↑)

                   📷                 ← CameraSpot, high up, looking at the middle
```

### The ship

| Part name | What it does | Who can use it |
|---|---|---|
| `DeckSpot1` … `DeckSpot6` | where the crew appears on deck | — |
| `MapTable` | Sea Chart + READY button | everyone |
| `CraftBench` | crafting | everyone |
| `CrewChest` | shared storage (built by crafting it) | everyone |
| `RepairBench` | repair the hull with Hull Patches | everyone |
| `Lockers` | your own private storage | everyone |
| `Galley` | snacks: heal the crew 10% | Cook |
| `Infirmary` | treat the crew: heal 20% | Doctor |
| `CrowsNest` | look-out | Navigator |
| `Stage` | sea shanty: +3% damage next fight | Musician |
| `Study` | find hidden supplies | Archaeologist |
| `LobbyCamera` (optional) | the camera shot in the lobby menu | — |

- A station part can be the real thing (your table) **or** a small invisible part on top of it.
  The game puts a floating sign and the **E** button on that part.
- Put rails around the deck, so nobody falls off (later, devil fruit users will drown in the sea!).
- You can add your own **SpawnLocation** on the deck. If you don't, the game makes one at `DeckSpot1`.

## 3. How to test

1. Put your model in the right folder.
2. Press **Play**.
3. Ship: you should appear on your deck. Walk to each station: a sign and an **E** button should show.
4. Islands: pick a role, READY, go to the Map Table, READY, vote for a fight. You should land on your island.
5. Open the **Output** window (View → Output). If a marker is missing, it says so, for example:
   `[Ship] the ship map has no part named CraftBench`.

## Quick checklist

- [ ] Map is **one Model** in the right folder
- [ ] Marker names are **exactly** right
- [ ] Markers are **Anchored** and sit **on the floor**
- [ ] Front faces point the right way
- [ ] Islands are **far** from the ship
- [ ] Boss arena named after the boss (optional)
