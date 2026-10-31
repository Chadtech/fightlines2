module Shared exposing
    ( Model
    , Msg
    , addError
    , audioMuteButtonClicked
    , devPanelErrors
    , devPanelMsg
    , gotFromJsError
    , keyCommands
    , listeners
    , setSeed
    , superUpdate
    )

import Audio
import Browser.Dom
import Browser.Navigation as Navigation
import DevPanel
import Effect as E exposing (Eff)
import Error exposing (Error)
import ErrorHistory
import Game.DirectionPlanning as DirectionPlanning
import Game.IndirectFirePlanning as IndirectFirePlanning
import Game.OrderDependencies as OrderDependencies
import Game.OrderPlanning as OrderPlanning
import Game.PlannedTransport as PlannedTransport
import Game.PlayerNumber as PlayerNumber
import Game.UnitId as UnitId
import Json.Decode as Decode
import KeyCmd exposing (KeyCmd)
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Ports.Js.From as FromJs
import Ports.Js.To as ToJs
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
        , devPanel : DevPanel.Model
        , devPanelOpen : Bool
        , audioMute : Audio.MuteState
    }


type Msg
    = GotLocalstorage LocalStorage
    | GotFromJsError FromJs.Error
    | AudioErrorReceived Error
    | DevPanelToggleKeyPressed
    | DevPanelMsg DevPanel.Msg
    | AudioMuteButtonClicked



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


audioMuteButtonClicked : Msg
audioMuteButtonClicked =
    AudioMuteButtonClicked


devPanelErrors : Model fields -> List DevPanel.Error
devPanelErrors model =
    List.map toDevPanelError model.errors.errors


devPanelMsg : DevPanel.Msg -> Msg
devPanelMsg =
    DevPanelMsg


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
-- HELPERS --
----------------------------------------------------------------


audioErrorDecoder : Decode.Decoder Error
audioErrorDecoder =
    Decode.map2
        (\operation details -> Error.AudioFailed { operation = operation, details = details })
        (Decode.field "operation" Decode.string)
        (Decode.field "details" Decode.string)


setDevPanelOpen : Bool -> Model fields -> Model fields
setDevPanelOpen devPanelOpen model =
    { model | devPanelOpen = devPanelOpen }


toDevPanelError : Error -> DevPanel.Error
toDevPanelError error =
    case error of
        Error.TestError ->
            DevPanel.Error
                { title = "test error"
                , details = "this error was added with the test error button."
                }

        Error.LocalStorageDecodeFailed failure ->
            DevPanel.Error
                { title = "local storage decode failed"
                , details = failure.key ++ ": " ++ Decode.errorToString failure.error
                }

        Error.UnitOwnerNotFound missing ->
            DevPanel.Error
                { title = "unit owner not found"
                , details = "unit " ++ UnitId.toString missing.unitId ++ " · " ++ PlayerNumber.label missing.playerNumber
                }

        Error.FromJsFailed failure ->
            DevPanel.Error
                { title = "javascript message failed"
                , details = FromJs.errorToString failure
                }

        Error.AudioFailed failure ->
            DevPanel.Error
                { title = "audio " ++ failure.operation
                , details = failure.details
                }

        Error.ElementFocusFailed failure ->
            DevPanel.Error
                { title = "element focus failed"
                , details = domErrorDetails failure
                }

        Error.BattlefieldMeasurementFailed failure ->
            DevPanel.Error
                { title = "battlefield measurement failed"
                , details = domErrorDetails failure
                }

        Error.OrderPlanningInvariantViolated violation ->
            DevPanel.Error
                { title = "order planning invariant violated"
                , details = planningErrorDetails violation
                }


domErrorDetails : Browser.Dom.Error -> String
domErrorDetails failure =
    case failure of
        Browser.Dom.NotFound elementHtmlId ->
            "could not find element \"" ++ elementHtmlId ++ "\"."


