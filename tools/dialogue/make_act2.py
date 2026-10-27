"""Writes the Act 2 (Cairo recruitment) data: dialogue/act2_*.json, actions/act2_*.json and
sites/act2_cairo.json, then checks them the way Conversation.validate does, and a little more
(every node reachable, speakers declared, only known conditions and effects).

    python tools/dialogue/make_act2.py

Edit the content here, not in the JSON (the JSON is overwritten). Design: gameplan/primaryact.md
(Act 2), gameplan/character.md (the people). Money is in pounds; the player starts Act 2 with
START_MONEY (actions/act2_plan.json)."""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
START_MONEY = 3000


# ---------------------------------------------------------------- helpers

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


def B(*pairs):
    return {"branch": [({"if": cond, "next": nxt} if cond else {"next": nxt}) for cond, nxt in pairs]}


END = {"end": True}


def hire(who):
    return [{"recruit": who}, {"set_flag": "hired_" + who}]


def trust(who, n):
    return {"stat": [who, "trust", n]}


def conv(who, n):
    return {"stat": [who, "conviction", n]}


def flag(name, value=True):
    return {"set_flag": name} if value is True else {"set_flag": [name, value]}


def pay(n):
    return {"money": -n}


def talk(help_text, speakers, nodes, start="start"):
    return {"_help": help_text, "speakers": dict({"player": "You"}, **speakers), "start": start, "nodes": nodes}


def prefixed(nodes, prefix, ends):
    """The nodes with ids prefixed (to embed one talk in another); end nodes map to `ends`."""
    out = {}
    def fix(t):
        return ends.get(t, prefix + t)
    for nid, n in nodes.items():
        if nid in ends:
            continue
        n = json.loads(json.dumps(n))
        if "next" in n:
            n["next"] = fix(n["next"])
        for c in n.get("choices", []):
            c["next"] = fix(c["next"])
        for b in n.get("branch", []):
            b["next"] = fix(b["next"])
        out[prefix + nid] = n
    return out


TALKS = {}
ACTIONS = {}


# ---------------------------------------------------------------- the museum: Eleanor, Pembroke

def eleanor_nodes():
    return {
        "start": B(({"flag": "hired_eleanor"}, "already"), (None, "first")),
        "already": L("eleanor", "I've packed my notebooks twice already. Tell me we leave soon.", "end_left"),
        "first": L("eleanor", "Eleanor Whitmore. I read the inscriptions the Professor can't be bothered with. You'll need someone who can read the walls out there.", "fee"),
        "fee": L("eleanor", "The museum pays me one hundred pounds a month. I'll come for the same.", choices=[
            C("Hire her", "One hundred pounds it is.", "joined", if_={"money": 100}, do=[pay(100)]),
            C("Pay her properly", "Three hundred. It's a scholar's work.", "joined",
              if_={"money": 300}, do=[pay(300), trust("eleanor", 1)]),
            C("Pay nothing yet", "You'll get your share when we find it.", "joined_cool", do=[trust("eleanor", -1)]),
            C("Leave", "Sorry to have bothered you, miss.", "end_left"),
        ]),
        "joined": L("eleanor", "Then I'm coming. I'll fetch my things before the Professor finds out.", "end_recruited", do=hire("eleanor")),
        "joined_cool": L("eleanor", "Fine. I'm coming anyway. But I'm keeping my own notes.", "end_recruited", do=hire("eleanor")),
        "end_recruited": END,
        "end_left": END,
    }


def pembroke_nodes():
    return {
        "start": B(({"flag": "hired_pembroke"}, "already"), (None, "first")),
        "already": L("pembroke", "My equipment is crated and labelled. Every crate. I trust yours is too.", "end_left"),
        "first": L("pembroke", "Dr. Arthur Pembroke, field archaeologist. Seven hundred pounds, in advance, and I run the excavation records.", choices=[
            C("Hire him", "Seven hundred. Done.", "joined", if_={"money": 700}, do=[pay(700), trust("pembroke", 1)]),
            C("Haggle", "Seven hundred is steep.", "haggle_check", if_={"not_flag": "pembroke_haggled"}, do=[flag("pembroke_haggled")]),
            C("Leave", "I can't pay that.", "broke"),
        ]),
        # Having read the museum's Akmentar boxes (researched_akmentar) earns his respect, and a lower price.
        "haggle_check": B(({"flag": "researched_akmentar", "money": 500}, "homework"), (None, "haggle")),
        "homework": L("pembroke", "You're the one who signed out the Akmentar boxes. You've actually read them. Very well. Five hundred.", "joined",
                      do=[pay(500), trust("pembroke", 1)]),
        "haggle": L("pembroke", "I am not a porter to be haggled with. Seven hundred.", "first", do=[trust("pembroke", -1)]),
        "broke": L("pembroke", "Then try Dr. Hassan al-Masri in the old quarter. The museum dismissed him for less.", "end_left",
                   do=[flag("knows_hassan")]),
        "joined": L("pembroke", "Very well. I shall want a proper camera, and someone who can hold it still.", "end_recruited", do=hire("pembroke")),
        "end_recruited": END,
        "end_left": END,
    }


TALKS["act2_eleanor"] = talk("Act 2, the museum reading room: hiring Eleanor (hired_eleanor), a transaction: 100, 300 (trust), or nothing yet (trust -1). What she knows and what she wants (promised_eleanor_publish) are on her rapport ladder.",
                             {"eleanor": "Eleanor Whitmore"}, eleanor_nodes())
TALKS["act2_pembroke"] = talk("Act 2, the museum: hiring Dr. Arthur Pembroke (hired_pembroke), 700, or 500 if you haggle having researched the archive (researched_akmentar). Turning him down tells you about Hassan (knows_hassan). Wadi Natrun and his records (promised_pembroke_records) are on his rapport ladder.",
                              {"pembroke": "Dr. Arthur Pembroke"}, pembroke_nodes())

