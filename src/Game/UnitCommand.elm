module Game.UnitCommand exposing
    ( Command(..)
    , MenuOption(..)
    , all
    , assetName
    , available
    , canUse
    , enabledOptions
    , isImplemented
    , label
    , shortcut
    )

import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.UnitKind as Kind
import Game.Depot as Depot exposing (Depot)
import Game.Map as Map exposing (Map)
import Game.Terrain as Terrain
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Location as Location
import Game.UnitResources as UnitResources exposing (UnitResources)


type Command
    = StandGround
    | HoldPosition
    | Move
    | AttackMove
    | IndirectFire
    | Sabotage
    | DigIn
    | Ambush


type MenuOption
    = CommandOption Command
    | CancelOption


all : List Command
all =
    [ Move, HoldPosition, Ambush, StandGround, AttackMove, IndirectFire, DigIn, Sabotage ]


enabledOptions : Map -> List Depot -> Unit -> List MenuOption
enabledOptions map depots unit =
    let
        commands : List MenuOption
        commands =
            available depots unit
                |> List.filter (canUse map depots unit)
                |> List.map CommandOption
    in
    commands ++ [ CancelOption ]


available : List Depot -> Unit -> List Command
available depots unit =
    if Unit.carrierId unit /= Nothing then
        []

    else
        case unit.kind of
            Kind.Infantry ->
                [ Move, HoldPosition, Ambush, StandGround, AttackMove, DigIn ]
                    ++ sabotageCommands depots unit

            Kind.Tank ->
                [ Move, HoldPosition, Ambush, StandGround, AttackMove ]

            Kind.Truck ->
                [ Move, HoldPosition ]

            Kind.FieldGun ->
                [ Move, HoldPosition, Ambush, StandGround, IndirectFire ]


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

        Sabotage ->
            True

        DigIn ->
            True


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

        Sabotage ->
            "sabotage"

        DigIn ->
            "dig in"

        Ambush ->
            "ambush"


shortcut : Command -> String
shortcut command =
    case command of
        Move ->
            "m"

        HoldPosition ->
            "h"

        AttackMove ->
            "a"

        Ambush ->
            "b"

        StandGround ->
            "g"

        IndirectFire ->
            "i"

        DigIn ->
            "d"

        Sabotage ->
            "x"


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

        Sabotage ->
            "sabotage"

        DigIn ->
            "dig-in"

        Ambush ->
            "ambush"


canUse : Map -> List Depot -> Unit -> Command -> Bool
canUse map depots unit command =
    if command == Sabotage then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map
                        (\resources ->
                            resources.supplies.current >= resources.supplies.upkeepPerTurn
                        )
                    |> Maybe.withDefault False
        in
        List.member Sabotage (sabotageCommands depots unit) && affordable

    else if command == DigIn then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map
                        (\resources ->
                            resources.supplies.current >= resources.supplies.upkeepPerTurn + unit.combatRules.digInCost
                        )
                    |> Maybe.withDefault False
        in
        case unit.location of
            Location.OnMap position ->
                (unit.kind == Kind.Infantry)
                    && (unit.entrenchment == Entrenchment.Exposed)
                    && affordable
                    && not (Terrain.isRoad (Map.terrainAt map position))

            Location.Aboard _ ->
                False

            Location.Dismounting _ ->
                False

    else if command == IndirectFire then
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
                    |> Maybe.map
                        (\resources -> resources.supplies.current >= resources.supplies.upkeepPerTurn + unit.combatRules.readinessCost)
                    |> Maybe.withDefault False
        in
        unit.direction /= Nothing && Unit.onMap unit && affordable

    else if command == AttackMove then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map
                        (\resources ->
                            let
                                cost =
                                    resources.supplies.upkeepPerTurn
                                        + resources.supplies.movementPerTile
                                        + unit.combatRules.readinessCost
                                        + unit.combatRules.shotCost
                            in
                            resources.supplies.current >= cost
                        )
                    |> Maybe.withDefault False
        in
        Unit.onMap unit && affordable

    else
        isImplemented command


sabotageCommands : List Depot -> Unit -> List Command
sabotageCommands depots unit =
    case unit.location of
        Location.OnMap position ->
            let
                survivingDepot : Depot -> Bool
                survivingDepot depot =
                    (depot.position == position) && not (Depot.isDestroyed depot)

                eligible : Bool
                eligible =
                    (unit.kind == Kind.Infantry) && List.any survivingDepot depots
            in
            if eligible then
                [ Sabotage ]

            else
                []

        _ ->
            []
