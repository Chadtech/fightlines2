module Shared exposing
    ( Model
    , Msg
    , adaptDialog
    , addError
    , audioMuteButtonClicked
    , devPanelErrors
    , devPanelMsg
    , gotFromJsError
    , init
    , isMobileView
    , keyCommands
    , listeners
    , planningErrorDetails
    , setAudioMute
    , setAudioVolumes
    , setDevPanelOpen
    , setSeed
    , subscriptions
    , superUpdate
    )

import ApiRequest
import Audio
import Browser.Dom
import Browser.Events
import Browser.Navigation as Navigation
import Deployment
import DevPanel
import Effect as E exposing (Eff)
import Error exposing (Error)
import ErrorHistory
import Features
import Game.DirectionPlanning as DirectionPlanning
import Game.IndirectFirePlanning as IndirectFirePlanning
import Game.Movement as Movement
import Game.OrderDependencies as OrderDependencies
import Game.OrderPlanning as OrderPlanning
import Game.PlannedTransport as PlannedTransport
import Game.PlayerNumber as PlayerNumber
import Game.TurnPlayback as TurnPlayback
import Game.UnitId as UnitId
import Game.UnitKind as UnitKind
import Json.Decode as Decode
import KeyCmd exposing (KeyCmd)
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Ports.Js.From as FromJs
import Ports.Js.To as ToJs
import Random
import ScreenSize exposing (ScreenSize)
import Time
import Url exposing (Url)
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Browser state and diagnostics shared by all applications.
`now` is the latest browser clock sample, initialized by JavaScript and refreshed
by the shared clock subscription. `origin` contains the scheme, hostname, and
optional port for constructing complete application links. `screenSize` is the
required startup viewport size, refreshed by the shared resize subscription.
-}
type alias Model =
    { deployment : Deployment.Model
    , now : Time.Posix
    , key : Navigation.Key
    , screenSize : ScreenSize
    , operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , features : Features.Model
    , seed : Random.Seed
    , errors : ErrorHistory.Model Error
    , devPanel : DevPanel.Model
    , devPanelOpen : Bool
    , audioMute : Audio.MuteState
    , audioVolumes : Audio.Volumes
    , origin : String
    }


type Msg
    = CurrentTimeReceived Time.Posix
    | WindowResized ScreenSize
    | WindowVisibilityChanged Browser.Events.Visibility
    | GotLocalstorage LocalStorage
    | GotFromJsError FromJs.Error
    | AudioErrorReceived Error
    | DevPanelToggleKeyPressed
    | DevPanelMsg DevPanel.Msg
    | DevPanelTabFocused (Result Browser.Dom.Error ())
    | AudioMuteButtonClicked



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init :
    Time.Posix
    -> Random.Seed
    -> OperatingSystem
    -> ScreenSize
    -> LocalStorage
    -> Url
    -> Navigation.Key
    -> Model
init now seed operatingSystem screenSize localStorage url key =
    let
        ( features, featuresError ) =
            Features.init localStorage

        ( audioMute, muteError ) =
            Audio.loadMutePreference localStorage

        ( audioVolumes, volumesError ) =
            Audio.loadVolumesPreference localStorage
    in
    { deployment = Deployment.init url
    , now = now
    , key = key
    , screenSize = screenSize
    , operatingSystem = operatingSystem
    , localStorage = localStorage
    , features = features
    , seed = seed
    , errors = ErrorHistory.init
    , devPanel = DevPanel.init
    , devPanelOpen = False
    , audioMute = audioMute
    , audioVolumes = audioVolumes
    , origin =
        Url.toString
            { url
                | path = ""
                , query = Nothing
                , fragment = Nothing
            }
    }
        |> addError muteError
        |> addError volumesError
        |> addError featuresError



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Use the same device and viewport rules for mobile layout in every app.
-}
isMobileView : Model -> Bool
isMobileView model =
    OperatingSystem.isMobile model.operatingSystem
        || ScreenSize.isMobileSize model.screenSize


{-| Adapt every dialog, including shared dev tools, at the application boundary.
-}
adaptDialog : Model -> Dialog msg -> Dialog msg
adaptDialog model activeDialog =
    if isMobileView model then
        Dialog.fullscreen activeDialog

    else
        activeDialog


audioMuteButtonClicked : Msg
audioMuteButtonClicked =
    AudioMuteButtonClicked


devPanelErrors : Model -> List DevPanel.Error
devPanelErrors model =
    List.map toDevPanelError model.errors.errors


devPanelMsg : DevPanel.Msg -> Msg
devPanelMsg =
    DevPanelMsg


gotFromJsError : FromJs.Error -> Msg
gotFromJsError =
    GotFromJsError


setAudioMute : Audio.MuteState -> Model -> Model
setAudioMute audioMute model =
    { model | audioMute = audioMute }


setAudioVolumes : Audio.Volumes -> Model -> Model
setAudioVolumes audioVolumes model =
    { model | audioVolumes = audioVolumes }


setSeed : Random.Seed -> Model -> Model
setSeed seed model =
    { model | seed = seed }


addError : Maybe Error -> Model -> Model
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


