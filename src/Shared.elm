module Shared exposing
    ( Model
    , init
    )

import Browser.Navigation as Navigation
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
    }


init : OperatingSystem -> Url -> Navigation.Key -> Model
init operatingSystem url key =
    { key = key
    , operatingSystem = operatingSystem
    , origin =
        Url.toString
            { url
                | path = ""
                , query = Nothing
                , fragment = Nothing
            }
    }
