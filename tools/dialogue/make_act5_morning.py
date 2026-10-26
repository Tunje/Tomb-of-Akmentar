"""Writes dialogue/act5_morning.json (repetitive per-site branches). Usage: python -I make_morning.py <project dir>"""
import json, sys, pathlib

AMERICAN = {  # their draft priorities, in order, and what Whitfield says about each
    "anubis": "That jackal statue? Hollow under its feet, like I told you. Turns out the paw points at a slab you can press. A door, partner. A real door.",
    "scarabs": "Maggie found her backwards beetle on the scarab wall. The underside's worn smooth, like folks pressed it for centuries. She thinks it's a key.",
    "storeroom": "The storeroom we cracked was sealed from the inside. Tools dropped where they lay. Whoever closed it never came out.",
    "mummification": "In the embalming hall the fellow on the table still has his eyes open. Red won't go back in there.",
    "ra": "The sun statue's carved upside down, setting into the ground. Something about keeping the light off whoever's below.",
    "greetings": "Every visitor in the greeting hall carries a sealed jar. Bringing them in, not giving them away.",
}
GERMAN = {
    "horus": "The Horus throne was carved for two rulers. One name was removed so violently the chisel went through the stone. A usurper, and one the priests feared.",
    "hieroglyphs": "Under the plaster of the great inscription there is an older text. It speaks of a priest-king who 'did not stay dead'.",
    "obelisk": "The obelisk counts forty years of a reign and then stops. No death, only a line of guardians' names to the foot of the stone.",
    "astronomer": "Wilhelm's arithmetic on the platform holds: the marked star returns over Akmentar this season.",
    "souls": "In the Hall of Souls the ba is shown locked in a box, carried away from the body. The soul was separated on purpose.",
    "ra": "The solar disc on the Ra statue sets into the earth. The text asks that the light never reach the one below.",
}
WITHHOLD = {
    "americans": "And there's one more spot my boys went over... I'll keep that one under my hat for now, if it's all the same to you. Business is business.",
    "germans": "There is a third finding. I will not speak of it until it has been properly examined. A hasty reading would be worse than none.",
}
REVEAL = {
    "americans": "Oh, all right, you've earned it. Here's the last one, and don't say Charlie Whitfield never gave you anything.",
    "germans": "Very well. In the interest of everyone's safety, and against my better judgement, here is the third.",
}
REFUSE = {
    "americans": "Nice try, pal. A man's got to keep something back.",
    "germans": "No. When the work is finished, perhaps.",
}
CHALLENGED = {
    "americans": "Hiding? I'm sharing more than I have to! You want everything, you pay for it, like I did.",
    "germans": "I am not hiding anything, sir. I am being careful. You might try it yourself.",
}
LEADER = {"americans": ("whitfield", "Charlie Whitfield", AMERICAN), "germans": ("adler", "Professor Adler", GERMAN)}
OPEN = {
    "americans": "Morning, partner! Sleep well? Me neither. Come on, let's swap stories before we go down. Here's what my boys turned up.",
    "germans": "Good morning. We agreed to share our findings, so let us do so properly, before we go below. I will begin.",
}