setDevPanelOpen : Bool -> Model -> Model
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

        Error.DeploymentStatusFailed failure ->
            DevPanel.Error
                { title = "deployment status failed"
                , details = ApiRequest.errorDetails failure
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

        Error.ElementScrollFailed failure ->
            DevPanel.Error
                { title = "element scroll failed"
                , details = domErrorDetails failure
                }

        Error.OrderPlanningInvariantViolated violation ->
            DevPanel.Error
                { title = "order planning invariant violated"
                , details = planningErrorDetails violation
                }

        Error.PlanningErrorReportFailed message ->
            DevPanel.Error
                { title = "could not report planning error"
                , details = message
                }

        Error.TurnPlaybackInvariantViolated (TurnPlayback.TooFewFrames missing) ->
            DevPanel.Error
                { title = "turn playback invariant violated"
                , details =
                    "resolved turn "
                        ++ String.fromInt missing.resolvedTurn
                        ++ " has "
                        ++ String.fromInt missing.frameCount
                        ++ " playback frames (expected at least two)"
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

        OrderPlanning.OrderUnitHasNoPosition unitId ->
            "order unit has no position: " ++ UnitId.toString unitId

        OrderPlanning.LoadingOrderNotFound unitId ->
            "loading order not found: " ++ UnitId.toString unitId

        OrderPlanning.MovementInvariantViolated (Movement.RuleNotFound missing) ->
            "movement rule not found for "
                ++ UnitKind.label missing.kind
                ++ " "
                ++ UnitId.toString missing.unitId

        OrderPlanning.PassengerNotAboard relationship ->
            "passenger "
                ++ UnitId.toString relationship.passengerId
                ++ " is not aboard truck "
                ++ UnitId.toString relationship.truckId

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
                DirectionPlanning.OrderUnitNotOnMap unitId ->
                    "direction order unit not on map: " ++ UnitId.toString unitId

        OrderPlanning.IndirectFireInvariantViolated indirectFire ->
            case indirectFire of
                IndirectFirePlanning.OrderUnitNotOnMap unitId ->
                    "indirect fire order unit not on map: " ++ UnitId.toString unitId



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


{-| Check shared transitions after every shared message. Page dialog restoration
belongs to each app; Shared only opens its own dev panel.
-}
superUpdate : Msg -> Model -> ( Model, Eff Msg )
superUpdate msg model =
    let
        ( updated, effect ) =
            update msg model

        panelOpened : Bool
        panelOpened =
            not model.devPanelOpen && updated.devPanelOpen

        result : ( Model, Eff Msg )
        result =
            ( updated, effect )
    in
    if panelOpened then
        result
            |> E.and (E.toJs (ToJs.OpenDialog { htmlId = DevPanel.htmlId }))

    else
        result


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        CurrentTimeReceived now ->
            ( { model | now = now }
            , E.none
            )

        WindowResized screenSize ->
            ( { model
                | screenSize = screenSize
              }
            , E.none
            )

        WindowVisibilityChanged visibility ->
            let
                eff : Eff Msg
                eff =
                    case visibility of
                        Browser.Events.Visible ->
                            E.now CurrentTimeReceived

                        Browser.Events.Hidden ->
                            E.none
            in
            ( model, eff )

        AudioMuteButtonClicked ->
            let
                audioMute : Audio.MuteState
                audioMute =
                    Audio.toggleMute model.audioMute
            in
            ( setAudioMute audioMute model
            , E.batch
                [ E.audio (Audio.SetMute audioMute)
                , E.setLocalStorage (Audio.encodeMutePreference audioMute)
                ]
            )

        DevPanelToggleKeyPressed ->
            ( model
                |> setDevPanelOpen (not model.devPanelOpen)
            , E.none
            )

        DevPanelMsg panelMsg ->
            handleDevPanelMsg panelMsg model

        DevPanelTabFocused result ->
            case result of
                Ok () ->
                    ( model
                    , E.none
                    )

                Err error ->
                    ( addError (Just (Error.ElementFocusFailed error)) model
                    , E.none
                    )

        GotLocalstorage localStorage ->
            let
                ( features, featuresError ) =
                    Features.init localStorage

                ( audioMute, muteError ) =
                    Audio.loadMutePreference localStorage

                ( audioVolumes, volumesError ) =
                    Audio.loadVolumesPreference localStorage

                muteEffect : Eff Msg
                muteEffect =
                    if audioMute == model.audioMute then
                        E.none

                    else
                        E.audio (Audio.SetMute audioMute)

                volumesEffect : Eff Msg
                volumesEffect =
                    if audioVolumes == model.audioVolumes then
                        E.none

                    else
                        E.audio (Audio.SetVolumes audioVolumes)
            in
            ( { model
                | localStorage = localStorage
                , features = features
                , audioMute = audioMute
                , audioVolumes = audioVolumes
              }
                |> addError muteError
                |> addError volumesError
                |> addError featuresError
            , E.batch [ muteEffect, volumesEffect ]
            )

        GotFromJsError error ->
            ( addError (Just (Error.FromJsFailed error)) model, E.none )

        AudioErrorReceived error ->
            ( addError (Just error) model, E.none )


handleDevPanelMsg : DevPanel.Msg -> Model -> ( Model, Eff Msg )
handleDevPanelMsg msg model =
    case msg of
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
            ( { model
                | devPanel =
                    { panel | selectedTab = tab }
              }
            , E.none
            )

        DevPanel.TabNavigationPressed tab ->
            let
                panel : DevPanel.Model
                panel =
                    model.devPanel
            in
            ( { model
                | devPanel =
                    { panel | selectedTab = tab }
              }
            , E.focus
                { htmlId = DevPanel.tabHtmlId tab }
                DevPanelTabFocused
            )

        DevPanel.FeatureCheckboxChanged feature isEnabled ->
            let
                features : Features.Model
                features =
                    Features.setEnabled feature isEnabled model.features
            in
            ( { model | features = features }
            , E.setLocalStorage (Features.encodePreference features)
            )

        DevPanel.TestErrorButtonClicked ->
            ( addError (Just Error.TestError) model, E.none )



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Sub Msg
subscriptions =
    Sub.batch
        [ ScreenSize.onResize WindowResized
        , Time.every 1000 CurrentTimeReceived
        , Browser.Events.onVisibilityChange WindowVisibilityChanged
        ]


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
