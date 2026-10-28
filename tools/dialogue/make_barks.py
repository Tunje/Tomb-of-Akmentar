"""Writes barks/companions.json: short in-play lines for each companion, crew foreman and the two
last guardians, keyed by situation, in their voices (gameplan/character.md). scripts/barks.gd plays
them (Barks.say(node, "reloading")).

    python tools/dialogue/make_barks.py

Each speaker's situation is a list of lines; a line is a string, or [text, {condition}] (Game.check:
trust / conviction / fear stats, story flags). Lines with a condition are tried first when it passes.
"_any" holds fallbacks for a situation a speaker has no line for."""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SITUATIONS = ["combat_start", "reloading", "ally_down", "enemy_down", "low_health", "helped_up", "mummy_seen",
              "guardian_seen", "scarabs", "slab_falling", "entering_tomb", "idle_explore", "idle_city", "campfire",
              "horse_ride", "truck_ride", "act5_escape", "act7_curse",
              "helping_up", "callout_dynamite", "callout_flank_left", "callout_flank_right", "callout_leader_down",
              "callout_rifleman", "focus_target", "sandstorm"]


def T(who, n):
    return {"stat": [who, "trust", n]}


def F(who, n):
    return {"stat": [who, "fear", n]}


def V(who, n):
    return {"stat": [who, "conviction", n]}


