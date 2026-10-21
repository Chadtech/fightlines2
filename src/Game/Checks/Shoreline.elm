port module Game.Checks.Shoreline exposing (main)

import Api.Enum.Direction as Direction
import Api.Enum.MapTheme as MapTheme
import Api.Enum.Terrain as Terrain
import Game.Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.Shoreline as Shoreline exposing (Bank(..), Corner(..), Transition(..))
import Game.TerrainFeature exposing (TerrainFeature)
import Platform


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \message _ -> never message
        , subscriptions = \_ -> Sub.none
        }


board : List TerrainFeature -> Map
board features =
    Map.fromFeatures
        { width = 3
        , height = 3
        , baseTile = Terrain.Water
        , theme = MapTheme.GreenForest
        , features = features
        }


expect : String -> Bool -> List String
expect label passed =
    if passed then
        []

    else
        [ label ]


checks : List String
checks =
    let
        center : Coordinate
        center =
            { x = 1, y = 1 }

        mixed : Map
        mixed =
            board
                [ { position = { x = 1, y = 0 }, terrain = Terrain.Plain }
                , { position = { x = 2, y = 1 }, terrain = Terrain.Beach }
                , { position = { x = 1, y = 2 }, terrain = Terrain.Forest }
                , { position = { x = 0, y = 1 }, terrain = Terrain.Hills }
                ]

        mixedEdges : List Transition
        mixedEdges =
            Shoreline.at mixed center

        diagonalCases : List { position : Coordinate, corner : Corner }
        diagonalCases =
            [ { position = { x = 0, y = 0 }, corner = NorthWest }
            , { position = { x = 2, y = 0 }, corner = NorthEast }
            , { position = { x = 2, y = 2 }, corner = SouthEast }
            , { position = { x = 0, y = 2 }, corner = SouthWest }
            ]

        diagonalCheck : { position : Coordinate, corner : Corner } -> List String
        diagonalCheck fixture =
            let
                cliff : Map
                cliff =
                    board [ { position = fixture.position, terrain = Terrain.Plain } ]

                beach : Map
                beach =
                    board [ { position = fixture.position, terrain = Terrain.Beach } ]
            in
            expect "a diagonal land corner closes the shoreline without inventing an edge"
                (Shoreline.at cliff center == [ BankCorner fixture.corner Cliff ])
                ++ expect "a diagonal beach corner uses sand rather than cliffs"
                    (Shoreline.at beach center == [ BankCorner fixture.corner Sand ])

        coveredCorner : Map
        coveredCorner =
            board
                [ { position = { x = 0, y = 0 }, terrain = Terrain.Plain }
                , { position = { x = 1, y = 0 }, terrain = Terrain.Plain }
                ]

        beachIsland : Map
        beachIsland =
            board [ { position = center, terrain = Terrain.Beach } ]

        inlandBeach : Map
        inlandBeach =
            { beachIsland | baseTile = Terrain.Plain }

        adjoiningBeaches : Map
        adjoiningBeaches =
            board
                [ { position = center, terrain = Terrain.Beach }
                , { position = { x = 1, y = 0 }, terrain = Terrain.Beach }
                , { position = { x = 2, y = 1 }, terrain = Terrain.Plain }
                ]
    in
    List.concat
        [ expect "all four water edges choose the neighboring bank's terrain"
            ((List.length mixedEdges == 4)
                && List.member (BankEdge Direction.North Cliff) mixedEdges
                && List.member (BankEdge Direction.East Sand) mixedEdges
                && List.member (BankEdge Direction.South Cliff) mixedEdges
                && List.member (BankEdge Direction.West Cliff) mixedEdges
            )
        , expect "open water and map borders have no invented shoreline"
            (List.all (\position -> Shoreline.at (board []) position == []) (Map.positions (board [])))
        , List.concatMap diagonalCheck diagonalCases
        , expect "an existing edge covers its adjoining diagonal corner"
            (Shoreline.at coveredCorner center == [ BankEdge Direction.North Cliff ])
        , expect "a beach surrounded by water has no grassy fringe or cliffs"
            (Shoreline.at beachIsland center == [])
        , expect "an inland beach blends into all four land neighbors"
            (List.length (Shoreline.at inlandBeach center) == 4)
        , expect "adjacent beaches remain continuous while land gets a fringe"
            (Shoreline.at adjoiningBeaches center == [ GroundEdge Direction.East ])
        , expect "land does not duplicate the shoreline already rendered on water"
            (Shoreline.at { inlandBeach | baseTile = Terrain.Forest } { x = 0, y = 0 } == [])
        ]
