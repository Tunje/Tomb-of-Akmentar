"""Companion rapport ladders (Simon's core rule: hiring is a transaction; people open up slowly,
stop by stop, as trust grows; nobody tells you "their thing" on first contact).

Each companion has four rungs, heard one per stop (a camp, a night on the road, the last night):
  0  contact and small talk                       (first time you sit with them)
  1  the work, the road, the place                (after one talk)
  2  an opinion: how they see the expedition      (after two)
  3  the personal matter                          (after three, and only with trust 2+)
The count is the companion stat "talks" (Game.check "stat" >=), each rung's flag rapport_<id>_<n>
keeps it from repeating; with nothing new they say a line and the fire crackles on. Flags the old
hiring talks set (promised_eleanor_publish, idris_contacts, ...) are set here now, on the rung where
the topic belongs; until then they keep their default (unset).

ladder_nodes(who, prefix, back) gives the nodes to embed in a stop's talk (make_act3's camp,
make_act67's night on the road back); writing this file's own output gives dialogue/camp_<id>.json,
one talk per companion for the camp ActionSpots (actions/camp.json: Act 4's fire; actions/
hotel_lobby.json: Act 7's hotel lobby; also written here). make_act89's last night gates its
personal words on the same count.

    python tools/dialogue/rapport.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dlg import L, C, B, END, flag, trust, conv, fear, pay, talk, build  # noqa: E402

COMPANIONS = ["eleanor", "pembroke", "hassan", "hargreaves", "idris", "isabelle", "saleh", "youssef", "farid",
              "mahmoud", "khalil", "naguib"]
SPEAKERS = {"eleanor": "Eleanor Whitmore", "pembroke": "Dr. Arthur Pembroke", "hassan": "Dr. Hassan al-Masri",
            "hargreaves": "Tom Hargreaves", "idris": "Idris Mahjoub", "isabelle": "Isabelle Moreau",
            "saleh": "Saleh al-Rashidi", "youssef": "Youssef Nabil", "farid": "Farid Mansour",
            "mahmoud": "Mahmoud Fawzi", "khalil": "Khalil Darwish", "naguib": "Naguib Sabet"}
TRUST_FOR_PERSONAL = 2

# who -> [rung 0, 1, 2, 3], each (their line, (label, your line, effects, reply), (label, your line, effects, reply)),
# and IDLE[who]: what they say when there's nothing new tonight.
LADDER = {
    "eleanor": [
        ("Sand in the ink, sand in the bread. I'd no idea the desert got into everything.",
         ("Laugh with her", "Wait till it's in your boots.", [trust("eleanor", 1)], "It's already in my boots."),
         ("Tell her it gets worse", "It gets worse further west.", [], "Wonderful. I'll write that down too.")),
        ("Three papyri in the museum's basement name a king who appears on no list. Someone went to a great deal of trouble to forget him.",
         ("Ask her why", "Why would anyone bother?", [flag("heard_forgotten_king"), trust("eleanor", 1)], "That's what I mean to find out."),
         ("Ask what he's worth", "Is a forgotten king worth more?", [flag("heard_forgotten_king"), trust("eleanor", -1)], "To a dealer. Not to me.")),
        ("Do you think it's really out there? Not the gold. The answers.",
         ("Say you believe it", "I know it is. And you'll be the one who reads it.", [trust("eleanor", 1)], "Then I'd better not be wrong."),
         ("Say it's a payday", "I think it's a payday. Answers are your department.", [trust("eleanor", -1), conv("eleanor", 1)], "Then I'll find them on my own.")),
        ("At the museum they let me translate and never let me sign. Whatever we find out here, I want my name on it.",
         ("Promise her", "Your name, your work. You have my word.", [flag("promised_eleanor_publish"), trust("eleanor", 1), conv("eleanor", 1)], "...Thank you. I'll hold you to that."),
         ("Make no promises", "Let's find it first, then argue about the credit.", [trust("eleanor", -1)], "That's what they all say.")),
    ],
    "pembroke": [
        ("You've packed the plates badly. The camera will survive. The plates may not.",
         ("Let him repack", "Repack them however you like, Doctor.", [trust("pembroke", 1)], "Thank you. I shall."),
         ("Tell him they're fine", "They'll be fine.", [], "That is what everyone says before they aren't.")),
        ("Forty sherds catalogued since Cairo. All Roman, all worthless, all properly labelled.",
         ("Encourage him", "Keep at it, Doctor. When we get there, it'll matter.", [trust("pembroke", 1)], "Yes. Quite. Thank you."),
         ("Mock him", "Nobody's going to care about your pots.", [trust("pembroke", -1)], "Somebody has to care, or this is just looting.")),
        ("A site is a book you can only read once. Dig it badly and the page is gone. I'd like us to read it properly.",
         ("Agree with him", "Then we read it properly.", [trust("pembroke", 1)], "Good. Then we understand each other."),
         ("Say time matters more", "We're racing two expeditions, Doctor.", [conv("pembroke", 1)], "Then we shall lose the race and keep the book.")),
        ("Wadi Natrun, 1919. Bad funding, worse records. Half the finds vanished before they were catalogued, and my name went with them.",
         ("Promise every find recorded", "Not this time. Every find goes on paper before anyone touches it.", [flag("promised_pembroke_records"), trust("pembroke", 1)], "...I believe you mean that."),
         ("Ask whose fault it was", "Was it your fault?", [trust("pembroke", -1)], "Does it matter? It had my name on it.")),
    ],
    "hassan": [
        ("The stars are very clear tonight. In Cairo you forget there are so many.",
         ("Look up with him", "I'd forgotten too.", [trust("hassan", 1)], "Then the desert is already teaching us something."),
         ("Ask if he's tired", "You should sleep, Doctor.", [], "At my age sleep is a negotiation.")),
        ("Tell me, now that we are on the road. Why Akmentar, for you?",
         ("To see what's there", "Someone tried very hard to make the world forget it. I want to know why.", [trust("hassan", 1)], "Then we share a question, if not yet an answer."),
         ("For the treasure", "There's a king's gold out there.", [trust("hassan", -1), flag("hassan_heard_greed")], "Honest, at least. Gold has buried more men than the desert.")),
        ("Do you know why the old priests called it the Veil?",
         ("Ask him to tell you", "Tell me.", [trust("hassan", 1), flag("heard_veil")], "Because some things are not gone. Only covered."),
         ("Save it for later", "Save the stories for when we get there.", [conv("hassan", 1)], "As you wish. Stories keep.")),
        ("I have waited thirty years to see that place. When I say a door should stay closed, will you listen?",
         ("Promise to listen", "I'll listen. You have my word.", [flag("promised_hassan_listen"), trust("hassan", 1)], "Then I am glad I came."),
         ("Make no promises", "I'll decide about doors when I see them.", [conv("hassan", 1)], "Then I shall have to find other ways of being heard.")),
    ],
    "hargreaves": [
        ("Boots, rifle, water. In that order. Everything else is luxury.",
         ("Agree", "Sound order.", [trust("hargreaves", 1)], "Army taught me one thing, anyway."),
         ("Ask about tea", "Where does tea come in?", [], "Before the boots, if I'm honest.")),
        ("I'd like to drill the lads on the rifles each night. An hour. They'll thank me later.",
         ("Let him drill them", "Do it.", [trust("hargreaves", 1), flag("drilled_crew")], "Right. Up, you lot. Rifles."),
         ("Let them rest", "They're exhausted, Tom. Let them sleep.", [trust("hargreaves", -1)], "Your call. I hope you don't regret it.")),
        ("If it goes bad out there, and someone's hurt and can't walk, what do you do?",
         ("Carry them", "We carry them. Nobody gets left behind.", [trust("hargreaves", 1)], "Right answer."),
         ("Leave them, if I must", "If it's them or everyone, I leave them.", [trust("hargreaves", -1), conv("hargreaves", 1)], "I've heard that before. Once.")),
        ("Mesopotamia, 1917. An officer told us to leave the wounded at a well and march. I obeyed. I hear them most nights.",
         ("Tell him it wasn't him", "That was his order, Tom. Not your choice.", [trust("hargreaves", 1)], "Kind of you. Doesn't stop the hearing."),
         ("Listen in silence", "", [trust("hargreaves", 1), conv("hargreaves", 1)], "...Thanks for not saying anything.")),
    ],
    "idris": [
        ("You clean a rifle like a soldier. Too much oil.",
         ("Ask how he does it", "Show me, then.", [trust("idris", 1)], "Less. Always less. The sand loves oil."),
         ("Tell him it works", "It hasn't failed me yet.", [], "Yet. That word does a lot of work.")),
        ("Every thief in Cairo sells to someone, and I know most of the someones. If something valuable leaves that city, I can usually find out how.",
         ("Remember it", "I'll remember that.", [flag("idris_contacts"), trust("idris", 1)], "Good. I hope you never need to."),
         ("Ask how he knows", "How does an honest man know thieves?", [flag("idris_contacts")], "He guards their customers.")),
        ("The merchants I guard never ask my name. You ask. It is strange.",
         ("Say it should be normal", "It should be the least anyone does.", [trust("idris", 1)], "It should. It is not."),
         ("Keep him on the job", "Keep your mind on the job, Idris.", [trust("idris", -1)], "My mind is always on the job. That is why I am alive.")),
        ("My sisters are in Omdurman. Everything I earn goes home. One of them has a place at the school now.",
         ("Send them something", "Send them this from me. For the school.", [pay(200), flag("idris_paid_well"), trust("idris", 2)], "You are a strange kind of employer. A good kind."),
         ("Be glad for him", "Good. That's the best thing this money will do.", [trust("idris", 1)], "Yes. It is.")),
    ],
    "isabelle": [
        ("You keep watching me as if I'm about to ride off.",
         ("Tell her you're glad", "I'm just glad you're here.", [trust("isabelle", 1)], "Careful. That almost sounded sincere."),
         ("Ask if she would", "Would you?", [conv("isabelle", 1)], "Maybe. Keep giving me reasons not to.")),
        ("In a fight I pick my own ground. Don't send me where you'd stand; send me where I can see.",
         ("Agree", "Your ground, your call.", [flag("promised_isabelle_free"), trust("isabelle", 1)], "Then we'll get along."),
         ("Say you give the orders", "Out there you go where I say.", [trust("isabelle", -1)], "We'll see who does what, monsieur.")),
        ("Hargreaves thinks I take too many risks. Hargreaves has never been paid by the head.",
         ("Ask about bounty work", "Is that what you did?", [trust("isabelle", 1)], "Did. Do. Depends who's asking."),
         ("Change the subject", "Let's talk about tomorrow.", [], "Tomorrow, then. Always tomorrow.")),
        ("Those men in McKenna's said I owed someone a shipment. I didn't. My partner did, and he left me holding the bill.",
         ("Say you believe her", "I believe you.", [trust("isabelle", 1)], "...You might be the first."),
         ("Ask where he is now", "Where's your partner now?", [conv("isabelle", 1)], "Somewhere he hopes I'll never look.")),
    ],
    "saleh": [
        ("Drink before you are thirsty. Thirst is the desert telling you it is already too late.",
         ("Drink", "Then I'll drink.", [trust("saleh", 1)], "Good. Small sips. You are learning."),
         ("Say you're fine", "I'm not thirsty.", [], "That is what the dead say.")),
        ("We are drinking more water than I planned. Tomorrow, half rations.",
         ("Agree", "Half rations. Make sure everyone knows why.", [trust("saleh", 1), flag("rationing")], "Good. The desert respects a careful man."),
         ("Overrule him", "We'll manage. People need their strength.", [trust("saleh", -1)], "We will see who manages.")),
        ("The others race. I do not like a race. When I say stop, will you stop?",
         ("Promise to listen", "When you say stop, we stop.", [flag("promised_saleh_listen"), trust("saleh", 1)], "Then we will all come home."),
         ("Say it depends", "Depends who's ahead of us.", [trust("saleh", -1)], "The desert does not care who is ahead.")),
        ("I know three men who did not come back from this road. I led them. I have brought people home for forty years, and I remember the three.",
         ("Ask their names", "Tell me their names.", [trust("saleh", 1), conv("saleh", 1)], "...Hamid, Rashad, and my brother Ali."),
         ("Tell him not this time", "Not this time. Not with you leading.", [trust("saleh", 1)], "Inshallah.")),
    ],
    "youssef": [
        ("Did you see the hawk this morning? Following us since dawn. It is good luck. Probably.",
         ("Say you saw it", "I saw it.", [trust("youssef", 1)], "You see? Good luck!"),
         ("Ask about bad luck", "And what's bad luck?", [], "Vultures. Let us not talk about vultures.")),
        ("Let me scout ahead tomorrow, alone. I will find us a faster way.",
         ("Let him go", "Go. Back by noon.", [trust("youssef", 1), conv("youssef", 1)], "By noon! You will see."),
         ("Keep him close", "You stay with the column.", [trust("youssef", -1)], "As you say. But I would have found it.")),
        ("I have not been this far west before. Not truly. Saleh knows. He has not told anyone.",
         ("Say you'd guessed", "I'd guessed. You're doing fine.", [trust("youssef", 1)], "You guessed? ...Thank you for not saying."),
         ("Ask why he lied", "Why say you had?", [trust("youssef", -1)], "Because nobody hires a boy who has not.")),
        ("When we find it, will you tell them? That I am the one who found the road? My uncle says I will never be anything.",
         ("Promise him the credit", "If you find it, the road is yours. I'll tell them.", [flag("promised_youssef_credit"), trust("youssef", 1), conv("youssef", 1)], "Then I will find it!"),
         ("Credit goes to whoever earns", "Credit goes to whoever earns it.", [], "Then I will earn it.")),
    ],
    "farid": [
        ("Dates from Siwa. The best. Take one. No charge. This time.",
         ("Take one", "Thank you.", [trust("farid", 1)], "You see? Business begins with a gift."),
         ("Ask the catch", "What's the catch?", [], "No catch. A small debt of gratitude, only.")),
        ("There is a trader near here who owes me. Let me do a little business on the way.",
         ("Let him trade", "Go ahead. Just don't slow us down.", [trust("farid", 1), conv("farid", 1)], "You will not even notice I was gone."),
         ("No side deals", "No side deals, Farid. Not on my time.", [trust("farid", -1)], "Business never sleeps. But it can wait.")),
        ("Everyone in this caravan is counting something. Saleh counts water, Naguib counts camels. I count everything, so nobody has to worry.",
         ("Thank him", "I'm glad someone does.", [trust("farid", 1)], "At last, a man who appreciates arithmetic."),
         ("Ask what he counts", "And what do you count about me?", [], "Your money. Kindly.")),
        ("My father had a caravan of forty camels. He lost them all in one season, to one bad road. I have never once taken a road I had not counted twice.",
         ("Say he's done well", "You've done better than forty camels.", [trust("farid", 1)], "Twelve towns. He would have laughed. Then cried."),
         ("Ask if he's afraid", "Is this road counted twice?", [conv("farid", 1)], "This one I could not count at all. And I came.")),
    ],
    "mahmoud": [
        ("My men sing when they dig. If they stop singing, look up. Something is wrong.",
         ("Ask what they sing", "What do they sing?", [trust("mahmoud", 1)], "Old songs. About water, mostly."),
         ("Say you'll listen for it", "I'll listen.", [], "Good.")),
        ("The sand here is soft on top and hard under. We will need shoring before we go deep.",
         ("Trust his judgement", "Shore it however you think best.", [trust("mahmoud", 1)], "Then nobody will be buried."),
         ("Ask how long", "How long will that take us?", [], "Longer than you want. Shorter than a funeral.")),
        ("My men ask: when we dig, whose name goes on the finds?",
         ("Theirs", "The men who dig them up. The record says who found it.", [trust("mahmoud", 1), flag("promised_mahmoud_credit")], "I will tell them. They will dig twice as carefully."),
         ("The expedition's", "The expedition's. That's how it works.", [trust("mahmoud", -1)], "That is how it always works.")),
        ("My men have dug for the British, the French and the Americans. Every one of them took the credit. My father dug at Karnak. His name is on nothing.",
         ("Say that ends here", "Not on this dig.", [trust("mahmoud", 1)], "We will see. But thank you."),
         ("Ask his father's name", "What was his name?", [trust("mahmoud", 1), conv("mahmoud", 1)], "Fawzi. Like mine. Write it somewhere, if you like.")),
    ],
    "khalil": [
        ("The men want to know if there is meat tomorrow. I said yes. Is there meat tomorrow?",
         ("Say yes", "There's meat tomorrow.", [trust("khalil", 1)], "Good. Then I did not lie."),
         ("Say ask Farid", "Ask Farid.", [], "Farid will want money for the meat.")),
        ("Two of my men are sick from the water.",
         ("Give them your share", "Give them clean water from my ration.", [trust("khalil", 2), fear("khalil", -1)], "They will not forget this. Neither will I."),
         ("They'll toughen up", "They're grown men. They'll toughen up.", [trust("khalil", -2)], "They are men, not mules.")),
        ("My men are dockworkers without docks. They carry. Nobody thinks they can do anything else.",
         ("Say they're more than that", "They've done more than carry on this trip.", [trust("khalil", 1)], "I will tell them you said so."),
         ("Say carrying matters", "Somebody has to carry.", [], "Somebody always does.")),
        ("Half my men have been cheated before. A Frenchman left them in Luxor without a piastre. That is why they ask about pay.",
         ("Promise they'll be paid", "Every man gets paid. In full.", [trust("khalil", 1)], "Then they will follow you down any hole."),
         ("Ask about the Frenchman", "What happened to him?", [conv("khalil", 1)], "Nothing. That is what happens to such men.")),
    ],
    "naguib": [
        ("A good camel is worth three bad men. Do not tell the men.",
         ("Laugh", "Your secret's safe.", [trust("naguib", 1)], "Good. They would be offended."),
         ("Ask which is best", "Which camel is best?", [], "The one that does not bite you. Today.")),
        ("The camels are carrying too much. Lighten the loads, or we lose one by the end of the week.",
         ("Lighten the loads", "Do it. Leave the spare crates.", [trust("naguib", 1), flag("promised_naguib_loads")], "A wise choice. The camels thank you."),
         ("Push on", "We need everything. Push on.", [trust("naguib", -1)], "Then pray for cool nights.")),
        ("Every load has a place, and every place has a load. When something is out of place, I cannot sleep.",
         ("Say it shows", "It shows. The column runs well.", [trust("naguib", 1)], "It runs. Well is for God to say."),
         ("Tease him", "Must be a long night, then.", [], "Every night is a long night.")),
        ("I always pack for the way out. In the war, a column I carried for did not plan to come back. I did. Alone.",
         ("Say he packs well", "Then pack for all of us.", [trust("naguib", 1)], "I already have."),
         ("Ask what happened", "What happened to them?", [conv("naguib", 1)], "They believed in going forward. Only forward.")),
    ],
}
IDLE = {
    "eleanor": "Nothing much. Just thinking. Go on, I'm fine.",
    "pembroke": "I am cataloguing. Perhaps later.",
    "hassan": "Sit if you like. The fire is good company.",
    "hargreaves": "All quiet. Get some sleep.",
    "idris": "Nothing to report. Sleep; I will watch.",
    "isabelle": "Not tonight. I'm counting cartridges.",
    "saleh": "Drink some water. Then sleep.",
    "youssef": "Tomorrow I will find us a shortcut. You will see.",
    "farid": "Everything is counted. Good night.",
    "mahmoud": "My men are asleep. I should be too.",
    "khalil": "The men are well. Thank you for asking.",
    "naguib": "Loads are fine. Camels are fine. I am fine.",
}


def ladder_nodes(who, p, back):
    """The rung for `who` tonight, as nodes named p + "...", ending at node `back`."""
    rungs = LADDER[who]
    heard = ["rapport_%s_%d" % (who, n) for n in range(4)]
    nodes = {
        p + "start": B(({"stat": [who, "talks", 3], "not_flag": heard[3]}, p + "t3"),
                       ({"stat": [who, "talks", 2], "not_flag": heard[2]}, p + "r2"),
                       ({"stat": [who, "talks", 1], "not_flag": heard[1]}, p + "r1"),
                       ({"not_flag": heard[0]}, p + "r0"),
                       (None, p + "idle")),
        p + "t3": B(({"stat": [who, "trust", TRUST_FOR_PERSONAL]}, p + "r3"), (None, p + "idle")),
        p + "idle": L(who, IDLE[who], back),
    }
    for n, (line, a, b) in enumerate(rungs):
        step = [{"stat": [who, "talks", 1]}, flag(heard[n])]
        choices = []
        for k, (label, said, fx, reply) in enumerate((a, b)):
            nid = "%sr%d_%s" % (p, n, "ab"[k])
            cond = None
            for e in fx:  # a choice that costs money needs the money
                if "money" in e and e["money"] < 0:
                    cond = {"money": -e["money"]}
            choices.append(C(label, said, nid, if_=cond, do=fx + step))
            nodes[nid] = L(who, reply, back)
        if any(c.get("if") for c in choices):  # never a dead end: the free choice is always there
            assert not all(c.get("if") for c in choices), who
        nodes[p + "r%d" % n] = L(who, line, choices=choices)
    return nodes


def camp_talk(who):
    nodes = ladder_nodes(who, "", "end")
    nodes["end"] = END
    return talk("Camp talk with %s (camp ActionSpot, actions/camp.json): the next rung of their rapport ladder (tools/dialogue/rapport.py): "
                "contact, the work, an opinion, then with trust %d the personal matter; one rung a talk (stat talks, rapport_%s_<n>)."
                % (SPEAKERS[who].split(" ")[0], TRUST_FOR_PERSONAL, who), {who: SPEAKERS[who]}, nodes)


def camp_actions(name="Expedition camp", prompt="Sit with the expedition", where="Travel-stop actions"):
    return {
        "_help": where + ": a talk with each companion in the party, once a day, free (no action spent). Each is the next rung of their rapport ladder. Generated by tools/dialogue/rapport.py.",
        "name": name,
        "prompt": prompt,
        "empty": "Nobody wants to talk right now.",
        "actions": [{"id": "talk_" + w, "label": "Talk with " + SPEAKERS[w].split(" ")[0 if not SPEAKERS[w].startswith("Dr.") else 2],
                     "cost": 0, "daily": True, "if": {"in_party": w}, "hide_if_locked": True,
                     "conversation": "camp_" + w, "with": w, "log": "Talked with %s by the fire" % SPEAKERS[w].split(" ")[0 if not SPEAKERS[w].startswith("Dr.") else 2]}
                    for w in COMPANIONS],
    }


if __name__ == "__main__":
    build("rapport.py", {"camp_" + w: camp_talk(w) for w in COMPANIONS},
          {"actions/camp.json": camp_actions(),
           "actions/hotel_lobby.json": camp_actions("The hotel lobby", "Sit with the expedition", "Act 7's hotel lobby (Cairo again)")})
