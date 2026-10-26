"""Writes the Act 1 (a bad day in Cairo) data: dialogue/act1_*.json, the fragment's journal clue
(sites/act1_cairo.json) and the flow notes (actions/act1_plan.json), checked like
Conversation.validate.

    python tools/dialogue/make_act1.py

Edit here, not in the JSON. Design: gameplan/primaryact.md (Act 1), gameplan/character.md (Freddie
Mallory, Harold Finch, Musa Kamal, Karim Fahmy). Encounter A (the debt collectors) can be talked
out of, paid off or fought (the brawl tutorial); encounter B (armed men at the meeting) can be
talked down or fought (the gun tutorial; act1_gunfight_won)."""

import os
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dlg import L, C, B, END, flag, trust, pay, talk, build

START_MONEY = 25
TALKS = {}
FILES = {}

# ---------------------------------------------------------------- Freddie's office

TALKS["act1_office"] = talk(
    "Act 1, Freddie Mallory's office: he's gone, leaving debts. Searching his desk finds his note (freddie_note: he went to Alexandria), which you can use or keep (Act 7: Freddie as an informant).",
    {"landlady": "Umm Sayed", "freddie": "Freddie's note"}, {
        "start": L("landlady", "Mr. Mallory? Gone. Three days ago, in the night, with two suitcases and four months of my rent.", "menu",
                   do=[flag("freddie_gone")]),
        "menu": L("landlady", "And you are? Another one he owes?", choices=[
            C("Say he owes you", "He owes me for a job. A big one.", "owes", if_={"not_flag": "office_owes"}, do=[flag("office_owes")]),
            C("Search his desk", "Mind if I look around?", "search", if_={"not_flag": "freddie_note"}),
            C("Ask who else came", "Has anyone else come asking for him?", "others", if_={"not_flag": "office_others"}, do=[flag("office_others")]),
            C("Leave", "Thank you. I'll find him.", "bye"),
        ]),
        "owes": L("landlady", "Him owe you? Then get in line, effendi. The line goes down the stairs.", "menu"),
        "search": L("freddie", "'Gone to Alex till it blows over. Don't tell Finch. Sorry, old man. F.'", "menu",
                    do=[flag("freddie_note"), {"journal": ["act1_cairo", "note", "Freddie's desk"]}]),
        "others": L("landlady", "Mr. Finch, the moneylender, and his big one, Musa. Every day. They will be back. Probably they are on the stairs now.", "menu",
                    do=[flag("warned_finch")]),
        "bye": L("landlady", "If you find him, tell him the rent is still four months.", "end"),
        "end": END,
    })


# ---------------------------------------------------------------- encounter A: the debt collectors

TALKS["act1_debt_collectors"] = talk(
    "Act 1, encounter A: Harold Finch and his enforcer Musa Kamal think you know where Freddie is. Talk your way out (owe_finch, or freddie_betrayed with the note), pay part (debt_paid_part, 20), or provoke a fight: event fight_debt_collectors (end_fight; the brawl tutorial), after which act1_after_brawl. End ids end_talked / end_paid / end_fight.",
    {"finch": "Harold Finch", "musa": "Musa Kamal"}, {
        "start": L("finch", "There he is. Freddie Mallory's old army pal. Freddie owes me two hundred pounds, and I think you know where he is.", "menu"),
        "menu": L("finch", "So. Where is he?", choices=[
            C("Say you don't know", "I don't know. He owes me money too.", "dont_know", if_={"not_flag": "finch_dont_know"}, do=[flag("finch_dont_know")]),
            C("Give up Freddie", "Alexandria. He left a note.", "betray", if_={"flag": "freddie_note"}),
            C("Promise to pay", "I'll have work soon. I'll pay you part of his debt from it.", "promise"),
            C("Pay part now", "Here's twenty pounds. Call it interest. Now leave me alone.", "paid", if_={"money": 20}, do=[pay(20), flag("debt_paid_part")]),
            C("Insult him", "Get out of my way, Finch, before your bruiser needs a doctor.", "provoke"),
            C("Hit him", "", "fight"),
        ]),
        "dont_know": L("finch", "Then you're no use to me. Unless you'd like to pay his debts, being such good friends.", "menu"),
        "betray": L("finch", "Alexandria. There, that wasn't hard. Come on, Musa. We've a train to catch.", "end_talked",
                    do=[flag("freddie_betrayed")]),
        "promise": L("finch", "Part of it. From work you don't have. All right, soldier, I'll hold you to that. Fifty pounds within the month.", "end_talked",
                     do=[flag("owe_finch", 50)]),
        "paid": L("finch", "Twenty. Well, it's a start. We'll be seeing you.", "end_paid"),
        "provoke": L("musa", "Mr. Finch, may I?", "fight"),
        "fight": L("finch", "Musa. Teach him some manners.", "end_fight", do=[{"event": "fight_debt_collectors"}]),
        "end_talked": END,
        "end_paid": END,
        "end_fight": END,
    })

