module DevTools.CombatChart exposing
    ( Calculation
    , Chart
    , Factors
    , Hit
    , Key
    , Settings
    , defaultSettings
    , defenseLabel
    , defenses
    , key
    )

import Api.Enum.AttackAspect as Aspect
import Api.Enum.CombatChartCover as Cover exposing (CombatChartCover)
import Api.Enum.CombatChartDefense as Defense exposing (CombatChartDefense)
import Api.Enum.CombatKind as Attack
import Api.Enum.CombatReadyOrder as ReadyOrder
import Api.Enum.UnitKind exposing (UnitKind)
import Api.InputObject



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Settings =
    Api.InputObject.CombatChartInputRequiredFields


type alias Chart =
    { settings : Settings
    , hits : List Hit
    }


type alias Hit =
    { attacker : UnitKind
    , defender : UnitKind
    , defense : CombatChartDefense
    , cover : CombatChartCover
    , calculation : Calculation
    , remainingHp : Int
    }


type alias Calculation =
    { damage : Int
    , factors : Factors
    }


type alias Factors =
    { basePower : Int
    , relativeHealth : Float
    , matchup : Float
    , readiness : Float
    , defenderFacing : Float
    , attackerAim : Float
    , cover : Float
    , ambush : Float
    , entrenchment : Float
    , fortification : Float
    }


type alias Key =
    { attacker : UnitKind
    , defender : UnitKind
    , defense : CombatChartDefense
    , cover : CombatChartCover
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


defaultSettings : Settings
defaultSettings =
    { attack = Attack.Ambush
    , attackerHp = 16
    , defenderHp = 16
    , attackerAim = Aspect.Front
    , readyOrder = ReadyOrder.StandGround
    , entrenchedInfantry = False
    , fortress = False
    }


key : Hit -> Key
key hit =
    { attacker = hit.attacker
    , defender = hit.defender
    , defense = hit.defense
    , cover = hit.cover
    }


defenses : Settings -> List CombatChartDefense
defenses settings =
    if settings.attack == Attack.IndirectFire then
        [ Defense.Unready
        , Defense.Ready
        ]

    else
        [ Defense.Unready
        , Defense.Front
        , Defense.Flank
        , Defense.Rear
        ]


defenseLabel : CombatChartDefense -> String
defenseLabel defense =
    case defense of
        Defense.Unready ->
            "unready / exposed"

        Defense.Ready ->
            "ready"

        Defense.Front ->
            "ready · front"

        Defense.Flank ->
            "ready · side"

        Defense.Rear ->
            "ready · rear"
