# Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-or-later; see LICENSE and NOTICE.md.
"""The 1-60 Tauren Druid route for WoW: Forever.

gen.py turns this into Guide/*.lua. Segment types:
  quests   all Tauren-druid quests in `zones` within `levels`, ordered by hub and distance
  dungeon  gather / run / turn in the listed dungeon quests (tagged so they can be switched off)
  chain    hand-written steps with explicit quest IDs (class quests)
  flush    turn in every carried quest whose finisher is in `zones`
  step     one hand-written step (travel, level, training, note)
Area IDs are WoW AreaTable IDs (the same ones QuestieDB uses).
"""

# Zones
MULGORE, THUNDER_BLUFF, BARRENS, ORGRIMMAR, DUROTAR, MOONGLADE = 215, 1638, 17, 1637, 14, 493
SILVERPINE, TIRISFAL, UNDERCITY, STONETALON, ASHENVALE, NEEDLES = 130, 85, 1497, 406, 331, 400
HILLSBRAD, ALTERAC, ARATHI, WETLANDS, STV, DESOLACE, DUSTWALLOW = 267, 36, 45, 11, 33, 405, 15
TANARIS, FERALAS, RIVERGLADES, SHENDRALAS, BADLANDS, SWAMP = 440, 357, 16591, 16651, 3, 8
HINTERLANDS, SEARING, UNGORO, FELWOOD, AZSHARA, STEPPES = 47, 51, 490, 361, 16, 46
WPL, EPL, WINTERSPRING, SILITHUS, BLASTED, HYJAL = 28, 139, 618, 1377, 4, 616

HUB_AREAS = {THUNDER_BLUFF, ORGRIMMAR, UNDERCITY, MOONGLADE}
KALIMDOR = {MULGORE, THUNDER_BLUFF, BARRENS, ORGRIMMAR, DUROTAR, MOONGLADE, STONETALON, ASHENVALE, NEEDLES,
            DESOLACE, DUSTWALLOW, TANARIS, FERALAS, SHENDRALAS, UNGORO, FELWOOD, AZSHARA, WINTERSPRING,
            SILITHUS, HYJAL}


def continent(area):
    """'K' for Kalimdor, 'E' for the Eastern Kingdoms (Riverglades counted with Kalimdor: its ship leaves Tanaris)."""
    return 'K' if area in KALIMDOR or area == RIVERGLADES else 'E'
TRAIN_AREAS = (THUNDER_BLUFF, MOONGLADE)
ALL_AREAS = {v for k, v in dict(globals()).items() if k.isupper() and isinstance(v, int)}
ZONE_DISPLAY = {SHENDRALAS: "Shen'dralas", UNGORO: "Un'Goro Crater", STV: 'Stranglethorn Vale'}

# Spells
BEAR, AQUATIC, CAT, TRAVEL, DIRE_BEAR, TELEPORT_MOONGLADE = 5487, 1066, 768, 783, 9634, 18960

# Quests the generator must never pick up: other classes' or professions' quests that the
# database does not mark, seasonal / PvP / raid quests, and alternative starts for other races.
EXCLUDE = [
    861,                    # The Hunter's Way (hunter)
    76156, 76160, 76240,    # Stalk With The Earthmother (season rune quests)
    5927, 5928,             # Heeding the Call alternatives (we use 5926)
    9121, 9122, 9123,       # The Dread Citadel - Naxxramas (raid attunement, not leveling)
    5401, 92842, 91882,     # Alliance-side versions (Chillwind Camp, Nethergarde); Horde take 5405/97319
    1367,                   # Magram Alliance - opposes Gelkis Alliance (1368); a Tauren can only side with one
    854,                    # Journey to the Crossroads (Kirge Sternhorn breadcrumb, Barrens side)
]


# Quests that need a profession (crafted, skinned, fished or cooked items). Kept in the route but
# tagged, so the addon can leave them out when "Include profession quests" is off.
PROFESSION = {
    713: 'Alchemy', 715: 'Alchemy', 515: 'Alchemy',
    716: 'Blacksmithing', 1203: 'Blacksmithing', 96026: 'Blacksmithing',
    714: 'Engineering', 1371: 'Engineering', 6026: 'Engineering',
    2822: 'Skinning', 7734: 'Skinning',
    92817: 'Leatherworking', 90854: 'Leatherworking',
    92814: 'Tailoring',
    91610: 'Fishing',
    95982: 'Cooking', 97119: 'Cooking',
}


