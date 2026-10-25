module DevTools.Shared exposing
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


{-| Browser state shared by the DevTools pages.
-}
type alias Model =
    { key : Navigation.Key
    , operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , seed : Random.Seed
    , errors : List Error
    }


init : Random.Seed -> OperatingSystem -> LocalStorage -> Navigation.Key -> Model
init seed operatingSystem localStorage key =
    { key = key
    , operatingSystem = operatingSystem
    , localStorage = localStorage
    , seed = seed
    , errors = []
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