museum = {
    "start": B(({"flag": "met_archivist"}, "again"), (None, "first")),
    "again": L("archivist", "You again. My answer has not improved overnight.", "menu"),
    "first": L("archivist", "Another treasure hunter. This is a museum, sir, not a hiring hall. State your business, and be brief.", "menu",
               do=[flag("met_archivist")]),
    "menu": L("archivist", "Well?", choices=[
        C("Ask for an Egyptologist", "I'm putting together a private expedition. I need an Egyptologist, and they tell me you have the best in Cairo.", "ask"),
        C("Mention Akmentar", "We're going after the tombs of Akmentar.", "myth", if_={"not_flag": "archivist_myth"}, do=[flag("archivist_myth")]),
        C("Leave", "I'll see myself out.", "bye"),
    ]),
    "myth": L("archivist", "Akmentar is a story camel drivers tell tourists for a few piastres. There is no tomb, and there never was.", "menu"),
    "ask": L("archivist", "Absolutely not. No scholar of this museum will be seen chasing fairy tales with a hired gun.", choices=[
        C("Ask about his staff", "Surely not everyone here agrees with you.", "staff"),
        C("Offer a donation", "The museum could use a generous donation. Shall we say two hundred pounds?", "bribe",
          if_={"money": 200, "not_flag": "archivist_bribed"}, do=[pay(200), flag("archivist_bribed")]),
        C("Threaten him", "Find me someone, Professor, or I'll make this your problem. Personally.", "threat"),
        C("Leave", "Suit yourself.", "bye"),
    ]),
    "bribe": L("archivist", "Two hundred pounds buys the museum a display case. It does not buy you my staff. It may buy you a look at our basement, if you insist on wasting your time.", "ask"),
    "staff": L("archivist", "Two of my people might be foolish enough. Miss Whitmore believes every legend she translates. Dr. Pembroke believes nothing he cannot catalogue, and badly needs a success.", "pick",
               do=[flag("knows_eleanor"), flag("knows_pembroke"), flag("museum_staff_known")]),
    "pick": L("archivist", "Speak to one of them, if you must. The other I need at work today.", choices=[
        C("Approach Miss Whitmore", "Miss Whitmore? A word, if you have one.", "el_start", if_={"not_flag": "hired_eleanor"}),
        C("Approach Dr. Pembroke", "Dr. Pembroke? A moment of your time.", "pe_start", if_={"not_flag": "hired_pembroke"}),
        C("Leave", "Thank you, Professor. That's all.", "bye"),
    ]),
    "threat": L("archivist", "You dare threaten me in my own museum? Guards! Remove this man!", "end_fight",
                do=[flag("archivist_hostile"), flag("knows_eleanor"), flag("museum_staff_known"), {"event": "fight_museum_guards"}]),
    "bye": L("archivist", "Good day.", "end_left"),
    "end_recruited": END,
    "end_left": END,
    "end_fight": END,
}
museum.update(prefixed(eleanor_nodes(), "el_", {"end_recruited": "end_recruited", "end_left": "end_left"}))
museum.update(prefixed(pembroke_nodes(), "pe_", {"end_recruited": "end_recruited", "end_left": "end_left"}))
TALKS["act2_museum"] = talk(
    "Act 2, the museum, first visit (one action): the chief archivist refuses, names Eleanor and Pembroke (knows_eleanor, knows_pembroke), and you may approach ONE of them in the same visit (the el_ / pe_ nodes are act2_eleanor / act2_pembroke). Later visits use the find_ actions. Until you learn the names (museum_staff_known) you can come back and ask again. Threatening him: archivist_hostile + event fight_museum_guards (end_fight); Eleanor saw it (knows_eleanor). The 200-pound donation (archivist_bribed) opens the locked cabinet in act2_archive.",
    {"archivist": "Professor El-Gohary", "eleanor": "Eleanor Whitmore", "pembroke": "Dr. Arthur Pembroke"}, museum)

TALKS["act2_archive"] = talk(
    "Act 2, research Akmentar in the museum archive (one action): researched_akmentar and the journal clue act2_cairo/archive; with archivist_bribed also act2_cairo/archive_extra.",
    {"clerk": "Museum clerk", "archivist": "Professor El-Gohary"}, {
        "start": B(({"flag": "archivist_bribed"}, "bribed"), (None, "open")),
        "open": L("clerk", "The Akmentar boxes? Basement, row nine. Nobody has signed for them since before the war.", "read"),
        "bribed": L("archivist", "Our donor wishes to see the Akmentar papers. Bring him the locked cabinet as well. All of it.", "read_extra"),
        "read": L("player", "Travellers' tales, a few copied inscriptions, and one map with its edge burned away. Enough to start with.", "end",
                  do=[{"journal": ["act2_cairo", "archive", "the museum archive"]}, flag("researched_akmentar")]),
        "read_extra": L("player", "The boxes, and in the cabinet a field report nobody was meant to read.", "end",
                        do=[{"journal": ["act2_cairo", "archive", "the museum archive"]},
                            {"journal": ["act2_cairo", "archive_extra", "the museum's locked cabinet"]}, flag("researched_akmentar")]),
        "end": END,
    })


# ---------------------------------------------------------------- the old quarter: Hassan

def hassan_offer():
    return {
        "offer": L("hassan", "Hassan al-Masri. I read what the priests wrote and what they tried to erase. My fee is three hundred pounds.", choices=[
            C("Hire him", "Three hundred pounds. Welcome.", "joined", if_={"money": 300}, do=[pay(300), trust("hassan", 1)]),
            C("Ask him to come unpaid", "I can't pay you yet.", "joined_poor"),
            C("Leave", "I'll think about it.", "end_left"),
        ]),
        "joined": L("hassan", "Good. I will pack the books I kept.", "end_recruited", do=hire("hassan")),
        "joined_poor": L("hassan", "Keep your money. I will come anyway. You may pay me when you can.", "end_recruited", do=hire("hassan")),
    }


hassan = {
    "start": B(({"flag": "hired_hassan"}, "already"), ({"flag": "met_hassan"}, "again"), (None, "yacoub")),
    "already": L("hassan", "My books are packed. The ones I kept, at least.", "end_left"),
    "yacoub": L("yacoub", "An expedition to Akmentar? Then you want the doctor, not me. He is in the back room, as always, arguing with his books.", "offer",
                do=[flag("met_hassan"), flag("knows_hassan")]),
    "again": L("hassan", "You came back.", "offer"),
    "end_recruited": END,
    "end_left": END,
}
hassan.update(hassan_offer())
TALKS["act2_hassan"] = talk(
    "Act 2, Yacoub Ben-Ami's office in the old quarter: hiring Dr. Hassan al-Masri (hired_hassan), 300, or unpaid: the reliable fallback, he joins even if you can't pay. A transaction only; why he goes, and his promise about doors, come later on his rapport ladder (tools/dialogue/rapport.py).",
    {"hassan": "Dr. Hassan al-Masri", "yacoub": "Yacoub Ben-Ami"}, hassan)

TALKS["act2_hassan_fallback"] = talk(
    "Act 2, the morning you leave Cairo, at the hotel: if no Egyptologist was hired (none of hired_eleanor, hired_pembroke, hired_hassan), Hassan comes to you and joins for free. act2.gd starts this; the expedition can't leave without an Egyptologist.",
    {"hassan": "Dr. Hassan al-Masri"}, {
        "start": L("hassan", "Forgive me. I hear your expedition leaves today without anyone who can read a wall. Hassan al-Masri. I will come, no fee.", choices=[
            C("Accept gladly", "Welcome aboard, Doctor.", "joined", do=[trust("hassan", 1)]),
            C("Accept", "All right. Come.", "joined"),
        ]),
        "joined": L("hassan", "Then let us go.", "end_recruited", do=hire("hassan")),
        "end_recruited": END,
    })


