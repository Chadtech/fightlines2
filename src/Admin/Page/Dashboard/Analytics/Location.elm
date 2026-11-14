module Admin.Page.Dashboard.Analytics.Location exposing
    ( Location
    , arguments
    , cursors
    , forLog
    , latest
    )

import Admin.Page.Dashboard.Analytics.Cursor as Cursor exposing (Cursor)
import Admin.Page.Dashboard.Analytics.LogId as LogId exposing (LogId)
import Api.Query
import Graphql.OptionalArgument as Optional


type Location
    = Latest
    | LogPage LogId (List Cursor)


latest : Location
latest =
    Latest


forLog : LogId -> List Cursor -> Location
forLog =
    LogPage


cursors : Location -> List Cursor
cursors location =
    case location of
        Latest ->
            []

        LogPage _ history ->
            history


arguments :
    Location
    -> Api.Query.AdminAnalyticsOptionalArguments
    -> Api.Query.AdminAnalyticsOptionalArguments
arguments location defaults =
    case location of
        Latest ->
            defaults

        LogPage id history ->
            let
                before : Optional.OptionalArgument String
                before =
                    case history of
                        cursor :: _ ->
                            Optional.Present (Cursor.toString cursor)

                        [] ->
                            Optional.Absent
            in
            { logId = Optional.Present (LogId.toString id)
            , before = before
            }
