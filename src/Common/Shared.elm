module Common.Shared exposing
    ( Model
    , Msg
    , addError
    , gotFromJsError
    , listeners
    , setSeed
    , update
    )

import Browser.Navigation as Navigation
import ErrorHistory
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Ports.Js.From as FromJs
import Random



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Common browser state. Each app chooses its diagnostics and additional fields.
-}
type alias Model error fields =
    { fields
        | key : Navigation.Key
        , operatingSystem : OperatingSystem
        , localStorage : LocalStorage
        , seed : Random.Seed
        , errors : ErrorHistory.Model error
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


setSeed : Random.Seed -> Model error fields -> Model error fields
setSeed seed model =
    { model | seed = seed }


addError : Maybe error -> Model error fields -> Model error fields
addError maybeError model =
    { model | errors = ErrorHistory.add maybeError model.errors }



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : (FromJs.Error -> error) -> Msg -> Model error fields -> Model error fields
update fromJsError msg model =
    case msg of
        GotLocalstorage localStorage ->
            { model | localStorage = localStorage }

        GotFromJsError error ->
            addError (Just (fromJsError error)) model



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


listeners : FromJs.Listener Msg
listeners =
    FromJs.data
        "local storage changed"
        LocalStorage.decoder
        GotLocalstorage
