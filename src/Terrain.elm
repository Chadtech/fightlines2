module Terrain exposing (label)

import Api.Enum.Terrain as Terrain exposing (Terrain)


label : Terrain -> String
label terrain =
    case terrain of
        Terrain.GrassPlain ->
            "grass plain"

        Terrain.Hills ->
            "hills"

        Terrain.Forest ->
            "forest"
