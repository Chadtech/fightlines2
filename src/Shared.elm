module Shared exposing
    ( Model
    , addError
    , init
    , setSeed
    )

import Browser.Navigation as Navigation
import Error exposing (Error)
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Random
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
    , isProduction : Bool
    , operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , seed : Random.Seed
    , errors : List Error
    }


init : Bool -> Random.Seed -> OperatingSystem -> LocalStorage -> Url -> Navigation.Key -> Model
init isProduction seed operatingSystem localStorage url key =
    { key = key
    , isProduction = isProduction
    , operatingSystem = operatingSystem
    , localStorage = localStorage
    , seed = seed
    , errors = []
    , origin =
        Url.toString
            { url
                | path = ""
                , query = Nothing
                , fragment = Nothing
            }
    }


setSeed : Random.Seed -> Model -> Model
setSeed seed model =
    { model | seed = seed }


addError : Maybe Error -> Model -> Model
addError maybeError model =
    case maybeError of
        Just error ->
            { model | errors = error :: model.errors }

        Nothing ->
            model
