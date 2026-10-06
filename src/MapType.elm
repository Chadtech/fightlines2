module MapType exposing (label)

import Api.Enum.MapType
    exposing
        ( MapType
        )


label : MapType -> String
label mapType =
    case mapType of
        Api.Enum.MapType.SupplyPoint ->
            "supply point"
