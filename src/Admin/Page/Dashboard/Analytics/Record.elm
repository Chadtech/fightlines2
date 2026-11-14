module Admin.Page.Dashboard.Analytics.Record exposing
    ( Record
    , receiptLabel
    , selection
    , title
    )

import Api.Object
import Api.Object.AnalyticsRecord as RecordApi
import Game.Archive as Archive
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Record =
    { name : String
    , page : Maybe String
    , data : String
    , version : String
    , receivedAt : String
    }


selection : SelectionSet Record Api.Object.AnalyticsRecord
selection =
    SS.succeed Record
        |> SS.with RecordApi.name
        |> SS.with RecordApi.page
        |> SS.with RecordApi.data
        |> SS.with RecordApi.version
        |> SS.with RecordApi.receivedAt


title : Record -> String
title record =
    case record.page of
        Just page ->
            record.name ++ " · " ++ page

        Nothing ->
            record.name


receiptLabel : Record -> String
receiptLabel record =
    Archive.startedAtLabel record.receivedAt ++ " · server v" ++ record.version
