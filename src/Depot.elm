module Depot exposing
    ( Depot
    , selection
    )

import Api.Object
import Api.Object.Depot as DepotApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Supply


type alias Depot =
    { position : Coordinate
    , stock : Maybe Supply.Stock
    }


selection : SelectionSet Depot Api.Object.Depot
selection =
    SS.succeed Depot
        |> SS.with (DepotApi.position Coordinate.selection)
        |> SS.with (DepotApi.stock Supply.stockSelection)
