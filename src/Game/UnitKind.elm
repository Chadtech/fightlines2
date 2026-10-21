module Game.UnitKind exposing (label)

import Api.Enum.UnitKind as Kind exposing (UnitKind)


label : UnitKind -> String
label kind =
    case kind of
        Kind.Infantry ->
            "infantry"

        Kind.FieldGun ->
            "field gun"

        Kind.Tank ->
            "tank"

        Kind.Truck ->
            "truck"
