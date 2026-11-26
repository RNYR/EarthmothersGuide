# Notices

Copyright (C) 2026 Vard Ruun

Earthmother's Guide is free software: you can redistribute it and/or modify it under the terms of
the GNU General Public License as published by the Free Software Foundation, version 3 of the
License only (GPL-3.0-only), because its quest data is used under the GPLv3 terms its source
permits, which name no later version. See `LICENSE`.

## Quest data

The quest, NPC, object, item and coordinate data in `Guide/*.lua` is derived from
[QuestieDB](https://github.com/Questie/QuestieDB) v1.1.5, Forever flavor (build commit
`47a4756b775e8c73687fd3066d6c13f0bc43a55e`), which builds on
[Questie](https://github.com/Questie/Questie). That data is the work of the Questie and
QuestieDB contributors.

The Questie team permits reuse of its work under the GPLv3 terms, and that is the permission
this project relies on. Both upstream licence files say plainly that the historic data never
had a formal licence, that they cannot promise every historic contributor agreed, and that
anything not covered should be treated as "all rights reserved"
([QuestieDB LICENSE.md](https://github.com/Questie/QuestieDB/blob/master/LICENSE.md),
[Questie LICENSE.md](https://github.com/Questie/Questie/blob/master/LICENSE.md)). If you
contributed to that data and object to its use here, open an issue at https://github.com/RNYR/EarthmothersGuide/issues and it will
be removed.

Earthmother's Guide modified the data: `tools/gen.py` filters it for a Tauren Druid, orders it
into a 1-60 route, and reformats it as Lua tables. The Questie name and logo are not used for
branding.

The source needed to regenerate `Guide/*.lua` (the route specification `tools/route.py`, the
generator `tools/gen.py` and the database decoder `tools/extract_questiedb.py`) is in this
project's public source repository: https://github.com/RNYR/EarthmothersGuide

## World of Warcraft

World of Warcraft, Warcraft and all quest, NPC, zone, item and spell names and quest text are
trademarks and/or copyright of Blizzard Entertainment, Inc. The GPL covers only Earthmother's
Guide's own code, route and artwork, not Blizzard's names and text. Earthmother's Guide is a
fan-made add-on and is not affiliated with or endorsed by Blizzard Entertainment.

## Artwork

`Media/Arrow.tga` is original artwork drawn by `tools/make_arrow.py` (GPL v3, part of this
project). Icons referenced at runtime (`Interface\Icons\...`) are the game's own and are not
redistributed.
