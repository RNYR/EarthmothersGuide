# Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-or-later; see LICENSE and NOTICE.md.
"""Generate Guide/ChNN_*.lua from the route spec (route.py) and decoded QuestieDB Forever data.

Usage:
  python3 -I tools/extract_questiedb.py <QuestieDB_Forever.toc> /tmp/db.json
  python3 -I tools/gen.py /tmp/db.json <QuestieDB dir> <addon dir>

Quest names, NPCs, coordinates, prerequisites and objectives all come from the database.
The route (zone order, level windows, class and travel steps) comes from route.py.
"""
import json, math, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import route  # noqa: E402
import xp as xpsim  # noqa: E402

DB = json.load(open(sys.argv[1]))
QDB_DIR = sys.argv[2]
OUT_DIR = sys.argv[3]
Q, N, O, I = DB['quests'], DB['npcs'], DB['objects'], DB['items']

TAUREN, DRUID = 32, 1024

QUEST_XP = xpsim.load_quest_xp(QDB_DIR)

# quests a dungeon section lists by ID stay in that section (they often have no zone of their own)
DUNGEON_QUESTS = {q for ch in route.CHAPTERS for seg in ch['segments']
                  if seg.get('type') == 'dungeon' for q in seg.get('quests', [])}

# quest -> quests that lead to it (breadcrumbs, and the previous part of a chain)
LEADS_TO = {}
for _k, _q in Q.items():
    for _t in (_q.get('breadcrumbFor'), _q.get('next')):
        if _t:
            LEADS_TO.setdefault(_t, []).append(int(_k))

# quest -> quests it disables (field disabledBy) / quests only available until it is done
DISABLED_BY, AVAILABLE_UNTIL = {}, {}
for _k, _q in Q.items():
    if _q.get('disabledBy'):
        DISABLED_BY.setdefault(_q['disabledBy'], []).append(int(_k))
    if _q.get('availUntil'):
        AVAILABLE_UNTIL.setdefault(_q['availUntil'], []).append(int(_k))


def parse_pairs(path):
    out = {}
    for m in re.finditer(r'\[(\d+)\]\s*=\s*(\d+)', open(path, encoding='utf-8').read()):
        out.setdefault(int(m.group(1)), int(m.group(2)))
    return out


ZDIR = os.path.join(QDB_DIR, 'support', 'Forever', 'Zones')
AREA_TO_MAP = parse_pairs(os.path.join(ZDIR, 'areaIdToUiMapId.lua'))
SUB_TO_PARENT = parse_pairs(os.path.join(ZDIR, 'subZoneToParentZone.lua'))
ZONE_NAMES = {}
for m in re.finditer(r'([A-Z_0-9]+)\s*=\s*(-?\d+)',
                     open(os.path.join(QDB_DIR, 'src', 'corrections', 'enum', 'zones.lua')).read()):
    ZONE_NAMES.setdefault(int(m.group(2)), m.group(1).replace('_', ' ').title()
                          .replace("'S", "'s").replace(' Of ', ' of ').replace(' The ', ' the '))
ZONE_NAMES.update(route.ZONE_DISPLAY)


def parent(area):
    seen = 0
    while area in SUB_TO_PARENT and SUB_TO_PARENT[area] != area and seen < 5:
        area = SUB_TO_PARENT[area]
        seen += 1
    return area


# Quests seen on real Forever characters (QuestieDB's aggregated XP traces). Season of Discovery
# quests (IDs 76000-83999) are only routed when Forever players have actually done them.
TRACED = {int(m) for m in re.findall(r'QuestXP\.db\[(\d+)\]',
          open(os.path.join(QDB_DIR, 'support', 'Forever', 'QuestXP', 'xpDB-traces.lua')).read())}
SOD_RANGE = range(76000, 84000)

# Factions a Tauren starts Hostile with: any minimum standing with them (even Neutral) gates a quest.
HOSTILE_START = {87, 92, 93, 576}   # Bloodsail Buccaneers, Gelkis, Magram, Timbermaw Hold

LOG_CAP = 20   # quests you can carry at once (Classic-era limit; kept as the safe bound)
MAX_GRIND = 3  # at most this many levels of grinding before a quest; bigger gaps wait for a later pass


def exists_on_forever(qid):
    return qid not in SOD_RANGE or qid in TRACED


def available(q):
    r, c = q.get('races') or 0, q.get('classes') or 0
    if r and not (r & TAUREN):
        return False
    if c and not (c & DRUID):
        return False
    if q.get('skill'):
        return False
    if (q.get('special') or 0) & 1:  # repeatable
        return False
    rep = q.get('minRep')
    if isinstance(rep, list) and len(rep) == 2:
        if (rep[1] or 0) > 0:
            return False  # needs better than Neutral (raid, Argent Dawn, centaur camps...)
        if rep[0] in HOSTILE_START:
            return False  # needs at least Neutral with a faction that starts Hostile for a Tauren
    return True