TALKS["act1_after_brawl"] = talk(
    "Act 1, after the brawl. If you won: Musa is down; help him up (musa_respect; in encounter B he won't fight you) or humiliate him (musa_enemy). If you lost (act1.gd sets brawl_lost): they take 10 and leave.",
    {"finch": "Harold Finch", "musa": "Musa Kamal"}, {
        "start": B(({"flag": "brawl_lost"}, "lost"), (None, "won")),
        "lost": L("finch", "That's for the inconvenience. Ten pounds. Freddie's debt stands.", "end", do=[pay(10)]),
        "won": L("musa", "...", choices=[
            C("Help him up", "Here. Up you get. Nothing personal.", "respect", do=[flag("musa_respect"), trust("musa", 2)]),
            C("Humiliate him", "Stay down. Next time I won't be gentle.", "enemy", do=[flag("musa_enemy"), trust("musa", -2)]),
        ]),
        "respect": L("musa", "Not personal. No. I remember this.", "finch_leaves"),
        "enemy": L("musa", "I also remember this.", "finch_leaves"),
        "finch_leaves": L("finch", "This isn't over, soldier. Freddie's debt doesn't go away because you can throw a punch.", "end"),
        "end": END,
    })


# ---------------------------------------------------------------- encounter B and the offer

offer = {
    "start": B(({"flag": "act1_confrontation_done"}, "resume"), (None, "intro")),
    "intro": L("karim", "Karim Fahmy. I represent Sir Reginald Blackwood. He has heard you are a man who keeps expeditions alive. Please, sit.", "case"),
    "case": L("karim", "In this case is the reason I asked for you. But first...", "armed"),
    "armed": L("gunman", "Nobody move. The case, effendi. Slide it over, and nobody has to bleed on the tablecloth.", "standoff"),
    "standoff": B(({"flag": "musa_respect"}, "musa_there"), (None, "talk_down")),
    "musa_there": L("musa", "Wait. This one... this one helped me stand up. I do not shoot him.", "musa_leaves"),
    "musa_leaves": L("gunman", "Musa! Idiot! ...Fine. Fine! This isn't finished, Fahmy.", "avoided"),
    "talk_down": L("player", "Three of them. Pistols out. The leader's hand isn't steady.", choices=[
        C("Talk him down", "You don't want this. Look around: one shot and every policeman in Cairo comes running. Walk away.", "talk_try"),
        C("Offer him money", "Twenty pounds to forget you ever saw this case.", "bribe", if_={"money": 20}, do=[pay(20)]),
        C("Draw", "", "draw"),
    ]),
    "talk_try": B(({"flag": "warned_finch"}, "talk_works"), (None, "talk_fails")),
    "talk_works": L("gunman", "...Police. Right. You're Finch's problem anyway, not mine. Let's go.", "avoided"),
    "talk_fails": L("gunman", "Nice speech. The case. Now.", choices=[
        C("Draw", "", "draw"),
        C("Offer him money", "All right, all right. Twenty pounds, and you walk.", "bribe", if_={"money": 20}, do=[pay(20)]),
    ]),
    "bribe": L("gunman", "Twenty, and the case stays. Generous man. Enjoy your lunch.", "avoided", do=[trust("karim", -1)]),
    "draw": L("gunman", "Kill him!", "end_fight", do=[{"event": "fight_armed_men"}]),
    "avoided": L("karim", "...Well. Mr. Blackwood was right about you.", "offer", do=[flag("act1_confrontation_done"), flag("act1_gunfight_avoided")]),
    "resume": L("karim", "My hands are still shaking. Mr. Blackwood was right about you. Now, the case.", "offer"),
    "offer": L("karim", "A fragment of an inscription, and part of a map. Sir Reginald believes they lead to the tombs of Akmentar. He wants you to lead the expedition.", "menu",
               do=[{"journal": ["act1_cairo", "fragment", "Karim Fahmy's case"]}]),
    "menu": L("karim", "Fifty pounds now, for your... present difficulties. A great deal more if the tombs are found.", choices=[
        C("Ask about the first expedition", "This isn't Blackwood's first try, is it?", "first", if_={"not_flag": "karim_first"}, do=[flag("karim_first")]),
        C("Ask about the reward", "How much is a great deal?", "reward", if_={"not_flag": "karim_reward"}, do=[flag("karim_reward")]),
        C("Ask for more up front", "Fifty doesn't cover the men who just pointed guns at me.", "more",
          if_={"not_flag": "karim_more"}, do=[flag("karim_more"), trust("karim", -1)]),
        C("Accept", "All right. I'll take your expedition.", "accept"),
        C("Refuse", "Find another fool.", "refuse", if_={"not_flag": "karim_refused"}, do=[flag("karim_refused")]),
    ]),
    "first": L("karim", "There was an earlier expedition. It did not return. What happened to it is Sir Reginald's affair, and he does not discuss it.", "menu",
               do=[flag("knows_first_expedition_lost")]),
    "reward": L("karim", "Five thousand pounds when the tombs are found and documented. Enough to make Mr. Mallory's debts look very small.", "menu"),
    "more": L("karim", "...Seventy-five, then. And Sir Reginald will hear that you drive a hard bargain.", "menu", do=[{"money": 25}]),
    "refuse": L("karim", "Then consider this: the men who came for this case today will not stop at me. They know your face now.", "menu"),
    "accept": L("karim", "Excellent. The expedition fund will be at the bank in the morning. You leave Cairo in two days, ready or not.", "debts",
                do=[{"money": 50}, flag("act1_offer_accepted")]),
    "debts": B(({"flag": "owe_finch", "money": 50}, "pay_finch"), (None, "end_accepted")),
    "pay_finch": L("player", "Fifty pounds in my pocket, and Finch wants fifty.", choices=[
        C("Pay Finch off", "Might as well start the job with a clean slate.", "end_accepted", do=[pay(50), flag("owe_finch", 0), flag("finch_paid")]),
        C("Keep the money", "Finch can wait.", "end_accepted"),
    ]),
    "end_fight": END,
    "end_accepted": END,
}
TALKS["act1_offer"] = talk(
    "Act 1, the offer, with encounter B: Karim Fahmy meets you; armed men burst in for his case. With musa_respect, Musa is one of them and won't shoot; talking them down works if Umm Sayed warned you about Finch (warned_finch: you know the police watch him); 20 buys them off; drawing: event fight_armed_men (end_fight). When act1.gd wins that fight it sets act1_gunfight_won and act1_confrontation_done and starts this talk again, which resumes at the offer. Accepting: +50 (75 if you pushed), act1_offer_accepted, the fragment's journal clue (end_accepted). Then Act 2.",
    {"karim": "Karim Fahmy", "gunman": "Hired gunman", "musa": "Musa Kamal"}, offer)