B = {
    "eleanor": {
        "combat_start": ["Oh God. Right. Right, I can do this.", "Keep them off the inscriptions if you can!",
                         ["Behind you! I'll watch your back.", T("eleanor", 2)]],
        "reloading": ["I'm out. How do you do this so quickly?", "Reloading! Don't laugh."],
        "ally_down": ["Someone help them, please!", ["No, no, no. Stay with me!", T("eleanor", 2)]],
        "enemy_down": ["Is it... is it dead?", "I hit it. I actually hit it."],
        "low_health": ["I'm hurt. It's fine. It's mostly fine.", "I need a moment. Just one."],
        "helped_up": ["Thank you. I'm all right. Really.", ["You came back for me.", T("eleanor", 2)]],
        "mummy_seen": ["Those wrappings are Middle Kingdom. And it's moving.", "Linen, resin, and it's walking toward us."],
        "guardian_seen": ["The bound man from the reliefs. It's him.", "That's the guardian. The inscriptions were literal."],
        "scarabs": ["Scarabs! Don't let them touch your skin!", "They're coming out of the walls!"],
        "slab_falling": ["The ceiling, it's coming down!", "Run, the slab!"],
        "entering_tomb": ["No one has breathed this air for three thousand years.", "Mind where you step. Everything here matters."],
        "idle_explore": ["Look at the tool marks. They rushed this wall.", "I want a week with every one of these columns.",
                         ["Whatever we find, it's ours to tell. Properly.", V("eleanor", 1)]],
        "idle_city": ["The museum's that way. I'd rather not be seen.", "Do you think the Professor knows I've gone?"],
        "campfire": ["I've filled half a notebook since Cairo.", ["Thank you for treating me like a scholar.", T("eleanor", 2)]],
        "horse_ride": ["I've ridden in Hyde Park. This is not Hyde Park.", "Is it supposed to bounce this much?"],
        "truck_ride": ["Every bump is another page of notes in the wrong order.", "At least the trucks don't bite."],
        "act5_escape": ["Run! Don't look back, just run!", "The way out, which way is out?"],
        "act7_curse": ["The sky over Cairo, look at it. It's what the cradle said.", "It's getting darker every hour. We're running out of time."],
    },
    "pembroke": {
        "combat_start": ["This is not what I was engaged for.", "Keep your heads down and your fire disciplined!"],
        "reloading": ["One moment, I'm reloading.", "Reloading. Methodically."],
        "ally_down": ["Man down! Someone see to them!", "We've lost one. Note the time."],
        "enemy_down": ["One fewer.", "Down. Do try not to damage the floor."],
        "low_health": ["I'm wounded. Not badly. Not well, either.", "I seem to be bleeding."],
        "helped_up": ["Thank you. Most kind.", "I'm obliged to you."],
        "mummy_seen": ["That is... that cannot be.", "There must be a rational explanation. It is still coming."],
        "guardian_seen": ["Good Lord. It's real. All of it.", "I shall need to revise a great deal."],
        "scarabs": ["Beetles! Thousands of them!", "Back, back, they're swarming!"],
        "slab_falling": ["The slab! Move!", "It's dropping, get under it now!"],
        "entering_tomb": ["Nobody touches anything until it's recorded.", "Photographs first. Then we breathe."],
        "idle_explore": ["Roman sherds. Again.", ["Every find on paper, as agreed. Good.", {"flag": "promised_pembroke_records"}]],
        "idle_city": ["I know at least three of my creditors on this street.", "Cairo never improves."],
        "campfire": ["My record is up to date. Is yours?", "Wadi Natrun still keeps me awake."],
        "horse_ride": ["I am too old to be shaken like a cocktail.", "This animal has no respect for scholarship."],
        "truck_ride": ["Mind the crates, there are glass plates in those!", "Slower, please, the negatives!"],
        "act5_escape": ["Leave the equipment, just go!", "This is entirely unscientific. Run!"],
        "act7_curse": ["Some phenomena resist documentation.", "I would very much like this to be a sandstorm."],
    },
    "hassan": {
        "combat_start": ["God forgive us.", "Stay behind the stone. Let them come to us."],
        "sandstorm": ["The old texts call this the breath of the west."],
        "reloading": ["A moment. My hands are old.", "Reloading."],
        "ally_down": ["One of ours has fallen!", "Help them up. Quickly."],
        "enemy_down": ["Rest now.", "It is finished, for that one."],
        "low_health": ["I am hurt. I have been hurt before.", "Leave me a moment. I will follow."],
        "helped_up": ["Thank you, my friend.", ["You did not have to come back for me.", T("hassan", 2)]],
        "mummy_seen": ["They are not dead. Not the way we mean it.", "His servants. They walk ahead of him."],
        "guardian_seen": ["Menkheper. He was a man, once.", "Do not look him in the face. Shoot, and move."],
        "scarabs": ["The scarabs keep the dead. Get back!", "Do not stand still. They want stillness."],
        "slab_falling": ["The stone falls! Go!", "Under it, now, before it closes!"],
        "entering_tomb": ["Some doors were closed because those who built them understood what lay beyond.",
                          ["We should not be here. You know that.", {"flag": "hassan_heard_greed"}]],
        "idle_explore": ["Read the walls before you read the gold.", ["They called it the Veil because it is only covered.", {"flag": "heard_veil"}]],
        "idle_city": ["My city. It still does not know what is coming.", "Yacoub will be counting his books."],
        "campfire": ["The stars were the same over the priests.", ["I owe you more than I can say.", {"flag": "hassan_revealed"}]],
        "horse_ride": ["Slowly. The desert is patient. So must we be.", "I rode this road when I was young."],
        "truck_ride": ["The old ones walked. I prefer this.", "The sea on one side, the dead on the other."],
        "act5_escape": ["Up! Toward the light!", "He follows the amulet, not us. Run!"],
        "act7_curse": ["The second sign. The sky goes dark by day.", "Stones from heaven. We are nearly out of time."],
    },
    "hargreaves": {
        "combat_start": ["Contact! Get into cover!", "Pick your targets. Make them count.",
                         ["Lads, just like we drilled it!", {"flag": "drilled_crew"}]],
        "reloading": ["Changing magazine!", "Reloading, cover me!"],
        "ally_down": ["Man down! I've got him!", "Nobody gets left behind. Nobody."],
        "enemy_down": ["Target down.", "One less."],
        "low_health": ["I'm hit. Still in it.", "Flesh wound. Keep firing."],
        "helped_up": ["Cheers. Back in the fight.", "Owe you one."],
        "mummy_seen": ["That's not a man. Shoot it anyway.", "Aim for the legs, slow it down!"],
        "guardian_seen": ["Big one! Fall back and keep shooting!", "Bullets slow it. Keep it slow!"],
        "scarabs": ["Bugs! Fire, use fire if you've got it!", "Move, move, don't let them swarm you!"],
        "slab_falling": ["Slab! Everyone through, now!", "Under it! Go, go, go!"],
        "entering_tomb": ["One way in, so it's one way out. Remember that.", "Torches up. Stay together."],
        "idle_explore": ["Good ground for an ambush, this.", "I'll take the rear."],
        "idle_city": ["Club's round the corner. Later.", "Keep your wallet in your front pocket."],
        "campfire": ["I'll take first watch.", ["You're the kind of officer I'd follow.", T("hargreaves", 2)]],
        "horse_ride": ["Keep the column tight.", "Eyes on the ridgeline."],
        "truck_ride": ["Rifles ready. Trucks are a big target.", "Somebody watch the rear."],
        "act5_escape": ["Fall back! Fall back to the stairs!", "Everyone out, I'm last!"],
        "act7_curse": ["Seen men panic before. Never a whole city.", "Whatever's coming, we hold the line."],
    },
    "idris": {
        "combat_start": ["Here they come.", "Close in, quick, they do not like it close."],
        "reloading": ["Reloading.", "Empty. One moment."],
        "ally_down": ["One of ours is down!", "Help them, I will cover."],
        "enemy_down": ["That one is done.", "Got him."],
        "low_health": ["I am cut. I will live.", "My sisters will be angry."],
        "helped_up": ["Thank you, my friend.", ["I will not forget that.", T("idris", 2)]],
        "mummy_seen": ["I was hired to fight men with guns. Nobody mentioned the dead.", "God protect us, it walks."],
        "guardian_seen": ["That one I do not fight. That one I run from.", "Do not let it grab you!"],
        "scarabs": ["Beetles! Get off me!", "They are everywhere!"],
        "slab_falling": ["The stone! Run!", "Under, quick!"],
        "entering_tomb": ["Quiet places are where ambushes live.", "I will go first. I am used to it."],
        "idle_explore": ["Too quiet.", "Someone has walked here before us. Recently."],
        "idle_city": ["I know people in this street. Do not stop.", "That man is a thief. So is that one."],
        "campfire": ["My sisters would like the stars here.", ["You pay fair. That is rare.", {"flag": "idris_paid_well"}],
                     ["Two hundred pounds. I have not forgotten.", {"flag": "idris_underpaid"}]],
        "horse_ride": ["Watch the high ground.", "Good horses. Better than the merchants'."],
        "truck_ride": ["Trucks are loud. Everyone will know we are coming.", "Keep moving. Never stop on a road."],
        "act5_escape": ["Run! Run!", "This way, follow me!"],
        "act7_curse": ["Even the thieves are praying now.", "The city is afraid. Afraid people are dangerous."],
    },
    "isabelle": {
        "combat_start": ["Finally, something interesting.", "I'll take the left. Don't get in my way."],
        "reloading": ["Reloading. Cover me, or don't.", "Out. Give me a second."],
        "ally_down": ["Someone's down! Merde!", ["Hold on, I'm coming!", T("isabelle", 2)]],
        "enemy_down": ["That's one.", "Next."],
        "low_health": ["It's nothing. It's a scratch.", "I've had worse. Not much worse."],
        "helped_up": ["I didn't need that. Thank you.", ["Don't make a habit of saving me.", T("isabelle", 2)]],
        "mummy_seen": ["Well, that's new.", "Does it shoot back? No? Good."],
        "guardian_seen": ["Now that's a big one.", "I'll keep it busy. You think of something."],
        "scarabs": ["Bugs! I hate bugs!", "Get them off, get them off!"],
        "slab_falling": ["Slab! Move it!", "Under, under!"],
        "entering_tomb": ["After you. I insist.", "Stay sharp. Places like this bite."],
        "idle_explore": ["Are we nearly done looking at walls?", "If something moves, I'm shooting it."],
        "idle_city": ["Three men on that corner. Watching us.", "Cairo. Never a dull moment."],
        "campfire": ["Don't read anything into me sitting here.", ["You're not what I expected.", T("isabelle", 3)]],
        "horse_ride": ["Race you.", "Faster, or we'll be here all week."],
        "truck_ride": ["Let me drive. I drive better.", "Is this as fast as it goes?"],
        "act5_escape": ["Move, move, move!", "Don't you dare die in here!"],
        "act7_curse": ["The sky's wrong. I don't like it.", "Whatever this is, let's finish it."],
    },
    "saleh": {
        "combat_start": ["Stay low. The sand is your friend.", "Find cover, then fight."],
        "sandstorm": ["Down, and keep the camels' heads low. It passes."],
        "reloading": ["Reloading.", "Patience. One moment."],
        "ally_down": ["A traveller is down! Help them!", "We bring them home. All of them."],
        "enemy_down": ["Down.", "God have mercy."],
        "low_health": ["I am hurt. Keep moving.", "Old bones break slower than you think."],
        "helped_up": ["Thank you. I will walk.", "You are a good leader."],
        "mummy_seen": ["The old stories were true, then.", "The desert keeps its dead. Not this time."],
        "guardian_seen": ["Do not fight what you cannot kill. Run.", "Back! Back the way we came!"],
        "scarabs": ["Scarabs! Away from the walls!", "Keep moving, do not stop!"],
        "slab_falling": ["The stone falls! Quickly!", "Go, now!"],
        "entering_tomb": ["We have water, daylight, and a way out. Remember the way out.", "Count the turns."],
        "idle_explore": ["The wind is changing.", "We are drinking too much water."],
        "idle_city": ["Too many people. Too much noise.", "I prefer the desert."],
        "campfire": ["Sleep. Tomorrow is long.", ["You listen. That is why you will come home.", T("saleh", 2)]],
        "horse_ride": ["Gently. Save the horses.", "Follow my line. Not a step off it."],
        "truck_ride": ["Machines do not know the sand.", "Slowly here. Soft ground."],
        "act5_escape": ["The way out! This way!", "Count the turns! Left, then left!"],
        "act7_curse": ["The sky has never been this colour.", "Even the camels are afraid."],
    },
    "youssef": {
        "combat_start": ["Let them come! I'm not afraid!", ["I'm... I'm not afraid.", F("youssef", 1)]],
        "sandstorm": ["I cannot see the road! I can still feel it. Follow me."],
        "reloading": ["Reloading, reloading!", "How do you load this thing fast?"],
        "ally_down": ["They are down! What do we do?", "Help them!"],
        "enemy_down": ["I got one! Did you see?", "Ha! Down!"],
        "low_health": ["I'm hurt! It's nothing! It's a lot!", "It burns!"],
        "helped_up": ["Thank you! I tripped, that's all.", "I am fine! Completely fine!"],
        "mummy_seen": ["Is that... is that real?", "Nobody back home will believe this!"],
        "guardian_seen": ["That's the biggest one yet!", ["I want to go home.", F("youssef", 1)]],
        "scarabs": ["Beetles! Beetles everywhere!", "Ahh, they're in my boots!"],
        "slab_falling": ["The roof! Run!", "Go, go!"],
        "entering_tomb": ["Imagine being the first to see this!", "They will write my name on this door!"],
        "idle_explore": ["I could scout ahead. I'm fast.", ["Someone has to find the road. Why not me?", V("youssef", 1)]],
        "idle_city": ["My uncle lives two streets from here.", "Everyone in Cairo will know my name."],
        "campfire": ["Tell me about the other expeditions you've led.", "I can't sleep. Too excited."],
        "horse_ride": ["Faster! We can go faster!", "I know a quicker way!"],
        "truck_ride": ["So slow! A horse would be there already.", "Can I sit on the roof?"],
        "act5_escape": ["Which way? Which way?", "Run, run, run!"],
        "act7_curse": ["The sky is black at noon!", "Is this the end of the world?"],
    },
    "farid": {
        "combat_start": ["This was not in the contract!", "Protect the supplies!"],
        "reloading": ["Reloading. Expensively.", "Each bullet costs money, you know."],
        "ally_down": ["Someone's down! Medicine, quickly!", "A loss! A terrible loss!"],
        "enemy_down": ["Good. Good.", "One fewer bill to pay."],
        "low_health": ["I'm wounded. Write it in the accounts.", "This is very bad for business."],
        "helped_up": ["Thank you. I will remember this, at a discount.", "Most kind. Most kind."],
        "mummy_seen": ["No price for this. None at all.", "I did not budget for the dead."],
        "guardian_seen": ["Run! Business is concluded!", "No, no, no, no."],
        "scarabs": ["Beetles in the stores! Save the flour!", "Get them away!"],
        "slab_falling": ["The stone! Hurry!", "Move, move!"],
        "entering_tomb": ["Every minute here costs us supplies.", "A dead customer pays nothing. Be careful."],
        "idle_explore": ["How much do you think that statue weighs?", ["There is a trader near here who owes me.", {"flag": "farid_trading"}]],
        "idle_city": ["Good prices in this street. Very good.", "Let me do the haggling."],
        "campfire": ["We are on budget. Barely.", "The sums do not add up. I am staying anyway."],
        "horse_ride": ["The horses are eating our profits.", "Water the animals at the next well."],
        "truck_ride": ["Mind the cargo!", "Fuel is dear out here."],
        "act5_escape": ["Leave the crates! Leave everything!", "Out, out!"],
        "act7_curse": ["Half the merchants have closed. Terrible.", "Fear is very bad for business."],
    },
    "mahmoud": {
        "combat_start": ["Heads down! Stay together!", "Men, behind me! Keep together!"],  # (anywhere: the boat, the city, the tomb)
        "enemy_down": ["Down.", "Good."],
        "ally_down": ["One of my men is hurt!", "Carry him, carefully!"],
        "entering_tomb": ["Carefully. We dig carefully.", "My men will hold the lamps."],
        "idle_explore": ["This soil has been turned before.", ["The finds are ours to name. Good.", {"flag": "promised_mahmoud_credit"}]],
        "campfire": ["My men are tired, but they are proud.", "We have dug for many. Never like this."],
        "mummy_seen": ["God protect us, the dead are digging themselves out!", "Back, men!"],
    },
    "khalil": {
        "combat_start": ["Stay together! Nobody runs alone!", "Protect each other!"],
        "ally_down": ["Help him! He has children!", "Carry him, carry him!"],
        "enemy_down": ["Down!", "Good!"],
        "entering_tomb": ["My men are afraid. So am I.", "Lamps up. Stay close."],
        "idle_explore": ["Heavy work. Honest work.", ["My men know they will be paid. Thank you.", T("khalil", 2)]],
        "campfire": ["Two of the men are sick from the water.", "They ask if they can go home after this."],
        "mummy_seen": ["What is that? What is that?", "Run!"],
    },
    "naguib": {
        "combat_start": ["Protect the animals!", "Loads down, rifles up!"],
        "ally_down": ["A porter is down!", "Help him!"],
        "enemy_down": ["Down.", "Good shot."],
        "entering_tomb": ["Everything is packed for the way out.", "Nobody loses a lamp."],
        "idle_explore": ["The camels need rest.", ["The loads are right. Good.", {"flag": "promised_naguib_loads"}]],
        "campfire": ["I always pack for the way out.", "The camels are overloaded."],
        "horse_ride": ["Easy, easy with the animals.", "Water at the next stop."],
        "mummy_seen": ["God help us!", "Back!"],
    },
    "noura": {
        "combat_start": ["Keep them away from the amulet!", "Stand with us!"],
        "ally_down": ["One of ours has fallen!", "Help them!"],
        "enemy_down": ["Go back to your sleep.", "Rest."],
        "low_health": ["I am hurt. The rite matters more.", "I can still sing."],
        "mummy_seen": ["His servants. They know the amulet is here.", "They will not touch the eye."],
        "guardian_seen": ["Menkheper. Keep him from the altar!", "He comes for the eye. Stand between!"],
        "scarabs": ["The scarabs! Do not let them reach the jars!", "Away from the walls!"],
        "entering_tomb": ["Walk where I walk.", "This is where my family has kept watch for a thousand years."],
        "idle_explore": ["Listen. The tomb is breathing.", "Whatever you learned here before, use it now."],
    },
    "omar": {
        "combat_start": ["For my brothers!", "Fight, foreigner, if you can!"],
        "ally_down": ["She is down! Noura!", "One more of ours, gone."],
        "enemy_down": ["Down!", "Back to the dark!"],
        "low_health": ["It is nothing.", "I will not fall here."],
        "mummy_seen": ["The dead are awake. Because of you.", "They come."],
        "guardian_seen": ["The guardian himself. Do not let him reach her!", "Shoot him, slow him!"],
        "scarabs": ["The scarabs! Burn them!", "Move!"],
        "entering_tomb": ["You walk on my brothers' graves.", ["Stay close, foreigner. I will not lose you too.", T("omar", 1)]],
        "idle_explore": ["Hurry.", "We do not have time for looking."],
    },
    "_any": {
        "combat_start": ["Here they come!", "Get down!"],
        "reloading": ["Reloading!", "Cover me!"],
        "ally_down": ["Someone's down!", "Help them!"],
        "enemy_down": ["Got one.", "Down."],
        "low_health": ["I'm hurt.", "I need a moment."],
        "helped_up": ["Thank you.", "I'm all right."],
        "mummy_seen": ["It's moving!", "God help us."],
        "guardian_seen": ["Run!", "That's him!"],
        "scarabs": ["Beetles!", "Get back!"],
        "slab_falling": ["The slab! Move!", "Under it, quick!"],
        "entering_tomb": ["Stay together.", "Careful now."],
        "idle_explore": ["Quiet here.", "Keep your eyes open."],
        "idle_city": ["Busy today.", "Keep close in the crowd."],
        "campfire": ["Long day.", "Get some sleep."],
        "horse_ride": ["Easy now.", "Keep the pace."],
        "truck_ride": ["Bumpy road.", "Hold on."],
        "act5_escape": ["Run!", "This way!"],
        "act7_curse": ["The sky...", "Something is coming."],
        "helping_up": ["Up you get!", "Come on, on your feet.", "I've got you."],
        "callout_dynamite": ["Dynamite!", "Get clear, dynamite!", "Fuse! Move!"],
        "callout_flank_left": ["Flanking left!", "One going round on the left!"],
        "callout_flank_right": ["Flanking right!", "One going round on the right!"],
        "callout_leader_down": ["Their leader's down!", "That was their man in charge!"],
        "callout_rifleman": ["Rifle, long range!", "Rifleman! Keep your head down!"],
        "focus_target": ["On it.", "That one, got it.", "Him? Right."],
        "sandstorm": ["Cover your faces!", "Sandstorm! Keep close, keep moving!", "Tie the scarves, it's coming!",
                      "Stay with the trucks, you'll lose the road in this!"],
    },
}

