module Direction exposing (alongPath, between)

import Api.Enum.Direction as Direction exposing (Direction)
import Coordinate exposing (Coordinate)


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


alongPath : List Coordinate -> Direction -> Direction
alongPath path initial =
    case path of
        from :: to :: remaining ->
            alongPath (to :: remaining) (between from to |> Maybe.withDefault initial)

        _ ->
            initial
