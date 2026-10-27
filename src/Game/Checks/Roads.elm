port module Game.Checks.Roads exposing (main)

import Api.Enum.Direction as Direction exposing (Direction)
import Api.Enum.MapTheme as MapTheme
import Api.Enum.Terrain as TerrainApi
import EditableMap exposing (Definition)
import Game.Coordinate exposing (Coordinate)
import Game.Direction as Direction
import Game.Map as Map
import Game.Road as Road exposing (RoadShape)
import Game.Terrain as Terrain
import Platform


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \message _ -> never message
        , subscriptions = \_ -> Sub.none
        }


expect : String -> Bool -> List String
expect label passed =
    if passed then
        []

    else
        [ label ]


definition : List Coordinate -> Definition
definition positions =
    { description = "road authoring fixture"
    , width = 3
    , height = 3
    , theme = MapTheme.GreenForest
    , features = List.map (\position -> { position = position, terrain = Terrain.Road Road.NorthSouth }) positions
    , units = []
    , depots = []
    }


checks : List String
checks =
    let
        center : Coordinate
        center =
            { x = 1, y = 1 }

        cases : List { directions : List Direction, expected : RoadShape }
        cases =
            [ { directions = [], expected = Road.NorthSouth }
            , { directions = [ Direction.North ], expected = Road.NorthSouth }
            , { directions = [ Direction.East ], expected = Road.EastWest }
            , { directions = [ Direction.South ], expected = Road.NorthSouth }
            , { directions = [ Direction.West ], expected = Road.EastWest }
            , { directions = [ Direction.North, Direction.South ], expected = Road.NorthSouth }
            , { directions = [ Direction.East, Direction.West ], expected = Road.EastWest }
            , { directions = [ Direction.North, Direction.East ], expected = Road.NorthEast }
            , { directions = [ Direction.East, Direction.South ], expected = Road.SouthEast }
            , { directions = [ Direction.South, Direction.West ], expected = Road.SouthWest }
            , { directions = [ Direction.North, Direction.West ], expected = Road.NorthWest }
            , { directions = [ Direction.North, Direction.East, Direction.South ], expected = Road.NorthEastSouth }
            , { directions = [ Direction.East, Direction.South, Direction.West ], expected = Road.EastSouthWest }
            , { directions = [ Direction.North, Direction.South, Direction.West ], expected = Road.NorthSouthWest }
            , { directions = [ Direction.North, Direction.East, Direction.West ], expected = Road.NorthEastWest }
            , { directions = [ Direction.North, Direction.East, Direction.South, Direction.West ], expected = Road.Crossroads }
            ]

        checkShape : { directions : List Direction, expected : RoadShape } -> List String
        checkShape fixture =
            let
                positions : List Coordinate
                positions =
                    center :: List.map (Direction.step center) fixture.directions

                connected : Definition
                connected =
                    definition positions |> EditableMap.reconnectRoads [ center ]
            in
            expect "editor stores the expected road shape for every neighbor combination"
                (Map.terrainAt (EditableMap.map connected) center == Terrain.Road fixture.expected)
                ++ expect "road connections preserve every authored shape"
                    (Road.fromConnections (Road.connections fixture.expected) == fixture.expected)

        checkApiTerrain : TerrainApi.Terrain -> List String
        checkApiTerrain terrain =
            expect "terrain API conversion preserves every terrain and road shape"
                (Terrain.toApi (Terrain.fromApi terrain) == terrain)

        cross : Definition
        cross =
            definition (center :: List.map (Direction.step center) Direction.all)
                |> EditableMap.reconnectRoads [ center ]

        east : Coordinate
        east =
            Direction.step center Direction.East

        removed : Definition
        removed =
            (cross
                |> EditableMap.setFeatures (List.filter (\feature -> feature.position /= east) cross.features)
            )
                |> EditableMap.reconnectRoads [ east ]

        unrelated : Definition
        unrelated =
            (cross
                |> EditableMap.setFeatures
                    [ { position = { x = 0, y = 0 }, terrain = Terrain.Road Road.EastWest } ]
            )
                |> EditableMap.reconnectRoads [ { x = 2, y = 2 } ]
    in
    List.concatMap checkShape cases
        ++ List.concatMap checkApiTerrain TerrainApi.list
        ++ expect "erasing a branch updates the neighboring crossroads to a t-junction"
            (Map.terrainAt (EditableMap.map removed) center == Terrain.Road Road.NorthSouthWest)
        ++ expect "editing elsewhere preserves an authored road orientation"
            (Map.terrainAt (EditableMap.map unrelated) { x = 0, y = 0 } == Terrain.Road Road.EastWest)
        ++ expect "road connection selection ignores input order and duplicates"
            (Road.fromConnections [ Direction.West, Direction.East, Direction.East ] == Road.EastWest)
        ++ expect "ordinary terrain is not a road" (not (Terrain.isRoad Terrain.Plain))
