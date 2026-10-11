module Coordinate exposing (Coordinate, selection)

import Api.Object
import Api.Object.Coordinate as CoordinateApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Coordinate =
    { x : Int
    , y : Int
    }


selection : SelectionSet Coordinate Api.Object.Coordinate
selection =
    SS.succeed Coordinate
        |> SS.with CoordinateApi.x
        |> SS.with CoordinateApi.y
