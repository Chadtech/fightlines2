module Admin.Page.Dashboard.Analytics.Cursor exposing
    ( Cursor
    , fromString
    , toString
    )


type Cursor
    = Cursor String


fromString : String -> Cursor
fromString =
    Cursor


toString : Cursor -> String
toString (Cursor value) =
    value