# Far-away cities: a quest waiting to be handed in there gets a detour once it is this many
# levels below the route, so it is handed in before it loses its XP.
CITY_AREAS = (ORGRIMMAR, UNDERCITY, THUNDER_BLUFF, MULGORE)
MAX_WAIT_LEVELS = 4

# How to get to a zone (used for travel steps and detours). Hearthstone hints are added
# automatically when your hearth is set in the destination.
TRAVEL_TIPS = {
    UNDERCITY: "Zeppelin from Orgrimmar (or from Grom'gol in Stranglethorn).",
    ORGRIMMAR: 'Fly to Orgrimmar, or take the zeppelin.',
    THUNDER_BLUFF: 'Fly to Thunder Bluff - or cast Teleport: Moonglade and train/hand in at Nighthaven if that is all you need.',
    MOONGLADE: 'Cast Teleport: Moonglade - it does not use your hearthstone.',
    FELWOOD: 'Fly to Bloodvenom Post, or ride north from Ashenvale. In Felwood, take Timbermaw Ally from Grazle in Deadwood Village: the Timbermaw quests make the Moonglade tunnel safe later.',
    WINTERSPRING: "Timbermaw Hold is still hostile to you, so the furbolgs in the tunnel attack: run straight through, don't fight. Finishing the Felwood Timbermaw quests (Grazle, Nafien) makes it safe.",
    STV: "Zeppelin from Orgrimmar to Grom'gol Base Camp.",
    RIVERGLADES: 'Steamwheedle ship from Tanaris to Powderfuse Port.',
    SILVERPINE: 'Zeppelin to Undercity, then ride south.',
    HILLSBRAD: 'Zeppelin to Undercity, then ride south through Silverpine.',
    TANARIS: 'Fly to Gadgetzan.',
}


# Tips that only apply once you have a reputation standing (checked live in the game).
# Timbermaw Hold (faction 576) starts Hostile; its furbolgs stop attacking at Unfriendly (3).
TIMBERMAW, UNFRIENDLY = 576, 3
REP_TIPS = {
    FELWOOD: (TIMBERMAW, UNFRIENDLY, 'Druid shortcut: Teleport: Moonglade, then walk south through the Timbermaw Hold tunnel into Felwood - the furbolgs leave you alone now.'),
    WINTERSPRING: (TIMBERMAW, UNFRIENDLY, 'Druid shortcut: Teleport: Moonglade, then walk east through the Timbermaw Hold tunnel into Winterspring - the furbolgs leave you alone now.'),
}


def bind(npc_id, place, area):
    """Set your hearthstone with this innkeeper. `place` is the name the game reports."""
    return {'type': 'bind', 'npc': npc_id, 'place': place, 'area': area}


def step(**kw):
    return {'type': 'step', 'step': kw}


def train(lvl):
    where = 'Bloodhoof Village or Thunder Bluff' if lvl < 10 else 'Moonglade or Thunder Bluff'
    return step(t='train', lvl=lvl, text=f'Level {lvl}: train new druid ranks ({where}).')


def quests(zones, lo, hi, **kw):
    d = {'type': 'quests', 'zones': zones if isinstance(zones, list) else [zones], 'levels': (lo, hi)}
    d.update(kw)
    return d


def dungeon(name, lo, hi, quest_ids=(), zones=(), note=None, turnin_zones=()):
    return {'type': 'dungeon', 'name': name, 'levels': (lo, hi), 'quests': list(quest_ids),
            'zones': list(zones), 'note': note, 'turnin_zones': list(turnin_zones)}


def flush(*zones):
    return {'type': 'flush', 'zones': list(zones)}


def chain(*steps):
    return {'type': 'chain', 'steps': list(steps)}


