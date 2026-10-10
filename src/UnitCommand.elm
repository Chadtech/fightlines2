module UnitCommand exposing
    ( Command(..)
    , assetName
    , available
    , isImplemented
    , label
    )

import Api.Enum.UnitKind as Kind exposing (UnitKind)


type Command
    = StandGround
    | HoldPosition
    | Move
    | AttackMove
    | IndirectFire
    | DigIn
    | Ambush


available : UnitKind -> List Command
available kind =
    case kind of
        Kind.Infantry ->
            [ StandGround, HoldPosition, Move, AttackMove, DigIn ]

        Kind.Tank ->
            [ StandGround, HoldPosition, Move, AttackMove ]

        Kind.SupplyTruck ->
            [ Move, HoldPosition ]

        Kind.FieldGun ->
            [ HoldPosition, Move, IndirectFire, DigIn, Ambush ]


isImplemented : Command -> Bool
isImplemented command =
    case command of
        Move ->
            True

        HoldPosition ->
            True

        _ ->
            False


label : Command -> String
label command =
    case command of
        StandGround ->
            "stand ground"

        HoldPosition ->
            "hold position"

        Move ->
            "move"

        AttackMove ->
            "attack move"

        IndirectFire ->
            "indirect fire"

        DigIn ->
            "dig in"

        Ambush ->
            "ambush"


assetName : Command -> String
assetName command =
    case command of
        StandGround ->
            "stand-ground"

        HoldPosition ->
            "hold-position"

        Move ->
            "move"

        AttackMove ->
            "attack-move"

        IndirectFire ->
            "indirect-fire"

        DigIn ->
            "dig-in"

        Ambush ->
            "ambush"