def spawn_points(entity):
    """[(area, x, y)] with areas normalised to parent zones."""
    sp = entity.get('spawns') or {}
    pts = []
    if isinstance(sp, dict):
        for z, lst in sp.items():
            for p in lst or []:
                if isinstance(p, list) and len(p) >= 2 and p[0] is not None:
                    if p[0] >= 0:
                        pts.append((parent(int(z)), float(p[0]), float(p[1])))
                    else:  # inside an instance: no map coordinates
                        pts.append((parent(int(z)), None, None))
    return pts


def entity(kind, eid):
    return (N if kind == 'n' else O).get(str(eid))


def givers(g):
    """Questgiver list -> [(kind, id, name, points)] for NPCs and objects."""
    out = []
    if isinstance(g, dict):
        g = [g.get('1'), g.get('2'), g.get('3')]
    if not isinstance(g, list):
        return out
    for kind, ids in zip(('n', 'o'), g[:2]):
        for i in ids or []:
            e = entity(kind, i)
            if e:
                out.append((kind, i, e.get('name'), spawn_points(e)))
    # quests started by an item you loot: only used when there is no NPC or object starter
    if not out and len(g) > 2:
        for iid in g[2] or []:
            it = I.get(str(iid)) or {}
            pts = []
            for nid in (it.get('npcDrops') or [])[:12]:
                e = N.get(str(nid))
                if e:
                    pts += spawn_points(e)
            for oid in (it.get('objectDrops') or [])[:12]:
                e = O.get(str(oid))
                if e:
                    pts += spawn_points(e)
            if pts and it.get('name'):
                out.append(('i', iid, it['name'], pts))
    return out


def best_point(points, prefer_areas, near=None):
    pts = [p for p in points if p[0] in prefer_areas] or points
    if not pts:
        return None
    if near and near[1] is not None and near[0] in {p[0] for p in pts if p[1] is not None}:
        same = [p for p in pts if p[0] == near[0] and p[1] is not None]
        return min(same, key=lambda p: (p[1] - near[1]) ** 2 + (p[2] - near[2]) ** 2)
    return pts[0]


def objective_points(q, areas):
    """Rough location for a quest's objectives: centroid of the first creature/object/item source."""
    obj = q.get('objectives')
    if isinstance(obj, dict):
        obj = [obj.get(str(k)) for k in range(1, 7)]
    if not isinstance(obj, list):
        return None
    cands = []
    # "go to this spot" quests (explore, use an item there): the database gives the spot directly
    trig = q.get('trigger')
    if isinstance(trig, list) and len(trig) >= 2 and isinstance(trig[1], dict):
        pts = []
        for z, lst in trig[1].items():
            for pnt in lst or []:
                if isinstance(pnt, list) and len(pnt) >= 2 and pnt[0] is not None and pnt[0] >= 0:
                    pts.append((parent(int(z)), float(pnt[0]), float(pnt[1])))
        cands.append(pts)
    # kill credit (e.g. "kill any of these NPCs"): group 5 lists the NPC IDs that count
    kc = obj[4] if len(obj) > 4 else None
    for entry in kc or []:
        if isinstance(entry, list) and entry and isinstance(entry[0], list):
            pts = []
            for nid in entry[0][:12]:
                e = N.get(str(nid))
                if e:
                    pts += spawn_points(e)
            cands.append(pts)
    for idx, group in enumerate(obj[:3]):
        for entry in group or []:
            if not isinstance(entry, list) or not entry:
                continue
            eid = entry[0]
            if idx == 0:
                e = N.get(str(eid)); cands.append(spawn_points(e) if e else [])
            elif idx == 1:
                e = O.get(str(eid)); cands.append(spawn_points(e) if e else [])
            else:
                it = I.get(str(eid)) or {}
                pts = []
                for nid in (it.get('npcDrops') or [])[:8]:
                    e = N.get(str(nid))
                    if e: pts += spawn_points(e)
                for oid in (it.get('objectDrops') or [])[:8]:
                    e = O.get(str(oid))
                    if e: pts += spawn_points(e)
                cands.append(pts)
    for pts in cands:
        pts = [p for p in pts if p[0] in areas and p[1] is not None]
        if pts:
            # centroid of the densest area
            area = max({p[0] for p in pts}, key=lambda a: sum(1 for p in pts if p[0] == a))
            sel = [p for p in pts if p[0] == area]
            cx = sum(p[1] for p in sel) / len(sel); cy = sum(p[2] for p in sel) / len(sel)
            return (area, cx, cy)
    return None


def horde_ok(q, areas):
    """The quest starts at a Horde-friendly giver somewhere a Tauren can reach."""
    gs = givers(q.get('start'))
    if not gs:
        return False
    kind, gid, name, pts = gs[0]
    if kind == 'n' and (N.get(str(gid)) or {}).get('friendly') == 'A':
        return False
    for fkind, fid, _fname, _fpts in givers(q.get('end')):
        if fkind == 'n' and (N.get(str(fid)) or {}).get('friendly') == 'A':
            return False  # handed in to an Alliance NPC: the Alliance version of a quest
    reach = set(route.ALL_AREAS) | set(areas)
    return any(p[0] in reach for p in pts)


