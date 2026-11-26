# Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-only; see LICENSE and NOTICE.md.
"""Decode QuestieDB Forever baked TOC metadata into JSON (quests, npcs, objects).
Usage: python3 -I extract.py <QuestieDB_Forever.toc> <out.json>
"""
import base64, json, struct, sys, zlib


def cbor(buf, i=0):
    ib = buf[i]; i += 1
    mt, ai = ib >> 5, ib & 31
    if mt == 7:
        if ai == 25:
            v = struct.unpack('>e', buf[i:i+2])[0]; return v, i + 2
        if ai == 26:
            v = struct.unpack('>f', buf[i:i+4])[0]; return v, i + 4
        if ai == 27:
            v = struct.unpack('>d', buf[i:i+8])[0]; return v, i + 8
        return {20: False, 21: True, 22: None, 23: None}.get(ai), i
    if ai < 24:
        n = ai
    elif ai == 24:
        n = buf[i]; i += 1
    elif ai == 25:
        n = struct.unpack('>H', buf[i:i+2])[0]; i += 2
    elif ai == 26:
        n = struct.unpack('>I', buf[i:i+4])[0]; i += 4
    elif ai == 27:
        n = struct.unpack('>Q', buf[i:i+8])[0]; i += 8
    else:
        raise ValueError('indefinite length unsupported')
    if mt == 0:
        return n, i
    if mt == 1:
        return -1 - n, i
    if mt in (2, 3):
        s = buf[i:i+n]
        return s.decode('utf-8', 'replace'), i + n
    if mt == 4:
        out = []
        for _ in range(n):
            v, i = cbor(buf, i); out.append(v)
        return out, i
    if mt == 5:
        out = {}
        for _ in range(n):
            k, i = cbor(buf, i); v, i = cbor(buf, i); out[k] = v
        return out, i
    if mt == 6:
        return cbor(buf, i)
    raise ValueError(mt)


def dec(s):
    return cbor(base64.b64decode(s))[0]


def dec_ids(s):
    raw = base64.b64decode(s)
    for wbits in (15, -15, 31):
        try:
            return cbor(zlib.decompress(raw, wbits))[0]
        except zlib.error:
            pass
    raise ValueError('cannot decompress ids')


def load(path):
    meta = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            if line.startswith('## ') and ': ' in line:
                k, v = line[3:].rstrip('\n').split(': ', 1)
                meta[k] = v
    return meta


def stored(meta, key):
    v = meta.get(key)
    if v is None:
        return None
    if v.startswith('~') and v.endswith('~'):
        n = int(v[1:-1])
        return ''.join(meta[f'{key}-{i}'] for i in range(1, n + 1))
    return v


def row(meta, prefix, eid, table_fields):
    s = stored(meta, f'X-{prefix}-{eid}-S')
    if s is None:
        return None
    r = dec(s)
    if isinstance(r, list):
        r = {i + 1: v for i, v in enumerate(r)}
    out = {k: v for k, v in r.items() if isinstance(k, int)}
    for f in table_fields:
        t = stored(meta, f'X-{prefix}-{eid}-{f}')
        if t is not None:
            out[f] = dec(t)
    return out


def main():
    meta = load(sys.argv[1])
    data = {'quests': {}, 'npcs': {}, 'objects': {}}
    qf = {1: 'name', 2: 'start', 3: 'end', 4: 'reqLevel', 5: 'level', 6: 'races', 7: 'classes', 9: 'trigger',
          8: 'objText', 10: 'objectives', 12: 'preGroup', 13: 'preSingle', 14: 'children',
          16: 'exclusive', 17: 'zone', 18: 'skill', 19: 'minRep', 20: 'maxRep', 22: 'next', 23: 'flags', 24: 'special',
          27: 'breadcrumbFor', 32: 'maxLevel', 33: 'availUntil', 36: 'disabledBy'}
    for qid in dec_ids(stored(meta, 'X-Quest-IDS')):
        r = row(meta, 'Quest', qid, [2, 3, 8, 9, 10, 12, 13, 14, 16, 18, 19, 20])
        if r:
            data['quests'][qid] = {qf[k]: v for k, v in r.items() if k in qf}
    nf = {1: 'name', 4: 'minLevel', 5: 'maxLevel', 7: 'spawns', 9: 'zone', 13: 'friendly', 14: 'sub'}
    for nid in dec_ids(stored(meta, 'X-Npc-IDS')):
        r = row(meta, 'Npc', nid, [7])
        if r:
            data['npcs'][nid] = {nf[k]: v for k, v in r.items() if k in nf}
    of = {1: 'name', 4: 'spawns', 5: 'zone'}
    for oid in dec_ids(stored(meta, 'X-Object-IDS')):
        r = row(meta, 'Object', oid, [4])
        if r:
            data['objects'][oid] = {of.get(k, k): v for k, v in r.items()}
    data['items'] = {}
    for iid in dec_ids(stored(meta, 'X-Item-IDS')):
        r = row(meta, 'Item', iid, [2, 3, 5])
        if r:
            data['items'][iid] = {'name': r.get(1), 'npcDrops': r.get(2), 'objectDrops': r.get(3), 'startQuest': r.get(5)}
    with open(sys.argv[2], 'w') as f:
        json.dump(data, f, default=str)
    print({k: len(v) for k, v in data.items()})


main()
