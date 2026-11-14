module Admin.Page.Dashboard.Analytics.QueryResults exposing
    ( QueryResults
    , request
    )

import Admin.Page.Dashboard.Analytics.Cursor as Cursor exposing (Cursor)
import Admin.Page.Dashboard.Analytics.Location as Location exposing (Location)
import Admin.Page.Dashboard.Analytics.Log as Log exposing (Log)
import Admin.Page.Dashboard.Analytics.LogId as LogId exposing (LogId)
import Admin.Page.Dashboard.Analytics.Record as Record exposing (Record)
import Api.Object.AnalyticsPage as PageApi
import Api.Query
import ApiRequest
import Graphql.Http
import Graphql.SelectionSet as SS


type alias QueryResults =
    { logs : List Log
    , selectedLog : Maybe LogId
    , records : List Record
    , unreadable : Int
    , older : Maybe Cursor
    }


request : Location -> Graphql.Http.Request QueryResults
request location =
    SS.succeed QueryResults
        |> SS.with (PageApi.logs Log.selection)
        |> SS.with (SS.map (Maybe.map LogId.fromString) PageApi.selectedLog)
        |> SS.with (PageApi.records Record.selection)
        |> SS.with PageApi.unreadable
        |> SS.with (SS.map (Maybe.map Cursor.fromString) PageApi.older)
        |> Api.Query.adminAnalytics (Location.arguments location)
        |> ApiRequest.queryRequest
