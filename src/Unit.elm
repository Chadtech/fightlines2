module Unit exposing
    ( Unit
    , boardPosition
    , carrierId
    , label
    , loadingPartner
    , onBoard
    , physicalPosition
    , selection
    , setOnMap
    , supplyMovementLimit
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.Side exposing (Side)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Api.Object
import Api.Object.Unit as UnitApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import ListUtil
import Side
import Unit.Fuel as Fuel exposing (Fuel)
import Unit.HitPoints as HitPoints exposing (HitPoints)
import Unit.Location as Location exposing (Location)
import Unit.Supplies as Supplies exposing (Supplies)
import UnitId exposing (UnitId)


type alias Unit =
    { id : UnitId
    , side : Side
    , kind : UnitKind
    , direction : Maybe Direction
    , hitPoints : HitPoints
    , supplies : Supplies
    , fuel : Maybe Fuel
    , cargoCapacity : Int
    , location : Location
    }


selection : SelectionSet Unit Api.Object.Unit
selection =
    SS.succeed Unit
        |> SS.with UnitId.selection
        |> SS.with UnitApi.side
        |> SS.with UnitApi.kind
        |> SS.with UnitApi.direction
        |> SS.with (UnitApi.hitPoints HitPoints.selection)
        |> SS.with (UnitApi.supplies Supplies.selection)
        |> SS.with (UnitApi.fuel Fuel.selection)
        |> SS.with UnitApi.cargoCapacity
        |> SS.with (UnitApi.location Location.selection)


label : Unit -> String
label unit =
    let
        kind : String
        kind =
            case unit.kind of
                UnitKind.Infantry ->
                    "infantry"

                UnitKind.Tank ->
                    "tank"

                UnitKind.FieldGun ->
                    "field gun"

                UnitKind.Truck ->
                    "truck"
    in
    String.join " "
        [ Side.label unit.side
        , kind
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


loadingPartner : List Unit -> Unit -> Coordinate -> Maybe Unit
loadingPartner units mover destination =
    let
        compatible : Unit -> Bool
        compatible target =
            let
                hasRoom : Unit -> Bool
                hasRoom truck =
                    truck.kind
                        == UnitKind.Truck
                        && List.length (List.filter (\passenger -> carrierId passenger == Just truck.id) units)
                        < truck.cargoCapacity

                portable : Unit -> Bool
                portable unit =
                    unit.kind == UnitKind.Infantry || unit.kind == UnitKind.FieldGun

                alliedTarget : Bool
                alliedTarget =
                    boardPosition target == Just destination && target.id /= mover.id && target.side == mover.side

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
