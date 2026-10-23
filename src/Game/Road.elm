module Game.Road exposing
    ( RoadShape(..)
    , connections
    , fromConnections
    , label
    )

import Api.Enum.Direction as Direction exposing (Direction)


{-| Authored road geometry, shared by the editor and renderer.
-}
type RoadShape
    = NorthSouth
    | EastWest
    | NorthEast
    | SouthEast
    | SouthWest
    | NorthWest
    | NorthEastSouth
    | EastSouthWest
    | NorthSouthWest
    | NorthEastWest
    | Crossroads


connections : RoadShape -> List Direction
connections shape =
    case shape of
        NorthSouth ->
            [ Direction.North, Direction.South ]

        EastWest ->
            [ Direction.East, Direction.West ]

        NorthEast ->
            [ Direction.North, Direction.East ]

        SouthEast ->
            [ Direction.East, Direction.South ]

        SouthWest ->
            [ Direction.South, Direction.West ]

        NorthWest ->
            [ Direction.North, Direction.West ]

        NorthEastSouth ->
            [ Direction.North, Direction.East, Direction.South ]

        EastSouthWest ->
            [ Direction.East, Direction.South, Direction.West ]

        NorthSouthWest ->
            [ Direction.North, Direction.South, Direction.West ]

        NorthEastWest ->
            [ Direction.North, Direction.East, Direction.West ]

        Crossroads ->
            [ Direction.North, Direction.East, Direction.South, Direction.West ]


{-| The editor resolves neighbors once, storing the resulting road shape.
Isolated tiles and dead ends use a straight segment along their available axis.
-}
fromConnections : List Direction -> RoadShape
fromConnections directions =
    let
        ordered : List Direction
        ordered =
            [ Direction.North, Direction.East, Direction.South, Direction.West ]
                |> List.filter (\direction -> List.member direction directions)
    in
    case ordered of
        [ Direction.East ] ->
            EastWest

        [ Direction.West ] ->
            EastWest

        [ Direction.East, Direction.West ] ->
            EastWest

        [ Direction.North, Direction.East ] ->
            NorthEast

        [ Direction.East, Direction.South ] ->
            SouthEast

        [ Direction.South, Direction.West ] ->
            SouthWest

        [ Direction.North, Direction.West ] ->
            NorthWest

        [ Direction.North, Direction.East, Direction.South ] ->
            NorthEastSouth

        [ Direction.East, Direction.South, Direction.West ] ->
            EastSouthWest

        [ Direction.North, Direction.South, Direction.West ] ->
            NorthSouthWest

        [ Direction.North, Direction.East, Direction.West ] ->
            NorthEastWest

        [ Direction.North, Direction.East, Direction.South, Direction.West ] ->
            Crossroads

        _ ->
            NorthSouth


label : RoadShape -> String
label shape =
    case shape of
        NorthSouth ->
            "north–south"

        EastWest ->
            "east–west"

        NorthEast ->
            "north–east"

        SouthEast ->
            "south–east"

        SouthWest ->
            "south–west"

        NorthWest ->
            "north–west"

        NorthEastSouth ->
            "north–east–south"

        EastSouthWest ->
            "east–south–west"

        NorthSouthWest ->
            "north–south–west"

        NorthEastWest ->
            "north–east–west"

        Crossroads ->
            "crossroads"
