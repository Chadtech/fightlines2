module Unit exposing
    ( Unit
    , boardPosition
    , carrierId
    , crateCount
    , faceDirection
    , isDying
    , label
    , loadingTarget
    , onBoard
    , physicalPosition
    , selection
    , setOnMap
    , supplyMovementLimit
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Enum.SpriteFacing exposing (SpriteFacing)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Api.Object
import Api.Object.Unit as UnitApi
import CombatRules exposing (CombatRules)
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import PlayerNumber
import SpriteFacing
import Unit.Location as Location exposing (Location)
import Unit.Supplies exposing (Supplies)
import UnitId exposing (UnitId)
import UnitResources exposing (UnitResources)
import Util.List as ListUtil
import Util.UnitKind as UnitKindUtil


type alias Unit =
    { id : UnitId
    , playerNumber : PlayerNumber
    , kind : UnitKind
    , direction : Maybe Direction
    , spriteFacing : SpriteFacing
    , resources : Maybe UnitResources
    , cargoCapacity : Int
    , destroyed : Bool
    , combatRules : CombatRules
    , location : Location
    }


selection : SelectionSet Unit Api.Object.Unit
selection =
    SS.succeed Unit
        |> SS.with UnitId.selection
        |> SS.with UnitApi.side
        |> SS.with UnitApi.kind
        |> SS.with UnitApi.direction
        |> SS.with UnitApi.spriteFacing
        |> SS.with (UnitApi.resources UnitResources.selection)
        |> SS.with UnitApi.cargoCapacity
        |> SS.with UnitApi.destroyed
        |> SS.with (UnitApi.combatRules CombatRules.selection)
        |> SS.with (UnitApi.location Location.selection)


label : Unit -> String
label unit =
    String.join " "
        [ PlayerNumber.label unit.playerNumber
        , UnitKindUtil.label unit.kind
        , UnitId.toString unit.id
        ]


setOnMap : Coordinate -> Unit -> Unit
setOnMap position unit =
    { unit | location = Location.OnMap position }


{-| Upkeep is reserved before spending supplies on movement.
Units with no per-tile supply consumption have no supply movement limit.
-}
supplyMovementLimit : Supplies -> Maybe Int
supplyMovementLimit supplies =
    if supplies.movementPerTile > 0 then
        Just (max 0 (supplies.current - supplies.upkeepPerTurn) // supplies.movementPerTile)

    else
        Nothing


onBoard : Unit -> Bool
onBoard unit =
    boardPosition unit /= Nothing


isDying : Unit -> Bool
isDying unit =
    unit.destroyed
        || (unit.resources
                |> Maybe.map
                    (\resources ->
                        resources.supplies.current == 0 || resources.hitPoints.current == 0
                    )
                |> Maybe.withDefault False
           )


loadingTarget : List Unit -> Unit -> Coordinate -> Maybe Unit
loadingTarget units mover destination =
    let
        compatible : Unit -> Bool
        compatible target =
            let
                hasRoom : Unit -> Bool
                hasRoom truck =
                    let
                        passengers : List Unit
                        passengers =
                            List.filter (\passenger -> carrierId passenger == Just truck.id) units

                        occupiedBerths : Int
                        occupiedBerths =
                            List.length passengers + crateCount truck
                    in
                    (truck.kind == UnitKind.Truck)
                        && (occupiedBerths < truck.cargoCapacity)

                portable : Unit -> Bool
                portable unit =
                    unit.kind == UnitKind.Infantry || unit.kind == UnitKind.FieldGun

                alliedTarget : Bool
                alliedTarget =
                    boardPosition target == Just destination && target.id /= mover.id && target.playerNumber == mover.playerNumber

                loadingAllowed : Bool
                loadingAllowed =
                    (hasRoom mover && portable target) || (portable mover && hasRoom target)
            in
            alliedTarget && onBoard mover && onBoard target && loadingAllowed
    in
    ListUtil.find compatible units


boardPosition : Unit -> Maybe Coordinate
boardPosition unit =
    case unit.location of
        Location.OnMap position ->
            Just position

        Location.Aboard _ ->
            Nothing


carrierId : Unit -> Maybe UnitId
carrierId unit =
    case unit.location of
        Location.OnMap _ ->
            Nothing

        Location.Aboard carrier ->
            Just carrier


{-| Resolve a passenger through its carrier's board position. Missing carriers
and carriers that are themselves aboard have no physical position.
-}
physicalPosition : List Unit -> Unit -> Maybe Coordinate
physicalPosition units unit =
    case unit.location of
        Location.OnMap position ->
            Just position

        Location.Aboard carrier ->
            ListUtil.find (\truck -> truck.id == carrier) units
                |> Maybe.andThen boardPosition


faceDirection : Maybe Direction -> Unit -> Unit
faceDirection direction unit =
    { unit
        | direction = direction
        , spriteFacing = SpriteFacing.turn direction unit.spriteFacing
    }


crateCount : Unit -> Int
crateCount unit =
    unit.resources
        |> Maybe.map (.supplyCargo >> List.length)
        |> Maybe.withDefault 0
