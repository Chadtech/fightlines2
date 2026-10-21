module Game.Coordinate exposing (Coordinate, Key, inRange, key, selection)

import Api.Object
import Api.Object.Coordinate as CoordinateApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Coordinate =
    { x : Int
    , y : Int
    }


{-| A board coordinate key in (x, y) order, independent of map dimensions.
-}
type alias Key =
    ( Int, Int )


key : Coordinate -> Key
key position =
    ( position.x, position.y )


selection : SelectionSet Coordinate Api.Object.Coordinate
selection =
    SS.succeed Coordinate
        |> SS.with CoordinateApi.x
        |> SS.with CoordinateApi.y


{-| Circular tile range includes the origin and boundary.
-}
inRange : Coordinate -> Int -> Coordinate -> Bool
inRange origin range target =
    ((target.x - origin.x) ^ 2 + (target.y - origin.y) ^ 2) <= (range ^ 2)
