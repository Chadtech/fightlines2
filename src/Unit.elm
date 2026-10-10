module Unit exposing (Fuel, Supplies, Unit, label, supplyMovementLimit)

import Api.Enum.Direction exposing (Direction)
import Api.Enum.Side exposing (Side)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import Side
import UnitId exposing (UnitId)


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


type alias Unit =
    { id : UnitId
    , side : Side
    , kind : UnitKind
    , direction : Maybe Direction
    , supplies : Supplies
    , fuel : Maybe Fuel
    , position : Coordinate
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

                UnitKind.SupplyTruck ->
                    "supply truck"
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