# ---------------------------------------------------------------- the military club: Hargreaves

TALKS["act2_hargreaves"] = talk(
    "Act 2, the military club: hiring Tom Hargreaves (hired_hargreaves), 600, or 300 now and 300 owed (owe_hargreaves). An old comrade's hello, then a transaction; his question about the wounded is on his rapport ladder now.",
    {"hargreaves": "Tom Hargreaves"}, {
        "start": B(({"flag": "hired_hargreaves"}, "already"), (None, "first")),
        "already": L("hargreaves", "Rifles cleaned, boots polished. Say the word.", "end_left"),
        "first": L("hargreaves", "Well, I'll be. Heard you'd gone private. If it's a man who keeps people alive you want, I'm six hundred pounds.", choices=[
            C("Hire him", "Six hundred pounds. Worth every penny.", "joined", if_={"money": 600}, do=[pay(600)]),
            C("Half now, half later", "Three hundred now, three hundred when we're home.", "joined_owed",
              if_={"money": 300}, do=[pay(300), flag("owe_hargreaves", 300)]),
            C("Leave", "Too rich for me, Tom.", "too_rich"),
        ]),
        "joined": L("hargreaves", "Then I'm your man. I'll want to see every rifle before we leave.", "end_recruited", do=hire("hargreaves")),
        "joined_owed": L("hargreaves", "Your word's good with me. Don't make me regret it.", "end_recruited", do=hire("hargreaves")),
        "too_rich": L("hargreaves", "Door's always open. Bar's always open, come to that.", "end_left"),
        "end_recruited": END,
        "end_left": END,
    })


# ---------------------------------------------------------------- the tavern: Idris, Isabelle, McKenna

TALKS["act2_idris"] = talk(
    "Act 2, McKenna's tavern: hiring Idris Mahjoub (hired_idris), 350, or 200 haggled (idris_underpaid: he resents it). His family and his city contacts (idris_contacts, Act 7) are on his rapport ladder.",
    {"idris": "Idris Mahjoub"}, {
        "start": B(({"flag": "hired_idris"}, "already"), (None, "first")),
        "already": L("idris", "I am ready when you are.", "end_left"),
        "first": L("idris", "Idris Mahjoub. I guard merchants on the road south, and none of them has lost a piastre with me. Three hundred and fifty pounds.", choices=[
            C("Hire him", "Three hundred and fifty. Fair.", "joined", if_={"money": 350}, do=[pay(350), trust("idris", 1)]),
            C("Haggle", "Two hundred. Take it or leave it.", "joined_cool",
              if_={"money": 200}, do=[pay(200), trust("idris", -1), flag("idris_underpaid")]),
            C("Leave", "Can't afford you today.", "end_left"),
        ]),
        "joined": L("idris", "Then we have an agreement. I keep my agreements.", "end_recruited", do=hire("idris")),
        "joined_cool": L("idris", "Two hundred. I will remember it.", "end_recruited", do=hire("idris")),
        "end_recruited": END,
        "end_left": END,
    })


TALKS["act2_isabelle"] = talk(
    "Act 2, McKenna's tavern: hiring Isabelle Moreau (hired_isabelle), 450. She won't sign on with a stranger: Hargreaves in the party, act1_gunfight_won (Act 1's armed confrontation won), or settling her bounty-hunter trouble first (heard_isabelle_trouble from McKenna's rumours: event fight_bounty_hunters, end_fight). After that fight is won, act2.gd sets isabelle_trouble_settled and starts this talk again; it goes straight to her price. Her terms in a fight (promised_isabelle_free) are on her rapport ladder.",
    {"isabelle": "Isabelle Moreau"}, {
        "start": B(({"flag": "hired_isabelle"}, "already"), ({"flag": "isabelle_trouble_settled"}, "after_fight"), (None, "first")),
        "already": L("isabelle", "I'm here. Don't fuss.", "end_left"),
        "after_fight": L("isabelle", "Three of them, and not a scratch on you. All right, monsieur.", "fee", do=[trust("isabelle", 2)]),
        "first": L("isabelle", "Isabelle Moreau. I find people, and I keep people alive. I don't work for strangers.", choices=[
            C("Hargreaves vouches for me", "Tom Hargreaves is coming. Ask him about me.", "fee", if_={"in_party": "hargreaves"}, do=[trust("isabelle", 1)]),
            C("You saw Freddie's office", "You saw how it went at Freddie's office.", "fee", if_={"flag": "act1_gunfight_won"}, do=[trust("isabelle", 1)]),
            C("Offer to handle her trouble", "Those three by the window. Want me to have a word?", "trouble",
              if_={"flag": "heard_isabelle_trouble"}),
            C("Leave", "My mistake.", "come_back"),
        ]),
        "trouble": L("isabelle", "Be my guest.", "end_fight", do=[{"event": "fight_bounty_hunters"}]),
        "come_back": L("isabelle", "Come back when you've done something worth hearing about.", "end_left", do=[flag("knows_isabelle_terms")]),
        "fee": L("isabelle", "Four hundred and fifty pounds.", choices=[
            C("Hire her", "Four hundred and fifty. Done.", "joined", if_={"money": 450}, do=[pay(450)]),
            C("Leave", "I can't pay that today.", "end_left"),
        ]),
        "joined": L("isabelle", "Then try to keep up.", "end_recruited", do=hire("isabelle")),
        "end_recruited": END,
        "end_left": END,
        "end_fight": END,
    })


TALKS["act2_mckenna"] = talk(
    "Act 2, McKenna's tavern, gather rumours (one action): heard_isabelle_trouble (unlocks a way to recruit her), heard_americans_guns + heard_americans_boat (Acts 3 and 7), heard_first_expedition.",
    {"mckenna": "George McKenna"}, {
        "start": L("mckenna", "McKenna's. Cold beer and no questions. Well, you look like you've got questions.", "menu"),
        "menu": L("mckenna", "Go on.", choices=[
            C("Ask who's for hire", "Who's for hire in here?", "mercs", if_={"not_flag": "heard_isabelle_trouble"},
              do=[flag("heard_isabelle_trouble")]),
            C("Ask about rivals", "Anyone else heading out into the desert?", "rivals", if_={"not_flag": "heard_americans_guns"},
              do=[flag("heard_americans_guns"), flag("heard_americans_boat")]),
            C("Ask about Akmentar", "Ever hear anyone talk about Akmentar?", "akmentar", if_={"not_flag": "heard_first_expedition"},
              do=[flag("heard_first_expedition")]),
            C("That's all", "That'll do. Thanks, George.", "bye"),
        ]),
        "mercs": L("mckenna", "Idris Mahjoub, in the corner. Honest, for a gunman. And the Frenchwoman, Moreau. Best shot in Cairo, and three bounty men by the window waiting for her to leave.", "menu"),
        "rivals": L("mckenna", "Yanks. Loud ones. Whitfield's lot have been buying rounds for the whole bar and hired four guns off the docks. Booked on the riverboat south, I hear.", "menu"),
        "akmentar": L("mckenna", "A fellow sat right there last year asking the same. One of Blackwood's men. Never came back for his change.", "menu"),
        "bye": L("mckenna", "Mind how you go.", "end"),
        "end": END,
    })


