module Unit.Supplies exposing
    ( Supplies
    , selection
    , setCurrent
    )

import Api.Object
import Api.Object.Supplies as SuppliesApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Supplies =
    { current : Int
    , maximum : Int
    , upkeepPerTurn : Int
    , roughTerrainSurcharge : Int
    , movementPerTile : Int
    }


selection : SelectionSet Supplies Api.Object.Supplies
selection =
    SS.succeed Supplies
        |> SS.with SuppliesApi.current
        |> SS.with SuppliesApi.maximum
        |> SS.with SuppliesApi.upkeepPerTurn
        |> SS.with SuppliesApi.roughTerrainSurcharge
        |> SS.with SuppliesApi.movementPerTile


setCurrent : Int -> Supplies -> Supplies
setCurrent current supplies =
    { supplies | current = current }
