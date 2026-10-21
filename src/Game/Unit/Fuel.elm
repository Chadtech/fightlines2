module Game.Unit.Fuel exposing
    ( Fuel
    , selection
    , setCurrent
    )

import Api.Object
import Api.Object.Fuel as FuelApi
import Graphql.SelectionSet as SS exposing (SelectionSet)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Fuel =
    { current : Int
    , maximum : Int
    , movementPerTile : Int
    , movementPerCargoSlot : Int
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


selection : SelectionSet Fuel Api.Object.Fuel
selection =
    SS.succeed Fuel
        |> SS.with FuelApi.current
        |> SS.with FuelApi.maximum
        |> SS.with FuelApi.movementPerTile
        |> SS.with FuelApi.movementPerCargoSlot


setCurrent : Int -> Fuel -> Fuel
setCurrent current fuel =
    { fuel | current = current }
