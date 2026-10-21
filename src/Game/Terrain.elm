module Game.Terrain exposing (label)

import Api.Enum.Terrain as Terrain exposing (Terrain)


label : Terrain -> String
label terrain =
    case terrain of
        Terrain.Plain ->
            "plain"

        Terrain.Hills ->
            "hills"

        Terrain.Mountains ->
            "mountains"

        Terrain.Forest ->
            "forest"
