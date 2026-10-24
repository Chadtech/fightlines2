module Game.MapType exposing (label)

import Api.Enum.MapType
    exposing
        ( MapType
        )


label : MapType -> String
label mapType =
    Api.Enum.MapType.toString mapType
        |> String.replace "_" " "
        |> String.toLower
