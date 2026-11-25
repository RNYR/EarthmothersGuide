# Earthmother's Guide

A 1-60 **Tauren Druid** leveling guide for **WoW: Forever**, with dungeon quests and the Forever druid class quests. It is named after the Earthmother, An'she and Mu'sha - the sun and moon the Tauren and their druids revere.

It is an original route. Quest names, quest IDs, NPCs and coordinates come from the community QuestieDB Forever database; the zone order, level windows and druid steps are in `tools/route.py`.

## Install

Install it with the CurseForge app, or download the release zip and unpack it so the `EarthmothersGuide` folder ends up in:

```
/Applications/World of Warcraft/_forever_/Interface/AddOns/EarthmothersGuide
```

On Windows the folder is usually `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\EarthmothersGuide`.

Then restart the game and make sure the addon is enabled on the character screen. Commands start with `/emg`.

From a copy of the source repository, copy only the runtime files: `EarthmothersGuide.toc`, `Core.lua`, `Arrow.lua`, `UI.lua`, `Items.lua`, `Options.lua`, `Guide/` and `Media/` (not `tools/` or `tests/`).

## Use

**Starting with an existing character:** the first time a character logs in with the addon, it reads your level and the quests you have already handed in, and starts at whichever is further along: just after the last guide quest you finished, or the start of the chapter for your level. Quests from before that point that you never picked up are skipped, but anything still in your quest log stays in the route. It also tells you which druid forms you are missing for your level and which chapter has their quest (`/emg chapter N`). Run `/emg resume` at any time to redo this, and `/emg status` to see it again.

Quests 6 or more levels below you are skipped as grey (change with `/emg gray 0-10`, 0 = never). Druid class quests are never skipped.

A small brown panel shows the current step. It moves on by itself when you accept, finish or hand in the listed quests, learn a form, reach a level or arrive in a zone. Note and training steps say "Click the panel to continue": left-click the panel. Right-click the panel, or click the gear, to open the settings.

**Several quests at once:** at each quest hub the guide picks up every available quest, then shows the whole batch as one step: "Do these 9 quests in the area". Each quest is a checklist line with its remaining objectives; finished quests get a tick and stay in the list, quests you dropped are left out. The step completes when every quest in it is finished. Pickup steps show what is **Coming up** in the next batch, and **Also carrying** pins any other unfinished quest from the chapter in your log. **Compact quest list** (settings) shows one line per quest, e.g. "Disrupt the Attacks  12/19".

**Replaces Blizzard's quest tracker:** while the guide panel is shown, Blizzard's tracker under the minimap is hidden and the panel takes its place (your full quest log is still on `L`). Untick **Replace Blizzard's quest tracker** in the settings or use `/emg tracker on` to get it back; hiding the guide panel also brings it back. Hiding happens safely in combat (the tracker becomes invisible at once and is fully hidden when combat ends).

