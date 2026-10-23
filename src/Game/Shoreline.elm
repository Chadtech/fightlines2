module Game.Shoreline exposing
    ( Bank(..)
    , Corner(..)
    , Transition(..)
    , at
    )

import Api.Enum.Direction as Direction exposing (Direction)
import Game.Coordinate exposing (Coordinate)
import Game.Direction as Direction
import Game.Map as Map exposing (Map)
import Game.Terrain as Terrain exposing (Terrain)


type Bank
    = Cliff
    | Sand


type Corner
    = NorthWest
    | NorthEast
    | SouthEast
    | SouthWest


type Transition
    = BankEdge Direction Bank
    | BankCorner Corner Bank
    | GroundEdge Direction


{-| Shore artwork is derived from public terrain, never from units or visibility.
It occupies the water cell; the authored terrain and its movement rules stay intact.
-}
at : Map -> Coordinate -> List Transition
at map position =
    let
        neighbor : Direction -> Maybe Terrain
        neighbor direction =
            tileAt map (Direction.step position direction)

        edge : Direction -> Maybe Transition
        edge direction =
            neighbor direction
                |> Maybe.andThen bank
                |> Maybe.map (BankEdge direction)

        corner : Corner -> Maybe Transition
        corner location =
            let
                directions : { vertical : Direction, horizontal : Direction }
                directions =
                    cornerDirections location

                diagonal : Coordinate
                diagonal =
                    Direction.step (Direction.step position directions.vertical) directions.horizontal

                uncovered : Bool
                uncovered =
                    (neighbor directions.vertical == Just Terrain.Water)
                        && (neighbor directions.horizontal == Just Terrain.Water)
            in
            if uncovered then
                tileAt map diagonal
                    |> Maybe.andThen bank
                    |> Maybe.map (BankCorner location)

            else
                Nothing

        groundEdge : Direction -> Maybe Transition
        groundEdge direction =
            case neighbor direction |> Maybe.andThen bank of
                Just Cliff ->
                    Just (GroundEdge direction)

                _ ->
                    Nothing
    in
    case tileAt map position of
        Just Terrain.Water ->
            List.filterMap edge Direction.all
                ++ List.filterMap corner
                    [ NorthWest
                    , NorthEast
                    , SouthEast
                    , SouthWest
                    ]

        Just Terrain.Beach ->
            List.filterMap groundEdge Direction.all

        _ ->
            []


tileAt : Map -> Coordinate -> Maybe Terrain
tileAt map position =
    let
        inside : Bool
        inside =
            (position.x >= 0)
                && (position.y >= 0)
                && (position.x < map.width)
                && (position.y < map.height)
    in
    if inside then
        Just (Map.terrainAt map position)

    else
        Nothing


bank : Terrain -> Maybe Bank
bank terrain =
    case terrain of
        Terrain.Water ->
            Nothing

        Terrain.Beach ->
            Just Sand

        _ ->
            Just Cliff


cornerDirections : Corner -> { vertical : Direction, horizontal : Direction }
cornerDirections location =
    case location of
        NorthWest ->
            { vertical = Direction.North
            , horizontal = Direction.West
            }

        NorthEast ->
            { vertical = Direction.North
            , horizontal = Direction.East
            }

        SouthEast ->
            { vertical = Direction.South
            , horizontal = Direction.East
            }

        SouthWest ->
            { vertical = Direction.South
            , horizontal = Direction.West
            }
