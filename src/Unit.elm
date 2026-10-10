module Unit exposing (Fuel, Unit, label)

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


type alias Unit =
    { id : UnitId
    , side : Side
    , kind : UnitKind
    , direction : Maybe Direction
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