nodes = {
    "start": {"branch": [
        {"if": {"flag": "ally_is_americans"}, "next": "americans_open"},
        {"if": {"flag": "ally_is_germans"}, "next": "germans_open"},
        {"if": {"in_party": "eleanor"}, "next": "alone_eleanor"},
        {"next": "alone"}]},
    "alone_eleanor": {"speaker": "eleanor", "line": "There's no one left to compare notes with. Just us, and whatever we found ourselves.", "next": "end"},
    "alone": {"speaker": "player", "line": "No one left to compare notes with. We go down with what we've got.", "next": "end"},
    "end": {"end": True},
}
for side, (lid, lname, lines) in LEADER.items():
    p = side  # node prefix
    nodes[p + "_open"] = {"speaker": lid, "line": OPEN[side], "next": p + "_share"}
    nodes[p + "_share"] = {"branch": [
        {"if": {"flag": "claimed_%s_%s" % (s, side), "not_flag": "ally_shared_" + s}, "next": "%s_tell_%s" % (p, s)} for s in lines
    ] + [{"next": p + "_hold"}]}
    for s, text in lines.items():
        nodes["%s_tell_%s" % (p, s)] = {"speaker": lid, "line": text,
            "do": [{"set_flag": "ally_shared_" + s}, {"journal": ["akmentar_surface", s, "told by " + lname]}],
            "next": p + "_more"}
    # Two shares, then the third is held back: a silent step sends it round once more.
    nodes[p + "_more"] = {"branch": [{"if": {"flag": "act5_morning_shared_one"}, "next": p + "_hold"}, {"next": p + "_again"}]}
    nodes[p + "_again"] = {"do": [{"set_flag": "act5_morning_shared_one"}], "branch": [{"next": p + "_share"}]}
    nodes[p + "_hold"] = {"branch": [
        {"if": {"flag": "claimed_%s_%s" % (s, side), "not_flag": "ally_shared_" + s}, "next": "%s_keep_%s" % (p, s)} for s in lines
    ] + [{"next": p + "_menu"}]}
    for s in lines:
        nodes["%s_keep_%s" % (p, s)] = {"do": [{"set_flag": "ally_withheld"}, {"set_flag": "ally_withheld_" + s}], "branch": [{"next": p + "_keep"}]}
    nodes[p + "_keep"] = {"speaker": lid, "line": WITHHOLD[side], "next": p + "_menu"}
    nodes[p + "_menu"] = {"speaker": lid, "line": "Well?" if side == "americans" else "Is there anything else?", "choices": [
        {"label": "Press " + ("him" ), "line": "Come on, Whitfield. Partners share everything." if side == "americans" else "Professor, if it bears on our safety, we need to know.",
         "if": {"flag": "ally_withheld", "not_flag": "act5_pressed"}, "do": [{"set_flag": "act5_pressed"}], "next": p + "_press"},
        {"label": "Challenge " + ("him"), "line": "We agreed to share everything. What are you hiding?",
         "if": {"flag": "ally_withheld", "not_flag": "act5_pressed"}, "do": [{"set_flag": "act5_pressed"}, {"stat": [lid, "trust", -1]}], "next": p + "_challenged"},
        {"label": "Ask Eleanor", "line": "Eleanor, what do you make of all this?", "if": {"in_party": "eleanor", "not_flag": "act5_asked_eleanor"},
         "do": [{"set_flag": "act5_asked_eleanor"}], "next": p + "_eleanor"},
        {"label": "Let it go", "line": "Fine. Let's get moving.", "next": p + "_bye"},
    ]}
    nodes[p + "_press"] = {"branch": [{"if": {"stat": [lid, "trust", 1]}, "next": p + "_reveal"}, {"next": p + "_refuse"}]}
    nodes[p + "_refuse"] = {"speaker": lid, "line": REFUSE[side], "next": p + "_menu"}
    nodes[p + "_reveal"] = {"speaker": lid, "line": REVEAL[side], "next": p + "_reveal_which"}
    nodes[p + "_reveal_which"] = {"branch": [{"if": {"flag": "ally_withheld_" + s}, "next": "%s_show_%s" % (p, s)} for s in lines] + [{"next": p + "_menu"}]}
    for s, text in lines.items():
        nodes["%s_show_%s" % (p, s)] = {"speaker": lid, "line": text,
            "do": [{"set_flag": "ally_shared_" + s}, {"clear_flag": "ally_withheld"}, {"journal": ["akmentar_surface", s, "told by " + lname]}],
            "next": p + "_menu"}
    nodes[p + "_challenged"] = {"speaker": lid, "line": CHALLENGED[side], "next": p + "_challenged_eleanor"}
    nodes[p + "_challenged_eleanor"] = {"branch": [{"if": {"in_party": "eleanor"}, "next": p + "_eleanor_calm"}, {"next": p + "_menu"}]}
    nodes[p + "_eleanor_calm"] = {"speaker": "eleanor", "line": "Let him keep his secret. Whatever it is, we'll find it ourselves.", "next": p + "_menu"}
    nodes[p + "_eleanor"] = {"speaker": "eleanor", "line": "Every one of these points the same way: down. Whoever built this place wanted it found by the right people, and feared what the wrong ones would do.", "next": p + "_menu"}
    nodes[p + "_bye"] = {"speaker": lid, "line": "Then let's see what's under our feet." if side == "americans" else "Then we go down. Carefully.", "next": "end"}

doc = {
    "_help": "Act 5 morning: the ally's leader shares the first two of the surface sites their side claimed (ally_shared_<site> plus a journal entry) and holds back the third (ally_withheld, ally_withheld_<site>). Press him (works with [leader, trust] >= 1) or challenge him (trust -1); Eleanor chimes in. Needs the flag ally_is_<ally> (act5.gd sets it from ally). Generated by tools/dialogue/make_act5_morning.py; edit the lines here freely.",
    "speakers": {"player": "You", "whitfield": "Charlie Whitfield", "adler": "Professor Adler", "eleanor": "Eleanor Whitmore"},
    "start": "start",
    "nodes": nodes,
}
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from wheel import assign_slots
assign_slots(doc)  # Mass Effect positions by tone (tools/dialogue/wheel.py)
out = pathlib.Path(sys.argv[1]) / "dialogue/act5_morning.json"
out.write_text(json.dumps(doc, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
print("wrote", out, len(nodes), "nodes")