CHAPTERS = [
    {'file': 'Ch01_Mulgore.lua', 'title': 'Mulgore', 'levels': (1, 10), 'segments': [
        step(t='note', text='Welcome, Earthmother\'s child. Camp Narache first: talk to every "!" around the camp.',
             tip='Druid: keep Healing Touch for emergencies, Wrath to pull, melee to save mana.'),
        quests([MULGORE], 1, 7, box=(30, 70, 70, 95)),
        step(t='goto', text='Run north along the road to Bloodhoof Village.', area=MULGORE, x=47.0, y=60.5, radius=4),
        bind(6747, 'Bloodhoof Village', MULGORE),
        step(t='note', text='Grab the Bloodhoof Village flight path.'),
        train(4),
        quests([MULGORE], 4, 12, box=(30, 40, 70, 75), turnin_zones=[THUNDER_BLUFF]),
        train(8),
        step(t='level', lvl=10, text='Finish the Bloodhoof quests until you reach level 10.'),
        step(t='zone', text='Head north to Thunder Bluff.', area=THUNDER_BLUFF),
        flush(THUNDER_BLUFF),
        train(10),
        chain(
            dict(t='accept', q=[5926], text='Heeding the Call - from Innkeeper Pala'),
            dict(t='turnin', q=[5926]),
            dict(t='accept', q=[5922]),
            dict(t='spell', spell=TELEPORT_MOONGLADE, text='Learn Teleport: Moonglade from your trainer if you have not already.',
                 tip='Teleport: Moonglade is a druid-only second hearthstone: it does not use your hearthstone. Moonglade has a druid trainer (Loganaar), so you can train there and then hearth back to your quests.'),
            dict(t='turnin', q=[5922], text='Teleport to Moonglade and talk to Dendrite Starblaze'),
            dict(t='accept', q=[5930]),
            dict(t='complete', q=[5930], text='Talk to the Great Bear Spirit in north-western Moonglade',
                 tip='Just listen to the spirit; no fighting.'),
            dict(t='turnin', q=[5930]),
            dict(t='accept', q=[5932]),
            dict(t='turnin', q=[5932], text='Hearth or teleport back and see Turak Runetotem in Thunder Bluff'),
            dict(t='accept', q=[6002], tip='Lunaclaw waits at the Moonkin Stone west of Camp Taurajo; do it on the way into the Barrens.'),
        ),
    ]},
    {'file': 'Ch02_Barrens.lua', 'title': 'The Barrens', 'levels': (10, 16), 'segments': [
        step(t='zone', text='Leave Mulgore east through the gates into the Barrens.', area=BARRENS),
        bind(3934, 'The Crossroads', BARRENS),
        chain(
            dict(t='complete', q=[6002], m=1413, zone='The Barrens', x=42.0, y=60.9,
                 text='Use the Cenarion Lunardust at the Moonkin Stone and defeat Lunaclaw',
                 tip='Lunaclaw is level 12. Open with Moonfire, fight in melee, heal at half health.'),
        ),
        quests([BARRENS], 10, 15),
        train(12),
        step(t='zone', text='Back to Thunder Bluff for training and turn-ins.', area=THUNDER_BLUFF),
        chain(dict(t='turnin', q=[6002], tip='Body and Heart rewards Bear Form.')),
        step(t='spell', spell=BEAR, text='Learn Bear Form.'),
        flush(THUNDER_BLUFF),
        train(14),
        chain(
            dict(t='accept', q=[6126], text='Lessons Anew - the Cure Poison quest'),
            dict(t='turnin', q=[6126], text='Teleport to Moonglade and talk to Dendrite Starblaze'),
            dict(t='accept', q=[6127]),
            dict(t='complete', q=[6127], m=1413, zone='The Barrens', x=48.4, y=18.9,
                 text='Fill the Empty Dreadmist Peak Sampler at the pool on top of Dreadmist Peak'),
            dict(t='turnin', q=[6127], text='Bring the sample to Tonga Runetotem at the Crossroads'),
            dict(t='accept', q=[6128]),
            dict(t='complete', q=[6128], text='Collect the cure ingredients in the Barrens'),
            dict(t='turnin', q=[6128]),
            dict(t='accept', q=[6129]),
            dict(t='complete', q=[6129], text='Cure the sick creatures'),
            dict(t='turnin', q=[6129]),
            dict(t='accept', q=[6130]),
            dict(t='turnin', q=[6130]),
        ),
        dungeon('Ragefire Chasm', 13, 18, zones=[2437], turnin_zones=[ORGRIMMAR, THUNDER_BLUFF, BARRENS]),
        quests([BARRENS], 14, 17),
    ]},
    {'file': 'Ch03_Silverpine.lua', 'title': 'Aquatic Form and Silverpine', 'levels': (16, 21), 'segments': [
        train(16),
        chain(
            dict(t='accept', q=[27]),
            dict(t='turnin', q=[27], text='Teleport to Moonglade and talk to Dendrite Starblaze'),
            dict(t='accept', q=[28]),
            dict(t='complete', q=[28], text="Dive into Lake Elune'ara for a Shrine Bauble and use it at the Shrine of Remulos"),
            dict(t='turnin', q=[28]),
            dict(t='accept', q=[30], tip='Pendant halves for Horde: a lockbox near the Sludge Fen (north Barrens) and one off the Silverpine coast.'),
        ),
        step(t='zone', text='Take the zeppelin from Orgrimmar to Undercity.', area=UNDERCITY),
        step(t='zone', text='Ride south into Silverpine Forest.', area=SILVERPINE),
        bind(6739, 'The Sepulcher', SILVERPINE),
        quests([SILVERPINE], 10, 24, turnin_zones=[UNDERCITY]),
        dungeon('Ruins of Lordaeron', 15, 22, zones=[16611], turnin_zones=[UNDERCITY, TIRISFAL, SILVERPINE],
                note='Ruins of Lordaeron (new): the entrance is under Undercity. Grab its quests in Undercity, Tirisfal and Silverpine.'),
        dungeon('Shadowfang Keep', 20, 27, zones=[209], turnin_zones=[SILVERPINE, UNDERCITY]),
        step(t='goto', text='Aquatic Form: dive to the lockbox off the Silverpine coast and loot one Half Pendant.',
             area=SILVERPINE, x=29.6, y=29.2, radius=2),
    ]},
    {'file': 'Ch04_BarrensWC.lua', 'title': 'Barrens and Wailing Caverns', 'levels': (18, 23), 'segments': [
        bind(3934, 'The Crossroads', BARRENS),
        chain(
            dict(t='complete', q=[30], m=1413, zone='The Barrens', x=56.7, y=8.3,
                 text='Loot the other Half Pendant from the lockbox near the Sludge Fen, then join both halves at the Shrine of Remulos in Moonglade'),
            dict(t='turnin', q=[30]),
            dict(t='accept', q=[31]),
            dict(t='turnin', q=[31], tip='Pick the Idol of Shifting Tides: 40 less mana per shapeshift.'),
        ),
        step(t='spell', spell=AQUATIC, text='Learn Aquatic Form.'),
        quests([BARRENS], 16, 23),
        dungeon('Wailing Caverns', 17, 26, zones=[718], turnin_zones=[BARRENS, THUNDER_BLUFF],
                note='Wailing Caverns: optional extra - the 5-piece Fang set turns your Cat Form into a snake.'),
        train(20),
        chain(
            dict(t='accept', q=[98340], text='The Great Cat Spirit - the Cat Form quest'),
            dict(t='turnin', q=[98340], text='Teleport to Moonglade and talk to Dendrite Starblaze'),
            dict(t='accept', q=[98405]),
            dict(t='turnin', q=[98405], text='Find the Great Cat Spirit on the hill in southern Moonglade'),
            dict(t='accept', q=[98342]),
            dict(t='complete', q=[98342], text='Recover the Claw, Fang and Silent Shadow relics in the Stormrage Barrow Dens',
                 tip='Touch the cat statue at the entrance for stealth. If you are spotted, shift to bear.'),
            dict(t='turnin', q=[98342]),
            dict(t='accept', q=[98739]),
            dict(t='turnin', q=[98739]),
            dict(t='accept', q=[98362]),
            dict(t='turnin', q=[98362]),
        ),
        step(t='spell', spell=CAT, text='Learn Cat Form.'),
    ]},
    {'file': 'Ch05_StonetalonAshenvaleNeedles.lua', 'title': 'Stonetalon, Ashenvale and Thousand Needles',
     'levels': (20, 30), 'segments': [
        bind(7731, 'Sun Rock Retreat', STONETALON),
        quests([STONETALON], 17, 27, giver_zones=[BARRENS]),
        quests([ASHENVALE], 19, 28),
        dungeon('Blackfathom Deeps', 22, 30, zones=[719], turnin_zones=[ASHENVALE, ORGRIMMAR, THUNDER_BLUFF]),
        train(24),
        quests([BARRENS], 20, 27),
        bind(11116, 'Freewind Post', NEEDLES),
        quests([NEEDLES], 24, 31),
        dungeon('Razorfen Kraul', 25, 33, zones=[491, 1717], turnin_zones=[BARRENS, THUNDER_BLUFF]),
        train(28),
    ]},
    {'file': 'Ch06_HillsbradArathi.lua', 'title': 'Hillsbrad, Alterac and Arathi', 'levels': (28, 35), 'segments': [
        train(30),
        step(t='spell', spell=TRAVEL, text='Learn Travel Form at your trainer.'),
        step(t='zone', text='Zeppelin to Undercity, then south through Silverpine to Tarren Mill.', area=HILLSBRAD),
        bind(2388, 'Tarren Mill', HILLSBRAD),
        quests([HILLSBRAD], 24, 34, turnin_zones=[UNDERCITY]),
        quests([ALTERAC], 30, 36, giver_zones=[HILLSBRAD]),
        dungeon('City of Dalaran', 28, 35, zones=[16544], turnin_zones=[HILLSBRAD, ALTERAC],
                note='City of Dalaran (new): the key chain starts with Magus Wordeen Voidglare in Tarren Mill.'),
        quests([ARATHI], 30, 37),
        dungeon('Excavation Site: Wetlands', 26, 33, zones=[16732], turnin_zones=[ARATHI, ORGRIMMAR, WETLANDS],
                note='Excavation Site: Wetlands (new): it sits in Alliance land, so bring a group.'),
        dungeon('Scarlet Monastery', 30, 42, zones=[796], turnin_zones=[UNDERCITY, TIRISFAL, HILLSBRAD]),
        train(32),
    ]},
    {'file': 'Ch07_StranglethornDesolace.lua', 'title': 'Stranglethorn and Desolace', 'levels': (32, 40), 'segments': [
        step(t='zone', text="Zeppelin from Orgrimmar to Grom'gol in Stranglethorn.", area=STV),
        bind(5814, "Grom'gol Base Camp", STV),
        quests([STV], 30, 39),
        dungeon('The Drowned City', 35, 40, quest_ids=[95775, 95776, 95789, 95791, 96774], turnin_zones=[STV, MULGORE],
                note='The Drowned City (new): quests from Grom\'gol, Booty Bay and Mazu\'kon in north-west Mulgore.'),
        train(34),
        bind(11106, 'Shadowprey Village', DESOLACE),
        quests([DESOLACE], 30, 39),
        quests([NEEDLES], 30, 39),
        quests([DUSTWALLOW], 34, 39),
        flush(BARRENS),
        dungeon('Razorfen Downs', 35, 45, zones=[722], turnin_zones=[THUNDER_BLUFF, NEEDLES, SHENDRALAS, BARRENS]),
        train(36),
    ]},
    {'file': 'Ch08_Riverglades.lua', 'title': 'Riverglades', 'levels': (37, 44), 'segments': [
        step(t='zone', text='Fly to Gadgetzan and take the Steamwheedle ship to Powderfuse Port.', area=RIVERGLADES,
             tip='Riverglades has nearly 200 quests and replaces the old 36-44 zone hopping.'),
        bind(256675, "Rog'mar", RIVERGLADES),
        quests([RIVERGLADES], 36, 46),
        dungeon("Krol'dok Stronghold", 40, 45, quest_ids=[94968, 94972, 94975], turnin_zones=[RIVERGLADES]),
        train(40),
        step(t='spell', spell=DIRE_BEAR, text='Learn Dire Bear Form at your trainer.'),
        step(t='note', text='Level 40: buy your Kodo from Harb Clawhoof in Bloodhoof Village and train riding.'),
        train(42),
    ]},
    {'file': 'Ch09_TanarisFeralasShendralas.lua', 'title': "Tanaris, Feralas and Shen'dralas", 'levels': (42, 48), 'segments': [
        bind(7733, 'Gadgetzan', TANARIS),
        quests([TANARIS], 40, 48),
        bind(7737, 'Camp Mojache', FERALAS),
        quests([FERALAS], 40, 49),
        quests([DESOLACE], 40, 46),
        quests([SHENDRALAS], 38, 46, giver_zones=[DESOLACE],
               note="Shen'dralas (new): the way in starts with Uthek the Wise in Desolace and leads south through the Valley of Bones."),
        dungeon("Zul'Farrak", 44, 54, zones=[1176, 978], turnin_zones=[TANARIS, NEEDLES]),
        train(44),
        step(t='note', text="Eastern Kingdoms trip: zeppelin from Orgrimmar to Undercity for Arathi and the Badlands."),
        quests([ARATHI], 38, 45),
        quests([BADLANDS], 36, 46),
        dungeon('Uldaman', 40, 51, zones=[1337, 1517], turnin_zones=[BADLANDS]),
        quests([SWAMP], 40, 46),
        quests([STV], 40, 46),
        train(46),
    ]},
    {'file': 'Ch10_DustwallowHinterlands.lua', 'title': 'Maraudon, Dustwallow and the Hinterlands', 'levels': (46, 52),
     'segments': [
        dungeon('Maraudon', 45, 55, zones=[2100], turnin_zones=[DESOLACE, SHENDRALAS]),
        quests([FERALAS], 48, 51),
        quests([TANARIS], 48, 51),
        quests([DUSTWALLOW], 40, 53),
        dungeon('Alcaz Prison', 48, 53, quest_ids=[95285, 95309, 96332, 96334], turnin_zones=[DUSTWALLOW]),
        train(48),
        quests([AZSHARA], 45, 51),
        step(t='note', text='Eastern Kingdoms trip: the Hinterlands, Searing Gorge and the Badlands.'),
        bind(14731, 'Revantusk Village', HINTERLANDS),
        quests([HINTERLANDS], 42, 53),
        quests([SEARING], 43, 51),
        quests([BADLANDS], 43, 51),
        train(50),
    ]},
    {'file': 'Ch11_UngoroFelwoodAzshara.lua', 'title': "Un'Goro, Felwood, Azshara and Burning Steppes", 'levels': (50, 56),
     'segments': [
        chain(
            dict(t='accept', q=[9063], text='Torwa Pathfinder - druid quest for Un\'Goro'),
        ),
        bind(7733, 'Gadgetzan', TANARIS),
        quests([UNGORO], 48, 55),
        chain(
            dict(t='turnin', q=[9063]),
            dict(t='accept', q=[9052]),
            dict(t='complete', q=[9052]),
            dict(t='turnin', q=[9052]),
            dict(t='accept', q=[9051]),
            dict(t='complete', q=[9051]),
            dict(t='turnin', q=[9051]),
            dict(t='accept', q=[9053]),
            dict(t='complete', q=[9053]),
            dict(t='turnin', q=[9053]),
        ),
        step(t='note', text="Before leaving Un'Goro, collect power crystals - Shaper's Terrace at 58 needs them."),
        quests([TANARIS], 50, 56),
        quests([FERALAS], 50, 56),
        quests([FELWOOD], 47, 55),
        quests([AZSHARA], 50, 56),
        train(52),
        step(t='note', text='Eastern Kingdoms trip: Sunken Temple, Searing Gorge, the Burning Steppes and Blackrock Depths.'),
        dungeon('Sunken Temple', 50, 60, zones=[1477, 1417], turnin_zones=[SWAMP]),
        quests([HINTERLANDS], 50, 56),
        quests([SEARING], 50, 56),
        quests([STV], 50, 56),
        quests([BLASTED], 50, 56),
        bind(9356, 'Kargath', BADLANDS),
        quests([STEPPES], 50, 56),
        dungeon('Blackrock Depths', 52, 60, zones=[1584, 1585], turnin_zones=[STEPPES, SEARING, BADLANDS]),
        train(54),
    ]},
    {'file': 'Ch12_PlaguelandsWinterspring.lua', 'title': 'Plaguelands, Winterspring and Silithus', 'levels': (55, 60),
     'segments': [
        dungeon('Blackmaw Hold', 55, 60, quest_ids=[92066, 92065, 96246, 97198], turnin_zones=[AZSHARA, MULGORE]),
        quests([WPL], 50, 58, giver_zones=[TIRISFAL], turnin_zones=[UNDERCITY]),
        bind(16256, "Light's Hope Chapel", EPL),
        quests([EPL], 53, 60, turnin_zones=[WPL, TIRISFAL]),
        quests([BLASTED], 54, 59),
        train(56),
        step(t='zone', text='Travel to Winterspring (Everlook).', area=WINTERSPRING),
        bind(11118, 'Everlook', WINTERSPRING),
        quests([WINTERSPRING], 52, 60),
        flush(EPL, TIRISFAL, WPL),
        quests([FELWOOD], 54, 59),
        quests([AZSHARA], 54, 59),
        quests([UNGORO], 54, 59),
        quests([SILITHUS], 54, 59),
        step(t='note', text='Mount Hyjal is through Darkwhisper Gorge in southern Winterspring.'),
        quests([HYJAL], 56, 60),
        flush(WINTERSPRING, THUNDER_BLUFF, ORGRIMMAR, DUROTAR, BARRENS, TANARIS),
        train(58),
        dungeon("Shaper's Terrace", 58, 60, zones=[16985], turnin_zones=[UNGORO, SILITHUS, MULGORE]),
        step(t='zone', text='Head to Undercity to hand in the quests waiting there.', area=UNDERCITY),
        step(t='level', lvl=60, text='Finish any quests left in your log until you reach level 60.'),
        train(60),
        step(t='note', text='Level 60! Scholomance, Stratholme and Blackrock Spire quests are endgame from here.'),
    ]},
]