# ---------------------------------------------------------------- the caravanserai: Saleh, Youssef, Farid, Abdel

TALKS["act2_saleh"] = talk(
    "Act 2, the caravanserai: hiring Saleh al-Rashidi, the veteran guide (hired_saleh), 700. He doesn't haggle; he sends you to Youssef or Farid. How he means to cross, and the men he lost, are on his rapport ladder.",
    {"saleh": "Saleh al-Rashidi"}, {
        "start": B(({"flag": "hired_saleh"}, "already"), (None, "first")),
        "already": L("saleh", "Six days more water than you think. Always.", "end_left"),
        "first": L("saleh", "Saleh al-Rashidi. I guide caravans west, and my travellers come home. Seven hundred pounds.", choices=[
            C("Hire him", "Seven hundred. Bring us home.", "joined", if_={"money": 700}, do=[pay(700)]),
            C("Haggle", "Seven hundred is a lot of money.", "haggle", if_={"not_flag": "saleh_haggled"}, do=[flag("saleh_haggled")]),
            C("Leave", "Not today.", "end_left"),
        ]),
        "haggle": L("saleh", "My price is my price. Cheaper, ask Youssef. A merchant, ask Farid.", "first"),
        "joined": L("saleh", "Then we leave with water for six days more than you think you need.", "end_recruited", do=hire("saleh")),
        "end_recruited": END,
        "end_left": END,
    })


TALKS["act2_youssef"] = talk(
    "Act 2, the caravanserai: hiring Youssef Nabil, the young scout (hired_youssef), 250. His ambition (promised_youssef_credit) is on his rapport ladder.",
    {"youssef": "Youssef Nabil"}, {
        "start": B(({"flag": "hired_youssef"}, "already"), (None, "first")),
        "already": L("youssef", "When do we go? Today? Tomorrow is fine also.", "end_left"),
        "first": L("youssef", "Youssef Nabil! I find roads where there are no roads. Two hundred and fifty pounds. Cheap!", choices=[
            C("Hire him", "All right. You're hired.", "joined", if_={"money": 250}, do=[pay(250)]),
            C("Leave", "Not today, lad.", "end_left"),
        ]),
        "joined": L("youssef", "You will not be sorry! I go and tell my uncle.", "end_recruited", do=hire("youssef")),
        "end_recruited": END,
        "end_left": END,
    })


TALKS["act2_farid"] = talk(
    "Act 2, the caravanserai: hiring Farid Mansour, the caravan merchant (hired_farid). 400, or 200 haggled if he may trade along the way (farid_trading). He brings his own stores (rations).",
    {"farid": "Farid Mansour"}, {
        "start": B(({"flag": "hired_farid"}, "already"), (None, "first")),
        "already": L("farid", "Everything is counted twice. Shall I count it a third time?", "end_left"),
        "first": L("farid", "Farid Mansour. Water, fodder, flour, camels, tents: my stores travel with you. Four hundred pounds.", choices=[
            C("Hire him", "Four hundred. Done.", "joined", if_={"money": 400}, do=[pay(400), {"item": ["rations", 10]}]),
            C("Haggle", "Too much.", "haggle"),
            C("Leave", "I'll manage my own supplies.", "end_left"),
        ]),
        "haggle": L("farid", "Two hundred, if my goods may travel with yours and trade on the way.", choices=[
            C("Let him trade", "Two hundred, and you can trade.", "joined",
              if_={"money": 200}, do=[pay(200), flag("farid_trading"), {"item": ["rations", 10]}]),
            C("Leave", "No side deals.", "end_left"),
        ]),
        "joined": L("farid", "A pleasure doing business.", "end_recruited", do=hire("farid")),
        "end_recruited": END,
        "end_left": END,
    })


TALKS["act2_abdel"] = talk(
    "Act 2, the caravanserai manager (free): the three roads (Act 3) and the guides (heard_routes).",
    {"abdel": "Abdel Rahman"}, {
        "start": L("abdel", "Welcome. Merchants, guides, camels, horses: if it crosses the desert, it passes through my gate.", "menu", do=[flag("heard_routes")]),
        "menu": L("abdel", "What do you need to know?", choices=[
            C("Ask about the roads", "How do I get west, to the empty country?", "roads", if_={"not_flag": "abdel_roads"}, do=[flag("abdel_roads")]),
            C("Ask about the guides", "Who should I hire?", "guides", if_={"not_flag": "abdel_guides"}, do=[flag("abdel_guides")]),
            C("Thank him", "That's all. Thank you.", "bye"),
        ]),
        "roads": L("abdel", "Three ways. Across the sand on horseback: fastest, but horses cost money. Upriver on Captain Hamdi's boat: cheapest, if you like company. Or the long coast road by truck, slow but kind.", "menu"),
        "guides": L("abdel", "Saleh al-Rashidi, if you want to come home. Young Youssef, if you are in a hurry. Farid Mansour, if you want to eat well on the way.", "menu"),
        "bye": L("abdel", "Go in peace.", "end"),
        "end": END,
    })


# ---------------------------------------------------------------- the labour market: the three crews

def crew_intro(who, broker_line):
    return {"start": B(({"flag": "hired_" + who}, "already"), ({"flag": "met_fatima"}, "first"), (None, "fatima")),
            "fatima": L("fatima", broker_line, "first", do=[flag("met_fatima")])}


FATIMA = "I am Fatima el-Sayed. I place workers with employers. "
mahmoud = crew_intro("mahmoud", FATIMA + "Mahmoud Fawzi's men are the best excavators in Cairo.")
mahmoud.update({
    "already": L("mahmoud", "My men are ready. Picks sharpened, baskets mended.", "end_left"),
    "first": L("mahmoud", "Mahmoud Fawzi. Twelve excavators and their tools: six hundred pounds.", choices=[
        C("Hire the crew", "Six hundred. Welcome to the expedition.", "joined", if_={"money": 600}, do=[pay(600)]),
        C("Leave", "I can't pay that yet.", "end_left"),
    ]),
    "joined": L("mahmoud", "Good. We dig carefully, and we dig well.", "end_recruited", do=hire("mahmoud")),
    "end_recruited": END,
    "end_left": END,
})
TALKS["act2_mahmoud"] = talk(
    "Act 2, the labour market: hiring Mahmoud Fawzi's experienced excavators (hired_mahmoud), 600. Fatima el-Sayed, the broker, introduces the first crew you visit (met_fatima). Whose name goes on the finds (promised_mahmoud_credit) is on his rapport ladder.",
    {"mahmoud": "Mahmoud Fawzi", "fatima": "Fatima el-Sayed"}, mahmoud)

