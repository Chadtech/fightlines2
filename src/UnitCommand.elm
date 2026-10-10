module UnitCommand exposing
    ( Command(..)
    , assetName
    , available
    , isImplemented
    , label
    )

import Api.Enum.UnitKind as Kind
import Unit exposing (Unit)


type Command
    = StandGround
    | HoldPosition
    | Move
    | Rotate
    | AttackMove
    | IndirectFire
    | DigIn
    | Ambush


available : Unit -> List Command
available unit =
    if Unit.carrierId unit /= Nothing then
        []

    else
        case unit.kind of
            Kind.Infantry ->
                [ Move, HoldPosition, Rotate, StandGround, AttackMove, DigIn ]

            Kind.Tank ->
                [ Move, HoldPosition, Rotate, StandGround, AttackMove ]

            Kind.Truck ->
                [ Move, HoldPosition ]

            Kind.FieldGun ->
                [ Move, HoldPosition, Rotate, IndirectFire, DigIn, Ambush ]


isImplemented : Command -> Bool
isImplemented command =
    case command of
        Move ->
            True

        Rotate ->
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

        Rotate ->
            "rotate"

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

        Rotate ->
            "rotate"

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
