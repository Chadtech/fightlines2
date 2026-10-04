module Shared exposing
    ( Model
    , init
    )

import Browser.Navigation as Navigation
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
    }


init : Url -> Navigation.Key -> Model
init url key =
    { key = key
    , origin =
        Url.toString
            { url
                | path = ""
                , query = Nothing
                , fragment = Nothing
            }
    }
