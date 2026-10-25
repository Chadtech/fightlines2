module Shared exposing
    ( Model
    , Msg
    , addError
    , gotFromJsError
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



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Shared browser state and diagnostics. Each app supplies its additional fields.
-}
type alias Model fields =
    { fields
        | key : Navigation.Key
        , operatingSystem : OperatingSystem
        , localStorage : LocalStorage
        , seed : Random.Seed
        , errors : ErrorHistory.Model Error
    }


type Msg
    = GotLocalstorage LocalStorage
    | GotFromJsError FromJs.Error



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


gotFromJsError : FromJs.Error -> Msg
gotFromJsError =
    GotFromJsError


setSeed : Random.Seed -> Model fields -> Model fields
setSeed seed model =
    { model | seed = seed }


addError : Maybe Error -> Model fields -> Model fields
addError maybeError model =
    { model | errors = ErrorHistory.add maybeError model.errors }



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model fields -> Model fields
update msg model =
    case msg of
        GotLocalstorage localStorage ->
            { model | localStorage = localStorage }

        GotFromJsError error ->
            addError (Just (Error.FromJsFailed error)) model



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


listeners : FromJs.Listener Msg
listeners =
    FromJs.data
        "local storage changed"
        LocalStorage.decoder
        GotLocalstorage