khalil = crew_intro("khalil", FATIMA + "Khalil Darwish's men are dockworkers without docks. Strong, and cheap.")
khalil.update({
    "already": L("khalil", "My men are fed and ready.", "end_left"),
    "first": L("khalil", "Khalil Darwish. Ten men who lift anything, dig anything. Two hundred and fifty pounds.", choices=[
        C("Hire the crew", "Two hundred and fifty, up front.", "joined", if_={"money": 250}, do=[pay(250), trust("khalil", 1)]),
        C("Half now, half later", "Half now, the rest when we're back.", "joined_owed",
          if_={"money": 130}, do=[pay(130), trust("khalil", -1), flag("owe_khalil", 120)]),
        C("Leave", "I'll come back.", "end_left"),
    ]),
    "joined": L("khalil", "Paid before a stone is lifted. Good.", "end_recruited", do=hire("khalil")),
    "joined_owed": L("khalil", "Half. Very well. They will be waiting for the other half.", "end_recruited", do=hire("khalil")),
    "end_recruited": END,
    "end_left": END,
})
TALKS["act2_khalil"] = talk(
    "Act 2, the labour market: hiring Khalil Darwish's local labourers (hired_khalil), 250 up front, or 130 now and 120 owed (owe_khalil).",
    {"khalil": "Khalil Darwish", "fatima": "Fatima el-Sayed"}, khalil)

naguib = crew_intro("naguib", FATIMA + "Naguib Sabet runs porters. If it must be carried, he carries it.")
naguib.update({
    "already": L("naguib", "Loads weighed, camels shod. We are ready.", "end_left"),
    "first": L("naguib", "Naguib Sabet. Eight porters, with camels, tents and a cook. Four hundred and fifty pounds.", choices=[
        C("Hire the porters", "Four hundred and fifty. Done.", "joined", if_={"money": 450}, do=[pay(450)]),
        C("Leave", "Too much.", "end_left"),
    ]),
    "joined": L("naguib", "Then we leave at dawn, with everything in its place.", "end_recruited", do=hire("naguib")),
    "end_recruited": END,
    "end_left": END,
})
TALKS["act2_naguib"] = talk(
    "Act 2, the labour market: hiring Naguib Sabet's professional porters (hired_naguib), 450. They carry: more supplies on the road. Who decides the loads (promised_naguib_loads) is on his rapport ladder.",
    {"naguib": "Naguib Sabet", "fatima": "Fatima el-Sayed"}, naguib)


# ---------------------------------------------------------------- the other city contacts

TALKS["act2_telegraph"] = talk(
    "Act 2, the telegraph office (one action, once a day): one wire per visit. fletcher_wired (the pilot, Danny Fletcher, a late-game ally), the clue act2_cairo/first_expedition, or heard_desert_warnings.",
    {"nabil": "Nabil Sayegh"}, {
        "start": L("nabil", "Where to, sir? One wire per customer at this hour, and I send it myself.", choices=[
            C("Wire Danny Fletcher", "Alexandria. Captain Daniel Fletcher, Royal Flying Corps, retired.", "fletcher",
              if_={"not_flag": "fletcher_wired"}, do=[flag("fletcher_wired")]),
            C("Wire Blackwood's office", "London. Blackwood's office. Ask what happened to the first expedition.", "london",
              if_={"not_flag": "london_wired"}, do=[flag("london_wired")]),
            C("Ask what's come in", "What's been coming in from the desert towns?", "south",
              if_={"not_flag": "heard_desert_warnings"}, do=[flag("heard_desert_warnings"), trust("nabil", 1)]),
            C("Leave", "Nothing today.", "end"),
        ]),
        "fletcher": L("nabil", "A reply within the hour, sir: 'Old man! In Alex with a crate that flies. Shout if you need a lift. D.F.'", "end"),
        "london": L("nabil", "London answers by evening. Not much, sir, but I wrote it all down.", "end",
                    do=[{"journal": ["act2_cairo", "first_expedition", "a telegram from London"]}]),
        "south": L("nabil", "Strange messages, sir. Riders in dark robes stopping caravans. They take nothing. They only warn people to turn back.", "end"),
        "end": END,
    })

TALKS["act2_karim"] = talk(
    "Act 2, the sponsor's agent at the bank (one action; the same Karim Fahmy who made Act 1's offer, and he says so): an advance of 1000 (karim_advance), or 500 if you pressed him about the first expedition first (karim_pressed); pressing hard: heard_blackwood_silence.",
    {"karim": "Karim Fahmy"}, {
        "start": B(({"flag": "act1_offer_accepted"}, "again"), (None, "first")),
        "again": L("karim", "You again, and the fund barely a day old. Sir Reginald has been generous already. What more can the expedition possibly need?", "menu"),
        "first": L("karim", "Karim Fahmy, Sir Reginald Blackwood's agent. Sir Reginald has been generous already. What more can the expedition possibly need?", "menu"),
        "menu": L("karim", "Well?", choices=[
            C("Ask for more money", "More money. An advance on the reward.", "advance",
              if_={"not_flag": "karim_pressed"}, do=[{"money": 1000}, flag("karim_advance")]),
            C("Ask for more money", "Now, about that advance.", "advance_cold",
              if_={"flag": "karim_pressed"}, do=[{"money": 500}, flag("karim_advance")]),
            C("Ask about the first expedition", "What happened to Blackwood's first expedition?", "pressed",
              if_={"not_flag": "karim_pressed"}, do=[flag("karim_pressed"), trust("karim", -1)]),
            C("Leave", "Nothing. Good day.", "end"),
        ]),
        "advance": L("karim", "One thousand pounds, against your reward. Sign here, and here.", "end"),
        "advance_cold": L("karim", "Five hundred. And I shall mention your curiosity to Sir Reginald.", "end"),
        "pressed": L("karim", "That is not a matter for the expedition's leader.", choices=[
            C("Push harder", "It's exactly my matter. I'm the one walking into it.", "truth",
              if_={"not_flag": "heard_blackwood_silence"}, do=[flag("heard_blackwood_silence")]),
            C("Drop it", "Fine. Forget I asked.", "menu"),
        ]),
        "truth": L("karim", "Very well. They found something, and then they stopped answering. Sir Reginald sent no one after them. Until you.", "menu"),
        "end": END,
    })

