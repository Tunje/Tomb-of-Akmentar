"""Shared helpers for the dialogue generators (make_act1.py, make_act3.py): node builders, a checker
that mirrors Conversation.validate (plus reachability, declared speakers, known keys) and a writer.
make_act2.py predates this and keeps its own copy."""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CONDS = {"flag", "not_flag", "money", "actions", "stat", "in_party", "day"}
EFFECTS = {"set_flag", "clear_flag", "money", "spend_action", "stat", "recruit", "dismiss", "kill", "item", "countdown", "event", "journal"}
SLOTS = {"ur", "r", "lr", "ul", "l", "ll"}
END = {"end": True}


def L(speaker, line, next=None, do=None, choices=None):
    n = {"speaker": speaker, "line": line}
    if do:
        n["do"] = do
    if choices:
        n["choices"] = choices
    elif next:
        n["next"] = next
    return n


def C(label, line, next, if_=None, do=None):
    c = {"label": label, "line": line}
    if if_:
        c["if"] = if_
    if do:
        c["do"] = do
    c["next"] = next
    return c


def B(*pairs, do=None):
    n = {"branch": [({"if": cond, "next": nxt} if cond else {"next": nxt}) for cond, nxt in pairs]}
    if do:
        n["do"] = do
    return n


def flag(name, value=True):
    return {"set_flag": name} if value is True else {"set_flag": [name, value]}


def trust(who, n):
    return {"stat": [who, "trust", n]}


def conv(who, n):
    return {"stat": [who, "conviction", n]}


def fear(who, n):
    return {"stat": [who, "fear", n]}


def pay(n):
    return {"money": -n}


def talk(help_text, speakers, nodes, start="start"):
    return {"_help": help_text, "speakers": dict({"player": "You"}, **speakers), "start": start, "nodes": nodes}


def per_member(nodes, prefix, effects, then):
    """Silent nodes that apply effects[who] for each `who` in the party, then go to `then`.
    Adds them to `nodes`; returns the first node's id."""
    ids = list(effects)
    for k, who in enumerate(ids):
        nid = "%s_%d" % (prefix, k)
        nxt = "%s_%d" % (prefix, k + 1) if k + 1 < len(ids) else then
        nodes[nid] = B(({"in_party": who}, nid + "_do"), (None, nxt))
        nodes[nid + "_do"] = B((None, nxt), do=effects[who])
    return "%s_0" % prefix if ids else then


def check_talk(tid, d, problems, clue_areas=None):
    nodes = d["nodes"]

    def p(msg):
        problems.append("%s: %s" % (tid, msg))
    if d["start"] not in nodes:
        p("start is not a node")

    def conds(c, where):
        for k in c:
            if k not in CONDS:
                p("%s: unknown condition %s" % (where, k))

    def effects(es, where):
        for e in es:
            for k in e:
                if k not in EFFECTS:
                    p("%s: unknown effect %s" % (where, k))
                if k == "journal" and clue_areas is not None:
                    area, site = e[k][0], e[k][1]
                    if site not in clue_areas.get(area, {}).get("sites", {}):
                        p("%s: journal %s/%s has no clue" % (where, area, site))
    for nid, n in nodes.items():
        targets = []
        if "next" in n:
            targets.append(n["next"])
        if "speaker" in n and n["speaker"] not in d["speakers"]:
            p("%s: speaker %s not declared" % (nid, n["speaker"]))
        effects(n.get("do", []), nid)
        cs = n.get("choices", [])
        if len(cs) > 6:
            p("%s: more than 6 choices" % nid)
        for c in cs:
            targets.append(c["next"])
            conds(c.get("if", {}), nid)
            effects(c.get("do", []), nid)
            if "slot" in c and c["slot"] not in SLOTS:
                p("%s: bad slot" % nid)
        for b in n.get("branch", []):
            targets.append(b["next"])
            conds(b.get("if", {}), nid)
        for t in targets:
            if t not in nodes:
                p("%s: next %s is not a node" % (nid, t))
        if not ("line" in n or "branch" in n or n.get("end")):
            p("%s: no line, branch or end" % nid)
        if cs and not any(not c.get("if") for c in cs):
            p("%s: every choice is conditional (the wheel could be empty)" % nid)
        if "branch" in n and n["branch"][-1].get("if"):
            p("%s: the last branch has a condition (it could fall through and end)" % nid)
    seen, todo = set(), [d["start"]]
    while todo:
        t = todo.pop()
        if t in seen or t not in nodes:
            continue
        seen.add(t)
        n = nodes[t]
        todo += [n["next"]] if "next" in n else []
        todo += [c["next"] for c in n.get("choices", [])] + [b["next"] for b in n.get("branch", [])]
    for nid in nodes:
        if nid not in seen:
            p("%s is unreachable" % nid)


def write(rel, data):
    path = os.path.join(ROOT, rel)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")


def build(name, talks, files, clue_areas=None):
    """Checks every talk; on success writes dialogue/<id>.json for each talk and every
    {path: data} in `files`. Exits 1 on problems."""
    problems = []
    for tid, d in talks.items():
        check_talk(tid, d, problems, clue_areas)
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    from wheel import assign_slots
    for tid, d in talks.items():
        assign_slots(d)  # Mass Effect positions by tone (tools/dialogue/wheel.py)
        d["_help"] = d["_help"] + " Generated by tools/dialogue/%s." % name
        write("dialogue/%s.json" % tid, d)
    for rel, data in files.items():
        write(rel, data)
    print("%s: %d talks, %d other files, all checks passed" % (name, len(talks), len(files)))
