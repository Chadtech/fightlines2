module Game.SpriteFacing exposing
    ( alongPath
    , turn
    )

import Api.Enum.Direction as Direction exposing (Direction)
import Api.Enum.SpriteFacing as SpriteFacingEnum exposing (SpriteFacing)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Direction as Direction


turn : Maybe Direction -> SpriteFacing -> SpriteFacing
turn direction facing =
    case direction of
        Just Direction.West ->
            SpriteFacingEnum.Left

        Just Direction.East ->
            SpriteFacingEnum.Right

        _ ->
            facing


alongPath : List Coordinate -> SpriteFacing -> SpriteFacing
alongPath path facing =
    case path of
        from :: to :: remaining ->
            alongPath (to :: remaining) (turn (Direction.between from to) facing)

        _ ->
            facing
