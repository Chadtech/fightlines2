module Shot exposing (Shot, selection)

import Api.Object
import Api.Object.Shot as ShotApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Shot =
    { origin : Coordinate
    , destination : Coordinate
    , damage : Int
    }


selection : SelectionSet Shot Api.Object.Shot
selection =
    SS.succeed Shot
        |> SS.with (ShotApi.origin Coordinate.selection)
        |> SS.with (ShotApi.destination Coordinate.selection)
        |> SS.with ShotApi.damage
