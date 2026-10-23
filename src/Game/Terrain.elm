module Game.Terrain exposing
    ( Terrain(..)
    , all
    , fromApi
    , isRoad
    , label
    , toApi
    )

import Api.Enum.Terrain as TerrainApi
import Game.Road as Road exposing (RoadShape)


type Terrain
    = Plain
    | Hills
    | Forest
    | Mountains
    | Water
    | Beach
    | Road RoadShape


{-| Terrain choices without a shape parameter. Roads use the editor's road brush.
-}
all : List Terrain
all =
    [ Plain
    , Hills
    , Forest
    , Mountains
    , Water
    , Beach
    ]


{-| Keep the generated flat enum at the API boundary.
-}
fromApi : TerrainApi.Terrain -> Terrain
fromApi terrain =
    case terrain of
        TerrainApi.Plain ->
            Plain

        TerrainApi.Hills ->
            Hills

        TerrainApi.Forest ->
            Forest

        TerrainApi.Mountains ->
            Mountains

        TerrainApi.Water ->
            Water

        TerrainApi.Beach ->
            Beach

        TerrainApi.RoadNorthSouth ->
            Road Road.NorthSouth

        TerrainApi.RoadEastWest ->
            Road Road.EastWest

        TerrainApi.RoadNorthEast ->
            Road Road.NorthEast

        TerrainApi.RoadSouthEast ->
            Road Road.SouthEast

        TerrainApi.RoadSouthWest ->
            Road Road.SouthWest

        TerrainApi.RoadNorthWest ->
            Road Road.NorthWest

        TerrainApi.RoadNorthEastSouth ->
            Road Road.NorthEastSouth

        TerrainApi.RoadEastSouthWest ->
            Road Road.EastSouthWest

        TerrainApi.RoadNorthSouthWest ->
            Road Road.NorthSouthWest

        TerrainApi.RoadNorthEastWest ->
            Road Road.NorthEastWest

        TerrainApi.RoadCrossroads ->
            Road Road.Crossroads


toApi : Terrain -> TerrainApi.Terrain
toApi terrain =
    case terrain of
        Plain ->
            TerrainApi.Plain

        Hills ->
            TerrainApi.Hills

        Forest ->
            TerrainApi.Forest

        Mountains ->
            TerrainApi.Mountains

        Water ->
            TerrainApi.Water

        Beach ->
            TerrainApi.Beach

        Road shape ->
            case shape of
                Road.NorthSouth ->
                    TerrainApi.RoadNorthSouth

                Road.EastWest ->
                    TerrainApi.RoadEastWest

                Road.NorthEast ->
                    TerrainApi.RoadNorthEast

                Road.SouthEast ->
                    TerrainApi.RoadSouthEast

                Road.SouthWest ->
                    TerrainApi.RoadSouthWest

                Road.NorthWest ->
                    TerrainApi.RoadNorthWest

                Road.NorthEastSouth ->
                    TerrainApi.RoadNorthEastSouth

                Road.EastSouthWest ->
                    TerrainApi.RoadEastSouthWest

                Road.NorthSouthWest ->
                    TerrainApi.RoadNorthSouthWest

                Road.NorthEastWest ->
                    TerrainApi.RoadNorthEastWest

                Road.Crossroads ->
                    TerrainApi.RoadCrossroads


isRoad : Terrain -> Bool
isRoad terrain =
    case terrain of
        Road _ ->
            True

        _ ->
            False


label : Terrain -> String
label terrain =
    case terrain of
        Plain ->
            "plain"

        Hills ->
            "hills"

        Forest ->
            "forest"

        Mountains ->
            "mountains"

        Water ->
            "water"

        Beach ->
            "beach"

        Road shape ->
            "road · " ++ Road.label shape
