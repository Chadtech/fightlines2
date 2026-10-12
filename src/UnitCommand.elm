module UnitCommand exposing
    ( Command(..)
    , MenuOption(..)
    , assetName
    , available
    , canUse
    , enabledOptions
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


type MenuOption
    = CommandOption Command
    | CancelOption


enabledOptions : Unit -> List MenuOption
enabledOptions unit =
    let
        commands : List MenuOption
        commands =
            available unit
                |> List.filter (canUse unit)
                |> List.map CommandOption
    in
    commands ++ [ CancelOption ]


available : Unit -> List Command
available unit =
    if Unit.carrierId unit /= Nothing then
        []

    else
        case unit.kind of
            Kind.Infantry ->
                [ Move, HoldPosition, Rotate, Ambush, StandGround, AttackMove, DigIn ]

            Kind.Tank ->
                [ Move, HoldPosition, Rotate, Ambush, StandGround, AttackMove ]

            Kind.Truck ->
                [ Move, HoldPosition ]

            Kind.FieldGun ->
                [ Move, HoldPosition, Rotate, Ambush, IndirectFire, DigIn ]


isImplemented : Command -> Bool
isImplemented command =
    case command of
        AttackMove ->
            True

        Move ->
            True

        Ambush ->
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


canUse : Unit -> Command -> Bool
canUse unit command =
    if command == Ambush then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map (\resources -> resources.supplies.current >= resources.supplies.upkeepPerTurn + unit.combatRules.readinessCost)
                    |> Maybe.withDefault False
        in
        unit.direction /= Nothing && Unit.onBoard unit && affordable

    else if command == AttackMove then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map (\resources -> resources.supplies.current >= resources.supplies.upkeepPerTurn + resources.supplies.movementPerTile + unit.combatRules.shotCost)
                    |> Maybe.withDefault False
        in
        Unit.onBoard unit && affordable

    else
        isImplemented command
