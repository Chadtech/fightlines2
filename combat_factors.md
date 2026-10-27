- Trucks should be extremely vulnerable and always take severe damage
- field-gun crews remain exposed regardless of firing readiness; infantry have a ×3 damage multiplier against them
- field guns should obliterate most things, including tanks, except infantry dug into trenches, which they should do very little damage to
- tanks should devastate field guns at direct contact unless the tank is in the firing area of a ready gun that can still fire
- infantry should take little damage when dug in, except from tanks, who will obliterate them
- Units that are not battle ready should pretty much always lose at a great cost. Unready tanks should take big losses to ready infantry
- Ready tanks should obliterate infantry in frontal mutual combat; infantry should barely damage ready tanks except when ambushing their flank or rear
- Unready units do not establish a front, flank, or rear defense
- Units with lower health should be less powerful. This should not scale linearly. A unit with half health should be less than half effective.
- Flanking. A unit that is attacking or being attacked head on should do better than a unit being attacked adjacent or behind the direction it is facing.
- Being in hills and forests should give a slight defensive advantage
- If two units end up in direct combat, and one is attacking and the other is ambushing, the ambushing unit should have a slight bonus.

## Implemented damage model

Damage is deterministic and calculated in Rust for both ambushes and attack moves:

`round(base power × (attacker HP / maximum HP)² × matchup × readiness × defender facing × attacker aim × cover × ambush advantage × entrenchment)`

Round only once at the end; living armed shooters deal at least 1 HP, with damage
capped at the target's maximum HP (currently 16). Damage may exceed remaining HP;
health stops at zero. Trucks cannot shoot. These are initial balance values,
chosen to express the expectations above rather than a fixed outcome table.

| Factor | Value |
| --- | --- |
| Base power | infantry 4, tank 8, field gun 12 |
| Matchup | against trucks ×3.5; infantry against infantry ×1.75, field guns ×3, unready tanks ×2, ready tanks ×0.25; tanks against infantry ×2.5 or field guns ×2; field guns against other combat units ×1.5; otherwise ×1 |
| Exposed defender | ×1.5 incoming damage for unready units and all field guns |
| Ready defender facing | infantry/tanks: front ×1; flank ×1.25; rear ×1.5; unready units and field guns always ×1 |
| Attacker aim | front ×1; flank ×0.85; rear ×0.7 |
| Hills or forest cover | ×0.85 incoming damage |
| Ambush firing on an attack mover | ×1.125 |
| Infantry ambushing a ready tank's flank or rear | ×5 instead of the ordinary ambush factor; applies to all forms of tank readiness |
| Entrenched infantry | incoming infantry damage ×0.15; incoming field-gun damage ×0.06 (direct and indirect); tank damage unchanged |

Battle readiness means an ambush or stand-ground order, or an attack-move order with enough
supplies to fire while preserving upkeep. An attack mover that already fired
retains its defensive readiness for the turn. Ordinary holds, moves, and rotations
are unready. Stand ground costs the same readiness supplies as ambush but never fires.
Readiness does not grant automatic return fire or change targeting.
Field-gun readiness prepares the weapon to fire but gives its exposed crew no
defensive protection. Guns always take the ×1.5 exposed-defender multiplier,
regardless of order or approach direction. Their firing direction, coverage,
and tank interception still apply normally.
Facing uses 90-degree front and rear sectors, including diagonal boundaries;
other bearings are flank hits. Defensive facing applies only to battle-ready
infantry and tanks. An unready tank takes the same damage from every approach direction;
its stored sprite/facing direction does not create combat flanks. Units without
facing also use neutral facing factors.
Cover does not override forest concealment or firing-line visibility rules.
The infantry flank/rear ambush factor replaces, rather than stacks with, the
ordinary attack-mover ambush factor. Frontal ambushes and attack-move shots retain
their existing damage. Unready tanks do not receive the special factor.

## Example outcomes

Each row describes one hit. Units have 16 HP, stand on open ground, and face one
another unless the row says otherwise. The attacker aims directly at the target.
A ready defender has an ambush order; an unready defender is holding or moving
normally. Infantry and tank examples use attack-move shots. Field-gun examples
use ambush shots. Readiness does not grant return fire by itself.

| Attacker | Defender and situation | Damage | Defender HP left |
| --- | --- | ---: | ---: |
| Infantry | Unready truck | 16 | 0 |
| Infantry | Unready truck on a hill | 16 | 0 |
| Infantry | Unready tank | 12 | 4 |
| Infantry | Ready tank | 1 | 15 |
| Infantry | Ready tank hit from the flank | 1 | 15 |
| Infantry | Ready tank hit from behind | 2 | 14 |
| Infantry | Unready tank on a hill | 10 | 6 |
| Infantry | Ready tank on a hill | 1 | 15 |
| Infantry | Unready infantry | 11 | 5 |
| Infantry | Unready infantry on a hill | 9 | 7 |
| Infantry | Ready infantry | 7 | 9 |
| Infantry | Ready infantry on a hill | 6 | 10 |
| Infantry | Ready field gun | 16 | 0 |
| Infantry | Ready field gun on a hill | 15 | 1 |
| Tank | Unready infantry | 16 | 0 |
| Tank | Ready infantry on open ground | 16 | 0 |
| Tank | Ready infantry on a hill | 16 | 0 |
| Tank | Unready tank | 12 | 4 |
| Tank | Ready tank | 8 | 8 |
| Tank | Ready tank hit from behind | 12 | 4 |
| Tank | Ready tank on a hill | 7 | 9 |
| Tank | Ready field gun approached outside its firing area | 16 | 0 |
| Field gun | Ready tank on open ground | 16 | 0 |
| Field gun | Ready tank on a hill | 15 | 1 |
| Field gun | Ready infantry on open ground, without trenches | 16 | 0 |
| Ambushing tank | Attack-moving tank, head-on | 9 | 7 |
| Ambushing infantry | Attack-moving tank, head-on | 1 | 15 |
| Ambushing infantry | Ready tank hit from the flank | 6 | 10 |
| Ambushing infantry | Ready tank hit from behind | 8 | 8 |

