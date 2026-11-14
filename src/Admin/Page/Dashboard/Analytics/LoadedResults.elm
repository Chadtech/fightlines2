module Admin.Page.Dashboard.Analytics.LoadedResults exposing
    ( LoadedResults
    , init
    , key
    , newer
    , older
    , results
    )

import Admin.Page.Dashboard.Analytics.Cursor exposing (Cursor)
import Admin.Page.Dashboard.Analytics.Location as Location exposing (Location)
import Admin.Page.Dashboard.Analytics.QueryResults exposing (QueryResults)
import Admin.Page.Dashboard.Analytics.RequestId as RequestId exposing (RequestId)


type LoadedResults
    = LoadedResults
        { results : QueryResults
        , cursors : List Cursor
        , requestId : RequestId
        }


init : RequestId -> Location -> QueryResults -> LoadedResults
init requestId location queryResults =
    LoadedResults
        { results = queryResults
        , cursors = Location.cursors location
        , requestId = requestId
        }


results : LoadedResults -> QueryResults
results (LoadedResults loaded) =
    loaded.results


key : LoadedResults -> String
key (LoadedResults loaded) =
    RequestId.toString loaded.requestId


newer : LoadedResults -> Maybe Location
newer (LoadedResults loaded) =
    case
        ( loaded.results.selectedLog
        , loaded.cursors
        )
    of
        ( Just log, _ :: rest ) ->
            Just (Location.forLog log rest)

        _ ->
            Nothing


older : LoadedResults -> Maybe Location
older (LoadedResults loaded) =
    case
        ( loaded.results.selectedLog
        , loaded.results.older
        )
    of
        ( Just log, Just cursor ) ->
            Just
                (Location.forLog log (cursor :: loaded.cursors))

        _ ->
            Nothing