planningErrorDetails : OrderPlanning.InvariantViolation -> String
planningErrorDetails violation =
    case violation of
        OrderPlanning.PlanningUnitNotFound unitId ->
            "planning unit not found: " ++ UnitId.toString unitId

        OrderPlanning.CommandUnitHasNoPosition unitId ->
            "command unit has no position: " ++ UnitId.toString unitId

        OrderPlanning.LoadingOrderNotFound unitId ->
            "loading order not found: " ++ UnitId.toString unitId

        OrderPlanning.TransportInvariantViolated transport ->
            case transport of
                PlannedTransport.CarrierNotFound missing ->
                    "carrier " ++ UnitId.toString missing.carrierId ++ " not found for passenger " ++ UnitId.toString missing.passengerId

                PlannedTransport.CarrierNotOnMap missing ->
                    "carrier " ++ UnitId.toString missing.carrierId ++ " not on map for passenger " ++ UnitId.toString missing.passengerId

                PlannedTransport.ReceiverHasNoPosition unitId ->
                    "receiver has no position: " ++ UnitId.toString unitId

        OrderPlanning.OrderDependenciesInvariantViolated dependency ->
            case dependency of
                OrderDependencies.OrderUnitNotFound unitId ->
                    "order unit not found: " ++ UnitId.toString unitId

        OrderPlanning.DirectionInvariantViolated direction ->
            case direction of
                DirectionPlanning.CommandUnitNotOnMap unitId ->
                    "direction command unit not on map: " ++ UnitId.toString unitId

        OrderPlanning.IndirectFireInvariantViolated indirectFire ->
            case indirectFire of
                IndirectFirePlanning.CommandUnitNotOnMap unitId ->
                    "indirect fire command unit not on map: " ++ UnitId.toString unitId



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


{-| Check shared transitions after every shared message. Page dialog restoration
belongs to each app; Shared only opens its own dev panel.
-}
superUpdate : Msg -> Model fields -> ( Model fields, Eff Msg )
superUpdate msg model =
    let
        ( updated, effect ) =
            update msg model

        panelOpened : Bool
        panelOpened =
            not model.devPanelOpen && updated.devPanelOpen

        result : ( Model fields, Eff Msg )
        result =
            ( updated, effect )
    in
    if panelOpened then
        result
            |> E.and (E.toJs (ToJs.OpenDialog { htmlId = DevPanel.htmlId }))

    else
        result


update : Msg -> Model fields -> ( Model fields, Eff Msg )
update msg model =
    case msg of
        AudioMuteButtonClicked ->
            let
                audioMute : Audio.MuteState
                audioMute =
                    Audio.toggleMute model.audioMute
            in
            ( { model | audioMute = audioMute }
            , E.batch
                [ E.audio (Audio.SetMute audioMute)
                , E.toJs (ToJs.SetLocalStorage (Audio.encodeMutePreference audioMute))
                ]
            )

        DevPanelToggleKeyPressed ->
            ( model
                |> setDevPanelOpen (not model.devPanelOpen)
            , E.none
            )

        DevPanelMsg panelMsg ->
            case panelMsg of
                DevPanel.Canceled ->
                    ( model
                        |> setDevPanelOpen False
                    , E.none
                    )

                DevPanel.TabClicked tab ->
                    let
                        panel : DevPanel.Model
                        panel =
                            model.devPanel
                    in
                    ( { model | devPanel = { panel | selectedTab = tab } }, E.none )

                DevPanel.TestErrorButtonClicked ->
                    ( addError (Just Error.TestError) model, E.none )

        GotLocalstorage localStorage ->
            let
                ( audioMute, muteError ) =
                    Audio.loadMutePreference localStorage

                effect : Eff Msg
                effect =
                    if audioMute == model.audioMute then
                        E.none

                    else
                        E.audio (Audio.SetMute audioMute)
            in
            ( { model | localStorage = localStorage, audioMute = audioMute }
                |> addError muteError
            , effect
            )

        GotFromJsError error ->
            ( addError (Just (Error.FromJsFailed error)) model, E.none )

        AudioErrorReceived error ->
            ( addError (Just error) model, E.none )



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


keyCommands : KeyCmd Msg
keyCommands =
    KeyCmd.backQuote DevPanelToggleKeyPressed


listeners : FromJs.Listener Msg
listeners =
    FromJs.batch
        [ FromJs.data
            "local storage changed"
            LocalStorage.decoder
            GotLocalstorage
        , FromJs.data
            "audio error"
            audioErrorDecoder
            AudioErrorReceived
        ]