Hills and forests use the same damage reduction. Forest examples require an
otherwise legal encounter: forest concealment still prevents ordinary ambush
shots at hidden targets, while attack-move contact can engage concealed enemies.
Infantry without entrenchment remain exposed to heavy weapons even when ambushing. Ready tanks resist infantry fire particularly
strongly; infantry readiness does not make them effective against prepared armor.
Infantry flank and rear ambushes are the exception: at full health on open ground,
`round(4 × 0.25 × 1.25 × 5) = 6` and `round(4 × 0.25 × 1.5 × 5) = 8`.
Being ambushed still does not trigger automatic return fire or stop a surviving
attack mover's remaining route.
The 12-damage infantry hit against an unready tank applies from every direction.

Wounded attackers lose power much faster than their health percentage:

| Attacker and remaining HP | Defender | Damage | Defender HP left |
| --- | --- | ---: | ---: |
| Infantry, 12/16 HP | Unready tank | 7 | 9 |
| Infantry, 8/16 HP | Unready tank | 3 | 13 |
| Infantry, 4/16 HP | Unready tank | 1 | 15 |
| Infantry, 8/16 HP | Unready truck | 5 | 11 |
| Infantry, 8/16 HP | Ready field gun | 5 | 11 |
| Tank, 12/16 HP | Ready tank | 5 | 11 |
| Tank, 8/16 HP | Ready tank | 2 | 14 |
| Tank, 4/16 HP | Ready tank | 1 | 15 |
| Field gun, 8/16 HP | Ready tank | 5 | 11 |

These values are calculated from the factors above, rather than hardcoded
matchup outcomes. Rounding and the minimum 1 HP hit make very small attacks less
smooth. Some complete head-on exchanges on open ground:

- Two full-health tanks ambushing one another each deal 8 damage; both finish at 8 HP.
- Two half-health tanks ambushing one another each deal 2 damage; both finish at 6 HP.
- A full-health infantry unit and tank ambushing one another deal 1 and 16 damage respectively; the infantry is destroyed and the tank finishes at 15 HP.
- Full-health infantry attack-moving into a ready tank's firing line deal 1 damage. The tank fires back for 16, destroying the infantry and finishing at 15 HP, even if the infantry are on a hill.
- A half-health ready field gun intercepting a full-health attack-moving tank deals 5 first. The tank survives at 11 HP and returns an 11-damage hit, destroying the gun.

Reciprocal shots use pre-volley strength; the field-gun interception is a separate
volley, so the tank's return shot uses its reduced health.

## Tank and field-gun exchanges

A ready field gun gets a separate first volley when a tank engages it inside
its visible, unobstructed ambush coverage, through attack-move contact or an
opposing ambush. This includes contacts deferred at the start of the turn.
On open ground, a full-health gun destroys a full-health tank before it can shoot. From outside that area, against an unready
gun, or after the gun has spent its shot, the tank fires normally; a full-health
tank can destroy the gun. Wounded guns may fail to kill the tank; survivors return
fire with their reduced health. Existing range, cross coverage, visibility,
supply costs, and once-per-turn shot limits still apply.

Every shot in one volley uses health and facing from before that volley. Later
volleys use the surviving units' updated health. Encounter health presentation
continues to accumulate damage across pairs without changing simultaneous fire.

## Entrenchment

Only infantry already on the map can dig in. This exclusive stationary action
costs 16 supplies plus ordinary upkeep, requires that stock before submitting,
and never fires or grants readiness. Protection completes after all combat,
including indirect fire; diggers remain exposed throughout the digging turn.
Holding, ambush, stand ground, and rotation preserve entrenchment with no extra
maintenance. Firing still needs an ordinary ambush order and its supply costs.
Actual movement and boarding clear it; a move blocked before leaving preserves
it. No terrain or abandoned trench persists. Dismounting consumes movement, so
infantry cannot dig in during their unloading turn.

Full-health, head-on attacks against ready entrenched infantry on open ground
inflict 1 HP from infantry, 1 HP from a field gun (direct or indirect), and 16 HP
from a tank. Against holding entrenched infantry, infantry deal 2 HP and field
guns deal 2 HP. Health, facing, cover, readiness, and the existing minimum 1 HP
hit still apply. Entrenchment changes incoming damage without adding return
fire, range, visibility, or offensive power.
