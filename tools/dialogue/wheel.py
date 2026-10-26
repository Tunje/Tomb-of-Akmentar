"""Wheel positions by tone, the Mass Effect way (Simon's founding rule for the conversation wheel):
the right side moves the talk on, top-right friendly ("ur"), right neutral ("r"), bottom-right
hostile ("lr"); the left side asks about things ("ul", "l"), and bottom-left leaves ("ll").
assign_slots(talk) gives every choice of every node a slot from its label's tone, never two on the
same slot in one node. The generators call it before writing; run this file to apply it to the
hand-written talks:

    python tools/dialogue/wheel.py dialogue/act4_whitfield.json ..."""

import json
import re
import sys

PREFER = {
    "friendly": ["ur", "r", "ul"],
    "neutral": ["r", "ur", "lr", "l"],
    "hostile": ["lr", "r", "ll"],
    "ask": ["ul", "l", "ur"],
    "leave": ["ll", "l", "lr"],
}
ORDER = ["ur", "r", "lr", "ul", "l", "ll"]

# Exits and navigation (bottom-left); "Leave them, if I must" is a hard answer, not an exit.
LEAVE = r"^(leave$|back$|go$|go on$|move on|turn in|excuse yourself|thank (him|her)|that's all|drop it|nothing|not today|forget it|find another guide)"
# Questions (left side); a request ("Ask for horses") moves the talk on, so it's on the right.
ASK = r"^(ask (about|what|who|why|how|which|if|the way|him to tell|eleanor)|hear|catch up|mention|look for yourself)"
HOSTILE = (r"^(threaten|insult|hit|draw|mock|order|condemn|refuse|blame|take them|offer less|make no promises|"
           r"pay nothing|no promises|pay, but|leave them|overrule|they'll toughen|push on|i decide|keep him on|"
           r"push harder|press him|challenge|doubt|i pay, i take|no side deals|humiliate|needle|"
           r"give up freddie|give them the note|fight|force it|pay, she takes)")
FRIENDLY = (r"^(promise|accept$|accept gladly|agree|help|forgive|pay her properly|pay more|pay what|pay him|pay it all|pay and promise|"
            r"carry|encourage|be glad|tell her|lighten|give them your share|their finds|invite|on your advice|"
            r"trust him|say you believe|answer|share|hire|offer (him|her) (the job|work)|approach|"
            r"send the others|let (her|him) (go|drill|hold|trade)|apologi|yes|together|walk with|book passage|stay and study|"
            r"the temple|congratulate|shake on it|offer to|walk out to him|go down into)")


def tone(label: str) -> str:
    l = label.strip().lower()
    if re.search(LEAVE, l):
        return "leave"
    if re.search(HOSTILE, l):
        return "hostile"
    if re.search(ASK, l):
        return "ask"
    if re.search(FRIENDLY, l):
        return "friendly"
    return "neutral"


def assign_slots(talk: dict) -> dict:
    for n in talk.get("nodes", {}).values():
        cs = n.get("choices", [])
        taken = set()
        for c in cs:
            for s in PREFER[tone(c["label"])] + ORDER:
                if s not in taken:
                    c["slot"] = s
                    taken.add(s)
                    break
    return talk


if __name__ == "__main__":
    for p in sys.argv[1:]:
        d = json.load(open(p, encoding="utf-8"))
        assign_slots(d)
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(d, ensure_ascii=False, indent="\t") + "\n")
        print("slots:", p)