def has_objectives(q):
    obj = q.get('objectives')
    if isinstance(obj, dict):
        return any(obj.values())
    return isinstance(obj, list) and any(obj)


def short_obj(q):
    for t in q.get('objText') or []:
        if isinstance(t, str) and t.strip():
            t = t.strip()
            return t if len(t) <= 140 else t[:137].rsplit(' ', 1)[0] + '...'
    return ''


def qname(qid):
    return (Q.get(str(qid)) or {}).get('name') or f'Quest {qid}'


def dist(a, b):
    if not a or not b or a[0] != b[0] or a[1] is None or b[1] is None:
        return 1e6
    return math.hypot(a[1] - b[1], a[2] - b[2])


def greedy(items, start):
    """Order (key, point) items by nearest-neighbour from start."""
    out, pos, left = [], start, list(items)
    while left:
        nxt = min(left, key=lambda it: dist(pos, it[1]))
        left.remove(nxt)
        out.append(nxt)
        pos = nxt[1] or pos
    return out, pos


class Builder:
    def __init__(self):
        self.done = set()       # quests turned in by the guide so far
        self.used = set()       # quests the guide has already picked up
        self.pending = {}       # qid -> finisher (kind, id, name, points) for quests not yet turned in
        self.pos = None
        self.chapters = []
        self.stats = {}
        self.blocked = set()    # quests ruled out by an exclusive quest the route already chose
        self.log_full = 0       # how often a section stopped because the quest log was full
        self.hearth = None      # {'place', 'area'} where the hearthstone is set
        self.area = None        # zone the route is in right now
        self.char = xpsim.Character(QUEST_XP)   # simulated character (real Forever quest XP)
        self.deferred = {}      # zone -> quests skipped because the character was too low
        self.grinds = 0         # "grind to level N" steps added

    # ------------------------------------------------------------------ exclusive quests
    def on_accept(self, qid):
        """Choosing a quest rules out the quests it is exclusive with or disables, and any
        breadcrumb that leads to it (you can't pick a breadcrumb up once its target is taken)."""
        q = Q[str(qid)]
        for b in LEADS_TO.get(qid, ()):
            if b not in self.used and b not in self.done:
                self.blocked.add(b)
        for e in q.get('exclusive') or []:
            self.blocked.add(e)
        for other in DISABLED_BY.get(qid, ()):
            self.blocked.add(other)
        if q.get('disabledBy'):
            self.blocked.add(q['disabledBy'])

    def on_turnin(self, qid):
        for other in AVAILABLE_UNTIL.get(qid, ()):
            self.blocked.add(other)

    def choose(self, ready, areas):
        """From quests ready to accept, keep one of each exclusive group, preferring givers here."""
        def here(qid):
            gs = givers(Q[str(qid)].get('start'))
            return 0 if gs and any(p[0] in areas for p in gs[0][3]) else 1
        out = []
        ready_set = set(ready)
        for qid in sorted(ready, key=lambda q: (here(q), q)):
            if qid in self.blocked:
                continue
            # wait for a breadcrumb that is about to be (or already is) picked up
            if any((b in ready_set and b not in self.blocked) or b in self.pending
                   for b in LEADS_TO.get(qid, ()) if b != qid):
                continue
            out.append(qid)
            self.on_accept(qid)
        return out

    # ------------------------------------------------------------------ travel
    def travel_tip(self, area):
        """How to get to `area`: hearthstone first when it is set there, then the usual way."""
        tips = []
        if self.hearth and self.hearth['area'] == area and self.area != area:
            tips.append(f"Use your hearthstone (set to {self.hearth['place']}).")
        if area in route.TRAVEL_TIPS:
            tips.append(route.TRAVEL_TIPS[area])
        return ' '.join(tips) or None

    def travel(self, steps, area, text):
        s = dict(t='zone', text=text, zoneName=ZONE_NAMES.get(area), zone=ZONE_NAMES.get(area))
        if AREA_TO_MAP.get(area):
            s['m'] = AREA_TO_MAP[area]
        tip = self.travel_tip(area)
        if tip:
            s['tip'] = tip
        self.rep_tip(s, area)
        steps.append(s)
        self.area = area
        self.turnins(steps, {area})

    def rep_tip(self, s, area):
        """Attach a tip that replaces the normal one once you have a reputation standing."""
        if area in route.REP_TIPS:
            faction, standing, text = route.REP_TIPS[area]
            s['tipRep'] = {'faction': faction, 'standing': standing, 'text': text}

    def detours(self, steps):
        """Quests waiting in a far city get a trip once they are MAX_WAIT_LEVELS below the route."""
        for city in route.CITY_AREAS:
            if self.area == city:
                continue
            if route.continent(city) != route.continent(self.area):
                continue  # never cross to another continent in the middle of a trip
            over = []
            for qid, fin in self.pending.items():
                if fin and any(p[0] == city for p in fin[3]) and \
                        (Q[str(qid)].get('level') or 0) + route.MAX_WAIT_LEVELS <= self.char.level:
                    over.append(qid)
            if over:
                names = ', '.join(qname(q) for q in over[:3]) + (' and more' if len(over) > 3 else '')
                it = 'it loses' if len(over) == 1 else 'they lose'
                self.travel(steps, city, f'Detour to {ZONE_NAMES.get(city)}: hand in {names} before {it} XP.')

    # ------------------------------------------------------------------ step helpers
    def loc_fields(self, point):
        if not point:
            return {}
        area, x, y = point
        if x is None:
            return {'zone': ZONE_NAMES.get(area, str(area))}
        m = AREA_TO_MAP.get(area)
        f = {'zone': ZONE_NAMES.get(area, str(area)), 'x': round(x, 1), 'y': round(y, 1)}
        if m:
            f['m'] = m
        return f

    def prereq_ok(self, q, pool):
        single = q.get('preSingle') or []
        group = q.get('preGroup') or []
        if single and not any(p in self.done for p in single):
            return False
        if group and not all(p in self.done for p in group):
            return False
        return True

    def obtainable_later(self, q, pool):
        single = q.get('preSingle') or []
        group = q.get('preGroup') or []
        known = self.done | set(pool)
        if single and not any(p in known for p in single):
            return False
        if group and not all(p in known for p in group):
            return False
        return True

    # ------------------------------------------------------------------ quest blocks
    def quest_block(self, steps, pool, areas, dungeon=None, turnin_order=None, inside=None, box=None):
        """Accept / complete / turn in rounds for a pool of quest IDs, until the pool runs dry.
        Never lets the quest log go over LOG_CAP. In a dungeon block, the first round only picks
        up quests from givers outside (before the run); quests from givers inside the instance
        (follow-ups, givers that appear after a boss) come in later rounds, during the run."""
        pool = [p for p in pool if p not in self.used and p not in self.done and p not in self.blocked]
        extra = {}
        if dungeon:
            extra = {'d': dungeon[0], 'dmin': dungeon[1], 'dmax': dungeon[2]}
        for _round in range(200):
            ready = [p for p in pool if p not in self.used and p not in self.blocked
                     and self.prereq_ok(Q[str(p)], pool)]
            if not dungeon:
                # Only quests the simulated character can take now. If everything left needs a
                # little more level (up to MAX_GRIND), add a "grind to level N" step first - as
                # real players do - instead of dropping the quests.
                def need(p):
                    q = Q[str(p)]
                    return max(q.get('reqLevel') or 0, (q.get('level') or 0) - 3)
                now = [p for p in ready if need(p) <= self.char.level]
                if not now and ready:
                    target = min(need(p) for p in ready)
                    if target - self.char.level <= MAX_GRIND:
                        steps.append(dict(t='level', lvl=target,
                                          text=f'Grind to level {target}: kill mobs around here before the next quests.',
                                          tip='Mobs your level or a little higher give the most XP; a dungeon run also works.'))
                        self.char.level, self.char.xp = target, 0
                        self.grinds += 1
                        now = [p for p in ready if need(p) <= self.char.level]
                ready = now
            if dungeon and inside and _round == 0:
                outside = [p for p in ready if not any(pt[0] in inside for pt in (givers(Q[str(p)].get('start')) or [(0, 0, 0, [])])[0][3])]
                if outside:
                    ready = outside
            free = LOG_CAP - len(self.pending)
            if free <= 0:
                self.log_full += 1
                break
            ready = sorted(ready, key=lambda q: (Q[str(q)].get('level') or 0, q))[:max(0, free) * 3]
            ready = self.choose(ready, areas)[:free]
            if not ready:
                break
            # --- accept, grouped by questgiver
            by_giver = {}
            for qid in ready:
                gs = givers(Q[str(qid)].get('start'))
                if not gs:
                    continue
                kind, gid, gname, pts = gs[0]
                pt = best_point(pts, areas, self.pos)
                by_giver.setdefault((kind, gid, gname), {'pt': pt, 'q': []})['q'].append(qid)
            if not by_giver:
                break
            ordered, self.pos = greedy([(k, v['pt']) for k, v in by_giver.items()], self.pos)
            for (kind, gid, gname), pt in ordered:
                qs = sorted(by_giver[(kind, gid, gname)]['q'], key=lambda i: (Q[str(i)].get('level') or 0, i))
                if kind == 'i':
                    # an item that starts a quest: optional - never blocks the route; the panel
                    # lists it under "Look out for" while you are in its zone
                    steps.append(dict(t='accept', q=qs, npc=gname, opt=True,
                                      text=f"Optional: loot {gname} - it starts {qname(qs[0])}",
                                      **self.loc_fields(pt), **extra))
                else:
                    steps.append(dict(t='accept', q=qs, npc=gname, text='Accept from ' + gname,
                                      **self.loc_fields(pt), **extra))
                for qid in qs:
                    self.used.add(qid)
                    fin = givers(Q[str(qid)].get('end'))
                    self.pending[qid] = fin[0] if fin else None
            accepted = [q for k, _p in ordered for q in by_giver[k]['q']]
            # --- complete: the whole batch as one checklist step, with a location
            #     and short objective per quest so the arrow can lead to the nearest unfinished one
            if dungeon:
                todo = [q for q in accepted if has_objectives(Q[str(q)])]
                if todo:
                    steps.append(dict(t='complete', q=todo, text='Run ' + dungeon[0] + ' and finish its quests',
                                      obj={q: short_obj(Q[str(q)]) for q in todo}, **extra))
            else:
                items = []
                for qid in accepted:
                    q = Q[str(qid)]
                    if has_objectives(q):
                        items.append((qid, objective_points(q, areas)))
                ordered_c, self.pos = greedy(items, self.pos)
                if ordered_c:
                    qs = [qid for qid, _ in ordered_c]
                    pts = {}
                    for qid, pt in ordered_c:
                        lf = self.loc_fields(pt)
                        if 'm' in lf:
                            pts[qid] = {'m': lf['m'], 'x': lf['x'], 'y': lf['y']}
                    first = next((pt for _, pt in ordered_c if pt), None)
                    text = (short_obj(Q[str(qs[0])]) or qname(qs[0])) if len(qs) == 1 else \
                        f'Do these {len(qs)} quests in the area - the arrow leads to the nearest'
                    steps.append(dict(t='complete', q=qs, text=text, pts=pts,
                                      obj={q: short_obj(Q[str(q)]) for q in qs}, **self.loc_fields(first)))
            # --- turn in what can be turned in here (in a dungeon: only inside, during the run)
            only = set(pool) if dungeon else None
            for zone_set in (([inside] if dungeon and inside else None) or turnin_order or [areas]):
                self.turnins(steps, zone_set, extra, only=only, box=box)
        else:
            print(f'warning: quest_block stopped after 200 rounds ({len(pool)} quests in pool)')
        if dungeon and turnin_order:
            # after the run: hand in outside, nearest first
            for zone_set in turnin_order:
                self.turnins(steps, zone_set, extra, only=set(pool))
        return steps

    def turnins(self, steps, areas, extra=None, only=None, box=None):
        extra = extra or {}
        by_fin = {}
        for qid, fin in list(self.pending.items()):
            if only is not None and qid not in only:
                continue
            if fin is None:
                continue
            kind, fid, fname, pts = fin
            here = [p for p in pts if p[0] in areas]
            if box:
                # a boxed section (e.g. Camp Narache) only hands in inside its box
                here = [p for p in here if p[1] is not None and box[0] <= p[1] <= box[2] and box[1] <= p[2] <= box[3]]
            if not here:
                continue
            pt = best_point(here, areas, self.pos)
            by_fin.setdefault((kind, fid, fname), {'pt': pt, 'q': []})['q'].append(qid)
        ordered, self.pos = greedy([(k, v['pt']) for k, v in by_fin.items()], self.pos)
        for key, pt in ordered:
            qs = sorted(by_fin[key]['q'])
            step_extra = dict(extra)
            steps.append(dict(t='turnin', q=qs, npc=key[2], text='Turn in to ' + key[2],
                              **self.loc_fields(pt), **step_extra))
            for qid in qs:
                self.pending.pop(qid, None)
                self.done.add(qid)
                self.on_turnin(qid)
                self.char.turn_in(qid)

    # ------------------------------------------------------------------ segment handlers
    def zone_pool(self, seg):
        areas = set(seg['zones'])
        giver_areas = areas | set(seg.get('giver_zones', []))
        lo, hi = seg['levels']
        excl = set(route.EXCLUDE) | set(seg.get('exclude', [])) | DUNGEON_QUESTS
        pool = []
        for k, q in Q.items():
            qid = int(k)
            if qid in excl or qid in self.used or qid in self.done or qid in self.blocked or not available(q):
                continue
            if not exists_on_forever(qid):
                continue
            gs = givers(q.get('start'))
            z = q.get('zone')
            if not isinstance(z, int) or z == 0:
                # no zone in the database: use where its giver stands
                z = gs[0][3][0][0] if gs and gs[0][3] else None
            if not isinstance(z, int) or parent(z) not in areas:
                continue
            lvl = q.get('level') or 0
            if lvl < 1 or not (lo <= lvl <= hi) or (q.get('reqLevel') or 0) > hi:
                continue
            if not gs or not any(p[0] in giver_areas for p in gs[0][3]):
                continue
            box = seg.get('box')
            if box and not any(p[0] in areas and box[0] <= p[1] <= box[2] and box[1] <= p[2] <= box[3]
                               for p in gs[0][3]):
                continue
            if not horde_ok(q, areas):
                continue
            # objectives in another zone: leave the quest to a section in that zone
            op = objective_points(q, set(route.ALL_AREAS) | set(SUB_TO_PARENT.values()))
            if op and op[0] not in giver_areas and op[0] not in route.HUB_AREAS:
                continue
            pool.append(qid)
        pool += [i for i in seg.get('include', []) if i not in pool]
        # drop quests whose prerequisites can never be met inside the guide
        changed = True
        while changed:
            changed = False
            for qid in list(pool):
                if not self.obtainable_later(Q[str(qid)], pool):
                    pool.remove(qid); changed = True
        return pool

    def build(self):
        for ch in route.CHAPTERS:
            steps = []
            self.pos = None
            ch['_start_level'] = self.char.level
            for seg in ch['segments']:
                kind = seg['type']
                if kind == 'quests':
                    # questing happens in the section's zones; city hand-ins wait for one visit at the end
                    areas = set(seg['zones']) | set(seg.get('giver_zones', []))
                    pool = self.zone_pool(seg)
                    away = self.area is not None and self.area not in seg['zones']
                    # no trip for a zone with nothing (or a single quest) to do
                    if not pool or (away and len(pool) < 2):
                        self.stats[f"{ch['title']} / {ZONE_NAMES.get(seg['zones'][0])} #{len(self.stats)}"] = 0
                        continue
                    self.detours(steps)
                    if self.area is not None and self.area not in seg['zones']:
                        self.travel(steps, seg['zones'][0], 'Travel to ' + ZONE_NAMES.get(seg['zones'][0], ''))
                    elif self.area is None:
                        self.area = seg['zones'][0]
                    if seg.get('note'):
                        steps.append(dict(t='note', text=seg['note']))
                    self.quest_block(steps, pool, areas, box=seg.get('box'))
                    left = [q for q in pool if q not in self.used and q not in self.done and q not in self.blocked
                            and (Q[str(q)].get('reqLevel') or 0) > self.char.level]
                    if left:
                        self.deferred.setdefault(seg['zones'][0], set()).update(left)
                    if self.pos:
                        self.area = self.pos[0]
                    for tz in seg.get('turnin_zones', []):
                        if any(fin and any(p[0] == tz for p in fin[3]) for fin in self.pending.values()):
                            self.travel(steps, tz, f'Hand in at {ZONE_NAMES.get(tz)}')
                    self.stats[f"{ch['title']} / {','.join(ZONE_NAMES.get(z, str(z)) for z in seg['zones'])} #{len(self.stats)}"] = len(pool)
                elif kind == 'dungeon':
                    name, lo, hi = seg['name'], seg['levels'][0], seg['levels'][1]
                    self.detours(steps)
                    ids = list(seg['quests'])
                    dz = set(seg.get('zones', []))
                    if dz:
                        ids += sorted(int(k) for k, q in Q.items()
                                      if isinstance(q.get('zone'), int) and q.get('zone') in dz
                                      and int(k) not in route.EXCLUDE)
                    dzp = {parent(z) for z in dz} | dz
                    near = dzp | set(seg.get('turnin_zones', [])) | set(seg.get('giver_zones', []))

                    def dungeon_ok(i):
                        q = Q.get(str(i))
                        if not q or not available(q) or i in self.used or i in self.done or i in self.blocked:
                            return False
                        if not exists_on_forever(i):
                            return False
                        lvl = q.get('level') or 0
                        if lvl > hi + 2 or (q.get('reqLevel') or 0) > hi:
                            return False  # too high for this run
                        gs = givers(q.get('start'))
                        # picked up near the dungeon (or inside it), not in a faraway city
                        return bool(gs) and any(p[0] in near for p in gs[0][3]) and horde_ok(q, near)
                    pool = [i for i in dict.fromkeys(ids) if dungeon_ok(i)]
                    pool = [i for i in pool if self.obtainable_later(Q[str(i)], pool)]
                    steps.append(dict(t='note', text=seg.get('note') or
                                      f'{name}: gather the quests below before you queue or form a group.',
                                      d=name, dmin=lo, dmax=hi))
                    # Hand in right after the run only near the dungeon; quests for faraway NPCs
                    # stay carried and are handed in the next time the route reaches that zone.
                    dareas = set(seg.get('turnin_zones', [])) | dzp
                    order = [dzp] + [{z} for z in seg.get('turnin_zones', [])]
                    self.quest_block(steps, pool, near | dzp, dungeon=(name, lo, hi), turnin_order=order[1:], inside=dzp)
                elif kind == 'chain':
                    # hand-written ordered steps with explicit quest IDs
                    for st in seg['steps']:
                        s = dict(st)
                        s['cls'] = True  # class quest: never skipped as grey or out of range
                        missing = [q for q in s.get('q', []) if str(q) not in Q]
                        if missing:
                            raise SystemExit(f"chain step uses quest(s) not in the database: {missing}")
                        if s['t'] in ('accept', 'turnin') and 'npc' not in s:
                            q = Q[str(s['q'][0])]
                            g = givers(q.get('start' if s['t'] == 'accept' else 'end'))
                            if g:
                                pt = best_point(g[0][3], set(route.HUB_AREAS), self.pos)
                                s.update(npc=g[0][2], **self.loc_fields(pt))
                                s.setdefault('text', ('Accept from ' if s['t'] == 'accept' else 'Turn in to ') + g[0][2])
                        if s['t'] == 'complete':
                            s.setdefault('text', short_obj(Q[str(s['q'][0])]) or qname(s['q'][0]))
                        if s['t'] == 'complete' and 'x' not in s:
                            pt = objective_points(Q[str(s['q'][0])], set(route.ALL_AREAS))
                            if pt:
                                s.update(self.loc_fields(pt))
                        if s.get('x') is not None and s.get('zone'):
                            for ar, nm in ZONE_NAMES.items():
                                if nm == s['zone'] and ar in route.ALL_AREAS:
                                    self.area = ar
                                    break
                        for qid in s.get('q', []):
                            if s['t'] == 'accept':
                                self.on_accept(qid)
                            self.used.add(qid)
                            if s['t'] == 'turnin':
                                self.done.add(qid); self.pending.pop(qid, None)
                                self.char.turn_in(qid)
                        steps.append(s)
                elif kind == 'flush':
                    for z in seg['zones']:
                        if any(fin and any(p[0] == z for p in fin[3]) for fin in self.pending.values()):
                            if self.area != z:
                                self.travel(steps, z, f'Hand in at {ZONE_NAMES.get(z)}')
                            else:
                                self.turnins(steps, {z})
                elif kind == 'bind':
                    if self.area is not None and self.area != seg['area']:
                        self.travel(steps, seg['area'], 'Travel to ' + seg['place'])
                    e = N.get(str(seg['npc'])) or {}
                    if not e.get('name'):
                        raise SystemExit(f"bind: innkeeper {seg['npc']} not found in the database")
                    pt = best_point(spawn_points(e), {seg['area']}, self.pos)
                    steps.append(dict(t='bind', text=f"Set your hearthstone with {e.get('name')} in {seg['place']}",
                                      npc=e.get('name'), bind=seg['place'], **self.loc_fields(pt)))
                    self.hearth = {'place': seg['place'], 'area': seg['area']}
                    self.area = seg['area']
                elif kind == 'step':
                    s = dict(seg['step'])
                    if 'area' in s:
                        area = s.pop('area')
                        if 'x' in s:
                            s.update(self.loc_fields((area, s['x'], s['y'])))
                        else:
                            s['zoneName'] = ZONE_NAMES.get(area)
                            if AREA_TO_MAP.get(area):
                                s['m'] = AREA_TO_MAP[area]
                            s['zone'] = ZONE_NAMES.get(area)
                    steps.append(s)
                    if s.get('t') == 'zone' and 'area' in seg['step']:
                        area = seg['step']['area']
                        if 'tip' not in s:
                            tip = self.travel_tip(area)
                            if tip:
                                s['tip'] = tip
                        self.rep_tip(s, area)
                        self.area = area
                        self.turnins(steps, {area})
                    if s.get('t') == 'train':
                        lvl = seg['step'].get('lvl') or 0
                        if lvl < 10:
                            # Teleport: Moonglade is learned at 10
                            s['tip'] = 'Gennia Runetotem trains druids in Bloodhoof Village; Thunder Bluff has trainers on the Elder Rise.'
                        elif self.area == route.THUNDER_BLUFF:
                            s['tip'] = 'You are in Thunder Bluff: the druid trainers are on the Elder Rise.'
                        else:
                            back = f" then hearth back to {self.hearth['place']}" if self.hearth else ' then hearth back'
                            s['tip'] = ('Quickest: cast Teleport: Moonglade and train with Loganaar in Nighthaven,'
                                        + back + '.')
                            # the Moonglade trip is also when Moonglade hand-ins happen
                            self.turnins(steps, {route.MOONGLADE})
            ch['sim_levels'] = (ch.get('_start_level', 1), max(ch.get('_start_level', 1), min(60, self.char.level)))
            self.chapters.append((ch, steps))
        # Drop quests the route picks up but never hands in (deliveries to zones it never revisits).
        self.dropped = dict(self.pending)
        drop = set(self.pending)
        for ch, steps in self.chapters:
            keep = []
            for s in steps:
                if s.get('q'):
                    s['q'] = [q for q in s['q'] if q not in drop]
                    if not s['q']:
                        continue
                keep.append(s)
            steps[:] = keep

    # ------------------------------------------------------------------ output
    def write(self):
        names = {}
        guide_dir = os.path.join(OUT_DIR, 'Guide')
        os.makedirs(guide_dir, exist_ok=True)
        os.makedirs(os.path.join(OUT_DIR, 'tools'), exist_ok=True)
        wanted = {ch['file'] for ch, _ in self.chapters}
        for old in os.listdir(guide_dir):
            if old.endswith('.lua') and old not in wanted:
                os.remove(os.path.join(guide_dir, old))  # chapter renamed or removed
        for num, (ch, steps) in enumerate(self.chapters, 1):
            path = os.path.join(OUT_DIR, 'Guide', ch['file'])
            lv = ch.get('sim_levels') or ch['levels']
            lines = ["-- Earthmother's Guide - generated by tools/gen.py from tools/route.py. Do not edit by hand.",
                     '-- Quest/NPC/coordinate data derived from QuestieDB v1.1.5 (Questie contributors), used under',
                     '-- GPL-3.0; modified (filtered, ordered, reformatted). Names and quest text (c) Blizzard Entertainment.',
                     "-- Copyright (C) 2026 Vard Ruun. Earthmother's Guide is licensed under GPL-3.0-or-later; see LICENSE and NOTICE.md.",
                     'local _, ns = ...', 'ns = ns or _G.EarthmothersGuide', '',
                     f'ns.AddChapter({num}, {{',
                     f'  title = {lua(ch["title"])},',
                     f'  levels = {{ {lv[0]}, {lv[1]} }},',
                     '  steps = {']
            for s in steps:
                if s.get('q'):
                    s['qn'] = {q: qname(q) for q in s['q']}
                    s['ql'] = max((Q[str(q)].get('level') or 0) for q in s['q'])
                    prof = {q: route.PROFESSION[q] for q in s['q'] if q in route.PROFESSION}
                    if prof:
                        s['prof'] = prof
                lines.append('    ' + lua(s) + ',')
            lines += ['  },', '})', '']
            open(path, 'w', encoding='utf-8').write('\n'.join(lines))
            names[ch['file']] = len(steps)
        return names


