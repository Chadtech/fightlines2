module Admin.Page.Dashboard.Analytics.Record exposing
    ( Record
    , receiptLabel
    , selection
    , title
    )

import Api.Object
import Api.Object.AnalyticsRecord as RecordApi
import Graphql.SelectionSet as SS exposing (SelectionSet)
import LocalTime
import Time


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


receiptLabel : Time.Zone -> Record -> String
receiptLabel zone record =
    LocalTime.timestampLabel zone record.receivedAt ++ " · server v" ++ record.version
