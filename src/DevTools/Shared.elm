module DevTools.Shared exposing
    ( Model
    , Msg
    , addError
    , gotFromJsError
    , init
    , listeners
    , setSeed
    , update
    )

import Browser.Navigation as Navigation
import Error exposing (Error)
import ErrorHistory
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
    { key = key
    , operatingSystem = operatingSystem
    , localStorage = localStorage
    , seed = seed
    , errors = ErrorHistory.init
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


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


update : Msg -> Model -> Model
update =
    Shared.update



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


listeners : FromJs.Listener Shared.Msg
listeners =
    Shared.listeners
