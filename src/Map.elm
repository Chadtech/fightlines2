module Map exposing
    ( Map
    , selection
    , terrainAt
    )

import Api.Enum.MapTheme exposing (MapTheme)
import Api.Enum.Terrain exposing (Terrain)
import Api.Object
import Api.Object.Map as MapApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
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


selection : SelectionSet Map Api.Object.Map
selection =
    SS.succeed Map
        |> SS.with MapApi.width
        |> SS.with MapApi.height
        |> SS.with MapApi.baseTile
        |> SS.with MapApi.theme
        |> SS.with (MapApi.features TerrainFeature.selection)
