module Unit.Supplies exposing
    ( Supplies
    , selection
    )

import Api.Object
import Api.Object.Supplies as SuppliesApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Supplies =
    { current : Int
    , maximum : Int
    , upkeepPerTurn : Int
    , movementPerTile : Int
    }


selection : SelectionSet Supplies Api.Object.Supplies
selection =
    SS.succeed Supplies
        |> SS.with SuppliesApi.current
        |> SS.with SuppliesApi.maximum
        |> SS.with SuppliesApi.upkeepPerTurn
        |> SS.with SuppliesApi.movementPerTile
