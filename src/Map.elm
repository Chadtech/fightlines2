module Map exposing (Map, terrainAt)

import Api.Enum.Terrain exposing (Terrain)
import Coordinate exposing (Coordinate)
import TerrainFeature exposing (TerrainFeature)


type alias Map =
    { width : Int
    , height : Int
    , baseTile : Terrain
    , features : List TerrainFeature
    }


terrainAt : Map -> Coordinate -> Terrain
terrainAt map position =
    map.features
        |> List.filter (\feature -> feature.position == position)
        |> List.head
        |> Maybe.map .terrain
        |> Maybe.withDefault map.baseTile
