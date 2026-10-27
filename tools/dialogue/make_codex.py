"""Writes codex/people.json: the journal's People pages (scripts/sites/codex.gd). One page per
person, unlocked the first time they speak to you in a conversation (Codex.meet, from
Conversation) or when their "met_if" condition passes; written as the player knows them
(gameplan/character.md), with notes added as key flags come true (Hassan's secret only after
hassan_revealed, and so on).

    python tools/dialogue/make_codex.py

Entry: id: (name, role, text, [(condition, note), ...], met_if or None)."""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONDS = {"flag", "not_flag", "money", "actions", "stat", "in_party", "day"}


def T(who, n):
    return {"stat": [who, "trust", n]}


P = {
    # ---- the expedition
    "eleanor": ("Eleanor Whitmore", "Egyptologist, Cairo Museum",
                "A young scholar the museum treats as an assistant. Reads ancient languages better than anyone in the building, and badly wants to be taken seriously.",
                [({"flag": "promised_eleanor_publish"}, "You promised her the publication, under her own name."),
                 ({"flag": "hired_eleanor"}, "She came with the expedition."),
                 (T("eleanor", 3), "She trusts you now, and says what she thinks.")], None),
    "pembroke": ("Dr. Arthur Pembroke", "Archaeologist, Cairo Museum",
                 "Methodical and proud. His last expedition, at Wadi Natrun in 1919, went badly and took his name with it.",
                 [({"flag": "promised_pembroke_records"}, "You agreed: every find recorded before anyone touches it."),
                  ({"flag": "hired_pembroke"}, "He came with the expedition.")], None),
    "hassan": ("Dr. Hassan al-Masri", "Independent scholar",
               "Dismissed by the museum for insisting that whole dynasties were struck from the record. Has spent his life on Akmentar.",
               [({"flag": "hired_hassan"}, "He came with the expedition, on one condition: that you listen when he says a door should stay closed."),
                ({"flag": "hassan_caught"}, "At the temple he tried to steer you away from what was written there."),
                ({"flag": "hassan_revealed"}, "He is one of the Keepers of the Veil. He ordered the attacks on the expedition, to keep anyone from the tomb.")], None),
    "hargreaves": ("Tom Hargreaves", "Former sergeant",
                   "An old army acquaintance, taking security contracts since he left. Once obeyed an order that left men behind, and won't again.",
                   [({"flag": "hired_hargreaves"}, "He came with the expedition."), ({"flag": "hargreaves_rearguard"}, "He held the rear on the last day, as he said he would.")], None),
    "idris": ("Idris Mahjoub", "Merchant escort",
              "A Sudanese gunman who guards merchants on the road south. Knows half of Cairo's thieves. His pay goes home to his sisters in Omdurman.",
              [({"flag": "hired_idris"}, "He came with the expedition."), ({"flag": "idris_underpaid"}, "You paid him less than he asked. He remembers.")], None),
    "isabelle": ("Isabelle Moreau", "Bounty hunter",
                 "A French gunwoman with a reputation and no patience. Wouldn't follow you until you'd proved yourself.",
                 [({"flag": "hired_isabelle"}, "She came with the expedition, on her own terms."), (T("isabelle", 3), "She stays now because she wants to.")], None),
    "saleh": ("Saleh al-Rashidi", "Veteran caravan guide",
              "Forty years of desert roads, and his travellers come home. Expensive, careful, and not to be hurried.",
              [({"flag": "hired_saleh"}, "He came with the expedition.")], None),
    "youssef": ("Youssef Nabil", "Desert scout",
                "Young, fast, cheap and sure he will be the man who finds the road to Akmentar.",
                [({"flag": "promised_youssef_credit"}, "You promised him the credit for the road."), ({"flag": "shortcut_taken"}, "He took the expedition down his shortcut.")], None),
    "farid": ("Farid Mansour", "Caravan merchant",
              "Moves goods between Cairo and a dozen towns that aren't on the map. Treats everything as a transaction, nearly.",
              [({"flag": "farid_trading"}, "He trades as the expedition goes.")], None),
    "mahmoud": ("Mahmoud Fawzi", "Excavation foreman",
                "His crew has dug for the British, the French and the Americans, and every one of them took the credit.",
                [({"flag": "promised_mahmoud_credit"}, "You promised his men their names on the finds.")], None),
    "khalil": ("Khalil Darwish", "Labourers' foreman",
               "A former dockworker who keeps his men in honest work. Half of them have been cheated before.",
               [({"flag": "owe_khalil"}, "You still owe his crew half their pay.")], None),
    "naguib": ("Naguib Sabet", "Porters' foreman",
               "Porters, camels, tents and cooks. Always packs for the way out.", [], None),
    # ---- Cairo
    "karim": ("Karim Fahmy", "Sir Reginald Blackwood's agent",
              "Efficient and careful. Made you the offer at the café and keeps the expedition's money at the bank.",
              [({"flag": "karim_pressed"}, "He won't talk about Blackwood's first expedition."),
               ({"flag": "heard_blackwood_silence"}, "Pressed, he admitted it: they stopped answering, and Blackwood sent no one after them.")], None),
    "blackwood": ("Sir Reginald Blackwood", "The expedition's sponsor",
                  "A rich industrialist and collector who lost an expedition to Akmentar before yours.",
                  [({"flag": "blackwood_confessed"}, "He confessed: Ashby came back alone, raving about a man in bronze bands, and Blackwood buried the report."),
                   ({"flag": "blackwood_refused"}, "He wanted the amulet for his collection. You refused him.")],
                  {"flag": "knows_first_expedition_lost"}),
    "freddie": ("Freddie Mallory", "Your missing associate",
                "An old army friend who owes you for the last job, and half of Cairo besides. Gone, in the night.",
                [({"flag": "freddie_note"}, "His note said he'd gone to Alexandria until it blows over."),
                 ({"flag": "freddie_betrayed"}, "You gave him away."), ({"flag": "freddie_helped"}, "He came back, and paid part of what he owes in information.")], None),
    "landlady": ("Umm Sayed", "Freddie's landlady", "Owed four months' rent, and not shy about it.", [], None),
    "finch": ("Harold Finch", "Moneylender",
              "Freddie owes him two thousand pounds, and he thinks you know where Freddie is.",
              [({"flag": "owe_finch"}, "You owe him fifty within the month."), ({"flag": "finch_paid"}, "You paid him off.")], None),
    "musa": ("Musa Kamal", "Finch's enforcer",
             "Big, quiet, and doing unpleasant work because it pays.",
             [({"flag": "musa_respect"}, "You helped him up after the fight. He hasn't forgotten."), ({"flag": "musa_enemy"}, "You humiliated him. He hasn't forgotten.")], None),
    "archivist": ("Professor Mustafa El-Gohary", "Chief archivist, Cairo Museum",
                  "Irritable, brilliant, and certain that Akmentar is a camel drivers' story.",
                  [({"flag": "archivist_hostile"}, "You threatened him. You're not welcome in the museum."),
                   ({"flag": "lockdown"}, "He signed Hassan's ban on every antiquities export.")], None),
    "yacoub": ("Yacoub Ben-Ami", "Antiquities dealer", "Sells the legitimate and the less so from an office in the old quarter. Introduced you to Hassan.", [], None),
    "mckenna": ("George McKenna", "Tavern owner", "A former soldier who runs a bar for adventurers and hears everything.", [], None),
    "abdel": ("Abdel Rahman", "Caravanserai manager", "If it crosses the desert, it passes through his gate.", [], None),
    "fatima": ("Fatima el-Sayed", "Labour broker", "Places good workers with good employers, and remembers the bad ones.", [], None),
    "nabil": ("Nabil Sayegh", "Telegraph operator", "Discreet, mostly.", [({"flag": "nabil_asked"}, "He reads the wires he sends, for people he trusts.")], None),
    "clara": ("Clara Beaumont", "Hotel proprietor", "Doesn't gossip about her guests. Talks about the weather, which is crowded.",
              [({"flag": "clara_watching"}, "She keeps an eye on the rival expeditions for you.")], None),
    "hamdi": ("Captain Yusuf Hamdi", "Riverboat captain", "Runs a steamer upriver and looks after his crew first.", [], None),
    "fletcher": ("Captain Danny Fletcher", "Pilot", "An old friend in Alexandria with a crate that flies. Unreliable with money, very reliable in the air.",
                 [({"flag": "fletcher_delay"}, "He wrecked the thieves' booking for you."), ({"flag": "plane_companion"}, "He flew you back to Akmentar.")],
                 {"flag": "fletcher_wired"}),
    "salim": ("Salim Farouk", "Bazaar informant", "A former smuggler who sells information now. Mostly reliable.", [], None),
    "khalaf": ("Inspector Ibrahim Khalaf", "Cairo police", "Suspicious of foreigners with crates, and right to be.", [({"flag": "police_help"}, "He'll send men when you find the thieves.")], None),
    "watkins": ("Henry Watkins", "Stationmaster", "Keeps meticulous records of who leaves Cairo by train.", [], None),
    # ---- the road
    "rashid": ("Rashid Amin", "Elder of the desert town", "Keeps the peace in a town strangers have been asking about.", [], None),
    "mariam": ("Mariam Amin", "Merchant", "Sells water and flour at prices she swears are fair.", [], None),
    # ---- the rivals
    "whitfield": ("Charlie Whitfield", "Leader, the American expedition",
                  "A loud, generous American who treats Akmentar as a race, and bets on it.",
                  [({"flag": "wager_accepted"}, "You took his five-hundred-dollar wager."),
                   ({"flag": "thieves_americans"}, "His people took the jars and the amulet."),
                   ({"flag": "recovered_peacefully"}, "")], None),
    "maggie": ("Maggie Sullivan", "Archaeologist, the American expedition", "Takes the pictures and keeps Whitfield honest. Mostly.", [], None),
    "callahan": ("Red Callahan", "Security, the American expedition", "Keeps the bad men off Whitfield's investment.", [], None),
    "adler": ("Professor Friedrich Adler", "Leader, the German expedition",
              "A careful, respected archaeologist who will not let enthusiasm overrule evidence.",
              [({"flag": "thieves_germans"}, "His people took the jars and the amulet, for study.")], None),
    "kruger": ("Wilhelm Krüger", "Epigrapher, the German expedition", "A young scholar in his famous superior's shadow.", [], None),
    "vogel": ("Ernst Vogel", "Security, the German expedition", "A former soldier who wants to finish his contract with nobody else dead.", [], None),
    "bellini": ("Vittorio Bellini", "Leader, the Italian expedition",
                "Arrived late, quietly, expecting to profit from what the others uncovered.",
                [({"flag": "thieves_italians"}, "His people took the jars and the amulet, to sell.")], None),
    "sofia": ("Sofia Ricci", "Antiquities specialist, the Italian expedition", "Knows what the artifacts are worth, and what they are.", [], None),
    # ---- the Keepers
    "rashad": ("Sheikh Rashad al-Khatib", "Leader of the Keepers of the Veil",
               "His family has kept watch over Akmentar for generations. Explained the amulet and the guardian, and sent you after the thieves.",
               [({"flag": "act9_started"}, "He fell holding the guardian at Akmentar.")], None),
    "bashir": ("Bashir Haddad", "Commander of the Keepers' riders", "The man whose riders stopped expeditions on the roads to Akmentar.",
               [({"flag": "recognized_bandits"}, "His men are the ones you fought on the way.")], None),
    "noura": ("Noura al-Khatib", "Ritual keeper", "Rashad's niece, who knows the binding rite and thinks the Keepers' secrecy helped cause this.",
              [({"flag": "barrier_restored"}, "The rite was completed.")], None),
    "omar": ("Omar Saqr", "Guardian warrior", "Raised among the Keepers. Rode against the expeditions, and hates you for the brothers he lost.",
             [(T("omar", 1), "He has started to trust you, a little.")], None),
    "tariq": ("Tariq Selim", "The Keepers' messenger", "Carries the Sheikh's word.", [], None),
    "guardian": ("The guardian", "Akmentar's last guardian",
                 "Bound to the amulet when it was laid in its cradle. It follows the eye wherever it is carried, and it cannot be killed.",
                 [({"flag": "clue_sarcophagus"}, "The sarcophagus held him down with bronze bands, like a guard posted, not a king at rest."),
                  ({"flag": "barrier_restored"}, "With the eye back in its cradle, he sleeps again.")],
                 {"flag": "awakened"}),
}


def main():
    problems = []
    out = {}
    for pid, (name, role, text, notes, met_if) in P.items():
        e = {"name": name, "role": role, "text": text, "notes": []}
        for cond, note in notes:
            for k in cond:
                if k not in CONDS:
                    problems.append("%s: unknown condition %s" % (pid, k))
            if note:
                e["notes"].append({"if": cond, "text": note})
        if met_if:
            e["met_if"] = met_if
        out[pid] = e
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    data = {"_help": "The journal's People pages, by speaker id. A page appears once that person has spoken to you (Codex.meet) or its met_if passes; each note is added when its 'if' passes. Played by scripts/sites/codex.gd and JournalScreen. Generated by tools/dialogue/make_codex.py.",
            "people": out}
    os.makedirs(os.path.join(ROOT, "codex"), exist_ok=True)
    with open(os.path.join(ROOT, "codex", "people.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")
    print("codex: %d people, all checks passed" % len(out))


if __name__ == "__main__":
    main()
