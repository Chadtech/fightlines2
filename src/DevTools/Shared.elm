module DevTools.Shared exposing
    ( Model
    , Msg
    , addError
    , audioMuteButtonClicked
    , devPanelErrors
    , devPanelMsg
    , gotFromJsError
    , init
    , keyCommands
    , listeners
    , setSeed
    , update
    )

import Audio
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



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Browser state shared by the DevTools pages.
-}
type alias Model =
    Shared.Model {}


type alias Msg =
    Shared.Msg



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Random.Seed -> OperatingSystem -> LocalStorage -> Navigation.Key -> Model
init seed operatingSystem localStorage key =
    let
        ( audioMute, muteError ) =
            Audio.loadMutePreference localStorage
    in
    { key = key
    , operatingSystem = operatingSystem
    , localStorage = localStorage
    , seed = seed
    , errors = ErrorHistory.init
    , devPanel = DevPanel.init
    , devPanelOpen = False
    , audioMute = audioMute
    }
        |> Shared.addError muteError



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


audioMuteButtonClicked : Msg
audioMuteButtonClicked =
    Shared.audioMuteButtonClicked


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


update : Msg -> Model -> ( Model, Eff Msg )
update =
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