TALKS["act2_clara"] = talk(
    "Act 2, the hotel (one action): where the rivals stay (heard_rival_rooms) and a quiet Italian guest (heard_italians). For 5, Clara keeps an eye on them (clara_watching, an Act 7 lead).",
    {"clara": "Clara Beaumont"}, {
        "start": L("clara", "I don't gossip about my guests, monsieur. But I do talk about the weather, and the weather this week is crowded.", choices=[
            C("Ask about the rivals", "Who else is staying here?", "rivals", do=[flag("heard_rival_rooms"), flag("heard_italians")]),
            C("Leave", "Never mind.", "end"),
        ]),
        "rivals": L("clara", "Americans on the second floor, loud and generous. A German professor and his men on the third, up at dawn, maps on every table. And a gentleman who signs as Signor Rossi and never leaves his room before dark.", choices=[
            C("Ask her to keep watch", "Keep an eye on them for me? It's worth a few pounds.", "watch",
              if_={"money": 50}, do=[pay(50), flag("clara_watching"), trust("clara", 1)]),
            C("Thank her", "Thank you, madame.", "end"),
        ]),
        "watch": L("clara", "For my best guest, I notice things. It is a hotelier's habit.", "end"),
        "end": END,
    })

TALKS["act2_hamdi"] = talk(
    "Act 2, the docks (free): passage on the riverboat. heard_americans_boat; booking now (20) sets booked_riverboat for Act 3's river route; heard_river_warning.",
    {"hamdi": "Captain Yusuf Hamdi"}, {
        "start": L("hamdi", "Deck passage upriver for your whole party: two hundred pounds. But I warn you, the Americans have booked half my deck.", "menu",
                   do=[flag("heard_americans_boat")]),
        "menu": L("hamdi", "Well?", choices=[
            C("Book passage", "Two hundred pounds. Keep us a corner of that deck.", "booked",
              if_={"money": 200, "not_flag": "booked_riverboat"}, do=[pay(200), flag("booked_riverboat")]),
            C("Ask about the river", "Is the river safe these days?", "river",
              if_={"not_flag": "heard_river_warning"}, do=[flag("heard_river_warning")]),
            C("Leave", "I'll think about it.", "bye"),
        ]),
        "booked": L("hamdi", "Then you sail with us. Keep your guns cleaned and your Americans sober.", "end"),
        "river": L("hamdi", "Mostly. But riders have been seen on the banks, south of the bend. Strange ones. They don't rob boats. They watch them.", "menu"),
        "bye": L("hamdi", "The boat leaves with or without you.", "end"),
        "end": END,
    })


# ---------------------------------------------------------------- the action spots (one file per Cairo spot)

def spot(name, prompt, actions, help_text):
    return {"_help": help_text + " See scripts/actions/action_spot.gd for the format.", "name": name, "prompt": prompt, "actions": actions}


def recruit_action(who, label, log, talk_id=None, extra_if=None):
    cond = {"not_flag": "hired_" + who}
    if extra_if:
        assert not set(extra_if) & set(cond), "one condition per key"
        cond.update(extra_if)
    return {"id": "hire_" + who, "label": label, "cost": 1, "if": cond, "hide_if_locked": True,
            "conversation": talk_id or "act2_" + who, "with": who, "log": log}


def buy(id_, label, price, items, once=False, extra=None):
    a = {"id": id_, "label": "%s (£%d)" % (label, price), "cost": 0, "if": {"money": price},
         "do": [pay(price)] + [{"item": [i, n]} for i, n in items] + (extra or []),
         "log": "Bought: " + label.lower()}
    if once:
        a["once"] = True
    return a


ACTIONS["act2_museum"] = spot("The Cairo Museum", "Enter the museum", [
    {"id": "archivist", "label": "Ask the chief archivist for an Egyptologist", "cost": 1,
     "if": {"not_flag": "museum_staff_known"}, "hide_if_locked": True,
     "conversation": "act2_museum", "with": "archivist", "log": "Asked Professor El-Gohary for an Egyptologist"},
    recruit_action("eleanor", "Find Miss Whitmore in the reading room", "Spoke with Eleanor Whitmore", extra_if={"flag": "knows_eleanor"}),
    recruit_action("pembroke", "Find Dr. Pembroke in his office", "Spoke with Dr. Pembroke", extra_if={"flag": "knows_pembroke"}),
    {"id": "archive", "label": "Research Akmentar in the archive", "cost": 1, "once": True,
     "if": {"not_flag": "archivist_hostile"}, "locked_text": "The archivist has had you banned",
     "conversation": "act2_archive", "log": "Researched Akmentar in the museum archive"},
], "Act 2: the museum. The first visit (archivist) can recruit Eleanor OR Pembroke in the same action; the other costs a later visit.")

ACTIONS["act2_dealer"] = spot("Yacoub Ben-Ami, Antiquities", "Step into the dealer's office", [
    recruit_action("hassan", "Ask after the independent scholar", "Visited Dr. Hassan al-Masri at Yacoub's"),
    buy("survey_map", "An old survey map of the western desert", 150, [("survey_map", 1)], once=True, extra=[flag("has_survey_map")]),
], "Act 2: the antiquities dealer in the old quarter. Hassan is the reliable Egyptologist.")

ACTIONS["act2_club"] = spot("The Officers' Club", "Go into the club", [
    recruit_action("hargreaves", "Look up Tom Hargreaves", "Talked terms with Tom Hargreaves"),
], "Act 2: the military club.")

ACTIONS["act2_tavern"] = spot("McKenna's", "Go into the tavern", [
    {"id": "rumours", "label": "Gather rumours from George McKenna", "cost": 1, "once": True,
     "conversation": "act2_mckenna", "with": "mckenna", "log": "Gathered rumours at McKenna's"},
    recruit_action("idris", "Talk to Idris Mahjoub (gunman)", "Talked terms with Idris Mahjoub"),
    recruit_action("isabelle", "Talk to Isabelle Moreau (gunwoman)", "Talked to Isabelle Moreau"),
], "Act 2: the tavern. Isabelle needs proof of you; McKenna's rumours give one way.")

ACTIONS["act2_caravanserai"] = spot("The Caravanserai", "Enter the caravanserai", [
    {"id": "abdel", "label": "Ask Abdel Rahman about the roads west", "cost": 0, "once": True,
     "conversation": "act2_abdel", "with": "abdel", "log": "Asked Abdel Rahman about the roads"},
    recruit_action("saleh", "Talk to Saleh al-Rashidi (veteran guide)", "Talked terms with Saleh al-Rashidi"),
    recruit_action("youssef", "Talk to Youssef Nabil (young scout)", "Talked to Youssef Nabil"),
    recruit_action("farid", "Talk to Farid Mansour (caravan merchant)", "Talked business with Farid Mansour"),
], "Act 2: the caravanserai, the three desert guides.")

