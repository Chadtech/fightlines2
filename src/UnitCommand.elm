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
    | Unload
    | AttackMove
    | IndirectFire
    | DigIn
    | Ambush


available : Unit -> List Command
available unit =
    if Unit.carrierId unit /= Nothing then
        [ Unload, HoldPosition ]

    else
        case unit.kind of
            Kind.Infantry ->
                [ Move, HoldPosition, StandGround, AttackMove, DigIn ]

            Kind.Tank ->
                [ Move, HoldPosition, StandGround, AttackMove ]

            Kind.SupplyTruck ->
                [ Move, HoldPosition ]

            Kind.FieldGun ->
                [ Move, HoldPosition, IndirectFire, DigIn, Ambush ]


isImplemented : Command -> Bool
isImplemented command =
    case command of
        Move ->
            True

        Unload ->
            True

        HoldPosition ->
            True

        _ ->
            False


label : Command -> String
label command =
    case command of
        Unload ->
            "unload"

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
        Unload ->
            "move"

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
