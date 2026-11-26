# Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.
"""Level simulation for the route, from real WoW: Forever quest XP.

Quest XP: QuestieDB's Forever XP traces (aggregated from real Forever sessions), falling back to
its Classic table; scaled by the player's level with the same formula Questie uses (from cmangos).
XP per level: the Classic-era curve (Forever keeps the Classic XP curve).
Kill XP is not in any database; it is modelled as a share on top of quest XP (KILL_SHARE).
"""
import os, re

# XP needed to go from level L to L+1 (Classic-era curve, levels 1-59).
XP_TO_NEXT = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900,
              14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900,
              41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
              95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900,
              160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800]
MAX_LEVEL = 60

# Kill XP on top of quest XP while questing (the mobs you kill for objectives and on the way).
# Not in any database: 0.0 gives the hard lower bound, 0.4 a typical questing estimate.
KILL_SHARE = 0.4

# Kill XP from one full run of a leveling dungeon, as a share of the level you are at (an
# assumption, like KILL_SHARE; the dungeon's quest XP is counted separately from real data).
DUNGEON_RUN_LEVEL = 0.5


def load_quest_xp(qdb_dir):
    """quest id -> (quest level, base xp). Forever traces win over the Classic table."""
    xp = {}
    base = os.path.join(qdb_dir, 'support', 'Forever', 'QuestXP')
    classic = open(os.path.join(base, 'xpDB-classic.lua'), encoding='utf-8').read()
    for m in re.finditer(r'\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(\d+)\s*\}', classic):
        xp[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
    traces = open(os.path.join(base, 'xpDB-traces.lua'), encoding='utf-8').read()
    for m in re.finditer(r'QuestXP\.db\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(\d+)\s*\}', traces):
        xp[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
    return xp


def adjusted_xp(base_xp, quest_level, char_level):
    """Questie's (cmangos) scaling: full XP up to 5 levels below, then dropping to 10% when grey."""
    if char_level >= MAX_LEVEL or quest_level <= 0 or base_xp <= 0:
        return 0
    mult = max(1, min(10, 2 * (quest_level - char_level) + 20))
    xp = base_xp * mult / 10
    if xp <= 100:
        xp = 5 * ((xp + 2) // 5)
    elif xp <= 500:
        xp = 10 * ((xp + 5) // 10)
    elif xp <= 1000:
        xp = 25 * ((xp + 12) // 25)
    else:
        xp = 50 * ((xp + 25) // 50)
    return int(xp)


def grey_level(char_level):
    """Highest quest level that is grey (gives reduced XP) for a character - Classic's rule."""
    if char_level <= 5:
        return 0
    if char_level <= 39:
        return char_level - 5 - char_level // 10
    if char_level <= 59:
        return char_level - 1 - char_level // 5
    return char_level - 9


class Character:
    """A simulated character walking the route."""

    def __init__(self, quest_xp, kill_share=KILL_SHARE):
        self.quest_xp = quest_xp
        self.kill_share = kill_share
        self.level, self.xp = 1, 0

    @property
    def exact(self):
        """Level with the fraction of the current level, e.g. 23.4."""
        if self.level >= MAX_LEVEL:
            return float(MAX_LEVEL)
        return self.level + self.xp / XP_TO_NEXT[self.level]

    def gain(self, amount):
        while amount > 0 and self.level < MAX_LEVEL:
            need = XP_TO_NEXT[self.level] - self.xp
            if amount >= need:
                amount -= need
                self.level += 1
                self.xp = 0
            else:
                self.xp += amount
                amount = 0

    def run_dungeon(self):
        """Kill XP from clearing a dungeon at about its level."""
        if self.level < MAX_LEVEL:
            self.gain(int(DUNGEON_RUN_LEVEL * XP_TO_NEXT[self.level]))

    def turn_in(self, qid):
        """Hand in a quest; returns (xp gained, was it grey)."""
        lvl, base = self.quest_xp.get(qid, (0, 0))
        got = adjusted_xp(base, lvl, self.level)
        grey = lvl > 0 and lvl <= grey_level(self.level)
        self.gain(int(got * (1 + self.kill_share)))
        return got, grey
