module Game.MapId exposing (label, toString)

import Api.Scalar exposing (MapId(..))


toString : MapId -> String
toString (MapId value) =
    value


label : MapId -> String
label mapId =
    toString mapId
        |> String.replace "-" " "
        |> String.toLower
