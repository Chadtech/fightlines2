module Admin.Page.Dashboard.Analytics.LogId exposing
    ( LogId
    , fromString
    , toString
    )


type LogId
    = LogId String


fromString : String -> LogId
fromString =
    LogId


toString : LogId -> String
toString (LogId value) =
    value
