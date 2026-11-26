# Changelog

## 1.0.2 (alpha)

**Alpha:** this release has only been tested briefly in the game. The route, panel and quest
item buttons may still have rough edges - please report anything odd with the output of
`/emg status` or `/emg check <questID>` at https://github.com/RNYR/EarthmothersGuide/issues.

Fixes from two independent reviews of 1.0.1 and of this release, and a reworked panel.

Panel
- Quest item buttons sit beside their quest, as in Blizzard's quest tracker (one per quest
  with a usable item), instead of a single button under the panel.
- New "Panel max height" setting (and `/emg height`): an outline shows the maximum while you
  change it. A step with more than fits scrolls with the mouse wheel; every quest is listed,
  the "+N more" cut-offs are gone.
- Giving Blizzard's tracker back in combat shows it at once when the game allows it, otherwise
  right after combat.

Dungeons
- Dungeons are always part of the route: the "Include dungeon steps" option and
  `/emg dungeons` are gone. Their quests are a big share of the XP.
- The route reaches every dungeon inside its level range, so you can queue with the group
  finder: Shadowfang Keep is now a short trip from Kalimdor at about 27, the Excavation Site
  comes after City of Dalaran, Scarlet Monastery before the Arathi quests. If you are already
  above a dungeon's range its steps are skipped - but never the trip that brings you there.
- Escort and event quests (Protect Kaya, Escorting Erland...) now have a step that tells you to
  do them. Zul'Farrak, Uldaman and Razorfen Kraul are run once, with their outdoor pickups first.

Quests and levels
- Quests are skipped when they turn grey by the game's own rule (it used to be 6 levels below
  you, which skipped quests still worth most of their XP). A grey quest that starts a chain stays
  only while a later part of the chain is still worth doing. If you changed this setting in
  1.0.1, it keeps your old value: `/emg gray grey` switches to the new rule.
- Quests up to 4 levels above you are part of the route, and Land Ho! waits for its follow-ups:
  one grind step is left.
- Training steps never come before you reach their level; Dire Bear Form comes when you reach
  40. The level simulation now counts the route's own "Reach level" steps, so chapter levels and
  training levels match.
- Quests that need several earlier quests are dropped if any one of those can no longer happen.

Travel
- Fewer wasted trips: due city hand-ins happen before you leave the area, sections start at the
  hub on their edge (the Bulwark on the way into the Plaguelands), and the Excavation Site no
  longer sends you back to Orgrimmar mid-trip. Class steps in another zone get a travel step.
- Zeppelin tips only when you change continent.

Fixes
- Removed the in-game Ko-fi link: Blizzard's add-on policy keeps donation requests out of the
  game. It stays on the CurseForge page, GitHub and in the README.
- At login the guide waits for the quest log to really load before trusting it, so it no
  longer skips past hand-ins on a slow login.
- A step you chose by hand stays put after `/reload`.
- "Skip this step" no longer lands on a hand-in that is already done.
- Less work per quest update late in the route.

## 1.0.1

- The direction arrow is one solid colour instead of a lit and a shaded half.
- Each quest's skip checkbox sits level with the first line of its quest.
- `/emg support` (also `kofi`, `coffee`, `donate`) and a "Buy me a coffee" button on the
  settings page show a link to tip the author on Ko-fi. Optional: the addon never asks on its own.
- New project logo.

## 1.0.0

First release.

- 1-60 Tauren Druid route for WoW: Forever in 12 chapters, including Riverglades, Shen'dralas,
  Mount Hyjal and the new Forever dungeons.
- Druid class quests: Bear Form, Cure Poison, Aquatic Form, the new Cat Form chain, Un'Goro.
- Quest batches as one checklist step; "Also carrying", "Coming up" and "Ready to hand in"
  sections.
- Built-in arrow to the nearest unfinished objective; Blizzard map pin.
- Hearthstone suggestions, travel steps, detours for hand-ins that would lose XP, and
  Teleport: Moonglade tips (reputation-aware Timbermaw tunnel tip).
- Starts where your character is: reads your level and finished quests.
- Settings page with options and a route browser; optional quest item button; compact mode;
  dungeon and profession quest toggles.
- Replaces Blizzard's quest tracker under the minimap while the guide is shown (combat-safe).
- Quests started by looted items as optional "Look out for" pickups.
- Warns when a step's quests are 3 or more levels above you.
- Never more than 20 quests in your log at once.
- A checkbox beside every quest on the panel skips just that quest; Done checkbox for notes.
- Licensed GPL-3.0-only, matching the GPLv3 terms the quest data is used under.
- Level pacing simulated from real Forever quest XP (kill XP and dungeon runs are stated assumptions);
  a few short "grind to level" steps where quests run out.
