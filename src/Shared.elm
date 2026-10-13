module Shared exposing
    ( Model
    , addError
    , init
    )

import Browser.Navigation as Navigation
import Error exposing (Error)
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Url
    exposing
        ( Url
        )


{-| Shared browser state. `origin` is the scheme, hostname, and optional port
used to turn lobby paths into complete invite URLs.
-}
type alias Model =
    { key : Navigation.Key
    , origin : String
    , operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , errors : List Error
    }


init : OperatingSystem -> LocalStorage -> Url -> Navigation.Key -> Model
init operatingSystem localStorage url key =
    { key = key
    , operatingSystem = operatingSystem
    , localStorage = localStorage
    , errors = []
    , origin =
        Url.toString
            { url
                | path = ""
                , query = Nothing
                , fragment = Nothing
            }
    }


addError : Maybe Error -> Model -> Model
addError maybeError model =
    case maybeError of
        Just error ->
            { model | errors = error :: model.errors }

        Nothing ->
            model
