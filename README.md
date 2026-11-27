# Earthmother's Guide

A 1-60 **Tauren Druid** leveling guide for **WoW: Forever**, with dungeon quests and the Forever druid class quests. It is named after the Earthmother, An'she and Mu'sha - the sun and moon the Tauren and their druids revere.

It is an original route. Quest names, quest IDs, NPCs and coordinates come from the community QuestieDB Forever database; the zone order, level windows and druid steps are in `tools/route.py`.

Source code: https://github.com/RNYR/EarthmothersGuide

## Install

Install it with the CurseForge app, or download the zip from CurseForge and unpack it so the `EarthmothersGuide` folder ends up in your AddOns folder. On Windows that is usually:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\EarthmothersGuide
```

On a Mac:

```
/Applications/World of Warcraft/_forever_/Interface/AddOns/EarthmothersGuide
```

Then restart the game and make sure the addon is enabled on the character screen. Commands start with `/emg`. Found a problem? Comment on CurseForge or open an issue on GitHub (see [Support](#support)).

From a copy of the [source repository](https://github.com/RNYR/EarthmothersGuide), copy only the runtime files: `EarthmothersGuide.toc`, `Core.lua`, `Arrow.lua`, `UI.lua`, `Tracker.lua`, `Items.lua`, `Options.lua`, `Guide/` and `Media/Arrow.tga` (not `tools/`, `tests/` or the logo files in `Media/`).

## Use

**Starting with an existing character:** the first time a character logs in with the addon, it reads your level and the quests you have already handed in, and starts at whichever is further along: just after the last guide quest you finished, or the start of the chapter for your level. Quests from before that point that you never picked up are skipped, but anything still in your quest log stays in the route. It also tells you which druid forms you are missing for your level and which chapter has their quest (`/emg chapter N`). Run `/emg resume` at any time to redo this, and `/emg status` to see it again.

Quests that have turned grey for you are skipped (the game's grey rule; change with `/emg gray`: `grey`, `0` = never, or a number of levels below you). Druid class quests are never skipped. A grey quest that starts a chain stays only while a later part of that chain is still worth doing for you.

A small brown panel shows the current step. It moves on by itself when you accept, finish or hand in the listed quests, learn a form, reach a level or arrive in a zone. **Every quest line has a checkbox: tick it to skip just that quest** (the guide stops waiting for it; untick to put it back, or `/emg unskip` to clear all skips). Note, training and hearthstone steps have a **Done** checkbox instead. Left-drag moves the panel; right-click it to open the settings.

**Several quests at once:** at each quest hub the guide picks up every available quest, then shows the whole batch as one step: "Do these 9 quests in the area". Each quest is a checklist line with its remaining objectives; finished quests get a tick and stay in the list, quests you dropped are left out. The step completes when every quest in it is finished. **Also carrying** pins any other unfinished quest from the chapter in your log. **Compact quest list** (settings) shows one line per quest, e.g. "Disrupt the Attacks  12/19".

**Replaces Blizzard's quest tracker:** while the guide panel is shown, Blizzard's tracker under the minimap is hidden and the panel takes its place (your full quest log is still on `L`). Untick **Replace Blizzard's quest tracker** in the settings or use `/emg tracker on` to get it back; hiding the guide panel also brings it back. Hiding happens safely in combat (the tracker becomes invisible at once and is fully hidden when combat ends).

**Look out for:** some quests start from an item you loot (for example Hoof of Lakota'mani). They are optional: the panel lists them under **Look out for** while you are in their zone, and once you loot the item and take the quest, its steps join the route.

**Falling behind:** if a step's quests are 3 or more levels above you, the panel says so.

**Hand-ins:** after a dungeon, quests are handed in inside it first, then at NPCs near it. Turn-ins in faraway cities wait for the next time the route goes there (see **Detour** below), and Moonglade hand-ins happen on your training trips. **Ready to hand in** under the step lists the finished quests of the batch you are on, with the NPC and zone that takes each.

**Quests picked up out of order:** when you accept a quest whose steps the route has already passed (an item-started quest you loot late, for example), the guide goes back to it by itself, shows only that quest and its follow-ups, and then takes you back to where you were. The same happens when you hand in a quest whose follow-up the route has passed.

**Hearthstone and travel:** the route tells you where to set your hearthstone at each new hub (Bloodhoof Village, the Crossroads, the Sepulcher, Sun Rock Retreat, Freewind Post, Tarren Mill, Grom'gol, Shadowprey Village, Rog'mar, Gadgetzan, Camp Mojache, Revantusk Village, Kargath, Light's Hope Chapel, Everlook); the step completes by itself once the game reports the new hearth. Every move to a new zone is a **Travel** step with how to get there, and it says "Use your hearthstone" whenever your hearth is set where you are going. If a quest waiting in Orgrimmar, Undercity, Thunder Bluff, Mulgore or Brill has waited 4 or more levels, the route adds a **Detour** to hand it in before it loses XP (never across continents mid-trip).

**Druid travel with Teleport: Moonglade:** it does not use your hearthstone, so training steps suggest: teleport to Moonglade, train with Loganaar in Nighthaven, then hearth back to where your hearth is set. For Felwood and Winterspring the travel steps check your Timbermaw Hold reputation live: a Tauren starts Hostile, and the tunnel furbolgs attack until you are Unfriendly. Until then the guide routes you by flight path and tells you to run straight through the tunnel; the Felwood Timbermaw quests (Grazle, Nafien) on the route raise you to about Unfriendly, and from then on the tip switches to the Teleport: Moonglade + tunnel shortcut.

**Profession quests:** quests that need a profession (crafted, skinned, fished or cooked items, e.g. alchemy, blacksmithing, engineering, leatherworking, tailoring, skinning, fishing, cooking) are tagged with the profession. Untick **Include profession quests** in the settings to leave them out; any you already have in your log stay.

**Quest item buttons:** a quest on the panel that has a usable quest item gets a small button with the item's icon at the end of its row, as in Blizzard's quest tracker; click it to use the item. The buttons only change out of combat (a game rule for secure buttons), so if the panel changes during a fight they catch up when it ends.

**Panel size:** set **Panel width** (260-520 px, or `/emg width`) and **Panel max height** (or `/emg height 150-900`) in the settings; while you change either, an outline on the panel shows the new size. When a step has more than fits, the panel scrolls with the mouse wheel and a thin bar on the right shows where you are; every quest is listed, nothing is cut off.

**Arrow:** an arrowhead in the top-right corner of the panel points to the current step's NPC or, in a batch, to the nearest quest you have not finished (marked with ">" in the list; the map pin follows it), with the distance underneath (no TomTom needed). It is green when you face the target, yellow to the side and red behind, and says "here" within 8 yards. It works across zones on the same continent; on another continent or inside an instance it turns grey and says "far".

**Settings** (right-click the panel, `/emg options`, or Esc > Options > AddOns > Earthmother's Guide):
- show the panel, arrow, Blizzard map pin, lock position, compact quest list, carried quests, quest item buttons, profession quests, replace Blizzard's quest tracker
- panel size, panel width, panel max height (it scrolls beyond that), and when low quests are skipped
- Find my place, Back one step, Skip this step
- the route browser: all 12 chapters, each with its level range, % done and a progress bar; pick one to see its zones, its dungeons with level ranges, and every step grouped by zone, with done steps ticked and your current step marked. Click a step to jump there.

| Command | What it does |
|---|---|
| `/emg` | show or hide the panel |
| `/emg options` | settings and route browser |
| `/emg next`, `/emg prev` (also `skip`, `back`) | move one step |
| `/emg unskip` | put every quest you skipped with its checkbox back in the route |
| `/emg chapter 1-12` (also `ch`) | jump to a chapter |
| `/emg check <questID>` | what the guide sees for one quest (useful for bug reports) |
| `/emg way` | set the arrow and map pin for the step again |
| `/emg tracker on\|off` | show or hide Blizzard's quest tracker |
| `/emg resume` | work out your place again from your level and finished quests |
| `/emg status` | level, finished guide quests, missing druid forms |
| `/emg gray grey\|0-10` | skip quests once they turn grey (default), never (0), or this many levels below you |
| `/emg scale 0.6-1.6`, `/emg width 260-520`, `/emg height 150-900`, `/emg lock`, `/emg unlock` | panel size, width, maximum height and dragging |
| `/emg arrow on\|off` | the guide's own waypoint arrow |
| `/emg waypoints on\|off` | Blizzard map pin for each step |

Dungeon steps are marked `[Dungeon lo-hi]` in orange. Dungeons are always part of the route: their quests are a big share of the XP, and each needs only a run or two. The route reaches every dungeon inside its level range, so you can queue for it with the group finder; if you are already above a dungeon's range, its steps are skipped (quests from it you already carry stay).

If your saved position is ever lost or out of date, the guide works out where you are from your completed quests.

## Chapters

Level ranges are what a character reaches by following the route, simulated with **real WoW: Forever quest XP** plus two **assumptions**: kills along the way give 40% on top of quest XP, and a full dungeon run gives about half a level. With quest XP alone you would be several levels lower by the end. Quests up to 4 levels above you are part of the route. Where the route needs a higher level than the simulation reaches, it adds a short **Grind to level N** step (one, in Chapter 7; with the route's other level checkpoints about 4% of the XP for 1-60); if you run the dungeons you will usually be past them already.

1. Mulgore 1-10 (Bear Form chain starts)
2. The Barrens 10-16 (Lunaclaw, Cure Poison, Ragefire Chasm)
3. Aquatic Form and Silverpine 16-19 (Ruins of Lordaeron)
4. The Barrens and Wailing Caverns 19-23 (Aquatic Form, new Cat Form chain)
5. Stonetalon, Ashenvale, Thousand Needles 23-30 (Blackfathom Deeps, a short trip to Shadowfang Keep, Razorfen Kraul)
6. Hillsbrad, Alterac, Arathi 30-33 (City of Dalaran, Excavation Site: Wetlands, Scarlet Monastery before the Arathi quests)
7. Stranglethorn, Desolace, Thousand Needles, Dustwallow 33-38 (The Drowned City, Razorfen Downs)
8. Riverglades 38-43 (Krol'dok Stronghold, Dire Bear, Kodo)
9. Arathi, Badlands, Swamp of Sorrows, Stranglethorn, Tanaris, Feralas, Desolace, Shen'dralas 43-48 (Uldaman, Zul'Farrak)
10. Desolace, Feralas, Tanaris, Dustwallow, Azshara, Hinterlands, Searing Gorge, Badlands 48-52 (Maraudon, Alcaz Prison)
11. Un'Goro, Tanaris, Feralas, Felwood, Azshara, then Hinterlands, Searing Gorge, Stranglethorn, Blasted Lands, Burning Steppes 52-56 (Sunken Temple, Blackrock Depths)
12. Plaguelands, Blasted Lands, then Winterspring, Felwood, Azshara, Un'Goro, Silithus, Mount Hyjal 56-60 (Blackmaw Hold, Shaper's Terrace)

## Known limits

- Kill XP is an estimate (40% on top of quest XP, half a level per dungeon run); if you level faster or slower, the guide still follows your quests, and warns when quests are above you.
- Quest data is community data, not Blizzard's. Some Forever quests may be missing or placed oddly; skip a stuck step with `/emg next` or "Skip this step" in the settings.
- Quest order inside a zone is worked out by distance, so it is good but not hand-tuned.
- Quests started by a looted item are optional pickups ("Look out for"), never required.
- A few quests have no location in the community data, so the arrow cannot point at them.
- The guide drops quests that hand in somewhere the route never goes back to.
- The route never asks you to carry more than 20 quests at once, but at its busiest it fills your log: keep a slot free by finishing a quest before you pick up anything extra.

## Development

The packaged addon only contains the runtime files. The source repository also has `tools/` (route specification `route.py`, generator `gen.py`, level simulation `xp.py`, database decoder `extract_questiedb.py`, arrow and logo drawing `make_arrow.py` and `make_logo.py`) and `tests/`.


```bash
python3 -I tools/extract_questiedb.py "/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc" /tmp/emg-db.json
python3 -I tools/gen.py /tmp/emg-db.json "/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestieDB" .
luajit tests/run.lua
```

The generator also simulates a character walking the route, using QuestieDB's real Forever quest XP (aggregated from real Forever sessions, scaled by level with Questie's formula) and the Classic-era XP curve. Kill XP is not in any database: it is modelled as 40% on top of quest XP (`KILL_SHARE`) plus half a level per dungeon run (`DUNGEON_RUN_LEVEL`), both in `tools/xp.py`. The simulation sets the chapter level ranges and adds the grind steps; every build prints a per-chapter report with three columns (quests only; with the kill assumptions but no grinds; as routed) and how much XP the grind steps stand for. Treat the levels as estimates good to a few levels.

The arrow texture is drawn by `python3 -I tools/make_arrow.py Media/Arrow.tga`.

Edit `tools/route.py` to change the route, then rebuild. Never edit `Guide/*.lua` by hand.

## Language

The guide text is English. Quest and NPC names come from the English game data.

## Support

Earthmother's Guide is free and open source, and it stays that way. If it saved you some alt-tabbing on the way to 60, you can buy me a coffee on [Ko-fi](https://ko-fi.com/v4rdr). Tips are optional and go toward keeping the route up to date as Forever changes.

Bug reports and route fixes help just as much. If you run into a problem, comment on the CurseForge page or open an issue at https://github.com/RNYR/EarthmothersGuide/issues, ideally with the output of `/emg status` or `/emg check <questID>`.

## Credits and license

Earthmother's Guide is licensed under the GNU GPL v3 only (GPL-3.0-only, see `LICENSE`). Its quest, NPC and
coordinate data is derived from [QuestieDB](https://github.com/Questie/QuestieDB) and
[Questie](https://github.com/Questie/Questie), used under the GPL v3. See `NOTICE.md` for details.
World of Warcraft names and quest text are (c) Blizzard Entertainment. This is a fan-made add-on,
not affiliated with Blizzard.