# ---------------------------------------------------------------- plan and clues

FILES["sites/act1_cairo.json"] = {
    "_help": "Act 1: journal clues in Cairo (written by the act1 talks). Generated by tools/dialogue/make_act1.py.",
    "place": "Cairo",
    "sites": {
        "note": {"name": "Freddie Mallory's Desk", "desc": "A note under the blotter",
                 "clue": {"id": "clue_freddie_note", "title": "Freddie's note",
                          "text": "'Gone to Alex till it blows over. Don't tell Finch. Sorry, old man. F.' Freddie owes you for the last job, and he owes half of Cairo besides."}},
        "fragment": {"name": "Karim Fahmy's Case", "desc": "A limestone fragment and a torn map",
                     "clue": {"id": "clue_fragment", "title": "The Blackwood fragment",
                              "text": "A limestone fragment: '...Akmentar, where the three keep the door and the eye keeps the veil...' With it, a torn map with a river, a line of wells, and nothing beyond. Sir Reginald Blackwood has already lost one expedition to it."}},
    },
}

FILES["actions/act1_plan.json"] = {
    "_help": "Act 1 (a bad day in Cairo) flow for act1.gd. Generated by tools/dialogue/make_act1.py. Not an ActionSpot file.",
    "start": [{"money": START_MONEY}],
    "scenes": [
        "arrival: you step off the train / riverboat with a suitcase, a revolver and little money",
        "act1_office: Umm Sayed at Freddie's office (freddie_gone; freddie_note; warned_finch)",
        "act1_debt_collectors: on the stairs or in the street; end_fight -> event fight_debt_collectors (brawl, maybe a chase through the market) -> act1_after_brawl (set brawl_lost first if you lost)",
        "act1_offer: Karim Fahmy at a cafe; armed men; end_fight -> event fight_armed_men (the gunfight; on a win set act1_gunfight_won + act1_confrontation_done and start act1_offer again)",
        "end_accepted -> Act 2 (actions/act2_plan.json adds the expedition fund)",
    ],
    "events": {"fight_debt_collectors": "Finch's men: Musa Kamal and one or two more, fists only",
               "fight_armed_men": "three hired gunmen after Karim's case: pistols, cover, reloading"},
    "flags_for_later": ["act1_gunfight_won (Isabelle's proof in Act 2)", "act1_gunfight_avoided", "musa_respect", "musa_enemy",
                        "freddie_note", "freddie_betrayed", "owe_finch", "finch_paid", "debt_paid_part",
                        "knows_first_expedition_lost", "act1_offer_accepted"],
}

PEOPLE = {"landlady": "Umm Sayed", "finch": "Harold Finch", "musa": "Musa Kamal", "freddie": "Freddie Mallory"}


if __name__ == "__main__":
    import json
    from dlg import ROOT, write
    build("make_act1.py", TALKS, FILES, {"act1_cairo": FILES["sites/act1_cairo.json"]})
    people_path = os.path.join(ROOT, "actions", "people.json")
    with open(people_path, encoding="utf-8") as f:
        people = json.load(f)
    people.setdefault("_act1", "Act 1: Freddie's office, the debt collectors (actions/act1_plan.json).")
    for k, v in PEOPLE.items():
        people.setdefault(k, v)
    write("actions/people.json", people)
