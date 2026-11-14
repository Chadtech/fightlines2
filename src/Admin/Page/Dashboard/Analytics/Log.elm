module Admin.Page.Dashboard.Analytics.Log exposing
    ( Log
    , label
    , selection
    )

import Admin.Page.Dashboard.Analytics.LogId as LogId exposing (LogId)
import Api.Object
import Api.Object.AnalyticsLog as LogApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Log =
    { id : LogId
    , day : String
    , source : String
    }


selection : SelectionSet Log Api.Object.AnalyticsLog
selection =
    SS.succeed Log
        |> SS.with (SS.map LogId.fromString LogApi.id)
        |> SS.with LogApi.day
        |> SS.with LogApi.source


label : Log -> String
label log =
    log.day ++ " utc · " ++ log.source
