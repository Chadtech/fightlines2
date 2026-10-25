module Fightlines.Shared exposing
    ( Model
    , Msg
    , addError
    , devPanelErrors
    , devPanelMsg
    , gotFromJsError
    , init
    , keyCommands
    , listeners
    , setSeed
    , superUpdate
    )

import Browser.Navigation as Navigation
import DevPanel
import Effect exposing (Eff)
import Error exposing (Error)
import ErrorHistory
import KeyCmd exposing (KeyCmd)
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Ports.Js.From as FromJs
import Random
import Shared
import Url
    exposing
        ( Url
        )



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Shared browser state. `origin` is the scheme, hostname, and optional port
used to turn lobby paths into complete invite URLs.
-}
type alias Model =
    Shared.Model
        { origin : String
        }


type alias Msg =
    Shared.Msg



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Random.Seed -> OperatingSystem -> LocalStorage -> Url -> Navigation.Key -> Model
init seed operatingSystem localStorage url key =
    { key = key
    , operatingSystem = operatingSystem
    , localStorage = localStorage
    , seed = seed
    , errors = ErrorHistory.init
    , devPanel = DevPanel.init
    , devPanelOpen = False
    , origin =
        Url.toString
            { url
                | path = ""
                , query = Nothing
                , fragment = Nothing
            }
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


devPanelErrors : Model -> List DevPanel.Error
devPanelErrors =
    Shared.devPanelErrors


devPanelMsg : DevPanel.Msg -> Msg
devPanelMsg =
    Shared.devPanelMsg


gotFromJsError : FromJs.Error -> Msg
gotFromJsError =
    Shared.gotFromJsError


setSeed : Random.Seed -> Model -> Model
setSeed =
    Shared.setSeed


addError : Maybe Error -> Model -> Model
addError =
    Shared.addError



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


superUpdate : Msg -> Model -> ( Model, Eff Msg )
superUpdate =
    Shared.superUpdate



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


keyCommands : KeyCmd Msg
keyCommands =
    Shared.keyCommands


listeners : FromJs.Listener Shared.Msg
listeners =
    Shared.listeners
