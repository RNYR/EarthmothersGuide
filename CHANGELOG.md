# Changelog

## 1.0.0

First release.

If you run into a problem, comment on the CurseForge page or open an issue at
https://github.com/RNYR/EarthmothersGuide/issues - the output of `/emg status` or
`/emg check <questID>` helps.

Route
- 1-60 Tauren Druid route for WoW: Forever in 12 chapters, including Riverglades, Shen'dralas,
  Mount Hyjal and the new Forever dungeons.
- Druid class quests: Bear Form, Cure Poison, Aquatic Form, the new Cat Form chain, Travel Form,
  Dire Bear Form and the Torwa Pathfinder chain.
- Dungeons are part of the route, each reached inside its level range so you can queue with the
  group finder; if you are already above a dungeon's range, its steps are skipped.
- Quest batches as one checklist step; "Also carrying", "Coming up" and "Ready to hand in"
  sections. Escort and event quests have their own step.
- Hearthstone suggestions, travel steps with how to get there, detours for hand-ins that would
  lose XP, and Teleport: Moonglade tips (reputation-aware Timbermaw tunnel tip).
- Quests up to 4 levels above you are part of the route; level pacing simulated from real Forever
  quest XP (kill XP and dungeon runs are stated assumptions), with one short "grind to level" step.
- Never more than 20 quests in your log at once.

Panel
- Built-in arrow to the nearest unfinished objective, and a Blizzard map pin.
- Replaces Blizzard's quest tracker under the minimap while the guide is shown (combat-safe).
- A checkbox beside every quest skips just that quest; Done checkbox for notes.
- Quest item buttons beside their quest, as in Blizzard's quest tracker.
- "Panel max height" setting with a preview outline; longer steps scroll.
- Settings page with a route browser; compact mode; profession quest toggle.

Smart about where you are
- Starts where your character is: reads your level and finished quests.
- Skips quests once they turn grey (the game's grey rule); a grey chain start stays only while
  the rest of the chain is worth doing.
- Waits for the quest log to load at login; a step you chose by hand survives /reload.
- Quests started by looted items are optional "Look out for" pickups.
- Warns when a step's quests are 3 or more levels above you.

Licensed GPL-3.0-only, matching the GPLv3 terms the quest data is used under.