KEY_ORDER = ['t', 'text', 'q', 'qn', 'npc', 'zone', 'm', 'x', 'y', 'zoneName', 'lvl', 'spell', 'd', 'dmin', 'dmax', 'ql', 'cls', 'pts', 'obj', 'prof', 'bind', 'opt', 'tip', 'tipRep', 'radius']


def lua(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(v, list):
        return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, dict):
        keys = sorted(v, key=lambda k: (KEY_ORDER.index(k) if k in KEY_ORDER else 99, str(k)))
        parts = []
        for k in keys:
            if v[k] is None:
                continue
            key = f'[{k}]' if isinstance(k, int) else k
            parts.append(f'{key} = {lua(v[k])}')
        return '{ ' + ', '.join(parts) + ' }'
    raise TypeError(type(v))


if __name__ == '__main__':
    b = Builder()
    b.build()
    for _pass in range(3):
        if not b.dropped:
            break
        # quests the route would pick up but never hand in: leave them out entirely and rebuild,
        # so they neither clutter the route nor take quest log space
        route.EXCLUDE = list(route.EXCLUDE) + sorted(b.dropped)
        dropped_before = dict(b.dropped)
        b = Builder()
        b.build()
        b.dropped = {**dropped_before, **b.dropped}
    counts = b.write()
    for k, v in b.stats.items():
        print(f'{v:4d} quests  {k}')
    for k, v in counts.items():
        print(f'{v:4d} steps   {k}')
    print('sections stopped early because the quest log was full:', b.log_full)
    print('"grind to level" steps added:', b.grinds)
    for z, qs in b.deferred.items():
        still = [q for q in qs if q not in b.used]
        if still:
            print(f'  {len(still):3d} quests in {ZONE_NAMES.get(z)} never reached: character too low when there')
    peak, log = 0, set()
    for _ch, steps in b.chapters:
        for st in steps:
            if st.get('t') == 'accept':
                log |= set(st['q'])
            elif st.get('t') == 'turnin':
                log -= set(st['q'])
            peak = max(peak, len(log))
    print('largest quest log along the route:', peak)
    if peak > LOG_CAP:
        raise SystemExit(f'quest log goes over {LOG_CAP} ({peak})')
    # --- simulated level along the route, from real Forever quest XP
    QXP = xpsim.load_quest_xp(QDB_DIR)
    report = {}
    for share in (0.0, xpsim.KILL_SHARE):
        char = xpsim.Character(QXP, share)
        rows = []
        for ch, steps in b.chapters:
            start = char.exact
            hard = grey = 0
            for st in steps:
                if st.get('t') == 'level' and share == xpsim.KILL_SHARE and (st.get('lvl') or 0) > char.level:
                    char.level, char.xp = st['lvl'], 0      # the grind the route asks for
                if st.get('t') == 'accept' and not st.get('opt'):
                    for q in st['q']:
                        if (Q[str(q)].get('reqLevel') or 0) > char.level:
                            hard += 1
                if st.get('t') == 'turnin':
                    for q in st['q']:
                        _got, was_grey = char.turn_in(q)
                        grey += was_grey
            rows.append((ch['title'], ch['levels'], round(start, 1), round(char.exact, 1), hard, grey))
        report[share] = rows
    print('\nSimulated level by chapter (real Forever quest XP; kills modelled as a share on top):')
    print(f"{'chapter':48} {'label':>7} {'quests only':>13} {'+' + str(int(xpsim.KILL_SHARE * 100)) + '% kills':>13} {'too high':>9} {'grey':>5}")
    for (t, lv, s0, e0, _h0, _g0), (_t, _lv, s1, e1, h1, g1) in zip(report[0.0], report[xpsim.KILL_SHARE]):
        print(f"{t[:48]:48} {lv[0]:>3}-{lv[1]:<3} {s0:>5}->{e0:<6} {s1:>5}->{e1:<6} {h1:>9} {g1:>5}")
    json.dump({str(k): v for k, v in report.items()}, open(os.path.join(OUT_DIR, 'tools', 'levels.json'), 'w'), indent=1)
    left = [q for q in b.dropped]
    print('quests accepted but never turned in by the route:', len(left))
    json.dump({str(q): qname(q) for q in left}, open(os.path.join(OUT_DIR, 'tools', 'unfinished.json'), 'w'), indent=1)