ACTIONS["act2_labour"] = spot("The Labour Market", "Look over the labour market", [
    recruit_action("mahmoud", "Hire Mahmoud Fawzi's excavators", "Talked terms with Mahmoud Fawzi's crew"),
    recruit_action("khalil", "Hire Khalil Darwish's labourers", "Talked terms with Khalil Darwish's crew"),
    recruit_action("naguib", "Hire Naguib Sabet's porters", "Talked terms with Naguib Sabet's porters"),
], "Act 2: the labour market, the three crews (one action each), through the broker Fatima el-Sayed.")

ACTIONS["act2_gunsmith"] = spot("Ahmed Zaki, Gunsmith", "Look at the guns", [
    buy("revolver_ammo", "Revolver cartridges, 24", 30, [("revolver_ammo", 24)]),
    buy("rifle", "A lever rifle and 20 cartridges", 250, [("rifle", 1), ("rifle_ammo", 20)], once=True),
    buy("rifle_ammo", "Rifle cartridges, 20", 40, [("rifle_ammo", 20)]),
    buy("shotgun", "A double shotgun and 12 shells", 200, [("shotgun", 1), ("shotgun_shells", 12)], once=True),
    buy("shotgun_shells", "Shotgun shells, 12", 30, [("shotgun_shells", 12)]),
    {"id": "arm_party", "label": "Have Zaki arm the whole expedition (£400)", "cost": 1, "once": True, "if": {"money": 400},
     "do": [pay(400), flag("party_armed"), {"item": ["rifle_ammo", 60]}],
     "log": "Had Ahmed Zaki fit the expedition with good rifles"},
], "Act 2: the gunsmith. Single purchases are free (money only); fitting out the whole expedition with good rifles takes an action (party_armed).")

ACTIONS["act2_outfitter"] = spot("Samira Haddad, Outfitter", "Look at the supplies", [
    buy("rations", "Rations, a week for the party", 100, [("rations", 7)]),
    buy("water", "Water casks, a week", 60, [("water", 7)]),
    buy("tents", "Tents and bedding", 120, [("tents", 1)], once=True),
    buy("tools", "Digging tools", 100, [("tools", 1)], once=True),
    buy("lanterns", "Lanterns and oil", 50, [("lanterns", 1)], once=True),
    buy("rope", "Rope, a hundred feet", 20, [("rope", 1)]),
    buy("medicine", "A medical kit", 80, [("medicine", 1)]),
    {"id": "outfit", "label": "Order a full expedition outfit (£450)", "cost": 1, "once": True, "if": {"money": 450},
     "do": [pay(450), flag("well_supplied"), {"item": ["rations", 14]}, {"item": ["water", 14]}, {"item": ["tents", 1]},
            {"item": ["tools", 1]}, {"item": ["lanterns", 1]}, {"item": ["rope", 1]}, {"item": ["medicine", 2]}],
     "log": "Samira Haddad outfitted the expedition"},
], "Act 2: the general outfitter. Single purchases are free; a full outfit at a better price takes an action (well_supplied).")

ACTIONS["act2_bazaar"] = spot("The Khan Bazaar", "Wander into the bazaar", [
    buy("cheap_rations", "Cheap rations, a week (of doubtful age)", 60, [("rations", 7)]),
    {"id": "bargains", "label": "Hunt the bazaar with Rafiq el-Tayeb (£150)", "cost": 1, "once": True, "if": {"money": 150},
     "do": [pay(150), flag("bazaar_bargains"), {"item": ["dynamite", 4]}, {"item": ["flares", 3]}, {"item": ["rifle_ammo", 20]}],
     "log": "Found dynamite, flares and cheap cartridges with Rafiq el-Tayeb"},
    {"id": "salim", "label": "Pay Salim Farouk for a lead (£100)", "cost": 1, "once": True, "if": {"money": 100},
     "do": [pay(100), flag("heard_italians"), flag("salim_lead")],
     "log": "Salim Farouk: an Italian collector is quietly buying maps of the west"},
], "Act 2: the bazaar. Unusual equipment and a paid informant (heard_italians).")

ACTIONS["act2_telegraph"] = spot("The Telegraph Office", "Go into the telegraph office", [
    {"id": "wire", "label": "Send a telegram", "cost": 1, "daily": True,
     "conversation": "act2_telegraph", "with": "nabil", "log": "Sent a telegram"},
], "Act 2: the telegraph office, one wire a day.")

ACTIONS["act2_bank"] = spot("The Bank: Blackwood's Agent", "Call on Karim Fahmy", [
    {"id": "funds", "label": "Negotiate more funds with Karim Fahmy", "cost": 1, "once": True,
     "conversation": "act2_karim", "with": "karim", "log": "Negotiated with Karim Fahmy"},
], "Act 2: the sponsor's agent.")

ACTIONS["act2_hotel"] = spot("Hotel Beaumont", "Speak to the proprietor", [
    {"id": "clara", "label": "Ask Clara Beaumont about her other guests", "cost": 1, "once": True,
     "conversation": "act2_clara", "with": "clara", "log": "Learned where the rival expeditions are staying"},
], "Act 2: the hotel (the bed, save and end of day are hotel_bed, in cairo.gd).")

ACTIONS["act2_docks"] = spot("The Docks", "Find the riverboat captain", [
    {"id": "hamdi", "label": "Ask Captain Hamdi about passage upriver", "cost": 0,
     "conversation": "act2_hamdi", "with": "hamdi", "log": "Asked about passage upriver"},
], "Act 2: the docks. Free; booking passage here (booked_riverboat) pays for Act 3's river route in advance.")

RECRUITS = {
    "eleanor": ["egyptologist", "museum", "0, 10 or 30", "Ancient languages and obscure texts; romance"],
    "pembroke": ["egyptologist", "museum", "70 (50 with researched_akmentar)", "Excavation method, identifying artifacts"],
    "hassan": ["egyptologist", "dealer", "30 or nothing", "Religion, forgotten dynasties; the fallback; secretly a Keeper"],
    "hargreaves": ["gunman", "club", "60 (or 30 + 30 owed)", "Rifle fire, discipline"],
    "idris": ["gunman", "tavern", "20, 35 or 50", "Close range, Cairo's underworld"],
    "isabelle": ["gunman", "tavern", "45 after you prove yourself", "Pistols, fast reactions; romance"],
    "saleh": ["guide", "caravanserai", "70", "Navigation, water"],
    "youssef": ["guide", "caravanserai", "25", "Scouting, other routes"],
    "farid": ["guide", "caravanserai", "40 (20 if he trades)", "Logistics, supplies (brings 10 rations)"],
    "mahmoud": ["crew", "labour", "60 (75 if you keep the credit)", "Experienced excavators"],
    "khalil": ["crew", "labour", "25 (or 13 + 12 owed)", "Local labourers, cheap"],
    "naguib": ["crew", "labour", "45", "Professional porters, carrying"],
}