**Look out for:** some quests start from an item you loot (for example Hoof of Lakota'mani). They are optional: the panel lists them under **Look out for** while you are in their zone, and once you loot the item and take the quest, its steps join the route.

**Falling behind:** if a step's quests are 3 or more levels above you, the panel says so.

**Hand-ins:** quests are handed in right after a dungeon only when the NPC is nearby. Turn-ins in faraway cities wait for the next time the route goes there (for example the Ragefire Chasm quest for Varimathras is handed in when you reach Undercity at the start of chapter 3), and anything waiting in Thunder Bluff or Moonglade is handed in on your training trips. **Ready to hand in** under the step lists every finished quest in your log with the NPC and zone that takes it, so nothing waiting is ever invisible.

**Hearthstone and travel:** the route tells you where to set your hearthstone at each new hub (Bloodhoof Village, the Crossroads, the Sepulcher, Sun Rock Retreat, Freewind Post, Tarren Mill, Grom'gol, Shadowprey Village, Rog'mar, Gadgetzan, Camp Mojache, Revantusk Village, Kargath, Light's Hope Chapel, Everlook); the step completes by itself once the game reports the new hearth. Every move to a new zone is a **Travel** step with how to get there, and it says "Use your hearthstone" whenever your hearth is set where you are going. If a quest waiting in Orgrimmar, Undercity or Thunder Bluff has waited 4 or more levels, the route adds a **Detour** to hand it in before it loses XP.

**Druid travel with Teleport: Moonglade:** it does not use your hearthstone, so training steps suggest: teleport to Moonglade, train with Loganaar in Nighthaven, then hearth back to where your hearth is set. For Felwood and Winterspring the travel steps check your Timbermaw Hold reputation live: a Tauren starts Hostile, and the tunnel furbolgs attack until you are Unfriendly. Until then the guide routes you by flight path and tells you to run straight through the tunnel; the Felwood Timbermaw quests (Grazle, Nafien) on the route raise you to about Unfriendly, and from then on the tip switches to the Teleport: Moonglade + tunnel shortcut.

**Profession quests:** quests that need a profession (crafted, skinned, fished or cooked items, e.g. alchemy, blacksmithing, engineering, leatherworking, tailoring, skinning, fishing, cooking) are tagged with the profession. Untick **Include profession quests** in the settings to leave them out; any you already have in your log stay.

**Quest item button:** when a quest in the current step has a usable quest item, a button with its icon appears under the panel; click it to use the item. It only changes out of combat (a game rule for secure buttons).

**Arrow:** an arrowhead in the top-right of the panel points to the current step's NPC or, in a batch, to the nearest quest you have not finished (marked with ">" in the list; the map pin follows it), with the distance underneath (no TomTom needed). It is green when you face the target, yellow to the side and red behind, and says "here" within 8 yards. It works across zones on the same continent; on another continent or inside an instance it turns grey and says "far".

**Settings** (gear, right-click, `/emg options`, or Esc > Options > AddOns > Earthmother's Guide):
- show the panel, dungeon steps, arrow, Blizzard map pin, lock position, compact quest list, carried quests, quest item button, profession quests
- panel size, and how many levels below you a quest must be to be skipped
- Find my place, Back one step, Skip this step
- the route browser: all 12 chapters, each with its level range, % done and a progress bar; pick one to see its zones, its dungeons with level ranges, and every step grouped by zone, with done steps ticked and your current step marked. Click a step to jump there.

| Command | What it does |
|---|---|
| `/emg` | show or hide the panel |
| `/emg options` | settings and route browser |
| `/emg next`, `/emg prev` | move one step |
| `/emg chapter 1-12` | jump to a chapter |
| `/emg dungeons on\|off` | include or skip dungeon steps (also "Include dungeon steps" in the settings) |
| `/emg check <questID>` | what the guide sees for one quest (useful for bug reports) |
| `/emg way` | set the arrow and map pin for the step again |
| `/emg tracker on\|off` | show or hide Blizzard's quest tracker |
| `/emg resume` | work out your place again from your level and finished quests |
| `/emg status` | level, finished guide quests, missing druid forms |
| `/emg gray 0-10` | skip quests this many levels below you (0 = never) |
| `/emg scale 0.6-1.6`, `/emg lock`, `/emg unlock` | panel size and dragging |
| `/emg arrow on\|off` | the guide's own waypoint arrow |
| `/emg waypoints on\|off` | Blizzard map pin for each step |

Dungeon steps are marked `[Dungeon lo-hi]` in orange. They are skipped automatically once you are above the dungeon's top level, or always when dungeons are off.

If your saved position is ever lost or out of date, the guide works out where you are from your completed quests.

## Chapters

1. Mulgore 1–10 (Bear Form chain starts)
2. The Barrens 10–16 (Lunaclaw, Cure Poison, Ragefire Chasm)
3. Aquatic Form and Silverpine 16–21 (Ruins of Lordaeron, Shadowfang Keep)
4. Barrens and Wailing Caverns 18–23 (new Cat Form chain)
5. Stonetalon, Ashenvale, Thousand Needles 20–30 (Blackfathom Deeps, Razorfen Kraul)
6. Hillsbrad, Alterac, Arathi 28–35 (City of Dalaran, Excavation Site: Wetlands, Scarlet Monastery)
7. Stranglethorn and Desolace 32–40 (The Drowned City, Razorfen Downs)
8. Riverglades 37–44 (Krol'dok Stronghold, Dire Bear, Kodo)
9. Tanaris, Feralas, Shen'dralas 42–48 (Zul'Farrak, Uldaman)
10. Maraudon, Dustwallow, Hinterlands 46–52 (Alcaz Prison)
11. Un'Goro, Felwood, Azshara, Burning Steppes 50–56 (Sunken Temple, Blackrock Depths)
12. Plaguelands, Winterspring, Silithus 55–60 (Blackmaw Hold, Shaper's Terrace, Mount Hyjal)

## Known limits

- Quest data is community data, not Blizzard's. Some Forever quests may be missing or placed oddly; skip a stuck step with `/emg next` or "Skip this step" in the settings.
- Quest order inside a zone is worked out by distance, so it is good but not hand-tuned.
- Quests started by a looted item are optional pickups ("Look out for"), never required.
- A few quests have no location in the community data, so the arrow cannot point at them.
- The guide drops quests that hand in somewhere the route never goes back to.
- The route never asks you to carry more than 20 quests at once.

## Development

The packaged addon only contains the runtime files. The source repository also has `tools/` (route specification, generator, database decoder, arrow drawing) and `tests/`.


```bash
python3 -I tools/extract_questiedb.py "/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc" /tmp/emg-db.json
python3 -I tools/gen.py /tmp/emg-db.json "/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestieDB" .
luajit tests/run.lua
```

The arrow texture is drawn by `python3 -I tools/make_arrow.py Media/Arrow.tga`.

Edit `tools/route.py` to change the route, then rebuild. Never edit `Guide/*.lua` by hand.

## Language

The guide text is English. Quest and NPC names come from the English game data.

## Credits and license

Earthmother's Guide is licensed under the GNU GPL v3 or later (see `LICENSE`). Its quest, NPC and
coordinate data is derived from [QuestieDB](https://github.com/Questie/QuestieDB) and
[Questie](https://github.com/Questie/Questie), used under the GPL v3. See `NOTICE.md` for details.
World of Warcraft names and quest text are (c) Blizzard Entertainment. This is a fan-made add-on,
not affiliated with Blizzard.
