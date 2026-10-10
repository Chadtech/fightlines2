module Unit exposing
    ( Fuel
    , HitPoints
    , Location(..)
    , Supplies
    , Unit
    , boardPosition
    , carrierId
    , label
    , loadingPartner
    , onBoard
    , physicalPosition
    , supplyMovementLimit
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.Side exposing (Side)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import ListUtil
import Side
import UnitId exposing (UnitId)


type alias HitPoints =
    { current : Int
    , maximum : Int
    }


type alias Fuel =
    { current : Int
    , maximum : Int
    }


type alias Supplies =
    { current : Int
    , maximum : Int
    , upkeepPerTurn : Int
    , movementPerTile : Int
    }


{-| Board occupancy and transport are mutually exclusive. Aboard units derive
physical position from their carrier, without storing a duplicate coordinate.
-}
type Location
    = OnMap Coordinate
    | Aboard UnitId


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
    Side.label unit.side ++ " " ++ kind ++ " " ++ UnitId.toString unit.id


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
        OnMap position ->
            Just position

        Aboard _ ->
            Nothing


carrierId : Unit -> Maybe UnitId
carrierId unit =
    case unit.location of
        OnMap _ ->
            Nothing

        Aboard carrier ->
            Just carrier


{-| Resolve a passenger through its carrier's board position. Missing carriers
and carriers that are themselves aboard have no physical position.
-}
physicalPosition : List Unit -> Unit -> Maybe Coordinate
physicalPosition units unit =
    case unit.location of
        OnMap position ->
            Just position

        Aboard carrier ->
            ListUtil.find (\truck -> truck.id == carrier) units
                |> Maybe.andThen boardPosition