ITEMS = {
    "revolver_ammo": "Revolver cartridges", "rifle": "Lever rifle", "rifle_ammo": "Rifle cartridges",
    "shotgun": "Double shotgun", "shotgun_shells": "Shotgun shells", "rations": "Rations (party-days)",
    "water": "Water (party-days)", "tents": "Tents and bedding", "tools": "Digging tools", "lanterns": "Lanterns and oil",
    "rope": "Rope", "medicine": "Medical kit", "dynamite": "Dynamite", "flares": "Signal flares", "survey_map": "Old survey map",
}

PLAN = {
    "_help": "Act 2 (Cairo recruitment) overview for act2.gd, written by tools/dialogue/make_act2.py. Not an ActionSpot file.",
    "days": 2,
    "actions_per_day": 3,
    "start": [{"money": START_MONEY}],
    "spots": {s[len("act2_"):]: s for s in ACTIONS},
    "egyptologist_flags": ["hired_eleanor", "hired_pembroke", "hired_hassan"],
    "_egyptologist": "Required. If none of egyptologist_flags is set when the expedition leaves (after day 2), start dialogue act2_hassan_fallback (Hassan joins for free).",
    "recruits": {k: {"role": v[0], "spot": v[1], "fee": v[2], "strength": v[3], "talk": "act2_" + k, "flag": "hired_" + k}
                 for k, v in RECRUITS.items()},
    "hosts": {"museum": "archivist", "dealer": "yacoub", "tavern": "mckenna", "caravanserai": "abdel", "labour": "fatima",
              "gunsmith": "zaki", "outfitter": "samira", "bazaar": "rafiq", "telegraph": "nabil", "bank": "karim",
              "hotel": "clara", "docks": "hamdi"},
    "items": ITEMS,
    "events": {"fight_museum_guards": "threatening the archivist (museum guards brawl)",
               "fight_bounty_hunters": "Isabelle's three bounty men at the tavern; when won set isabelle_trouble_settled and start act2_isabelle (free)"},
    "flags_for_later": ["heard_americans_boat", "heard_americans_guns", "booked_riverboat", "heard_routes", "heard_italians",
                        "heard_rival_rooms", "clara_watching", "idris_contacts", "fletcher_wired", "heard_desert_warnings",
                        "heard_river_warning", "heard_blackwood_silence", "party_armed", "well_supplied", "has_survey_map",
                        "owe_hargreaves", "owe_khalil", "farid_trading", "promised_*"],
}

PEOPLE = {
    "pembroke": "Dr. Arthur Pembroke", "hassan": "Dr. Hassan al-Masri", "hargreaves": "Tom Hargreaves",
    "idris": "Idris Mahjoub", "isabelle": "Isabelle Moreau", "saleh": "Saleh al-Rashidi", "youssef": "Youssef Nabil",
    "farid": "Farid Mansour", "mahmoud": "Mahmoud Fawzi", "khalil": "Khalil Darwish", "naguib": "Naguib Sabet",
    "yacoub": "Yacoub Ben-Ami", "mckenna": "George McKenna", "abdel": "Abdel Rahman", "fatima": "Fatima el-Sayed",
    "zaki": "Ahmed Zaki", "samira": "Samira Haddad", "rafiq": "Rafiq el-Tayeb", "nabil": "Nabil Sayegh",
    "karim": "Karim Fahmy", "clara": "Clara Beaumont", "hamdi": "Captain Yusuf Hamdi",
}

CAIRO_SITES = {
    "_help": "Act 2: journal clues found in Cairo (not walk-up sites; the Act 2 talks write them with the journal effect).",
    "place": "Cairo",
    "sites": {
        "archive": {"name": "The Museum Archive", "desc": "Boxes nobody has opened since before the war",
                    "clue": {"id": "clue_cairo_archive", "title": "The Akmentar papers",
                             "text": "The travellers' accounts agree on little, but three of them mention a temple of three gods, Anubis, Horus and Ra, standing before the tomb, and a king 'whose name the priests cut from the walls'. A burned map puts the site west of the river, beyond the last well."}},
        "archive_extra": {"name": "The Locked Cabinet", "desc": "A field report that was never published",
                          "clue": {"id": "clue_cairo_first_report", "title": "Blackwood's first expedition",
                                   "text": "A field report from Sir Reginald Blackwood's first expedition: 'We found the door. Mr. Ashby insists that something followed us back to camp. Two of the workers have gone.' The report stops there."}},
        "first_expedition": {"name": "The Telegraph Office", "desc": "A wire from London",
                             "clue": {"id": "clue_cairo_last_telegram", "title": "The last telegram",
                                      "text": "Blackwood's London office answers your wire. The first expedition's last telegram came from a desert town on the coast road: 'Site found. Sending for more men. Do not tell the museum.' Nothing came after it."}},
    },
}


# ---------------------------------------------------------------- checks

CONDS = {"flag", "not_flag", "money", "actions", "stat", "in_party", "day"}
EFFECTS = {"set_flag", "clear_flag", "money", "spend_action", "stat", "recruit", "dismiss", "kill", "item", "countdown", "event", "journal"}
SLOTS = {"ur", "r", "lr", "ul", "l", "ll"}


def check_talk(tid, d, problems):
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
                if k == "journal":
                    area, site = e[k][0], e[k][1]
                    if area != "act2_cairo" or site not in CAIRO_SITES["sites"]:
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


def main():
    problems = []
    for tid, d in TALKS.items():
        check_talk(tid, d, problems)
    for sid, s in ACTIONS.items():
        for a in s["actions"]:
            if "conversation" in a and a["conversation"] not in TALKS:
                problems.append("%s/%s: no talk %s" % (sid, a["id"], a["conversation"]))
    if problems:
        print("\n".join(problems))
        sys.exit(1)

    def write(rel, data):
        path = os.path.join(ROOT, rel)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    sys.dont_write_bytecode = True
    from wheel import assign_slots
    for tid, d in TALKS.items():
        assign_slots(d)  # Mass Effect positions by tone (tools/dialogue/wheel.py)
        d["_help"] = d["_help"] + " Generated by tools/dialogue/make_act2.py."
        write("dialogue/%s.json" % tid, d)
    for sid, s in ACTIONS.items():
        write("actions/%s.json" % sid, s)
    write("actions/act2_plan.json", PLAN)
    write("sites/act2_cairo.json", CAIRO_SITES)

    people_path = os.path.join(ROOT, "actions", "people.json")
    with open(people_path, encoding="utf-8") as f:
        people = json.load(f)
    if "_act2" not in people:
        people["_act2"] = "Act 2: the companions and the Cairo contacts (actions/act2_plan.json)."
    for k, v in PEOPLE.items():
        people.setdefault(k, v)
    write("actions/people.json", people)
    print("act2: %d talks, %d spots, all checks passed" % (len(TALKS), len(ACTIONS)))


if __name__ == "__main__":
    main()
