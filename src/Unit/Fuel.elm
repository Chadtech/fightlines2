module Unit.Fuel exposing
    ( Fuel
    , selection
    )

import Api.Object
import Api.Object.Fuel as FuelApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Fuel =
    { current : Int
    , maximum : Int
    }


selection : SelectionSet Fuel Api.Object.Fuel
selection =
    SS.succeed Fuel
        |> SS.with FuelApi.current
        |> SS.with FuelApi.maximum
