module Game.Map exposing
    ( Map
    , fromFeatures
    , positions
    , selection
    , terrainAt
    , toSize
    )

import Api.Enum.MapTheme exposing (MapTheme)
import Api.Enum.Terrain exposing (Terrain)
import Api.Object
import Api.Object.Map as MapApi
import Dict exposing (Dict)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.TerrainFeature as TerrainFeature exposing (TerrainFeature)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Size exposing (Size)


type alias Map =
    { width : Int
    , height : Int
    , baseTile : Terrain
    , theme : MapTheme
    , features : Dict Coordinate.Key Terrain
    }


toSize : Map -> Size
toSize map =
    { width = map.width
    , height = map.height
    }


positions : Map -> List Coordinate
positions map =
    List.range 0 (map.height - 1)
        |> List.concatMap
            (\y ->
                List.range 0 (map.width - 1)
                    |> List.map (\x -> { x = x, y = y })
            )


terrainAt : Map -> Coordinate -> Terrain
terrainAt map position =
    Dict.get (Coordinate.key position) map.features
        |> Maybe.withDefault map.baseTile


{-| Index sparse terrain once when constructing a map. The first feature at a
coordinate wins, matching the original list lookup; absent coordinates use baseTile.
No bounds filtering is applied here, preserving lookup semantics outside the map.
-}
fromFeatures :
    { width : Int
    , height : Int
    , baseTile : Terrain
    , theme : MapTheme
    , features : List TerrainFeature
    }
    -> Map
fromFeatures source =
    { width = source.width
    , height = source.height
    , baseTile = source.baseTile
    , theme = source.theme
    , features = indexFeatures source.features
    }


indexFeatures : List TerrainFeature -> Dict Coordinate.Key Terrain
indexFeatures features =
    let
        insert : TerrainFeature -> Dict Coordinate.Key Terrain -> Dict Coordinate.Key Terrain
        insert feature indexed =
            Dict.insert (Coordinate.key feature.position) feature.terrain indexed
    in
    List.foldr insert Dict.empty features


selection : SelectionSet Map Api.Object.Map
selection =
    SS.succeed Map
        |> SS.with MapApi.width
        |> SS.with MapApi.height
        |> SS.with MapApi.baseTile
        |> SS.with MapApi.theme
        |> SS.with (SS.map indexFeatures (MapApi.features TerrainFeature.selection))
