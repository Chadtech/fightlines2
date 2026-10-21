module Game.Unit.HitPoints exposing
    ( HitPoints
    , selection
    , setCurrent
    )

import Api.Object
import Api.Object.HitPoints as HitPointsApi
import Graphql.SelectionSet as SS exposing (SelectionSet)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias HitPoints =
    { current : Int
    , maximum : Int
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


selection : SelectionSet HitPoints Api.Object.HitPoints
selection =
    SS.succeed HitPoints
        |> SS.with HitPointsApi.current
        |> SS.with HitPointsApi.maximum


setCurrent : Int -> HitPoints -> HitPoints
setCurrent current hitPoints =
    { hitPoints | current = current }
