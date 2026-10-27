module Game.Direction exposing
    ( all
    , alongPath
    , between
    , label
    , reversesPath
    , step
    )

import Api.Enum.Direction as Direction exposing (Direction)
import Game.Coordinate as Coordinate exposing (Coordinate)


all : List Direction
all =
    Direction.list


between : Coordinate -> Coordinate -> Maybe Direction
between from to =
    let
        dx : Int
        dx =
            to.x - from.x

        dy : Int
        dy =
            to.y - from.y
    in
    if dx == 0 && dy == -1 then
        Just Direction.North

    else if dx == 1 && dy == 0 then
        Just Direction.East

    else if dx == 0 && dy == 1 then
        Just Direction.South

    else if dx == -1 && dy == 0 then
        Just Direction.West

    else
        Nothing


alongPath : List Coordinate -> Maybe Direction -> Maybe Direction
alongPath path initial =
    case path of
        from :: to :: remaining ->
            alongPath (to :: remaining) (initial |> Maybe.map (\direction -> between from to |> Maybe.withDefault direction))

        _ ->
            initial


{-| Whether facing points back along the final segment of a route.
-}
reversesPath : List Coordinate -> Direction -> Bool
reversesPath path direction =
    case List.reverse path of
        destination :: previous :: _ ->
            between destination previous == Just direction

        _ ->
            False


label : Direction -> String
label direction =
    case direction of
        Direction.North ->
            "north"

        Direction.East ->
            "east"

        Direction.South ->
            "south"

        Direction.West ->
            "west"


{-| Move one tile in a cardinal direction. The caller validates map bounds.
-}
step : Coordinate -> Direction -> Coordinate
step origin direction =
    case direction of
        Direction.North ->
            origin
                |> Coordinate.setY (origin.y - 1)

        Direction.East ->
            origin
                |> Coordinate.setX (origin.x + 1)

        Direction.South ->
            origin
                |> Coordinate.setY (origin.y + 1)

        Direction.West ->
            origin
                |> Coordinate.setX (origin.x - 1)
