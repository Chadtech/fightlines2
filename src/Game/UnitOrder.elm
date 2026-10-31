module Game.UnitOrder exposing
    ( MenuOption(..)
    , Order(..)
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


type Order
    = StandGround
    | HoldPosition
    | Move
    | AttackMove
    | IndirectFire
    | Sabotage
    | DigIn
    | Ambush


type MenuOption
    = OrderOption Order
    | CancelOption


all : List Order
all =
    [ Move, AttackMove, Ambush, HoldPosition, IndirectFire, StandGround, DigIn, Sabotage ]


enabledOptions : Map -> List Depot -> Unit -> List MenuOption
enabledOptions map depots unit =
    let
        orders : List MenuOption
        orders =
            available depots unit
                |> List.filter (canUse map depots unit)
                |> List.map OrderOption
    in
    orders ++ [ CancelOption ]


available : List Depot -> Unit -> List Order
available depots unit =
    if Unit.carrierId unit /= Nothing then
        []

    else
        case unit.kind of
            Kind.Infantry ->
                [ Move, AttackMove, Ambush, HoldPosition, StandGround, DigIn ]
                    ++ sabotageOrders depots unit

            Kind.Tank ->
                [ Move, AttackMove, Ambush, HoldPosition, StandGround ]

            Kind.Truck ->
                [ Move, HoldPosition ]

            Kind.FieldGun ->
                [ Move, Ambush, HoldPosition, IndirectFire, StandGround ]


isImplemented : Order -> Bool
isImplemented order =
    case order of
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


label : Order -> String
label order =
    case order of
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


shortcut : Order -> String
shortcut order =
    case order of
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


assetName : Order -> String
assetName order =
    case order of
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


canUse : Map -> List Depot -> Unit -> Order -> Bool
canUse map depots unit order =
    if order == Sabotage then
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
        List.member Sabotage (sabotageOrders depots unit) && affordable

    else if order == DigIn then
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
                let
                    hasBuilding : Bool
                    hasBuilding =
                        List.any (\depot -> depot.position == position) depots
                in
                (unit.kind == Kind.Infantry)
                    && (unit.entrenchment == Entrenchment.Exposed)
                    && affordable
                    && not (Terrain.isRoad (Map.terrainAt map position))
                    && not hasBuilding

            Location.Aboard _ ->
                False

            Location.Dismounting _ ->
                False

    else if order == IndirectFire then
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

    else if (order == Ambush) || (order == StandGround) then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map
                        (\resources -> resources.supplies.current >= resources.supplies.upkeepPerTurn + unit.combatRules.readinessCost)
                    |> Maybe.withDefault False
        in
        unit.direction /= Nothing && Unit.onMap unit && affordable

    else if order == AttackMove then
        let
            affordable : Bool
            affordable =
                unit.resources
                    |> Maybe.map
                        (\resources ->
                            let
                                cost : Int
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
        isImplemented order


sabotageOrders : List Depot -> Unit -> List Order
sabotageOrders depots unit =
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
