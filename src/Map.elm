module Map exposing (Map, terrainAt)

import Api.Enum.MapTheme exposing (MapTheme)
import Api.Enum.Terrain exposing (Terrain)
import Coordinate exposing (Coordinate)
import ListUtil
import TerrainFeature exposing (TerrainFeature)


type alias Map =
    { width : Int
    , height : Int
    , baseTile : Terrain
    , theme : MapTheme
    , features : List TerrainFeature
    }


terrainAt : Map -> Coordinate -> Terrain
terrainAt map position =
    map.features
        |> ListUtil.find (\feature -> feature.position == position)
        |> Maybe.map .terrain
        |> Maybe.withDefault map.baseTile