CONDS = {"flag", "not_flag", "money", "actions", "stat", "in_party", "day"}


def main():
    problems = []
    out = {}
    for who, sits in B.items():
        out[who] = {}
        for sit, lines in sits.items():
            if sit not in SITUATIONS:
                problems.append("%s: unknown situation %s" % (who, sit))
            norm = []
            for ln in lines:
                if isinstance(ln, list):
                    text, cond = ln
                    for k in cond:
                        if k not in CONDS:
                            problems.append("%s/%s: unknown condition %s" % (who, sit, k))
                    norm.append({"text": text, "if": cond})
                else:
                    norm.append({"text": ln})
                if len(norm[-1]["text"]) > 90:
                    problems.append("%s/%s: line too long for a bark: %s" % (who, sit, norm[-1]["text"]))
            out[who][sit] = norm
    for sit in SITUATIONS:
        if sit not in B["_any"]:
            problems.append("_any has no %s" % sit)
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    data = {"_help": "Companion barks: short in-play lines by speaker and situation (lines with an 'if' are tried first when it passes; '_any' is the fallback). Played by scripts/barks.gd. Generated by tools/dialogue/make_barks.py.",
            "situations": SITUATIONS, "speakers": out}
    os.makedirs(os.path.join(ROOT, "barks"), exist_ok=True)
    with open(os.path.join(ROOT, "barks", "companions.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")
    n = sum(len(v) for s in out.values() for v in s.values())
    print("barks: %d speakers, %d lines, all checks passed" % (len(out), n))


if __name__ == "__main__":
    main()
