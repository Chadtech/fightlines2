module UnitCommand exposing
    ( Command(..)
    , MenuOption(..)
    , all
    , assetName
    , available
    , canUse
    , enabledOptions
    , isImplemented
    , label
    )

import Api.Enum.UnitKind as Kind
import Unit exposing (Unit)
import UnitResources exposing (UnitResources)


type Command
    = StandGround
    | HoldPosition
    | Move
    | AttackMove
    | IndirectFire
    | DigIn
    | Ambush


type MenuOption
    = CommandOption Command
    | CancelOption


all : List Command
all =
    [ Move, HoldPosition, Ambush, StandGround, AttackMove, IndirectFire, DigIn ]


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
                [ Move, HoldPosition, Ambush, StandGround, AttackMove, DigIn ]

            Kind.Tank ->
                [ Move, HoldPosition, Ambush, StandGround, AttackMove ]

            Kind.Truck ->
                [ Move, HoldPosition ]

            Kind.FieldGun ->
                [ Move, HoldPosition, Ambush, StandGround, IndirectFire, DigIn ]


isImplemented : Command -> Bool
isImplemented command =
    case command of
        IndirectFire ->
            True

        AttackMove ->
            True

        Move ->
            True

        StandGround ->
            True

        Ambush ->
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


canUse : Unit -> Command -> Bool
canUse unit command =
    if command == IndirectFire then
        let
            canAffordShell : UnitResources -> Bool
            canAffordShell resources =
                resources.supplies.current
                    >= (resources.supplies.upkeepPerTurn
                            + unit.combatRules.readinessCost
                            + unit.combatRules.shotCost
                       )

            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map canAffordShell
                    |> Maybe.withDefault False
        in
        (unit.kind == Kind.FieldGun) && Unit.onMap unit && affordable

    else if command == Ambush || command == StandGround then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map (\resources -> resources.supplies.current >= resources.supplies.upkeepPerTurn + unit.combatRules.readinessCost)
                    |> Maybe.withDefault False
        in
        unit.direction /= Nothing && Unit.onMap unit && affordable

    else if command == AttackMove then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map (\resources -> resources.supplies.current >= resources.supplies.upkeepPerTurn + resources.supplies.movementPerTile + unit.combatRules.readinessCost + unit.combatRules.shotCost)
                    |> Maybe.withDefault False
        in
        Unit.onMap unit && affordable

    else
        isImplemented command
