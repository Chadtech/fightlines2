module Unit.HitPoints exposing
    ( HitPoints
    , selection
    )

import Api.Object
import Api.Object.HitPoints as HitPointsApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias HitPoints =
    { current : Int
    , maximum : Int
    }


selection : SelectionSet HitPoints Api.Object.HitPoints
selection =
    SS.succeed HitPoints
        |> SS.with HitPointsApi.current
        |> SS.with HitPointsApi.maximum
