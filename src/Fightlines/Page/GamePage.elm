module Fightlines.Page.GamePage exposing
    ( Flags
    , Model
    , Msg
    , dialog
    , init
    , keyCommands
    , load
    , resize
    , setDepots
    , setShared
    , setUnits
    , stopPlaybackAudio
    , subscriptions
    , superUpdate
    , view
    )

import Api.Enum.Direction as DirectionEnum exposing (Direction)
import Api.Enum.InactivityRenewalReason as RenewalReason exposing (InactivityRenewalReason)
import Api.Enum.PlayerNumber as PlayerNumberEnum exposing (PlayerNumber)
import Api.Enum.ResourceKind as ResourceKind
import Api.Enum.TurnEventKind as TurnEventKind
import Api.Enum.UnitKind as UnitKind
import Api.Mutation
import Api.Object
import Api.Object.GameSnapshot as SnapshotApi
import Api.Object.Scenario as Scenario
import Api.Query
import Api.Scalar
    exposing
        ( MapId
        )
import ApiRequest
import AppVersion
import Audio
import Browser.Dom
import Browser.Events
import Css exposing (Style)
import Effect as E
    exposing
        ( Eff
        )
import Error exposing (Error)
import Features
import Fightlines.Feedback as Feedback
import Fightlines.Route as Route
import Fightlines.View.About as About
import Fightlines.View.Feedback as FeedbackView
import Fightlines.View.GameMenu as GameMenu
import Fightlines.View.MobileBattlefield as MobileBattlefield
import Fightlines.View.OrderGuide as OrderGuide
import Fightlines.View.OrderMenu as OrderMenu
import Fightlines.View.Settings as Settings
import Fightlines.View.TurnIntroduction as TurnIntroduction
import Fightlines.View.UnloadPassenger as UnloadPassenger
import Fightlines.View.WelcomeBriefing as WelcomeBriefing
import Game.AnimationFrame as AnimationFrame
import Game.Assets as Assets
import Game.BattlefieldNavigation as BattlefieldNavigation
import Game.BattlefieldSnapshot as BattlefieldSnapshot exposing (Player)
import Game.Camera as Camera
import Game.Chat as Chat
import Game.CombatRules as CombatRules
import Game.CombatTheaterCalibrations as CombatTheaterCalibrations
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.CurrentTurn as CurrentTurn
import Game.Depot as Depot
    exposing
        ( Depot
        , LoadingSource
        )
import Game.DestinationFeedback exposing (DestinationFeedback(..))
import Game.Direction as Direction
import Game.DirectionPlanning as DirectionPlanning
import Game.Inactivity as Inactivity exposing (Inactivity)
import Game.IndirectFirePlanning as IndirectFirePlanning
import Game.Inspection as Inspection exposing (Inspection(..))
import Game.Map as Map exposing (Map)
import Game.MovePlanning as MovePlanning
import Game.Movement as Movement
import Game.OrderPlanning as OrderPlanning
import Game.Outcome as GameOutcome exposing (GameOutcome)
import Game.PlannedOrder as PlannedOrder
    exposing
        ( PlannedOrder
        , UnloadOrder
        )
import Game.PlannedTransport as PlannedTransport
import Game.PlaybackPresentation as PlaybackPresentation
import Game.PlayerNumber as PlayerNumber
import Game.Selection as Selection
    exposing
        ( Selection(..)
        , UnitInteraction(..)
        )
import Game.Supply as Supply
import Game.Turn as Turn
import Game.TurnLifecycle as TurnLifecycle exposing (Phase)
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitOrder as UnitOrder
import Game.UnitStats exposing (UnitStats)
import Game.UnloadCargo as UnloadCargo exposing (UnloadCargo)
import Game.UnloadPlanning
    exposing
        ( UnloadChoice
        , UnloadPlanning
        )
import Game.UnloadingTruck as UnloadingTruck exposing (UnloadingTruck)
import Game.View.Battlefield as Battlefield
    exposing
        ( UnloadRoute
        )
import Game.View.BattlefieldInspection as BattlefieldInspection
import Game.View.BattlefieldWorkspace as BattlefieldWorkspace
import Game.View.Cargo as Cargo
import Game.View.Chat as ChatView
import Game.View.CombatTheater as CombatTheater
import Game.View.InspectionHelp as InspectionHelp
import Game.View.LoadingNotice as LoadingNotice
import Game.View.MovementRoute as MovementRoute
import Game.View.RotationChoices as RotationChoices
import Game.View.TurnControls as TurnControls
import Game.View.UnitDeath as UnitDeath
import Game.View.UnitSprite as UnitSprite
import Game.View.UnitStatus as UnitStatus
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import InvariantCheck as IC exposing (InvariantCheck)
import Json.Decode as Decode
import Json.Encode as Encode
import KeyCmd exposing (KeyCmd)
import LobbyId
    exposing
        ( LobbyId
        )
import Point exposing (Point)
import Ports.Js.To as ToJs
import Preference
import Random
import Shared
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import Time
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import Util.Maybe as MaybeUtil
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)
import View.Layout as Layout exposing (Layout)
import View.RequestError as RequestError



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias BattlefieldViewport =
    { origin : Point
    , camera : Camera.Viewport
    }


type alias PlaybackAudio =
    { movement : List Audio.MovingUnit
    , ambience : List Audio.AmbientScene
    , infantryFire : List Audio.FiringInfantry
    }


type alias Model =
    { inactivity : Inactivity.Model
    , inactivityWakeAt : Maybe Time.Posix
    , currentTurn : CurrentTurn.Model
    , feedback : Feedback.Draft
    , chat : Chat.Model
    , shared : Shared.Model
    , welcomeBriefingPending : Bool
    , skipTurnIntroduction : Bool
    , skipUnplannedUnitsWarning : Bool
    , skipUnitLossDialogs : Bool
    , automaticallyCloseCombatTheater : Bool
    , name : String
    , mapType : MapId
    , players : List Player
    , map : Map
    , units : List Unit
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    , supplyRules : Supply.Rules
    , visibleTiles : List Coordinate
    , movementRules : List Movement.Rule
    , navigation : BattlefieldNavigation.Model
    , battlefieldViewport : Maybe BattlefieldViewport
    , frame : AnimationFrame.Frame
    , resigning : Bool
    , menu : Menu
    , inspectionHelp : Maybe InspectionHelp.Help
    , unitStats : List UnitStats
    , mobileTab : MobileBattlefield.Tab
    , planningReports : PlanningReports
    }


type alias PlanningReports =
    { seen : List OrderPlanning.InvariantViolation
    , pending : List PlanningReport
    , nextSendAt : Maybe Time.Posix
    }


type alias PlanningReport =
    { turnNumber : Int
    , violation : OrderPlanning.InvariantViolation
    }


type alias WorkspaceLayout =
    { inspectorOpen : Bool
    , activity : TurnControls.Activity
    , outcome : Maybe GameOutcome
    , playing : Bool
    }


type alias Snapshot =
    { inactivity : Inactivity
    , battlefield : BattlefieldSnapshot.Snapshot
    , supplyRules : Supply.Rules
    , movementRules : List Movement.Rule
    , turn : Turn.Snapshot
    , playbackFrames : List TurnPlayback.Frame
    }


type ResignationDestination
    = RemainInGame
    | GoHome


type alias PollStatus =
    { inactivity : Inactivity
    , number : Int
    , outcome : Maybe GameOutcome
    , submitted : Bool
    , opponentSubmitted : Bool
    }


type Menu
    = MenuClosed
    | MainMenu
    | MobileOrdersHelp
    | ConfirmingResignation ResignationDestination
    | FeedbackMenu
    | AboutMenu
    | SettingsMenu Settings.Tab


type alias RotationSelection =
    { unitId : UnitId
    , position : Coordinate
    , direction : Direction
    }


type ThumbnailUse
    = UnloadPortrait
    | SubmissionPortrait


type alias RequestErrorDetails =
    { title : String
    , message : String
    , guidance : String
    , retryEnabled : Bool
    }


type Msg
    = StillHereClicked
    | InactivityWakeElapsed Time.Posix
    | InactivityWakeTimeReceived Time.Posix Time.Posix
    | InactivityRenewalResponseReceived Inactivity.Report (ApiRequest.Response PollStatus)
    | BattlefieldSizeReceived (Result Browser.Dom.Error Browser.Dom.Element)
    | FeedbackMsg FeedbackView.Msg
    | FeedbackResponseReceived Feedback.RequestId (ApiRequest.Response Bool)
    | PlanningErrorReportTick Time.Posix
    | PlanningErrorReportReceived (ApiRequest.Response Bool)
    | ChatMsg ChatView.Msg
    | ChatPollElapsed Time.Posix
    | ChatPollReceived (ApiRequest.Response (List Chat.Message))
    | ChatSendReceived Chat.Submission (ApiRequest.Response Chat.Message)
    | ChatOverlayExpired Int
    | ChatScrollCompleted (Result Browser.Dom.Error ())
    | CombatEnterPressed
    | InspectorSizeReceived Browser.Dom.Element (Result Browser.Dom.Error Browser.Dom.Element)
    | ControlsSizeReceived { battlefield : Browser.Dom.Element, inspector : Browser.Dom.Element } (Result Browser.Dom.Error Browser.Dom.Element)
    | CameraReturnFinished
    | BattlefieldMsg Battlefield.Msg
    | BattlefieldNavigationMsg BattlefieldNavigation.Msg
    | OrderMenuMsg OrderMenu.Msg
    | GameMenuMsg GameMenu.Msg
    | SettingsMsg Settings.Msg
    | RotationNoticeCanceled
    | FocusCompleted (Result Browser.Dom.Error ())
    | PreviousOrderPressed
    | NextOrderPressed
    | OrderFocusCompleted (Result Browser.Dom.Error ())
    | PanLeftKeyPressed
    | PanRightKeyPressed
    | PanUpKeyPressed
    | PanDownKeyPressed
    | ZoomInKeyPressed
    | ZoomOutKeyPressed
    | AnimationTimerElapsed Time.Posix
    | TurnIntroductionMsg TurnIntroduction.Msg
    | UnitDeathMsg UnitDeath.Msg
    | LossDialogOpened String
    | CombatTheaterMsg CombatTheater.Msg
    | DirectionKeyPressed Direction
    | PathDirectionKeyPressed Direction
    | PathEnterPressed
    | NextUnorderedUnitKeyPressed
    | ClearMoveClicked
    | CancelOrderClicked
    | CargoUnitClicked UnitId
    | LoadCratesClicked UnitId Int
    | GroundFreightPickupClicked
    | UnloadCrateToggled Int Bool
    | UnloadUnitToggled UnitId Bool
    | UnloadChoicesConfirmed
    | UnloadSkipped
    | InspectClicked
    | InspectorCloseClicked
    | MobileTabClicked MobileBattlefield.Tab
    | MobileTabNavigationPressed MobileBattlefield.Tab
    | InspectionHelpClicked InspectionHelp.Help
    | InspectionHelpFocusReturned (Result Browser.Dom.Error ())
    | EscapePressed
    | WelcomeBriefingDismissed
    | DialogDismissed
    | SubmissionCancelled
    | SubmissionConfirmed
    | SubmitKeyPressed
    | SkipUnplannedUnitsWarningChanged Bool
    | TurnControlsMsg TurnControls.Msg
    | RequestRetryClicked
    | RequestErrorDismissed
    | SubmitResponseReceived Int (ApiRequest.Response Snapshot)
    | CurrentTurnMsg CurrentTurn.Msg
    | ResignResponseReceived ResignationDestination (ApiRequest.Response Snapshot)
    | PollStatusResponseReceived Int (ApiRequest.Response PollStatus)
    | PollResponseReceived (ApiRequest.Response Snapshot)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { snapshot : Snapshot
    , messages : List Chat.Message
    }


init : Shared.Model -> Flags -> ( Model, Eff Msg )
init shared flags =
    let
        ( automaticallyCloseCombatTheater, maybeError ) =
            PlaybackPresentation.loadPreference
                PlaybackPresentation.AutomaticallyCloseCombat
                shared.localStorage

        ( welcomeBriefingDismissed, welcomePreferenceError ) =
            Preference.load
                { key = welcomeBriefingPreferenceKey
                , decoder = Decode.bool
                , defaultValue = False
                }
                shared.localStorage

        ( skipTurnIntroduction, introductionPreferenceError ) =
            Preference.load
                { key = turnIntroductionPreferenceKey
                , decoder = Decode.bool
                , defaultValue = False
                }
                shared.localStorage

        ( skipUnplannedUnitsWarning, submissionPreferenceError ) =
            Preference.load
                { key = unplannedUnitsWarningPreferenceKey
                , decoder = Decode.bool
                , defaultValue = False
                }
                shared.localStorage

        ( skipLossDialogs, lossPreferenceError ) =
            PlaybackPresentation.loadPreference
                PlaybackPresentation.SkipLossDialogs
                shared.localStorage

        model : Model
        model =
            { inactivity = Inactivity.init shared.now flags.snapshot.inactivity
            , inactivityWakeAt = Nothing
            , currentTurn = CurrentTurn.init (turnObservation flags.snapshot)
            , chat = Chat.initGame flags.messages
            , shared =
                shared
                    |> Shared.addError maybeError
                    |> Shared.addError lossPreferenceError
                    |> Shared.addError welcomePreferenceError
                    |> Shared.addError introductionPreferenceError
                    |> Shared.addError submissionPreferenceError
            , welcomeBriefingPending = not welcomeBriefingDismissed && (flags.snapshot.turn.outcome == Nothing)
            , skipTurnIntroduction = skipTurnIntroduction
            , skipUnplannedUnitsWarning = skipUnplannedUnitsWarning
            , skipUnitLossDialogs = skipLossDialogs
            , automaticallyCloseCombatTheater = automaticallyCloseCombatTheater
            , name = flags.snapshot.battlefield.name
            , mapType = flags.snapshot.battlefield.mapType
            , players = flags.snapshot.battlefield.players
            , map = flags.snapshot.battlefield.map
            , units = flags.snapshot.battlefield.units
            , depots = flags.snapshot.battlefield.depots
            , supplyCrates = flags.snapshot.battlefield.supplyCrates
            , supplyRules = flags.snapshot.supplyRules
            , visibleTiles = flags.snapshot.battlefield.visibleTiles
            , movementRules = flags.snapshot.movementRules
            , unitStats = flags.snapshot.battlefield.unitStats
            , navigation =
                BattlefieldNavigation.init
                    |> BattlefieldNavigation.setMaxZoom
                        (maxBattlefieldZoom
                            shared
                            flags.snapshot.battlefield.map
                        )
            , battlefieldViewport = Nothing
            , frame = AnimationFrame.first
            , resigning = False
            , feedback = Feedback.init
            , menu = MenuClosed
            , inspectionHelp = Nothing
            , mobileTab = MobileBattlefield.Orders
            , planningReports = { seen = [], pending = [], nextSendAt = Nothing }
            }

        eff : Eff Msg
        eff =
            if hasDialog model then
                E.none

            else
                chatExpiration model
    in
    ( model
    , E.batch
        [ eff
        , measureWorkspace
        , E.toJs (ToJs.PreloadImages (Assets.imagePaths model.map.theme))
        ]
    )
        |> E.andThen (scheduleInactivity shared.now 0)


load : LobbyId -> Graphql.Http.Request Flags
load id =
    SS.succeed Flags
        |> SS.with (Api.Query.game { id = LobbyId.toString id } snapshotSelection)
        |> SS.with (Chat.query id 0)
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


isMobileView : Model -> Bool
isMobileView model =
    Shared.isMobileView model.shared


{-| Match the tile size at maximum zoom on the 17-tile-wide Supply Point map.
-}
maxBattlefieldZoom : Shared.Model -> Map -> Float
maxBattlefieldZoom shared map =
    let
        supplyPointMaxZoom : Float
        supplyPointMaxZoom =
            if Shared.isMobileView shared then
                6

            else
                3
    in
    max 1 (supplyPointMaxZoom * toFloat map.width / 17)


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


{-| Clear the active voices when the player app leaves this game page.
-}
stopPlaybackAudio : Model -> Eff msg
stopPlaybackAudio model =
    syncPlaybackAudio
        { before = playbackAudio model
        , after =
            { movement = []
            , ambience = []
            , infantryFire = []
            }
        }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


resize : { layoutChanged : Bool } -> Model -> ( Model, Eff Msg )
resize { layoutChanged } model =
    if layoutChanged then
        let
            maxZoom : Float
            maxZoom =
                maxBattlefieldZoom model.shared model.map

            navigation : BattlefieldNavigation.Model
            navigation =
                BattlefieldNavigation.setMaxZoom maxZoom model.navigation

            currentTurn : CurrentTurn.Model
            currentTurn =
                model.currentTurn
                    |> CurrentTurn.setPhase
                        (limitPlaybackZoom maxZoom model.currentTurn.phase)
        in
        ( model
            |> setNavigation navigation
            |> setCurrentTurn currentTurn
        , E.batch
            [ measureWorkspace
            , scrollChatHistory model.chat model.shared
            ]
        )

    else
        ( model, measureWorkspace )


limitPlaybackZoom : Float -> Phase -> Phase
limitPlaybackZoom maxZoom phase =
    let
        limit : PlaybackPresentation.PlaybackCamera -> PlaybackPresentation.PlaybackCamera
        limit held =
            if held.camera.zoom > maxZoom then
                { held
                    | camera =
                        Camera.zoomAt { x = 0, y = 0 } maxZoom held.camera
                }

            else
                held
    in
    case phase of
        TurnLifecycle.Playing playing ->
            playing
                |> TurnLifecycle.setPlaybackCamera (Maybe.map limit playing.camera)
                |> TurnLifecycle.Playing

        _ ->
            phase


setChat : Chat.Model -> Model -> Model
setChat chat model =
    { model | chat = chat }


setFeedback : Feedback.Draft -> Model -> Model
setFeedback feedback model =
    { model | feedback = feedback }


setCurrentTurn : CurrentTurn.Model -> Model -> Model
setCurrentTurn currentTurn model =
    let
        reports : PlanningReports
        reports =
            model.planningReports

        planningReports : PlanningReports
        planningReports =
            if currentTurn.number == model.currentTurn.number then
                reports

            else
                { reports | seen = [] }

        next : Model
        next =
            { model
                | currentTurn = currentTurn
                , planningReports = planningReports
            }

        previousInspection : Maybe Inspection
        previousInspection =
            Maybe.map Selection.toInspection (currentSelection model)

        nextInspection : Maybe Inspection
        nextInspection =
            Maybe.map Selection.toInspection (currentSelection next)
    in
    if previousInspection == nextInspection then
        next

    else
        resetMobileTab (selectedUnitId model) next


setCombatEnterHeld : Bool -> Model -> Model
setCombatEnterHeld held model =
    model
        |> setCurrentTurn
            (CurrentTurn.setPhase
                (TurnLifecycle.setCombatEnterHeld held model.currentTurn.phase)
                model.currentTurn
            )


canContinueCombatWithEnter : Model -> Bool
canContinueCombatWithEnter model =
    TurnLifecycle.combatEnterHeld model.currentTurn.phase && not (hasDialog model)


setMenu : Menu -> Model -> Model
setMenu menu model =
    { model | menu = menu }


setMap : Map -> Model -> Model
setMap map model =
    { model | map = map }


setDepots : List Depot -> Model -> Model
setDepots depots model =
    { model | depots = depots }


setSupplyCrates : List Supply.GroundCrate -> Model -> Model
setSupplyCrates supplyCrates model =
    { model | supplyCrates = supplyCrates }


setUnits : List Unit -> Model -> Model
setUnits units model =
    { model | units = units }
        |> resetMobileTab (selectedUnitId model)


setVisibleTiles : List Coordinate -> Model -> Model
setVisibleTiles visibleTiles model =
    { model | visibleTiles = visibleTiles }


setNavigation : BattlefieldNavigation.Model -> Model -> Model
setNavigation navigation model =
    { model | navigation = navigation }


setResigning : Bool -> Model -> Model
setResigning resigning model =
    { model | resigning = resigning }


setBattlefieldViewport : Maybe BattlefieldViewport -> Model -> Model
setBattlefieldViewport battlefieldViewport model =
    { model | battlefieldViewport = battlefieldViewport }


welcomeBriefingPreferenceKey : String
welcomeBriefingPreferenceKey =
    "welcomeBriefingDismissed"


turnIntroductionPreferenceKey : String
turnIntroductionPreferenceKey =
    "skipTurnIntroduction"


unplannedUnitsWarningPreferenceKey : String
unplannedUnitsWarningPreferenceKey =
    "skipUnplannedUnitsWarning"


rememberPlaybackPreference : PlaybackPresentation.Preference -> Bool -> Eff msg
rememberPlaybackPreference preference enabled =
    PlaybackPresentation.encodePreference preference enabled
        |> E.setLocalStorage


rememberTurnIntroductionPreference : Bool -> Eff Msg
rememberTurnIntroductionPreference skip =
    E.setLocalStorage
        { key = turnIntroductionPreferenceKey
        , value = Encode.bool skip
        }


setSkipTurnIntroduction : Bool -> Model -> Model
setSkipTurnIntroduction skip model =
    { model | skipTurnIntroduction = skip }


showTurnIntroduction : Model -> Bool
showTurnIntroduction model =
    (model.currentTurn.outcome /= Nothing || not model.skipTurnIntroduction)
        && CurrentTurn.introductionPending model.currentTurn


acknowledgeTurnIntroduction : Model -> ( Model, Eff Msg )
acknowledgeTurnIntroduction model =
    model
        |> setCurrentTurn (CurrentTurn.acknowledgeIntroduction model.currentTurn)
        |> resumeChatOverlay (showTurnIntroduction model)


{-| Save the chosen load count on an existing truck order, retaining its route and passenger exits.
-}
saveCrateLoading :
    UnitId
    -> Int
    -> OrderPlanning.Model
    -> InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
saveCrateLoading id count state =
    let
        retainsOrder : PlannedOrder -> Bool
        retainsOrder order =
            order.unitId /= id

        loadingOrder : PlannedOrder -> PlannedOrder
        loadingOrder order =
            { unitId = id
            , action =
                PlannedOrder.SupplyTransfer
                    { route = PlannedOrder.path order
                    , destination = PlannedOrder.destination order
                    , handling = PlannedOrder.LoadingCrates count
                    , passengers = PlannedOrder.unloads order
                    }
            }
    in
    case state of
        OrderPlanning.OrdinaryPlanning drafts ->
            case ListUtil.find (\order -> order.unitId == id) drafts.orders of
                Just order ->
                    OrderPlanning.OrdinaryPlanning
                        { orders = loadingOrder order :: List.filter retainsOrder drafts.orders
                        , selection = Just (Inspecting (UnitInspection id))
                        }
                        |> IC.happy

                Nothing ->
                    IC.violated (OrderPlanning.LoadingOrderNotFound id) state

        _ ->
            IC.happy state


depotLoadingRoom : Model -> Unit -> Int
depotLoadingRoom model unit =
    let
        depot : Maybe Depot.LoadingSource
        depot =
            plannedDepot model unit.id
                |> Maybe.andThen Depot.loadingSource

        stockLimit : Int
        stockLimit =
            case depot of
                Just source ->
                    let
                        capacity : Int
                        capacity =
                            Supply.cargoCapacity model.supplyRules source.kind
                    in
                    source.stock
                        |> Maybe.map (\stock -> (stock.current + capacity - 1) // capacity)
                        |> Maybe.withDefault 2

                Nothing ->
                    2
    in
    min
        stockLimit
        (PlannedTransport.cargoRoom model.units unit (plannedOrders model))


plannedDepot : Model -> UnitId -> Maybe Depot
plannedDepot model id =
    let
        atDestination : PlannedOrder -> Maybe Depot
        atDestination order =
            ListUtil.find
                (\depot -> depot.position == PlannedOrder.destination order)
                model.depots
    in
    plannedOrders model
        |> ListUtil.find (\order -> order.unitId == id)
        |> Maybe.andThen atDestination


ownPlayerNumbers : Model -> List PlayerNumber
ownPlayerNumbers model =
    List.filter .isYou model.players |> List.map .playerNumber


visibleSupplyCrates : List Coordinate -> List Supply.GroundCrate -> List Supply.GroundCrate
visibleSupplyCrates tiles =
    List.filter (\crate -> List.member crate.position tiles)


mapPlanning : (OrderPlanning.Model -> OrderPlanning.Model) -> Model -> Model
mapPlanning transition =
    mapCheckedPlanning (transition >> IC.happy)


mapCheckedPlanning :
    (OrderPlanning.Model
     ->
        InvariantCheck
            OrderPlanning.InvariantViolation
            OrderPlanning.Model
    )
    -> Model
    -> Model
mapCheckedPlanning transition model =
    let
        checked : InvariantCheck OrderPlanning.InvariantViolation CurrentTurn.Model
        checked =
            CurrentTurn.mapPlanning transition model.currentTurn

        applyChecked : Maybe OrderPlanning.InvariantViolation -> CurrentTurn.Model -> Model
        applyChecked violation currentTurn =
            model
                |> setCurrentTurn currentTurn
                |> recordPlanningViolation violation
    in
    IC.resolve applyChecked checked


recordPlanningViolation : Maybe OrderPlanning.InvariantViolation -> Model -> Model
recordPlanningViolation violation model =
    case violation of
        Just failure ->
            let
                reports : PlanningReports
                reports =
                    model.planningReports
            in
            if List.member failure reports.seen then
                model

            else
                let
                    pending : List PlanningReport
                    pending =
                        if List.length reports.pending < 8 then
                            { turnNumber = model.currentTurn.number
                            , violation = failure
                            }
                                :: reports.pending

                        else
                            reports.pending
                in
                { model
                    | planningReports =
                        { reports
                            | seen = failure :: reports.seen
                            , pending = pending
                        }
                }
                    |> setShared
                        (Shared.addError
                            (Just (Error.OrderPlanningInvariantViolated failure))
                            model.shared
                        )

        Nothing ->
            model


reportPlanningViolations : LobbyId -> Time.Posix -> Model -> ( Model, Eff Msg )
reportPlanningViolations lobbyId now model =
    let
        reports : PlanningReports
        reports =
            model.planningReports

        millis : Int
        millis =
            Time.posixToMillis now

        coolingDown : Bool
        coolingDown =
            reports.nextSendAt
                |> Maybe.map (\deadline -> millis < Time.posixToMillis deadline)
                |> Maybe.withDefault False

        entry : PlanningReport -> { turnNumber : Int, details : String }
        entry report =
            { turnNumber = report.turnNumber
            , details = Shared.planningErrorDetails report.violation
            }
    in
    if not coolingDown && not (List.isEmpty reports.pending) then
        ( { model
            | planningReports =
                { reports
                    | pending = []
                    , nextSendAt = Just (Time.millisToPosix (millis + 60000))
                }
          }
        , Api.Mutation.reportPlanningErrors
            { input =
                { gameId = LobbyId.toString lobbyId
                , clientVersion = AppVersion.current
                , errors = List.reverse reports.pending |> List.map entry
                }
            }
            |> ApiRequest.mutationRequest
            |> E.request PlanningErrorReportReceived
        )

    else
        E.withOut model


unloadChoice : Phase -> Maybe UnloadChoice
unloadChoice phase =
    TurnLifecycle.planning phase
        |> Maybe.andThen OrderPlanning.unloadChoice


unloadingPassengers : UnloadingTruck -> List Unit -> List Unit
unloadingPassengers truck units =
    let
        truckId : UnitId
        truckId =
            UnloadingTruck.unitId truck
    in
    List.filter (\unit -> Unit.carrierId unit == Just truckId) units


unloadPlanning : Phase -> Maybe UnloadPlanning
unloadPlanning phase =
    TurnLifecycle.planning phase |> Maybe.andThen OrderPlanning.unloadPlanning


isChoosingUnload : Model -> Bool
isChoosingUnload model =
    unloadPlanning model.currentTurn.phase /= Nothing


dismissDialog : Model -> ( Model, Eff Msg )
dismissDialog model =
    if model.inspectionHelp /= Nothing then
        { model | inspectionHelp = Nothing } |> E.withOut

    else if model.menu /= MenuClosed then
        model
            |> setMenu MenuClosed
            |> E.withOut

    else if showTurnIntroduction model then
        acknowledgeTurnIntroduction model

    else
        model
            |> mapPlanning
                (OrderPlanning.dismissDialog
                    >> OrderPlanning.promptDismountedOrders model.map model.units
                )
            |> E.withOut


dismissInspectionHelp : Model -> ( Model, Eff Msg )
dismissInspectionHelp model =
    case model.inspectionHelp of
        Just help ->
            ( { model | inspectionHelp = Nothing }
            , E.focus { htmlId = InspectionHelp.buttonHtmlId help } InspectionHelpFocusReturned
            )

        Nothing ->
            model
                |> E.withOut


partialOrdersDialogHtmlId : String
partialOrdersDialogHtmlId =
    "submit-turn-warning"


orderGuideOpen : Model -> Bool
orderGuideOpen model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.orderGuideOpen
        |> Maybe.withDefault False


hasDialog : Model -> Bool
hasDialog model =
    dialog model /= Nothing


canOpenDialog : Model -> Bool
canOpenDialog model =
    not (hasDialog model) && (playback model == Nothing)


plannedOrders : Model -> List PlannedOrder
plannedOrders model =
    TurnLifecycle.orders model.currentTurn.phase


playback : Model -> Maybe TurnPlayback.Playback
playback model =
    TurnLifecycle.playback model.currentTurn.phase


playbackAudio : Model -> PlaybackAudio
playbackAudio model =
    let
        animation : Maybe TurnPlayback.Playback
        animation =
            playback model

        camera : Maybe TurnLifecycle.PlaybackCamera
        camera =
            playbackCamera model
    in
    { movement =
        PlaybackPresentation.movingUnits
            { playback = animation
            , paused = False
            , camera = camera
            , skipLossDialogs = model.skipUnitLossDialogs
            }
    , ambience =
        PlaybackPresentation.ambience
            { map = model.map
            , playback = animation
            , paused = False
            }
    , infantryFire =
        PlaybackPresentation.firingInfantry
            { playback = animation
            , paused = False
            , camera = camera
            }
    }


syncPlaybackAudio :
    { before : PlaybackAudio, after : PlaybackAudio }
    -> Eff msg
syncPlaybackAudio { before, after } =
    E.batch
        [ E.audio
            (Audio.syncMovement
                { before = before.movement, after = after.movement }
            )
        , E.audio
            (Audio.syncAmbience
                { before = before.ambience, after = after.ambience }
            )
        , E.audio
            (Audio.syncInfantryFire
                { before = before.infantryFire
                , after = after.infantryFire
                }
            )
        ]


withPlaybackAudio : PlaybackAudio -> Model -> ( Model, Eff Msg )
withPlaybackAudio before model =
    ( model
    , syncPlaybackAudio
        { before = before, after = playbackAudio model }
    )


unitLoss : Model -> Maybe TurnPlayback.Loss
unitLoss model =
    PlaybackPresentation.loss model.skipUnitLossDialogs (playback model)


ownerName : Model -> Unit -> Maybe String
ownerName model =
    PlaybackPresentation.ownerName model.players


combatEncounter : Model -> Maybe TurnPlayback.Encounter
combatEncounter model =
    playback model |> Maybe.andThen TurnPlayback.activeEncounter


deathInFocus : Model -> Bool
deathInFocus model =
    List.any
        (\unit -> Unit.onMap unit && Unit.isDying unit)
        model.units


planningLocked : Model -> Bool
planningLocked model =
    model.currentTurn.outcome /= Nothing || TurnLifecycle.planningLocked model.currentTurn.phase


unitsWithoutOrders : Model -> List Unit
unitsWithoutOrders model =
    OrderPlanning.missingOrders
        model.map
        model.units
        (ownPlayerNumbers model)
        (plannedOrders model)


readyToSubmit : Model -> Bool
readyToSubmit model =
    not (planningLocked model) && List.isEmpty (unitsWithoutOrders model)


submitTurn : LobbyId -> Model -> ( Model, Eff Msg )
submitTurn lobbyId model =
    case CurrentTurn.startSubmission model.currentTurn of
        Just currentTurn ->
            let
                sendOrders :
                    Maybe OrderPlanning.InvariantViolation
                    -> List PlannedOrder
                    -> ( Model, Eff Msg )
                sendOrders violation orders =
                    case violation of
                        Nothing ->
                            model
                                |> setCurrentTurn currentTurn
                                |> resumeChatOverlay (showTurnIntroduction model)
                                |> E.and
                                    (E.request
                                        (SubmitResponseReceived model.currentTurn.number)
                                        (submitRequest lobbyId model.currentTurn.number orders)
                                    )

                        Just failure ->
                            model
                                |> mapPlanning OrderPlanning.dismissDialog
                                |> setSubmissionPreparationError failure
                                |> E.withOut
            in
            OrderPlanning.submissionOrders
                model.map
                model.units
                (ownPlayerNumbers model)
                (plannedOrders model)
                |> IC.resolve sendOrders

        Nothing ->
            ( model, E.none )


setSubmissionPreparationError : OrderPlanning.InvariantViolation -> Model -> Model
setSubmissionPreparationError failure model =
    let
        message : String
        message =
            "an order could not be prepared for one of your units."
    in
    model
        |> setCurrentTurn
            (CurrentTurn.setError (Just (CurrentTurn.SubmissionError message)) model.currentTurn)
        |> recordPlanningViolation (Just failure)


unloadDialogHtmlId : String
unloadDialogHtmlId =
    "unload-passengers"


selectedUnit : Model -> Maybe Unit
selectedUnit model =
    selectedBattlefieldUnit model
        |> Maybe.map
            (PlannedTransport.planningUnit
                model.map
                (plannedOrders model)
            )


selectedUnitId : Model -> Maybe UnitId
selectedUnitId model =
    selectedBattlefieldUnit model |> Maybe.map .id


selectedBattlefieldUnit : Model -> Maybe Unit
selectedBattlefieldUnit model =
    OrderPlanning.selectedUnitFromSelection
        model.units
        (currentSelection model)


selectedPosition : Model -> Maybe Coordinate
selectedPosition model =
    case unloadPlanning model.currentTurn.phase of
        Just planning ->
            Just (UnloadingTruck.destination planning.truck)

        Nothing ->
            inspectionPosition model


inspectionPosition : Model -> Maybe Coordinate
inspectionPosition model =
    case currentSelection model of
        Just (Inspecting (TileInspection position)) ->
            Just position

        Just (Inspecting (UnitInspection _)) ->
            Maybe.andThen Unit.mapPosition (selectedUnit model)

        Just (UnitSelection _) ->
            Maybe.andThen Unit.mapPosition (selectedUnit model)

        Nothing ->
            Nothing


isOwnUnit : Model -> Unit -> Bool
isOwnUnit model unit =
    OrderPlanning.isOwnUnit (ownPlayerNumbers model) unit


applyOrder : UnitOrder.Order -> Model -> Model
applyOrder order model =
    model
        |> mapCheckedPlanning
            (OrderPlanning.applyOrder
                model.map
                model.units
                (ownPlayerNumbers model)
                model.movementRules
                (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                model.depots
                order
            )


plannedUnloadRoutes : Model -> List UnloadRoute
plannedUnloadRoutes model =
    let
        truckUnloads : PlannedOrder -> List UnloadRoute
        truckUnloads plan =
            let
                route : UnloadOrder -> Maybe UnloadRoute
                route unload =
                    let
                        withDirection : Direction -> UnloadRoute
                        withDirection direction =
                            { unitId = unload.unitId
                            , origin = PlannedOrder.destination plan
                            , direction = direction
                            }
                    in
                    Direction.between
                        (PlannedOrder.destination plan)
                        unload.destination
                        |> Maybe.map withDirection
            in
            List.filterMap route (PlannedOrder.unloads plan)
    in
    List.concatMap truckUnloads (plannedOrders model)


focusedOrder : Model -> Maybe UnitOrder.MenuOption
focusedOrder model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.andThen OrderPlanning.focusedOrder


orderMenuUnit : Model -> Maybe Unit
orderMenuUnit model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.andThen
            (OrderPlanning.orderMenuUnit model.map model.units)


submitRequest : LobbyId -> Int -> List PlannedOrder -> Graphql.Http.Request Snapshot
submitRequest lobbyId turnNumber orders =
    Api.Mutation.submitTurn
        { id = LobbyId.toString lobbyId
        , turnNumber = turnNumber
        , orders = List.map PlannedOrder.toInput orders
        }
        snapshotSelection
        |> ApiRequest.mutationRequest


turnObservation : Snapshot -> CurrentTurn.Observation
turnObservation snapshot =
    { turn = snapshot.turn
    , playbackFrames = snapshot.playbackFrames
    }


applyTurnSnapshot :
    LobbyId
    -> Snapshot
    -> CurrentTurn.Model
    -> Model
    -> ( Model, Eff Msg )
applyTurnSnapshot lobbyId snapshot currentTurn model =
    let
        next : Model
        next =
            model
                |> setCurrentTurn currentTurn
                |> reconcileActivityTurn model.currentTurn.number
                |> reconcileTurnSnapshot snapshot model.currentTurn

        transition : ( Model, Eff Msg )
        transition =
            case ( playback model, playback next ) of
                ( Nothing, Just _ ) ->
                    startPlayback next

                ( Just _, Nothing ) ->
                    finishPlayback (playbackCamera model) next

                _ ->
                    next
                        |> closeMenuForTurnIntroduction
                        |> E.withOut
    in
    transition
        |> E.andThen (renewInactivityTimer lobbyId model.shared.now)
        |> E.andThen
            (resumeChatOverlay (chatOverlayPaused model))


reconcileActivityTurn : Int -> Model -> Model
reconcileActivityTurn previousTurn model =
    if model.currentTurn.number > previousTurn then
        { model | inactivity = Inactivity.nextTurn model.inactivity }

    else
        model


reconcileTurnSnapshot : Snapshot -> CurrentTurn.Model -> Model -> Model
reconcileTurnSnapshot snapshot previousTurn model =
    if previousTurn.outcome /= Nothing then
        model

    else if GameOutcome.interruptsPlayback model.currentTurn.outcome then
        { model
            | welcomeBriefingPending = False
            , inspectionHelp = Nothing
        }
            |> setChat (Chat.close model.chat)
            |> setMap snapshot.battlefield.map
            |> setDepots snapshot.battlefield.depots
            |> setSupplyCrates snapshot.battlefield.supplyCrates
            |> setUnits snapshot.battlefield.units
            |> setVisibleTiles snapshot.battlefield.visibleTiles
            |> setMenu MenuClosed
            |> setNavigation (BattlefieldNavigation.finishReturn model.navigation)

    else if model.currentTurn.number > previousTurn.number then
        let
            applyFrame : Maybe TurnPlayback.InvariantViolation -> TurnPlayback.Frame -> Model
            applyFrame violation frame =
                { model | supplyRules = snapshot.supplyRules }
                    |> setMap snapshot.battlefield.map
                    |> setDepots frame.depots
                    |> setSupplyCrates frame.supplyCrates
                    |> setUnits frame.units
                    |> setVisibleTiles frame.visibleTiles
                    |> setShared (Shared.addError (Maybe.map Error.TurnPlaybackInvariantViolated violation) model.shared)
        in
        TurnPlayback.initial
            { resolvedTurn = snapshot.turn.number - 1
            , frames = snapshot.playbackFrames
            }
            { departures = []
            , losses = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            , units = snapshot.battlefield.units
            , visibleTiles = snapshot.battlefield.visibleTiles
            , depots = snapshot.battlefield.depots
            , supplyCrates = snapshot.battlefield.supplyCrates
            }
            |> IC.resolve applyFrame

    else
        model


plannedAction : Model -> Unit -> Movement.Option -> String
plannedAction model unit move =
    if Unit.carrierId unit /= Nothing && List.length move.path > 1 then
        "unload at"

    else if
        PlannedTransport.loadingTarget
            model.units
            unit
            move.destination
            (plannedOrders model)
            /= Nothing
    then
        "load at"

    else
        "move to"


receivingLoad : Unit -> Model -> Bool
receivingLoad unit model =
    PlannedTransport.receivingLoad
        model.units
        unit
        (plannedOrders model)


currentSelection : Model -> Maybe Selection
currentSelection model =
    TurnLifecycle.selection model.currentTurn.phase


setSelection : Maybe Selection -> Model -> Model
setSelection selected model =
    model
        |> setCurrentTurn (CurrentTurn.setSelection selected model.currentTurn)


focusOrder : UnitOrder.MenuOption -> Model -> Model
focusOrder order model =
    model
        |> mapPlanning
            (OrderPlanning.focusOrder model.map model.units order)


revokeSelectedOrder : Model -> Model
revokeSelectedOrder model =
    model
        |> mapCheckedPlanning
            (OrderPlanning.revokeSelectedOrder model.map model.units (ownPlayerNumbers model))


choosingDirection : Model -> Bool
choosingDirection model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.choosingDirection
        |> Maybe.withDefault False


saveDirection : Direction -> Model -> Model
saveDirection direction model =
    model
        |> mapCheckedPlanning
            (OrderPlanning.saveDirection model.map model.units (ownPlayerNumbers model) direction)


rotationSelection : Model -> Maybe RotationSelection
rotationSelection model =
    let
        atPosition : UnitId -> Direction -> Coordinate -> RotationSelection
        atPosition unitId direction position =
            { unitId = unitId
            , position = position
            , direction = direction
            }
    in
    case ( currentSelection model, selectedUnit model ) of
        ( Just (UnitSelection selection), Just unit ) ->
            case selection.interaction of
                ChoosingDirection planning ->
                    case planning of
                        DirectionPlanning.AttackMove move direction ->
                            Just { unitId = unit.id, position = move.destination, direction = direction }

                        DirectionPlanning.Stationary _ direction ->
                            Unit.mapPosition unit
                                |> Maybe.map (atPosition unit.id direction)

                OrderMenu _ ->
                    Nothing

                ChoosingIndirectFire _ ->
                    Nothing

                ChoosingMove _ ->
                    Nothing

        _ ->
            Nothing


previewDirection : Direction -> Model -> Model
previewDirection direction model =
    if BattlefieldNavigation.active model.navigation then
        model

    else
        model
            |> mapPlanning (OrderPlanning.previewDirection direction)


loadSnapshot : LobbyId -> Graphql.Http.Request Snapshot
loadSnapshot id =
    Api.Query.game { id = LobbyId.toString id } snapshotSelection
        |> ApiRequest.queryRequest


pollRequest : LobbyId -> Graphql.Http.Request PollStatus
pollRequest id =
    Api.Query.game { id = LobbyId.toString id } pollStatusSelection
        |> ApiRequest.queryRequest


pollStatusSelection : SelectionSet PollStatus Api.Object.GameSnapshot
pollStatusSelection =
    SS.succeed PollStatus
        |> SS.with Inactivity.selection
        |> SS.with SnapshotApi.turnNumber
        |> SS.with (SnapshotApi.outcome GameOutcome.selection)
        |> SS.with SnapshotApi.submitted
        |> SS.with SnapshotApi.opponentSubmitted


snapshotSelection : SelectionSet Snapshot Api.Object.GameSnapshot
snapshotSelection =
    SS.succeed Snapshot
        |> SS.with Inactivity.selection
        |> SS.with BattlefieldSnapshot.selection
        |> SS.with (SnapshotApi.scenario (Scenario.supplyRules Supply.rulesSelection))
        |> SS.with (SnapshotApi.movementRules Movement.ruleSelection)
        |> SS.with Turn.selection
        |> SS.with (TurnPlayback.selection Unit.selection Coordinate.selection)


destinationFeedback : Model -> DestinationFeedback
destinationFeedback model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.destinationFeedback
        |> Maybe.withDefault NoDestinationFeedback


pathPreview : Model -> Maybe Movement.Option
pathPreview model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.andThen OrderPlanning.pathPreview


clearSelection : Model -> Model
clearSelection model =
    setSelection Nothing model


selectUnit : UnitId -> Model -> Model
selectUnit id model =
    if planningLocked model then
        case ListUtil.find (\unit -> unit.id == id) model.units of
            Just unit ->
                if Maybe.map .id (selectedUnit model) == Just id then
                    clearSelection model

                else
                    setSelection (Just (Inspecting (UnitInspection unit.id))) model

            Nothing ->
                model

    else
        model
            |> mapCheckedPlanning
                (OrderPlanning.selectUnit
                    model.map
                    model.units
                    (ownPlayerNumbers model)
                    model.movementRules
                    (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                    model.depots
                    id
                )


selectTile : Coordinate -> Model -> Model
selectTile position model =
    if planningLocked model then
        setSelection (Just (Inspecting (TileInspection position))) model

    else
        model
            |> mapCheckedPlanning
                (OrderPlanning.selectTile
                    model.map
                    model.units
                    (ownPlayerNumbers model)
                    model.movementRules
                    (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                    model.depots
                    position
                )


inspectDepot : Coordinate -> Model -> Model
inspectDepot position model =
    if choosingIndirectFire model then
        selectTile position model

    else
        setSelection (Just (Inspecting (TileInspection position))) model


previewUnit : UnitId -> Model -> Model
previewUnit id model =
    if planningLocked model then
        model

    else
        model.units
            |> ListUtil.find (\unit -> unit.id == id)
            |> Maybe.andThen Unit.mapPosition
            |> Maybe.map (\position -> previewTile position model)
            |> Maybe.withDefault model


previewTile : Coordinate -> Model -> Model
previewTile position model =
    if BattlefieldNavigation.active model.navigation && pathPreview model == Nothing then
        model

    else
        model
            |> mapPlanning
                (OrderPlanning.previewTile
                    model.map
                    model.units
                    (ownPlayerNumbers model)
                    model.movementRules
                    position
                )


extendPath : Direction -> Model -> Model
extendPath direction model =
    if BattlefieldNavigation.active model.navigation then
        model

    else
        model
            |> mapPlanning
                (OrderPlanning.extendPath
                    model.map
                    model.units
                    (ownPlayerNumbers model)
                    model.movementRules
                    direction
                )


confirmPath : Model -> Model
confirmPath model =
    model
        |> mapCheckedPlanning
            (OrderPlanning.confirmPath
                model.map
                model.units
                (ownPlayerNumbers model)
                model.movementRules
                (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                model.depots
            )


focusAdjacentOrder :
    (List UnitOrder.MenuOption -> List UnitOrder.MenuOption)
    -> Maybe UnitOrder.MenuOption
    -> Model
    -> Eff Msg
focusAdjacentOrder arrangeOptions current model =
    let
        afterCurrent : List UnitOrder.MenuOption -> List UnitOrder.MenuOption
        afterCurrent remaining =
            case remaining of
                [] ->
                    []

                order :: rest ->
                    if Just order == current then
                        rest

                    else
                        afterCurrent rest
    in
    case orderMenuUnit model of
        Just unit ->
            let
                orders : List UnitOrder.MenuOption
                orders =
                    UnitOrder.enabledOptions model.map model.depots unit
                        |> arrangeOptions

                adjacent : Maybe UnitOrder.MenuOption
                adjacent =
                    case afterCurrent orders |> List.head of
                        Just order ->
                            Just order

                        Nothing ->
                            List.head orders
            in
            case adjacent of
                Just order ->
                    E.focus
                        { htmlId = OrderMenu.optionHtmlId order }
                        OrderFocusCompleted

                Nothing ->
                    E.none

        Nothing ->
            E.none


mapNavigation : (BattlefieldNavigation.Model -> BattlefieldNavigation.Model) -> Model -> Model
mapNavigation change model =
    (model
        |> setNavigation (change model.navigation |> BattlefieldNavigation.finishReturn)
    )
        |> updatePlaybackCamera


handleBattlefieldTouch : BattlefieldNavigation.TouchInput -> Model -> Model
handleBattlefieldTouch input model =
    let
        mode : BattlefieldNavigation.DragMode
        mode =
            if pathPreview model /= Nothing then
                BattlefieldNavigation.TraceRoute

            else
                BattlefieldNavigation.PanCamera

        touched : BattlefieldNavigation.TouchUpdate
        touched =
            BattlefieldNavigation.touchWithRoute mode input model.navigation

        next : Model
        next =
            mapNavigation (always touched.navigation) model

        routeAt :
            (Coordinate -> Model -> Model)
            -> Point
            -> Model
            -> Model
        routeAt action point state =
            case ( pathPreview state, state.battlefieldViewport ) of
                ( Just _, Just viewport ) ->
                    Camera.coordinateAt
                        viewport.camera.size
                        state.map
                        (BattlefieldNavigation.camera state.navigation)
                        { x = point.x - viewport.origin.x
                        , y = point.y - viewport.origin.y
                        }
                        |> Maybe.map (\position -> action position state)
                        |> Maybe.withDefault state

                _ ->
                    state

        traceContact : BattlefieldNavigation.TouchRoute -> Model -> Model
        traceContact contact =
            case contact of
                BattlefieldNavigation.TraceAt point ->
                    routeAt previewTile point

                BattlefieldNavigation.ReleaseAt point ->
                    routeAt selectTile point
    in
    List.foldl traceContact next touched.route


groundPickupDialogHtmlId : String
groundPickupDialogHtmlId =
    "ground-freight-pickup-dialog"


loadCratesDialogHtmlId : String
loadCratesDialogHtmlId =
    "load-supply-crates-dialog"


suppressesBattlefieldClick : { detail : Int } -> Model -> Bool
suppressesBattlefieldClick click model =
    (click.detail /= 0)
        && BattlefieldNavigation.suppressesClick model.navigation


choosingIndirectFire : Model -> Bool
choosingIndirectFire model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.choosingIndirectFire
        |> Maybe.withDefault False


indirectFireDetails : Unit -> List (Html Msg)
indirectFireDetails unit =
    let
        costs : String
        costs =
            "range: "
                ++ String.fromInt unit.combatRules.indirectRange
                ++ " tiles · supplies: upkeep + "
                ++ String.fromInt unit.combatRules.readinessCost
                ++ " readiness + "
                ++ String.fromInt unit.combatRules.shotCost
                ++ " per shot"
    in
    [ H.p
        []
        [ H.text "choose any tile in range, including fog. fires after movement and unloading at whoever remains there; friendly units can be hit. empty tiles waste the shot. unseen hits stay unconfirmed."
        ]
    , H.p
        []
        [ H.text costs
        ]
    ]


battlefieldMsgCountsAsInteraction : Battlefield.Msg -> Bool
battlefieldMsgCountsAsInteraction msg =
    case msg of
        Battlefield.PanLeftClicked ->
            True

        Battlefield.PanRightClicked ->
            True

        Battlefield.PanUpClicked ->
            True

        Battlefield.PanDownClicked ->
            True

        Battlefield.ZoomInClicked ->
            True

        Battlefield.ZoomOutClicked ->
            True

        Battlefield.ResetViewClicked ->
            True

        Battlefield.RotationChoicesMsg rotationMsg ->
            case rotationMsg of
                RotationChoices.MouseMovedOverDirection _ ->
                    False

                RotationChoices.FocusedDirection _ ->
                    False

                RotationChoices.ClickedDirection _ ->
                    True

                RotationChoices.DirectionActivationKeyPressed _ ->
                    True

        Battlefield.ClickedUnit _ _ ->
            True

        Battlefield.PressedEnterOnUnit _ ->
            True

        Battlefield.PressedSpaceOnUnit _ ->
            True

        Battlefield.MouseOverUnit _ ->
            False

        Battlefield.ClickedDepot _ _ ->
            True

        Battlefield.PressedEnterOnDepot _ ->
            True

        Battlefield.PressedSpaceOnDepot _ ->
            True

        Battlefield.MouseOverDepot _ ->
            False

        Battlefield.ClickedDepotStock _ _ ->
            True

        Battlefield.PressedEnterOnDepotStock _ ->
            True

        Battlefield.PressedSpaceOnDepotStock _ ->
            True

        Battlefield.ClickedTile _ _ ->
            True

        Battlefield.PressedEnterOnTile _ ->
            True

        Battlefield.PressedSpaceOnTile _ ->
            True

        Battlefield.FocusedBoardUnit _ ->
            False

        Battlefield.FocusedBoardTile _ ->
            False

        Battlefield.TargetPreviewLeft ->
            False

        Battlefield.MouseOverTile _ ->
            False

        Battlefield.PointerPressed _ ->
            True

        Battlefield.TouchInputReceived _ ->
            True

        Battlefield.WheelScrolled _ _ ->
            True

        Battlefield.HomePressed ->
            True


handleBattlefieldMsg : Battlefield.Msg -> Model -> Model
handleBattlefieldMsg msg model =
    case msg of
        Battlefield.PanLeftClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panLeft

        Battlefield.PanRightClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panRight

        Battlefield.PanUpClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panUp

        Battlefield.PanDownClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panDown

        Battlefield.ZoomInClicked ->
            model
                |> mapNavigation BattlefieldNavigation.zoomIn

        Battlefield.ZoomOutClicked ->
            model
                |> mapNavigation BattlefieldNavigation.zoomOut

        Battlefield.ResetViewClicked ->
            model
                |> mapNavigation BattlefieldNavigation.resetViewport

        Battlefield.RotationChoicesMsg rotationMsg ->
            case rotationMsg of
                RotationChoices.MouseMovedOverDirection direction ->
                    previewDirection direction model

                RotationChoices.FocusedDirection direction ->
                    previewDirection direction model

                RotationChoices.DirectionActivationKeyPressed direction ->
                    saveDirection direction model

                RotationChoices.ClickedDirection direction ->
                    if BattlefieldNavigation.suppressesClick model.navigation then
                        model

                    else
                        saveDirection direction model

        Battlefield.ClickedUnit id click ->
            if suppressesBattlefieldClick click model then
                model

            else
                selectUnit id model

        Battlefield.PressedEnterOnUnit id ->
            let
                confirmsSelectedUnitPreview : Bool
                confirmsSelectedUnitPreview =
                    (pathPreview model /= Nothing)
                        && (Maybe.map .id (selectedUnit model) == Just id)
            in
            if confirmsSelectedUnitPreview then
                confirmPath model

            else
                selectUnit id model

        Battlefield.PressedSpaceOnUnit id ->
            model
                |> selectUnit id

        Battlefield.MouseOverUnit id ->
            previewUnit id model

        Battlefield.ClickedDepot position click ->
            if suppressesBattlefieldClick click model then
                model

            else
                selectTile position model

        Battlefield.PressedEnterOnDepot position ->
            model
                |> selectTile position

        Battlefield.PressedSpaceOnDepot position ->
            model
                |> selectTile position

        Battlefield.MouseOverDepot position ->
            if planningLocked model then
                model

            else
                previewTile position model

        Battlefield.ClickedDepotStock position click ->
            if suppressesBattlefieldClick click model then
                model

            else
                inspectDepot position model

        Battlefield.PressedEnterOnDepotStock position ->
            inspectDepot position model

        Battlefield.PressedSpaceOnDepotStock position ->
            inspectDepot position model

        Battlefield.ClickedTile position click ->
            if suppressesBattlefieldClick click model then
                model

            else
                selectTile position model

        Battlefield.PressedEnterOnTile position ->
            model
                |> selectTile position

        Battlefield.PressedSpaceOnTile position ->
            model
                |> selectTile position

        Battlefield.FocusedBoardUnit id ->
            if choosingIndirectFire model then
                previewUnit id model

            else
                model

        Battlefield.FocusedBoardTile position ->
            if choosingIndirectFire model then
                previewTile position model

            else
                model

        Battlefield.TargetPreviewLeft ->
            mapPlanning OrderPlanning.clearTargetPreview model

        Battlefield.MouseOverTile position ->
            if planningLocked model then
                model

            else
                previewTile position model

        Battlefield.TouchInputReceived input ->
            handleBattlefieldTouch input model

        Battlefield.PointerPressed point ->
            model
                |> mapNavigation (BattlefieldNavigation.press point)

        Battlefield.WheelScrolled anchor delta ->
            model
                |> mapNavigation (BattlefieldNavigation.scroll anchor delta)

        Battlefield.HomePressed ->
            model
                |> mapNavigation BattlefieldNavigation.resetViewport


canSurrender : Model -> Bool
canSurrender model =
    canOpenDialog model
        && not model.resigning
        && (model.currentTurn.outcome == Nothing)


requestResignation : ResignationDestination -> Model -> ( Model, Eff Msg )
requestResignation destination model =
    let
        canRequestResignation : Bool
        canRequestResignation =
            case destination of
                RemainInGame ->
                    canSurrender model

                GoHome ->
                    (model.menu == MainMenu)
                        && not model.resigning
                        && (model.currentTurn.outcome == Nothing)
    in
    if canRequestResignation then
        ( model
            |> setMenu (ConfirmingResignation destination)
        , E.focus
            { htmlId = GameMenu.resignationCancelButtonHtmlId }
            (GameMenu.FocusReturned >> GameMenuMsg)
        )

    else
        model
            |> E.withOut


resignGame : LobbyId -> ResignationDestination -> Model -> ( Model, Eff Msg )
resignGame lobbyId destination model =
    let
        canResign : Bool
        canResign =
            (model.menu == ConfirmingResignation destination)
                && not model.resigning
                && (model.currentTurn.outcome == Nothing)
    in
    if canResign then
        ( model
            |> setResigning True
            |> setMenu MenuClosed
        , Api.Mutation.resignGame { id = LobbyId.toString lobbyId } snapshotSelection
            |> ApiRequest.mutationRequest
            |> E.request (ResignResponseReceived destination)
        )

    else
        model
            |> E.withOut


recordFocusResult : Result Browser.Dom.Error () -> Model -> Model
recordFocusResult result model =
    case result of
        Ok () ->
            model

        Err error ->
            model
                |> setShared (Shared.addError (Just (Error.ElementFocusFailed error)) model.shared)


{-| Retain playback framing across subject changes. Only projected positions
can request a pan, and the saved planning navigation remains independent.
-}
updatePlaybackCamera : Model -> Model
updatePlaybackCamera model =
    case ( model.currentTurn.phase, model.battlefieldViewport ) of
        ( TurnLifecycle.Playing playing, Just viewport ) ->
            let
                held : PlaybackPresentation.PlaybackCamera
                held =
                    PlaybackPresentation.frameCamera
                        viewport.camera
                        model.map
                        (BattlefieldNavigation.camera model.navigation)
                        playing.animation
                        playing.camera

                currentTurn : CurrentTurn.Model
                currentTurn =
                    model.currentTurn
            in
            model
                |> setCurrentTurn
                    (currentTurn
                        |> CurrentTurn.setPhase
                            (TurnLifecycle.Playing
                                (playing
                                    |> TurnLifecycle.setPlaybackCamera (Just held)
                                )
                            )
                    )

        _ ->
            model


playbackCamera : Model -> Maybe TurnLifecycle.PlaybackCamera
playbackCamera model =
    phasePlaybackCamera model.currentTurn.phase


phasePlaybackCamera : Phase -> Maybe TurnLifecycle.PlaybackCamera
phasePlaybackCamera phase =
    case phase of
        TurnLifecycle.Playing playing ->
            playing.camera

        _ ->
            Nothing


measureWorkspace : Eff Msg
measureWorkspace =
    E.measure Battlefield.htmlId BattlefieldSizeReceived


remeasureWorkspace : Model -> ( Model, Eff Msg )
remeasureWorkspace model =
    ( model
        |> setBattlefieldViewport Nothing
    , measureWorkspace
    )


resetMobileTab : Maybe UnitId -> Model -> Model
resetMobileTab previousUnitId next =
    let
        selectionChanged : Bool
        selectionChanged =
            previousUnitId /= selectedUnitId next
    in
    if selectionChanged then
        let
            tab : MobileBattlefield.Tab
            tab =
                if mobileOrdersAvailable next then
                    MobileBattlefield.Orders

                else
                    MobileBattlefield.Details
        in
        { next | mobileTab = tab }

    else
        next


workspaceLayout : Model -> WorkspaceLayout
workspaceLayout model =
    { inspectorOpen = currentSelection model /= Nothing
    , activity = turnActivity model
    , outcome = model.currentTurn.outcome
    , playing = playback model /= Nothing
    }


{-| Selection changes the inspector inset; turn controls can change
the height available to the battlefield. Playback start requests its own fresh
measurement, so this check does not request a second one for that transition.
-}
withLayoutMeasurement : WorkspaceLayout -> Model -> ( Model, Eff Msg )
withLayoutMeasurement previousLayout model =
    let
        layout : WorkspaceLayout
        layout =
            workspaceLayout model

        playbackStarted : Bool
        playbackStarted =
            not previousLayout.playing && layout.playing

        layoutChanged : Bool
        layoutChanged =
            (previousLayout.inspectorOpen /= layout.inspectorOpen)
                || (previousLayout.activity /= layout.activity)
                || (previousLayout.outcome /= layout.outcome)
    in
    if layoutChanged && not playbackStarted then
        remeasureWorkspace model

    else
        model
            |> E.withOut


closeMenuForTurnIntroduction : Model -> Model
closeMenuForTurnIntroduction model =
    if showTurnIntroduction model then
        { model | inspectionHelp = Nothing }
            |> setMenu MenuClosed

    else
        model


startPlayback : Model -> ( Model, Eff Msg )
startPlayback model =
    remeasureWorkspace
        ({ model | inspectionHelp = Nothing }
            |> setMenu MenuClosed
            |> setChat (Chat.hide model.chat)
        )


finishPlayback : Maybe TurnLifecycle.PlaybackCamera -> Model -> ( Model, Eff Msg )
finishPlayback previousCamera next =
    let
        ( returned, cameraEffect ) =
            if previousCamera /= Nothing then
                ( next
                    |> setNavigation (BattlefieldNavigation.startReturn next.navigation)
                , E.after PlaybackPresentation.cameraPanDurationMs CameraReturnFinished
                )

            else
                next
                    |> E.withOut
    in
    returned
        |> closeMenuForTurnIntroduction
        |> E.with cameraEffect


presentPlaybackTransition : Phase -> Model -> ( Model, Eff Msg )
presentPlaybackTransition previous next =
    case ( TurnLifecycle.playback previous, playback next ) of
        ( Just _, Nothing ) ->
            finishPlayback (phasePlaybackCamera previous) next

        _ ->
            next
                |> updatePlaybackCamera
                |> E.withOut


turnActivity : Model -> TurnControls.Activity
turnActivity model =
    let
        submitLocked : Bool
        submitLocked =
            planningLocked model || isChoosingUnload model || choosingDirection model
    in
    case model.currentTurn.phase of
        TurnLifecycle.Submitting _ ->
            TurnControls.Submitting

        TurnLifecycle.WaitingForOpponent _ ->
            TurnControls.Waiting

        TurnLifecycle.Playing _ ->
            TurnControls.Playing

        TurnLifecycle.Planning _ ->
            if submitLocked then
                TurnControls.Locked

            else if readyToSubmit model then
                TurnControls.Ready

            else
                TurnControls.Planning


applyChatUpdate : Chat.Model -> Model -> ( Model, Eff Msg )
applyChatUpdate chat model =
    let
        next : Model
        next =
            setChat chat model

        effects : Eff Msg
        effects =
            if chat.overlayVersion /= model.chat.overlayVersion then
                E.batch [ chatExpiration next, scrollChatHistory next.chat next.shared ]

            else
                E.none
    in
    ( next, effects )


chatHistoryVisible : Chat.Model -> Shared.Model -> Bool
chatHistoryVisible chat shared =
    if Shared.isMobileView shared then
        Chat.isOpen chat

    else
        Chat.historyVisible chat


scrollChatHistory : Chat.Model -> Shared.Model -> Eff Msg
scrollChatHistory chat shared =
    let
        canFollow : Bool
        canFollow =
            chatHistoryVisible chat shared
                && Chat.followsHistory chat
                && not shared.devPanelOpen
    in
    if canFollow then
        E.scrollToBottom { htmlId = ChatView.messagesHtmlId } ChatScrollCompleted

    else
        E.none


chatExpiration : Model -> Eff Msg
chatExpiration model =
    if chatOverlayPaused model || List.isEmpty model.chat.recent then
        E.none

    else
        E.after 8000 (ChatOverlayExpired model.chat.overlayVersion)


chatOverlayPaused : Model -> Bool
chatOverlayPaused model =
    model.welcomeBriefingPending || showTurnIntroduction model


resumeChatOverlay : Bool -> Model -> ( Model, Eff Msg )
resumeChatOverlay wasPaused model =
    if wasPaused then
        ( model, chatExpiration model )

    else
        E.withOut model


openChat : Model -> ( Model, Eff Msg )
openChat model =
    if canOpenDialog model then
        ( model
            |> setCombatEnterHeld False
            |> setChat (Chat.open model.chat)
        , E.focus { htmlId = ChatView.inputHtmlId } FocusCompleted
        )

    else
        model
            |> E.withOut


sendChat : LobbyId -> Model -> ( Model, Eff Msg )
sendChat lobbyId model =
    case Chat.prepareSend model.shared.seed model.chat of
        Just ( chat, seed, submission ) ->
            ( model
                |> setChat (Chat.close chat)
                |> setShared (Shared.setSeed seed model.shared)
            , E.batch
                [ E.request (ChatSendReceived submission) (Chat.sendRequest lobbyId submission)
                , E.audio Audio.chatSent
                , E.focus { htmlId = Battlefield.htmlId } FocusCompleted
                ]
            )

        Nothing ->
            model
                |> E.withOut


pollChat : LobbyId -> Model -> ( Model, Eff Msg )
pollChat lobbyId model =
    case Chat.beginPoll model.chat of
        Nothing ->
            model
                |> E.withOut

        Just chat ->
            ( model
                |> setChat chat
            , Chat.query lobbyId chat.cursor
                |> ApiRequest.queryRequest
                |> E.request ChatPollReceived
            )


{-| Classify the player input that renews the inactivity clock.
-}
isUserInteraction : Msg -> Bool
isUserInteraction msg =
    case msg of
        StillHereClicked ->
            True

        FeedbackMsg _ ->
            True

        ChatMsg ChatView.OpenPressed ->
            True

        ChatMsg ChatView.CloseClicked ->
            True

        ChatMsg (ChatView.TextChanged _) ->
            True

        ChatMsg ChatView.HistoryClicked ->
            True

        ChatMsg ChatView.SendPressed ->
            True

        ChatMsg ChatView.RetrySendPressed ->
            True

        ChatMsg ChatView.RetryUpdatesPressed ->
            True

        ChatMsg ChatView.DismissErrorClicked ->
            True

        BattlefieldMsg battlefieldMsg ->
            battlefieldMsgCountsAsInteraction battlefieldMsg

        BattlefieldNavigationMsg (BattlefieldNavigation.MouseReleased _) ->
            True

        OrderMenuMsg OrderMenu.InfoClicked ->
            True

        OrderMenuMsg OrderMenu.CancelClicked ->
            True

        OrderMenuMsg (OrderMenu.OrderPicked _) ->
            True

        OrderMenuMsg (OrderMenu.ArrowedUpOrderMenu _) ->
            True

        OrderMenuMsg (OrderMenu.ArrowedDownOrderMenu _) ->
            True

        GameMenuMsg GameMenu.ChatClicked ->
            True

        GameMenuMsg GameMenu.OpenClicked ->
            True

        GameMenuMsg GameMenu.FeedbackClicked ->
            True

        GameMenuMsg GameMenu.AboutClicked ->
            True

        GameMenuMsg GameMenu.SettingsClicked ->
            True

        GameMenuMsg GameMenu.DevPanelClicked ->
            True

        GameMenuMsg GameMenu.CloseClicked ->
            True

        GameMenuMsg GameMenu.ResignationConfirmed ->
            True

        GameMenuMsg GameMenu.ResignationCanceled ->
            True

        GameMenuMsg GameMenu.HomeClicked ->
            True

        SettingsMsg _ ->
            True

        PreviousOrderPressed ->
            True

        NextOrderPressed ->
            True

        PanLeftKeyPressed ->
            True

        PanRightKeyPressed ->
            True

        PanUpKeyPressed ->
            True

        PanDownKeyPressed ->
            True

        ZoomInKeyPressed ->
            True

        ZoomOutKeyPressed ->
            True

        TurnIntroductionMsg _ ->
            True

        UnitDeathMsg _ ->
            True

        CombatTheaterMsg _ ->
            True

        DirectionKeyPressed _ ->
            True

        PathDirectionKeyPressed _ ->
            True

        PathEnterPressed ->
            True

        NextUnorderedUnitKeyPressed ->
            True

        ClearMoveClicked ->
            True

        CancelOrderClicked ->
            True

        CargoUnitClicked _ ->
            True

        LoadCratesClicked _ _ ->
            True

        GroundFreightPickupClicked ->
            True

        UnloadCrateToggled _ _ ->
            True

        UnloadUnitToggled _ _ ->
            True

        UnloadChoicesConfirmed ->
            True

        UnloadSkipped ->
            True

        InspectClicked ->
            True

        InspectorCloseClicked ->
            True

        MobileTabClicked _ ->
            True

        MobileTabNavigationPressed _ ->
            True

        InspectionHelpClicked _ ->
            True

        EscapePressed ->
            True

        WelcomeBriefingDismissed ->
            True

        DialogDismissed ->
            True

        SubmissionCancelled ->
            True

        SubmissionConfirmed ->
            True

        SubmitKeyPressed ->
            True

        SkipUnplannedUnitsWarningChanged _ ->
            True

        TurnControlsMsg _ ->
            True

        RequestRetryClicked ->
            True

        RequestErrorDismissed ->
            True

        CurrentTurnMsg (CurrentTurn.GotPlaybackPresentationMsg PlaybackPresentation.CombatEnterReleased) ->
            True

        _ ->
            False


recordUserInteraction : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
recordUserInteraction lobbyId msg model =
    if
        isUserInteraction msg
            && (model.currentTurn.outcome == Nothing)
    then
        { model | inactivity = Inactivity.recordInteraction model.inactivity }
            |> renewInactivityTimer lobbyId model.shared.now

    else
        E.withOut model


inactivityTimerNeeded : Model -> Bool
inactivityTimerNeeded model =
    case model.currentTurn.phase of
        TurnLifecycle.WaitingForOpponent _ ->
            False

        _ ->
            True


inactivityPresentation : Model -> Maybe InactivityRenewalReason
inactivityPresentation model =
    if playback model /= Nothing then
        Just RenewalReason.PlaybackAllowance

    else if model.welcomeBriefingPending && (model.currentTurn.number == 1) then
        Just RenewalReason.BriefingAllowance

    else
        Nothing


canRenewInactivity : Model -> Bool
canRenewInactivity model =
    (model.currentTurn.outcome == Nothing) && inactivityTimerNeeded model


scheduleInactivity : Time.Posix -> Int -> Model -> ( Model, Eff Msg )
scheduleInactivity now minimumDelay model =
    if (model.inactivityWakeAt == Nothing) && canRenewInactivity model then
        case Inactivity.reportDelay now (inactivityPresentation model) model.inactivity of
            Just reportDelay ->
                let
                    delay : Int
                    delay =
                        max minimumDelay reportDelay

                    wakeAt : Time.Posix
                    wakeAt =
                        Time.millisToPosix (Time.posixToMillis now + delay)
                in
                ( { model | inactivityWakeAt = Just wakeAt }
                , E.after (toFloat delay) (InactivityWakeElapsed wakeAt)
                )

            Nothing ->
                E.withOut model

    else
        E.withOut model


renewInactivityTimer :
    LobbyId
    -> Time.Posix
    -> Model
    -> ( Model, Eff Msg )
renewInactivityTimer lobbyId now model =
    if canRenewInactivity model then
        let
            ( activity, report ) =
                Inactivity.beginReport now
                    { turnNumber = model.currentTurn.number
                    , presentation = inactivityPresentation model
                    }
                    model.inactivity

            next : Model
            next =
                { model | inactivity = activity }
        in
        case report of
            Just request ->
                ( { next | inactivityWakeAt = Nothing }
                , Api.Mutation.renewInactivityTimer
                    { id = LobbyId.toString lobbyId
                    , turnNumber = request.turnNumber
                    , reason = request.reason
                    }
                    pollStatusSelection
                    |> ApiRequest.mutationRequest
                    |> E.request (InactivityRenewalResponseReceived request)
                )

            Nothing ->
                scheduleInactivity now 0 next

    else
        model |> E.withOut



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


{-| Record player activity, synchronize playback audio, play UI cues, and
remeasure the workspace when the rendered layout changes.
-}
superUpdate : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
superUpdate lobbyId msg model =
    model
        |> update lobbyId msg
        |> E.andThen (recordUserInteraction lobbyId msg)
        |> E.andThen (withLayoutMeasurement (workspaceLayout model))
        |> E.and (E.audio (playAudio msg model))
        |> E.andThen (withPlaybackAudio (playbackAudio model))


update : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
update lobbyId msg model =
    case msg of
        CombatEnterPressed ->
            model
                |> setCombatEnterHeld (not (hasDialog model))
                |> E.withOut

        StillHereClicked ->
            E.withOut model

        InactivityWakeElapsed wakeAt ->
            if model.inactivityWakeAt == Just wakeAt then
                ( model, E.now (InactivityWakeTimeReceived wakeAt) )

            else
                E.withOut model

        InactivityWakeTimeReceived wakeAt now ->
            if model.inactivityWakeAt == Just wakeAt then
                { model | inactivityWakeAt = Nothing }
                    |> renewInactivityTimer lobbyId now

            else
                E.withOut model

        InactivityRenewalResponseReceived report result ->
            case result of
                Ok status ->
                    if report.turnNumber == model.currentTurn.number then
                        { model
                            | inactivity =
                                Inactivity.succeeded
                                    model.shared.now
                                    report
                                    status.inactivity
                                    model.inactivity
                        }
                            |> renewInactivityTimer lobbyId model.shared.now

                    else
                        model |> E.withOut

                Err error ->
                    { model | inactivity = Inactivity.failed report (ApiRequest.errorMessage error) model.inactivity }
                        |> scheduleInactivity model.shared.now 1000

        ChatMsg chatMsg ->
            handleChatMsg lobbyId chatMsg model

        ChatPollElapsed _ ->
            pollChat lobbyId model

        ChatPollReceived result ->
            case result of
                Ok messages ->
                    let
                        notification : Eff Msg
                        notification =
                            if
                                Chat.hasNewIncoming
                                    { known = model.chat.messages
                                    , received = messages
                                    , ownNames =
                                        model.players
                                            |> List.filter .isYou
                                            |> List.map .name
                                    }
                            then
                                E.audio Audio.chatReceived

                            else
                                E.none
                    in
                    model
                        |> applyChatUpdate (Chat.receive messages model.chat)
                        |> E.and notification

                Err error ->
                    model
                        |> setChat (Chat.pollFailed (ApiRequest.errorMessage error) model.chat)
                        |> E.withOut

        ChatSendReceived submission result ->
            let
                chat : Chat.Model
                chat =
                    Chat.sent
                        submission
                        (Result.mapError ApiRequest.errorMessage result)
                        model.chat

                visibleSubmission : Bool
                visibleSubmission =
                    case model.chat.panel of
                        Chat.Composing composer ->
                            composer.delivery == Chat.Sending submission

                        _ ->
                            False

                focus : Eff Msg
                focus =
                    if Chat.isOpen model.chat && not (Chat.isOpen chat) then
                        E.focus { htmlId = Battlefield.htmlId } FocusCompleted

                    else if visibleSubmission && Chat.isOpen chat then
                        E.focus { htmlId = ChatView.inputHtmlId } FocusCompleted

                    else
                        E.none
            in
            model
                |> applyChatUpdate chat
                |> E.and focus

        ChatScrollCompleted result ->
            case result of
                Err error ->
                    if chatHistoryVisible model.chat model.shared && not model.shared.devPanelOpen then
                        model
                            |> setShared (Shared.addError (Just (Error.ElementScrollFailed error)) model.shared)
                            |> E.withOut

                    else
                        model
                            |> E.withOut

                Ok () ->
                    model
                        |> E.withOut

        ChatOverlayExpired version ->
            if showTurnIntroduction model then
                model
                    |> E.withOut

            else
                model
                    |> setChat (Chat.expire version model.chat)
                    |> E.withOut

        FeedbackMsg feedbackMsg ->
            case feedbackMsg of
                FeedbackView.TextChanged text ->
                    model
                        |> setFeedback (Feedback.edit text model.feedback)
                        |> E.withOut

                FeedbackView.CloseClicked ->
                    let
                        focusHtmlId : String
                        focusHtmlId =
                            if showTurnIntroduction model then
                                TurnIntroduction.feedbackButtonHtmlId

                            else
                                GameMenu.buttonHtmlId
                    in
                    ( model |> setMenu MenuClosed
                    , E.focus { htmlId = focusHtmlId } FocusCompleted
                    )

                FeedbackView.SubmitClicked ->
                    let
                        ( id, seed ) =
                            Random.step Feedback.requestId model.shared.seed
                    in
                    case Feedback.beginSubmission id model.feedback of
                        Just pending ->
                            ( model
                                |> setShared (Shared.setSeed seed model.shared)
                                |> setFeedback pending
                            , E.request (FeedbackResponseReceived id) (Feedback.request pending)
                            )

                        Nothing ->
                            ( model, E.none )

        FeedbackResponseReceived id response ->
            model
                |> setFeedback (Feedback.receive id response model.feedback)
                |> E.withOut

        PlanningErrorReportTick now ->
            reportPlanningViolations lobbyId now model

        PlanningErrorReportReceived result ->
            case result of
                Ok _ ->
                    model |> E.withOut

                Err error ->
                    model
                        |> setShared
                            (Shared.addError
                                (Just (Error.PlanningErrorReportFailed (ApiRequest.errorMessage error)))
                                model.shared
                            )
                        |> E.withOut

        GameMenuMsg menuMsg ->
            handleGameMenuMsg lobbyId menuMsg model

        SettingsMsg settingsMsg ->
            case model.menu of
                SettingsMenu _ ->
                    handleSettingsMsg settingsMsg model

                _ ->
                    model
                        |> E.withOut

        RequestRetryClicked ->
            case model.currentTurn.error of
                Just (CurrentTurn.SubmissionError _) ->
                    requestSubmission lobbyId model

                Just (CurrentTurn.PollError _) ->
                    refreshTurn lobbyId model

                Just (CurrentTurn.ResignationError _) ->
                    requestResignation RemainInGame model

                _ ->
                    model
                        |> E.withOut

        RequestErrorDismissed ->
            ( model
                |> setCurrentTurn (CurrentTurn.dismissError model.currentTurn)
            , E.focus { htmlId = Battlefield.htmlId } FocusCompleted
            )

        RotationNoticeCanceled ->
            E.withOut model

        FocusCompleted result ->
            recordFocusResult result model
                |> E.withOut

        ResignResponseReceived destination result ->
            case result of
                Ok snapshot ->
                    let
                        effect : Eff Msg
                        effect =
                            case destination of
                                RemainInGame ->
                                    E.none

                                GoHome ->
                                    Route.navigate model.shared.deployment
                                        Route.Home
                    in
                    (model
                        |> setResigning False
                    )
                        |> applyTurnSnapshot lobbyId
                            snapshot
                            (CurrentTurn.pollSucceeded (turnObservation snapshot) model.currentTurn)
                        |> E.and effect

                Err error ->
                    let
                        currentTurn : CurrentTurn.Model
                        currentTurn =
                            model.currentTurn
                    in
                    (model
                        |> setResigning False
                        |> setMenu MenuClosed
                        |> setCurrentTurn
                            (currentTurn
                                |> CurrentTurn.setError
                                    (Just (CurrentTurn.ResignationError (ApiRequest.errorMessage error)))
                            )
                    )
                        |> E.withOut

        BattlefieldMsg boardMsg ->
            handleBattlefieldMsg boardMsg model
                |> E.withOut

        CameraReturnFinished ->
            (model
                |> setNavigation (BattlefieldNavigation.finishReturn model.navigation)
            )
                |> updatePlaybackCamera
                |> E.withOut

        BattlefieldSizeReceived result ->
            case result of
                Ok battlefield ->
                    if (battlefield.element.width <= 0) || (battlefield.element.height <= 0) then
                        E.withOut model

                    else if isMobileView model then
                        let
                            viewport : Camera.Viewport
                            viewport =
                                { size =
                                    { x = battlefield.element.width
                                    , y = battlefield.element.height
                                    }
                                , bottomInset = 0
                                , rightInset = 0
                                }
                        in
                        model
                            |> setBattlefieldViewport
                                (Just
                                    { origin = { x = battlefield.element.x, y = battlefield.element.y }
                                    , camera = viewport
                                    }
                                )
                            |> updatePlaybackCamera
                            |> E.withOut

                    else
                        ( model
                        , E.measure
                            BattlefieldWorkspace.inspectorHtmlId
                            (InspectorSizeReceived battlefield)
                        )

                Err error ->
                    (model
                        |> setShared (Shared.addError (Just (Error.BattlefieldMeasurementFailed error)) model.shared)
                    )
                        |> E.withOut

        InspectorSizeReceived battlefield result ->
            case result of
                Ok inspector ->
                    ( model
                    , E.measure BattlefieldWorkspace.controlsHtmlId
                        (ControlsSizeReceived { battlefield = battlefield, inspector = inspector })
                    )

                Err error ->
                    model
                        |> setShared
                            (Shared.addError (Just (Error.BattlefieldMeasurementFailed error)) model.shared)
                        |> E.withOut

        ControlsSizeReceived measured result ->
            case result of
                Ok measuredControls ->
                    let
                        viewport : Camera.Viewport
                        viewport =
                            BattlefieldWorkspace.viewport
                                { battlefield = measured.battlefield
                                , inspector = measured.inspector
                                , controls = measuredControls
                                }
                    in
                    model
                        |> setBattlefieldViewport
                            (Just
                                { origin = { x = measured.battlefield.element.x, y = measured.battlefield.element.y }
                                , camera = viewport
                                }
                            )
                        |> updatePlaybackCamera
                        |> E.withOut

                Err error ->
                    model
                        |> setShared
                            (Shared.addError
                                (Just (Error.BattlefieldMeasurementFailed error))
                                model.shared
                            )
                        |> E.withOut

        PanLeftKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panLeft
                |> E.withOut

        PanRightKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panRight
                |> E.withOut

        PanUpKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panUp
                |> E.withOut

        PanDownKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panDown
                |> E.withOut

        ZoomInKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.zoomIn
                |> E.withOut

        ZoomOutKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.zoomOut
                |> E.withOut

        BattlefieldNavigationMsg navigationMsg ->
            let
                dragMode : BattlefieldNavigation.DragMode
                dragMode =
                    if pathPreview model /= Nothing then
                        BattlefieldNavigation.TraceRoute

                    else
                        BattlefieldNavigation.PanCamera

                traced : Model
                traced =
                    model
                        |> mapNavigation (BattlefieldNavigation.update dragMode navigationMsg)
            in
            case navigationMsg of
                BattlefieldNavigation.MouseReleased _ ->
                    let
                        confirmsRoute : Bool
                        confirmsRoute =
                            (pathPreview model /= Nothing)
                                && BattlefieldNavigation.suppressesClick traced.navigation

                        next : Model
                        next =
                            if confirmsRoute then
                                confirmPath traced

                            else
                                traced
                    in
                    E.withOut next

                BattlefieldNavigation.MouseMoved _ _ ->
                    E.withOut traced

                BattlefieldNavigation.WindowVisibilityChanged _ ->
                    E.withOut traced

        UnloadUnitToggled id checked ->
            model
                |> mapCheckedPlanning
                    (OrderPlanning.toggleAvailableUnloadCargo
                        model.map
                        model.units
                        (ownPlayerNumbers model)
                        model.movementRules
                        (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                        (UnloadCargo.Passenger id)
                        checked
                    )
                |> E.withOut

        UnloadChoicesConfirmed ->
            model
                |> mapCheckedPlanning
                    (OrderPlanning.confirmPassengers
                        model.map
                        model.units
                        (ownPlayerNumbers model)
                        model.movementRules
                        (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                        model.depots
                    )
                |> E.withOut

        UnloadSkipped ->
            model
                |> mapPlanning
                    (OrderPlanning.skipUnloading
                        model.map
                        model.units
                        (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                        model.depots
                    )
                |> E.withOut

        GroundFreightPickupClicked ->
            model
                |> mapCheckedPlanning
                    (OrderPlanning.confirmGroundPickup
                        >> IC.map
                            (OrderPlanning.promptDismountedOrders model.map model.units)
                    )
                |> E.withOut

        LoadCratesClicked id count ->
            case
                ListUtil.find
                    (\unit -> unit.id == id && isOwnUnit model unit)
                    model.units
            of
                Just _ ->
                    model
                        |> mapCheckedPlanning
                            (OrderPlanning.dismissDialog
                                >> saveCrateLoading id count
                                >> IC.map (OrderPlanning.promptDismountedOrders model.map model.units)
                            )
                        |> E.withOut

                Nothing ->
                    model
                        |> E.withOut

        UnloadCrateToggled index checked ->
            model
                |> mapCheckedPlanning
                    (OrderPlanning.toggleAvailableUnloadCargo
                        model.map
                        model.units
                        (ownPlayerNumbers model)
                        model.movementRules
                        (visibleSupplyCrates model.visibleTiles model.supplyCrates)
                        (UnloadCargo.Crate index)
                        checked
                    )
                |> E.withOut

        CargoUnitClicked id ->
            model
                |> clearSelection
                |> selectUnit id
                |> E.withOut

        NextUnorderedUnitKeyPressed ->
            model
                |> mapPlanning
                    (OrderPlanning.selectNextUnorderedUnit model.map model.units (ownPlayerNumbers model))
                |> E.withOut

        OrderMenuMsg orderMsg ->
            model
                |> handleOrderMsg orderMsg

        PreviousOrderPressed ->
            ( model, focusAdjacentOrder List.reverse (focusedOrder model) model )

        NextOrderPressed ->
            ( model, focusAdjacentOrder identity (focusedOrder model) model )

        OrderFocusCompleted result ->
            recordFocusResult result model
                |> E.withOut

        DirectionKeyPressed direction ->
            model
                |> saveDirection direction
                |> E.withOut

        PathDirectionKeyPressed direction ->
            model
                |> extendPath direction
                |> E.withOut

        PathEnterPressed ->
            model
                |> confirmPath
                |> E.withOut

        CancelOrderClicked ->
            model
                |> mapCheckedPlanning (OrderPlanning.cancelInteraction model.map model.units)
                |> E.withOut

        ClearMoveClicked ->
            model
                |> revokeSelectedOrder
                |> E.withOut

        InspectClicked ->
            model
                |> clearSelection
                |> E.withOut

        InspectorCloseClicked ->
            model
                |> clearSelection
                |> E.withOut

        MobileTabClicked tab ->
            { model | mobileTab = tab }
                |> E.withOut

        MobileTabNavigationPressed tab ->
            ( { model | mobileTab = tab }
            , E.focus
                { htmlId = MobileBattlefield.tabHtmlId tab }
                FocusCompleted
            )

        InspectionHelpClicked help ->
            if hasDialog model then
                model
                    |> E.withOut

            else
                { model | inspectionHelp = Just help }
                    |> E.withOut

        InspectionHelpFocusReturned result ->
            recordFocusResult result model
                |> E.withOut

        EscapePressed ->
            if model.inspectionHelp /= Nothing then
                dismissInspectionHelp model

            else if (model.menu /= MenuClosed) || showTurnIntroduction model then
                model
                    |> dismissDialog

            else if planningLocked model then
                model
                    |> clearSelection
                    |> E.withOut

            else
                model
                    |> mapCheckedPlanning (OrderPlanning.cancelInteraction model.map model.units)
                    |> E.withOut

        TurnControlsMsg turnControlsMsg ->
            handleTurnControlsMsg lobbyId turnControlsMsg model

        WelcomeBriefingDismissed ->
            { model | welcomeBriefingPending = False }
                |> resumeChatOverlay model.welcomeBriefingPending
                |> E.and
                    (E.setLocalStorage
                        { key = welcomeBriefingPreferenceKey
                        , value = Encode.bool True
                        }
                    )

        DialogDismissed ->
            if model.inspectionHelp /= Nothing then
                dismissInspectionHelp model

            else
                model
                    |> dismissDialog

        SubmissionCancelled ->
            case model.currentTurn.phase of
                TurnLifecycle.Planning (OrderPlanning.ConfirmingSubmission _) ->
                    dismissDialog model

                _ ->
                    model
                        |> E.withOut

        SubmitKeyPressed ->
            if canSubmitWithKeyboard model then
                requestSubmission lobbyId model

            else
                model
                    |> E.withOut

        SubmissionConfirmed ->
            confirmSubmission lobbyId model

        SkipUnplannedUnitsWarningChanged skip ->
            ( { model | skipUnplannedUnitsWarning = skip }
            , E.setLocalStorage
                { key = unplannedUnitsWarningPreferenceKey
                , value = Encode.bool skip
                }
            )

        SubmitResponseReceived turnNumber result ->
            case result of
                Ok snapshot ->
                    model
                        |> applyTurnSnapshot
                            lobbyId
                            snapshot
                            (CurrentTurn.submissionSucceeded
                                turnNumber
                                (turnObservation snapshot)
                                model.currentTurn
                            )

                Err error ->
                    (model
                        |> setCurrentTurn
                            (CurrentTurn.submissionFailed
                                turnNumber
                                (ApiRequest.errorMessage error)
                                model.currentTurn
                            )
                    )
                        |> E.withOut

        CurrentTurnMsg turnMsg ->
            handleCurrentTurnMsg lobbyId turnMsg model

        PollStatusResponseReceived activitySequence result ->
            case result of
                Ok status ->
                    let
                        currentTurn : CurrentTurn.Model
                        currentTurn =
                            model.currentTurn

                        observed : Model
                        observed =
                            if status.number == currentTurn.number then
                                { model | inactivity = Inactivity.observe model.shared.now activitySequence status.inactivity model.inactivity }

                            else
                                model

                        needsSnapshot : Bool
                        needsSnapshot =
                            (currentTurn.outcome == Nothing)
                                && ((status.outcome /= Nothing)
                                        || ((status.number > currentTurn.number) && (playback model == Nothing))
                                   )

                        observation : CurrentTurn.Observation
                        observation =
                            { turn =
                                { number = status.number
                                , outcome = status.outcome
                                , submitted = status.submitted
                                , opponentSubmitted = status.opponentSubmitted
                                , resolution = currentTurn.resolution
                                }
                            , playbackFrames = []
                            }
                    in
                    if needsSnapshot then
                        ( observed, E.request PollResponseReceived (loadSnapshot lobbyId) )

                    else
                        let
                            next : Model
                            next =
                                observed
                                    |> setCurrentTurn (CurrentTurn.pollSucceeded observation currentTurn)

                            reportingChanged : Bool
                            reportingChanged =
                                (canRenewInactivity model /= canRenewInactivity next)
                                    || (Inactivity.reportingContext model.inactivity
                                            /= Inactivity.reportingContext next.inactivity
                                       )
                        in
                        (if reportingChanged then
                            renewInactivityTimer lobbyId model.shared.now next

                         else
                            E.withOut next
                        )
                            |> E.andThen (resumeChatOverlay (showTurnIntroduction model))

                Err error ->
                    (model
                        |> setCurrentTurn (CurrentTurn.pollFailed (ApiRequest.errorMessage error) model.currentTurn)
                    )
                        |> E.withOut

        PollResponseReceived result ->
            case result of
                Ok snapshot ->
                    model
                        |> applyTurnSnapshot
                            lobbyId
                            snapshot
                            (CurrentTurn.pollSucceeded
                                (turnObservation snapshot)
                                model.currentTurn
                            )

                Err error ->
                    model
                        |> setCurrentTurn (CurrentTurn.pollFailed (ApiRequest.errorMessage error) model.currentTurn)
                        |> E.withOut

        AnimationTimerElapsed _ ->
            if deathInFocus model || combatEncounter model /= Nothing then
                model
                    |> E.withOut

            else
                { model | frame = AnimationFrame.next model.frame }
                    |> E.withOut

        TurnIntroductionMsg introMsg ->
            handleTurnIntroductionMsg introMsg model

        UnitDeathMsg lossMsg ->
            handleUnitDeathMsg lossMsg model

        CombatTheaterMsg panelMsg ->
            handleCombatTheaterMsg panelMsg model

        LossDialogOpened htmlId ->
            case unitLoss model of
                Just loss ->
                    if UnitDeath.dialogHtmlId loss == htmlId then
                        model
                            |> setShared
                                (Shared.addError
                                    (PlaybackPresentation.lossError model.players (Just loss))
                                    model.shared
                                )
                            |> E.withOut

                    else
                        E.withOut model

                Nothing ->
                    E.withOut model


{-| Classify message intent for UI feedback. Continuous input and background
work stay silent; focus and release notifications do not duplicate an action cue.
Clicks ignored after panning also stay silent.
-}
playAudio : Msg -> Model -> Audio.Event
playAudio msg model =
    case msg of
        CombatEnterPressed ->
            Audio.none

        StillHereClicked ->
            Audio.confirm

        InactivityWakeElapsed _ ->
            Audio.none

        InactivityWakeTimeReceived _ _ ->
            Audio.none

        InactivityRenewalResponseReceived _ _ ->
            Audio.none

        ChatMsg _ ->
            Audio.none

        ChatPollElapsed _ ->
            Audio.none

        ChatPollReceived _ ->
            Audio.none

        ChatSendReceived _ _ ->
            Audio.none

        ChatScrollCompleted _ ->
            Audio.none

        ChatOverlayExpired _ ->
            Audio.none

        BattlefieldSizeReceived _ ->
            Audio.none

        ControlsSizeReceived _ _ ->
            Audio.none

        InspectorSizeReceived _ _ ->
            Audio.none

        CameraReturnFinished ->
            Audio.none

        BattlefieldMsg battlefieldMsg ->
            case battlefieldMsg of
                Battlefield.PanLeftClicked ->
                    Audio.affirm

                Battlefield.PanRightClicked ->
                    Audio.affirm

                Battlefield.PanUpClicked ->
                    Audio.affirm

                Battlefield.PanDownClicked ->
                    Audio.affirm

                Battlefield.ZoomInClicked ->
                    Audio.affirm

                Battlefield.ZoomOutClicked ->
                    Audio.affirm

                Battlefield.ResetViewClicked ->
                    Audio.affirm

                Battlefield.RotationChoicesMsg rotationMsg ->
                    case rotationMsg of
                        RotationChoices.MouseMovedOverDirection _ ->
                            Audio.none

                        RotationChoices.FocusedDirection _ ->
                            Audio.none

                        RotationChoices.ClickedDirection _ ->
                            if BattlefieldNavigation.suppressesClick model.navigation then
                                Audio.none

                            else
                                Audio.confirm

                        RotationChoices.DirectionActivationKeyPressed _ ->
                            Audio.confirm

                Battlefield.ClickedUnit _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnUnit _ ->
                    Audio.affirm

                Battlefield.PressedSpaceOnUnit _ ->
                    Audio.affirm

                Battlefield.MouseOverUnit _ ->
                    Audio.none

                Battlefield.ClickedDepot _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnDepot _ ->
                    Audio.affirm

                Battlefield.PressedSpaceOnDepot _ ->
                    Audio.affirm

                Battlefield.MouseOverDepot _ ->
                    Audio.none

                Battlefield.ClickedDepotStock _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnDepotStock _ ->
                    Audio.affirm

                Battlefield.PressedSpaceOnDepotStock _ ->
                    Audio.affirm

                Battlefield.ClickedTile _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnTile _ ->
                    Audio.affirm

                Battlefield.PressedSpaceOnTile _ ->
                    Audio.affirm

                Battlefield.FocusedBoardUnit _ ->
                    Audio.none

                Battlefield.FocusedBoardTile _ ->
                    Audio.none

                Battlefield.TargetPreviewLeft ->
                    Audio.none

                Battlefield.MouseOverTile _ ->
                    Audio.none

                Battlefield.TouchInputReceived _ ->
                    Audio.none

                Battlefield.PointerPressed _ ->
                    Audio.none

                Battlefield.WheelScrolled _ _ ->
                    Audio.none

                Battlefield.HomePressed ->
                    Audio.affirm

        BattlefieldNavigationMsg navigationMsg ->
            case navigationMsg of
                BattlefieldNavigation.MouseMoved _ _ ->
                    Audio.none

                BattlefieldNavigation.MouseReleased _ ->
                    Audio.none

                BattlefieldNavigation.WindowVisibilityChanged _ ->
                    Audio.none

        OrderMenuMsg orderMsg ->
            case orderMsg of
                OrderMenu.InfoClicked ->
                    Audio.affirm

                OrderMenu.CancelClicked ->
                    Audio.cancel

                OrderMenu.OrderFocused _ ->
                    Audio.none

                OrderMenu.OrderPicked order ->
                    case order of
                        UnitOrder.StandGround ->
                            Audio.affirm

                        UnitOrder.HoldPosition ->
                            Audio.confirm

                        UnitOrder.Move ->
                            Audio.affirm

                        UnitOrder.AttackMove ->
                            Audio.affirm

                        UnitOrder.IndirectFire ->
                            Audio.affirm

                        UnitOrder.Sabotage ->
                            Audio.confirm

                        UnitOrder.DigIn ->
                            Audio.confirm

                        UnitOrder.Ambush ->
                            Audio.affirm

                OrderMenu.ArrowedUpOrderMenu _ ->
                    Audio.affirm

                OrderMenu.ArrowedDownOrderMenu _ ->
                    Audio.affirm

        SettingsMsg settingsMsg ->
            case settingsMsg of
                Settings.VolumeChanged _ _ ->
                    Audio.none

                Settings.CloseClicked ->
                    Audio.confirm

                _ ->
                    Audio.affirm

        RotationNoticeCanceled ->
            Audio.none

        FocusCompleted _ ->
            Audio.none

        FeedbackMsg feedbackMsg ->
            case feedbackMsg of
                FeedbackView.TextChanged _ ->
                    Audio.none

                FeedbackView.SubmitClicked ->
                    Audio.confirm

                FeedbackView.CloseClicked ->
                    Audio.cancel

        FeedbackResponseReceived _ _ ->
            Audio.none

        PlanningErrorReportTick _ ->
            Audio.none

        PlanningErrorReportReceived _ ->
            Audio.none

        GameMenuMsg menuMsg ->
            case menuMsg of
                GameMenu.OpenClicked ->
                    Audio.affirm

                GameMenu.ChatClicked ->
                    Audio.affirm

                GameMenu.SettingsClicked ->
                    Audio.affirm

                GameMenu.DevPanelClicked ->
                    Audio.affirm

                GameMenu.FeedbackClicked ->
                    Audio.affirm

                GameMenu.AboutClicked ->
                    Audio.affirm

                GameMenu.CloseClicked ->
                    Audio.cancel

                GameMenu.FocusReturned _ ->
                    Audio.none

                GameMenu.ResignationCanceled ->
                    Audio.cancel

                GameMenu.ResignationConfirmed ->
                    Audio.confirm

                GameMenu.HomeClicked ->
                    Audio.confirm

        PreviousOrderPressed ->
            Audio.affirm

        NextOrderPressed ->
            Audio.affirm

        OrderFocusCompleted _ ->
            Audio.none

        PanLeftKeyPressed ->
            Audio.affirm

        PanRightKeyPressed ->
            Audio.affirm

        PanUpKeyPressed ->
            Audio.affirm

        PanDownKeyPressed ->
            Audio.affirm

        ZoomInKeyPressed ->
            Audio.affirm

        ZoomOutKeyPressed ->
            Audio.affirm

        AnimationTimerElapsed _ ->
            Audio.none

        TurnIntroductionMsg introMsg ->
            case introMsg of
                TurnIntroduction.BeginClicked ->
                    Audio.confirm

                TurnIntroduction.ReplayClicked ->
                    Audio.affirm

                TurnIntroduction.BattlefieldViewClicked ->
                    Audio.confirm

                TurnIntroduction.FeedbackClicked ->
                    Audio.affirm

                TurnIntroduction.SkipDialogsChanged _ ->
                    Audio.affirm

        LossDialogOpened _ ->
            Audio.none

        UnitDeathMsg lossMsg ->
            case lossMsg of
                UnitDeath.ContinueClicked _ ->
                    Audio.confirm

                UnitDeath.SkipDialogsChanged _ ->
                    Audio.affirm

        CombatTheaterMsg theaterMsg ->
            case theaterMsg of
                CombatTheater.ContinueClicked ->
                    Audio.confirm

                CombatTheater.SeeMapPressed ->
                    Audio.affirm

                CombatTheater.SeeMapReleased ->
                    Audio.none

                CombatTheater.AutomaticallyCloseChanged _ ->
                    Audio.affirm

        DirectionKeyPressed _ ->
            Audio.confirm

        PathDirectionKeyPressed _ ->
            Audio.affirm

        PathEnterPressed ->
            Audio.confirm

        NextUnorderedUnitKeyPressed ->
            Audio.affirm

        ClearMoveClicked ->
            Audio.affirm

        CancelOrderClicked ->
            Audio.cancel

        CargoUnitClicked _ ->
            Audio.affirm

        LoadCratesClicked _ count ->
            if count == 0 then
                Audio.cancel

            else
                Audio.confirm

        GroundFreightPickupClicked ->
            Audio.confirm

        UnloadCrateToggled _ checked ->
            if checked then
                Audio.affirm

            else
                Audio.cancel

        UnloadUnitToggled _ checked ->
            if checked then
                Audio.affirm

            else
                Audio.cancel

        UnloadChoicesConfirmed ->
            Audio.confirm

        UnloadSkipped ->
            Audio.cancel

        InspectClicked ->
            Audio.cancel

        InspectorCloseClicked ->
            Audio.cancel

        MobileTabClicked _ ->
            Audio.affirm

        MobileTabNavigationPressed _ ->
            Audio.affirm

        InspectionHelpClicked _ ->
            Audio.affirm

        InspectionHelpFocusReturned _ ->
            Audio.none

        EscapePressed ->
            Audio.cancel

        WelcomeBriefingDismissed ->
            Audio.confirm

        DialogDismissed ->
            Audio.cancel

        SubmissionCancelled ->
            Audio.cancel

        SubmissionConfirmed ->
            Audio.confirm

        SubmitKeyPressed ->
            Audio.confirm

        SkipUnplannedUnitsWarningChanged _ ->
            Audio.affirm

        TurnControlsMsg turnControlsMsg ->
            case turnControlsMsg of
                TurnControls.SubmitClicked ->
                    Audio.confirm

                TurnControls.SurrenderClicked ->
                    Audio.affirm

        RequestRetryClicked ->
            Audio.confirm

        RequestErrorDismissed ->
            Audio.cancel

        SubmitResponseReceived _ _ ->
            Audio.none

        CurrentTurnMsg turnMsg ->
            case turnMsg of
                CurrentTurn.PollTimerElapsed ->
                    Audio.none

                CurrentTurn.GotPlaybackPresentationMsg playbackMsg ->
                    case playbackMsg of
                        PlaybackPresentation.FrameElapsed _ ->
                            Audio.none

                        PlaybackPresentation.CombatEnterReleased ->
                            if canContinueCombatWithEnter model then
                                Audio.confirm

                            else
                                Audio.none

                        PlaybackPresentation.CombatSeeMapReleased ->
                            Audio.none

        ResignResponseReceived _ _ ->
            Audio.none

        PollStatusResponseReceived _ _ ->
            Audio.none

        PollResponseReceived _ ->
            Audio.none


battlefieldClickAudio : { detail : Int } -> Model -> Audio.Event
battlefieldClickAudio click model =
    if suppressesBattlefieldClick click model then
        Audio.none

    else
        Audio.affirm


handleTurnIntroductionMsg : TurnIntroduction.Msg -> Model -> ( Model, Eff Msg )
handleTurnIntroductionMsg introMsg model =
    case introMsg of
        TurnIntroduction.BeginClicked ->
            acknowledgeTurnIntroduction model

        TurnIntroduction.ReplayClicked ->
            if showTurnIntroduction model then
                case CurrentTurn.replay model.currentTurn of
                    Just replay ->
                        model
                            |> setCurrentTurn replay.currentTurn
                            |> applyPlaybackFrame
                                { phase = replay.currentTurn.phase, frame = replay.frame }
                            |> startPlayback
                            |> E.andThen (resumeChatOverlay True)

                    Nothing ->
                        model
                            |> E.withOut

            else
                model
                    |> E.withOut

        TurnIntroduction.BattlefieldViewClicked ->
            acknowledgeTurnIntroduction model

        TurnIntroduction.FeedbackClicked ->
            let
                canGiveFeedback : Bool
                canGiveFeedback =
                    (model.currentTurn.outcome /= Nothing)
                        && showTurnIntroduction model
                        && (model.menu == MenuClosed)
            in
            if canGiveFeedback then
                ( model |> setMenu FeedbackMenu
                , E.focus { htmlId = FeedbackView.inputHtmlId } FocusCompleted
                )

            else
                model
                    |> E.withOut

        TurnIntroduction.SkipDialogsChanged skip ->
            model
                |> acknowledgeTurnIntroduction
                |> Tuple.mapFirst (setSkipTurnIntroduction skip)
                |> E.and (rememberTurnIntroductionPreference skip)


handleUnitDeathMsg : UnitDeath.Msg -> Model -> ( Model, Eff Msg )
handleUnitDeathMsg lossMsg model =
    case lossMsg of
        UnitDeath.ContinueClicked unitId ->
            let
                currentTurn : CurrentTurn.Model
                currentTurn =
                    model.currentTurn
            in
            model
                |> setCurrentTurn
                    (currentTurn
                        |> CurrentTurn.setPhase
                            (TurnLifecycle.acknowledgeLoss
                                unitId
                                currentTurn.phase
                            )
                    )
                |> presentPlaybackTransition currentTurn.phase

        UnitDeath.SkipDialogsChanged skip ->
            ( { model | skipUnitLossDialogs = skip }
            , rememberPlaybackPreference PlaybackPresentation.SkipLossDialogs skip
            )


handleCombatTheaterMsg : CombatTheater.Msg -> Model -> ( Model, Eff Msg )
handleCombatTheaterMsg panelMsg model =
    case panelMsg of
        CombatTheater.AutomaticallyCloseChanged automaticallyClose ->
            ( { model | automaticallyCloseCombatTheater = automaticallyClose }
            , rememberPlaybackPreference PlaybackPresentation.AutomaticallyCloseCombat automaticallyClose
            )

        CombatTheater.ContinueClicked ->
            continueCombat model
                |> presentPlaybackTransition model.currentTurn.phase

        CombatTheater.SeeMapPressed ->
            setCombatMapView TurnPlayback.SeeingMap model
                |> E.withOut

        CombatTheater.SeeMapReleased ->
            setCombatMapView TurnPlayback.CardVisible model
                |> E.withOut


handleChatMsg : LobbyId -> ChatView.Msg -> Model -> ( Model, Eff Msg )
handleChatMsg lobbyId msg model =
    case msg of
        ChatView.OpenPressed ->
            openChat model

        ChatView.CloseClicked ->
            ( model
                |> setChat (Chat.close model.chat)
            , E.focus { htmlId = Battlefield.htmlId } FocusCompleted
            )

        ChatView.TextChanged text ->
            model
                |> setChat (Chat.edit text model.chat)
                |> E.withOut

        ChatView.HistoryScrolled position ->
            model
                |> setChat (Chat.scrollHistory position model.chat)
                |> E.withOut

        ChatView.DialogOpened ->
            let
                newChat : Chat.Model
                newChat =
                    Chat.historyOpened model.chat
            in
            ( model
                |> setChat newChat
            , scrollChatHistory newChat model.shared
            )

        ChatView.HistoryClicked ->
            let
                newChat : Chat.Model
                newChat =
                    Chat.toggleHistory model.chat
            in
            ( model
                |> setChat newChat
            , scrollChatHistory newChat model.shared
            )

        ChatView.SendPressed ->
            sendChat lobbyId model

        ChatView.RetrySendPressed ->
            model
                |> setChat (Chat.open model.chat)
                |> sendChat lobbyId

        ChatView.RetryUpdatesPressed ->
            pollChat lobbyId model

        ChatView.DismissErrorClicked ->
            let
                focusHtmlId : String
                focusHtmlId =
                    if Chat.isOpen model.chat then
                        ChatView.inputHtmlId

                    else
                        Battlefield.htmlId
            in
            ( model
                |> setChat (Chat.dismissErrors model.chat)
            , E.focus { htmlId = focusHtmlId } FocusCompleted
            )


handleGameMenuMsg : LobbyId -> GameMenu.Msg -> Model -> ( Model, Eff Msg )
handleGameMenuMsg lobbyId msg model =
    case msg of
        GameMenu.ChatClicked ->
            openChat model

        GameMenu.OpenClicked ->
            if canOpenDialog model then
                ( model
                    |> setMenu MainMenu
                , E.none
                )

            else
                model
                    |> E.withOut

        GameMenu.FeedbackClicked ->
            if (model.menu == MainMenu) && not model.resigning then
                ( model |> setMenu FeedbackMenu
                , E.focus { htmlId = FeedbackView.inputHtmlId } FocusCompleted
                )

            else
                ( model, E.none )

        GameMenu.AboutClicked ->
            if (model.menu == MainMenu) && not model.resigning then
                ( model
                    |> setMenu AboutMenu
                , E.focus
                    { htmlId = About.htmlId ++ "-title" }
                    (GameMenu.FocusReturned >> GameMenuMsg)
                )

            else
                model
                    |> E.withOut

        GameMenu.SettingsClicked ->
            if (model.menu == MainMenu) && not model.resigning then
                ( model
                    |> setMenu (SettingsMenu Settings.Dialogs)
                , E.focus { htmlId = Settings.dialogHtmlId ++ "-title" } FocusCompleted
                )

            else
                model
                    |> E.withOut

        GameMenu.DevPanelClicked ->
            if model.menu == MainMenu then
                model
                    |> setShared (Shared.setDevPanelOpen True model.shared)
                    |> E.withOut

            else
                E.withOut model

        GameMenu.CloseClicked ->
            let
                returnHtmlId : String
                returnHtmlId =
                    if model.menu == MobileOrdersHelp then
                        MobileBattlefield.ordersHelpButtonHtmlId

                    else
                        GameMenu.buttonHtmlId
            in
            ( model
                |> setMenu MenuClosed
            , E.focus
                { htmlId = returnHtmlId }
                (GameMenu.FocusReturned >> GameMenuMsg)
            )

        GameMenu.ResignationConfirmed ->
            case model.menu of
                ConfirmingResignation destination ->
                    resignGame lobbyId destination model

                _ ->
                    model
                        |> E.withOut

        GameMenu.ResignationCanceled ->
            case model.menu of
                ConfirmingResignation destination ->
                    case destination of
                        RemainInGame ->
                            ( model
                                |> setMenu MenuClosed
                            , E.focus { htmlId = TurnControls.surrenderButtonHtmlId } FocusCompleted
                            )

                        GoHome ->
                            ( model
                                |> setMenu MainMenu
                            , E.focus
                                { htmlId = GameMenu.closeButtonHtmlId }
                                (GameMenu.FocusReturned >> GameMenuMsg)
                            )

                _ ->
                    model
                        |> E.withOut

        GameMenu.HomeClicked ->
            if (model.menu /= MainMenu) || model.resigning then
                model
                    |> E.withOut

            else if model.currentTurn.outcome /= Nothing then
                ( model, Route.navigate model.shared.deployment Route.Home )

            else
                requestResignation GoHome model

        GameMenu.FocusReturned result ->
            recordFocusResult result model
                |> E.withOut


handleSettingsMsg : Settings.Msg -> Model -> ( Model, Eff Msg )
handleSettingsMsg msg model =
    case msg of
        Settings.CloseClicked ->
            ( model
                |> setMenu MenuClosed
            , E.focus { htmlId = GameMenu.buttonHtmlId } FocusCompleted
            )

        Settings.TabClicked tab ->
            ( model
                |> setMenu (SettingsMenu tab)
            , E.none
            )

        Settings.TabNavigationPressed tab ->
            ( model
                |> setMenu (SettingsMenu tab)
            , E.focus { htmlId = Settings.tabHtmlId tab } FocusCompleted
            )

        Settings.SkipIntroductionChanged skip ->
            model
                |> setSkipTurnIntroduction skip
                |> resumeChatOverlay (showTurnIntroduction model)
                |> E.and (rememberTurnIntroductionPreference skip)

        Settings.SkipLossesChanged skip ->
            ( { model | skipUnitLossDialogs = skip }
            , rememberPlaybackPreference PlaybackPresentation.SkipLossDialogs skip
            )

        Settings.SkipOrdersWarningChanged skip ->
            ( { model | skipUnplannedUnitsWarning = skip }
            , E.setLocalStorage
                { key = unplannedUnitsWarningPreferenceKey
                , value = Encode.bool skip
                }
            )

        Settings.MuteChanged muted ->
            let
                mute : Audio.MuteState
                mute =
                    if muted then
                        Audio.Muted

                    else
                        Audio.Unmuted
            in
            ( setShared (Shared.setAudioMute mute model.shared) model
            , E.batch
                [ E.audio (Audio.SetMute mute)
                , E.setLocalStorage (Audio.encodeMutePreference mute)
                ]
            )

        Settings.VolumeChanged channel volume ->
            let
                volumes : Audio.Volumes
                volumes =
                    Audio.setChannelVolume channel volume model.shared.audioVolumes
            in
            ( setShared (Shared.setAudioVolumes volumes model.shared) model
            , E.batch
                [ E.audio (Audio.SetVolumes volumes)
                , E.setLocalStorage (Audio.encodeVolumesPreference volumes)
                ]
            )


handleTurnControlsMsg : LobbyId -> TurnControls.Msg -> Model -> ( Model, Eff Msg )
handleTurnControlsMsg lobbyId msg model =
    case msg of
        TurnControls.SubmitClicked ->
            requestSubmission lobbyId model

        TurnControls.SurrenderClicked ->
            requestResignation RemainInGame model


canSubmitWithKeyboard : Model -> Bool
canSubmitWithKeyboard model =
    case ( hasDialog model, model.currentTurn.phase ) of
        ( False, TurnLifecycle.Planning (OrderPlanning.OrdinaryPlanning { selection }) ) ->
            let
                idleSelection : Bool
                idleSelection =
                    case selection of
                        Just (UnitSelection _) ->
                            False

                        _ ->
                            True
            in
            idleSelection && not (BattlefieldNavigation.active model.navigation)

        _ ->
            False


confirmSubmission : LobbyId -> Model -> ( Model, Eff Msg )
confirmSubmission lobbyId model =
    case model.currentTurn.phase of
        TurnLifecycle.Planning (OrderPlanning.ConfirmingSubmission _) ->
            submitTurn lobbyId model

        _ ->
            model
                |> E.withOut


requestSubmission : LobbyId -> Model -> ( Model, Eff Msg )
requestSubmission lobbyId model =
    if
        planningLocked model
            || isChoosingUnload model
            || (unloadChoice model.currentTurn.phase /= Nothing)
    then
        model
            |> E.withOut

    else if model.skipUnplannedUnitsWarning || List.isEmpty (unitsWithoutOrders model) then
        model
            |> submitTurn lobbyId

    else
        model
            |> mapPlanning OrderPlanning.showSubmissionWarning
            |> E.withOut


refreshTurn : LobbyId -> Model -> ( Model, Eff Msg )
refreshTurn lobbyId model =
    if model.currentTurn.outcome /= Nothing || model.currentTurn.refreshing then
        model
            |> E.withOut

    else
        ( model
            |> setCurrentTurn (CurrentTurn.setRefreshing True model.currentTurn)
        , E.request (PollStatusResponseReceived (Inactivity.sequence model.inactivity)) (pollRequest lobbyId)
        )


handleCurrentTurnMsg : LobbyId -> CurrentTurn.Msg -> Model -> ( Model, Eff Msg )
handleCurrentTurnMsg lobbyId msg model =
    let
        currentTurn : CurrentTurn.Model
        currentTurn =
            model.currentTurn
    in
    case msg of
        CurrentTurn.PollTimerElapsed ->
            refreshTurn lobbyId model

        CurrentTurn.GotPlaybackPresentationMsg playbackMsg ->
            case playbackMsg of
                PlaybackPresentation.FrameElapsed delta ->
                    advanceCurrentPlayback delta model

                PlaybackPresentation.CombatEnterReleased ->
                    if canContinueCombatWithEnter model then
                        model
                            |> setCombatEnterHeld False
                            |> continueCombat
                            |> presentPlaybackTransition currentTurn.phase

                    else
                        model
                            |> setCombatEnterHeld False
                            |> E.withOut

                PlaybackPresentation.CombatSeeMapReleased ->
                    setCombatMapView TurnPlayback.CardVisible model
                        |> E.withOut


advanceCurrentPlayback : Float -> Model -> ( Model, Eff Msg )
advanceCurrentPlayback delta model =
    let
        currentTurn : CurrentTurn.Model
        currentTurn =
            model.currentTurn
    in
    case model.currentTurn.phase of
        TurnLifecycle.Playing playing ->
            case playing.camera of
                Just held ->
                    if held.remainingPanMs > 0 then
                        (model
                            |> setCurrentTurn
                                (currentTurn
                                    |> CurrentTurn.setPhase
                                        (TurnLifecycle.Playing
                                            (playing
                                                |> TurnLifecycle.setPlaybackCamera
                                                    (Just
                                                        (held
                                                            |> PlaybackPresentation.setRemainingPanMs
                                                                (max 0 (held.remainingPanMs - delta))
                                                        )
                                                    )
                                            )
                                        )
                                )
                        )
                            |> E.withOut

                    else
                        advancePlayback delta model

                Nothing ->
                    advancePlayback delta model

        _ ->
            model
                |> E.withOut


{-| Keep the action at its current frame while the camera settles.
-}
advancePlayback : Float -> Model -> ( Model, Eff Msg )
advancePlayback delta model =
    let
        advance : Float -> Phase -> Maybe { phase : Phase, frame : TurnPlayback.Frame }
        advance =
            if model.skipUnitLossDialogs then
                TurnLifecycle.tick

            else
                TurnLifecycle.tickUntilLoss
    in
    case advance delta model.currentTurn.phase of
        Just next ->
            let
                ( advanced, effect ) =
                    applyPlaybackFrame next model
                        |> automaticallyContinueCombat
                        |> presentPlaybackTransition model.currentTurn.phase

                sounds : List (Eff Msg)
                sounds =
                    PlaybackPresentation.audioBetween
                        { before = playback model
                        , after = playback advanced
                        }
                        |> List.map E.audio
            in
            ( advanced
            , E.batch (effect :: sounds)
            )

        Nothing ->
            model
                |> E.withOut


automaticallyContinueCombat : Model -> Model
automaticallyContinueCombat model =
    let
        ready : Bool
        ready =
            playback model
                |> Maybe.map (PlaybackPresentation.readyToAutomaticallyClose model.automaticallyCloseCombatTheater)
                |> Maybe.withDefault False
    in
    if ready then
        continueCombat model

    else
        model


continueCombat : Model -> Model
continueCombat model =
    case TurnLifecycle.continueCombat model.currentTurn.phase of
        Just next ->
            applyPlaybackFrame next model

        Nothing ->
            model


setCombatMapView : TurnPlayback.MapView -> Model -> Model
setCombatMapView mapView model =
    let
        currentTurn : CurrentTurn.Model
        currentTurn =
            model.currentTurn
    in
    (model
        |> setCurrentTurn
            (currentTurn
                |> CurrentTurn.setPhase (TurnLifecycle.setCombatMapView mapView currentTurn.phase)
            )
    )
        |> updatePlaybackCamera


applyPlaybackFrame :
    { phase : Phase
    , frame : TurnPlayback.Frame
    }
    -> Model
    -> Model
applyPlaybackFrame next model =
    let
        currentTurn : CurrentTurn.Model
        currentTurn =
            model.currentTurn
    in
    model
        |> setCurrentTurn
            (currentTurn
                |> CurrentTurn.setPhase next.phase
            )
        |> setDepots next.frame.depots
        |> setSupplyCrates next.frame.supplyCrates
        |> setUnits next.frame.units
        |> setVisibleTiles next.frame.visibleTiles


handleOrderMsg : OrderMenu.Msg -> Model -> ( Model, Eff Msg )
handleOrderMsg orderMsg model =
    case orderMsg of
        OrderMenu.InfoClicked ->
            if hasDialog model then
                model
                    |> E.withOut

            else if isMobileView model then
                model
                    |> setMenu MobileOrdersHelp
                    |> E.withOut

            else
                model
                    |> mapPlanning (OrderPlanning.openOrderGuide model.map model.units (ownPlayerNumbers model))
                    |> E.withOut

        OrderMenu.CancelClicked ->
            model
                |> clearSelection
                |> E.withOut

        OrderMenu.OrderFocused order ->
            model
                |> focusOrder order
                |> E.withOut

        OrderMenu.OrderPicked order ->
            model
                |> applyOrder order
                |> E.withOut

        OrderMenu.ArrowedUpOrderMenu current ->
            ( model
            , focusAdjacentOrder List.reverse (Just current) model
            )

        OrderMenu.ArrowedDownOrderMenu current ->
            ( model
            , focusAdjacentOrder identity (Just current) model
            )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    let
        workspace : List (Html Msg)
        workspace =
            if isMobileView model then
                mobileView model

            else
                desktopView model
    in
    ChatView.overlay model.chat.recent :: workspace


battlefieldView : Model -> Html Msg
battlefieldView model =
    let
        presentation : Battlefield.Presentation
        presentation =
            battlefieldPresentation model

        args : Battlefield.Args
        args =
            { map = model.map
            , units = model.units
            , depots = model.depots
            , supplyCrates = model.supplyCrates
            , visibleTiles = model.visibleTiles
            , frame = model.frame
            , armyStyle =
                Features.armyStyle model.shared.features
                    |> Maybe.map
                        (\style ->
                            { style = style
                            , players = ownPlayerNumbers model
                            }
                        )
            , selected = selectedPosition model
            , selectedUnitId = selectedUnit model |> Maybe.map .id
            , facingUnits = List.filter (unitShowsFacing model) model.units |> List.map .id
            , presentation = presentation
            }

        heldCamera : Maybe Camera.Camera
        heldCamera =
            playbackCamera model |> Maybe.map .camera

        viewportAttributes : List (H.Attribute Msg)
        viewportAttributes =
            Battlefield.viewportAttributes
                { dragging = BattlefieldNavigation.active model.navigation
                , interaction = Battlefield.interaction presentation
                }
                |> List.map (A.map BattlefieldMsg)
    in
    H.div
        viewportAttributes
        [ Battlefield.camera
            { camera = Maybe.withDefault (BattlefieldNavigation.camera model.navigation) heldCamera
            , transitioning = (heldCamera /= Nothing) || BattlefieldNavigation.returning model.navigation
            }
            [ Battlefield.toSvg args
                |> H.fromUnstyled
            ]
            |> H.map BattlefieldMsg
        ]


battlefieldPresentation : Model -> Battlefield.Presentation
battlefieldPresentation model =
    case playback model of
        Just animation ->
            Battlefield.Playing
                { animation = animation
                , loss = unitLoss model
                }

        Nothing ->
            Battlefield.Viewing
                { saved =
                    { orders = plannedOrders model
                    , unloadRoutes = plannedUnloadRoutes model
                    }
                , interaction = battlefieldInteraction model
                }


battlefieldInteraction : Model -> Battlefield.Interaction
battlefieldInteraction model =
    case unloadPlanning model.currentTurn.phase of
        Just unloading ->
            Battlefield.ChoosingDestination
                { options = unloading.options
                , action = "unload at"
                , purpose = MovementRoute.Travel
                , path = pathPreview model |> Maybe.map .path |> Maybe.withDefault []
                }

        Nothing ->
            case ( currentSelection model, selectedUnit model ) of
                ( Just (UnitSelection selection), Just unit ) ->
                    case selection.interaction of
                        ChoosingMove planning ->
                            let
                                purpose : MovementRoute.Purpose
                                purpose =
                                    case planning.purpose of
                                        MovePlanning.NormalMove ->
                                            MovementRoute.Travel

                                        MovePlanning.AttackMove ->
                                            MovementRoute.Attack

                                action : String
                                action =
                                    case planning.purpose of
                                        MovePlanning.NormalMove ->
                                            "move to"

                                        MovePlanning.AttackMove ->
                                            "attack move to"
                            in
                            Battlefield.ChoosingDestination
                                { options = planning.options
                                , action = action
                                , purpose = purpose
                                , path = planning.preview.path
                                }

                        ChoosingIndirectFire planning ->
                            case Unit.mapPosition unit of
                                Just origin ->
                                    Battlefield.ChoosingIndirectTarget
                                        { origin = origin
                                        , range = unit.combatRules.indirectRange
                                        , preview = IndirectFirePlanning.targetPreview planning
                                        }

                                Nothing ->
                                    Battlefield.Inspecting

                        ChoosingDirection planning ->
                            battlefieldDirection unit planning

                        OrderMenu _ ->
                            Battlefield.Inspecting

                _ ->
                    Battlefield.Inspecting


battlefieldDirection : Unit -> DirectionPlanning.DirectionPlanning -> Battlefield.Interaction
battlefieldDirection unit planning =
    case planning of
        DirectionPlanning.AttackMove move direction ->
            Battlefield.ChoosingDirection
                { unitId = unit.id
                , position = move.destination
                , direction = direction
                , purpose = Battlefield.AttackMoveFacing move.path
                }

        DirectionPlanning.Stationary stationaryPurpose direction ->
            case Unit.mapPosition unit of
                Just position ->
                    let
                        purpose : Battlefield.DirectionPurpose
                        purpose =
                            case stationaryPurpose of
                                DirectionPlanning.AmbushPurpose ->
                                    Battlefield.AmbushFacing unit.combatRules

                                DirectionPlanning.StandGroundPurpose ->
                                    Battlefield.StandGroundFacing
                    in
                    Battlefield.ChoosingDirection
                        { unitId = unit.id
                        , position = position
                        , direction = direction
                        , purpose = purpose
                        }

                Nothing ->
                    Battlefield.Inspecting


viewControls : Int -> Html Msg
viewControls zoom =
    Battlefield.navigationControls zoom
        |> H.map BattlefieldMsg


desktopView : Model -> List (Html Msg)
desktopView model =
    BattlefieldWorkspace.toHtml
        { loss = unitLoss model /= Nothing
        , combat = combatEncounter model /= Nothing
        , dying = deathInFocus model
        , battlefield = battlefieldView model
        , orders = orderMenu model
        , header =
            GameMenu.panel
                { enabled = canOpenDialog model
                , turnNumber = displayedTurnNumber model
                , mobile = False
                }
                |> H.map GameMenuMsg
                |> Just
        , controls = turnPanel model
        , notification = requestErrorCard model
        , inspection = selectionView Layout.Desktop model
        , hasSelection = currentSelection model /= Nothing
        , onCloseInspection = InspectorCloseClicked
        , combatOverlay =
            PlaybackPresentation.combatOverlay
                { calibrations = CombatTheaterCalibrations.catalog
                , automaticallyClose = model.automaticallyCloseCombatTheater
                , mobile = False
                }
                model.map
                (playback model)
                |> H.map CombatTheaterMsg
        }


mobileView : Model -> List (Html Msg)
mobileView model =
    let
        close : Button.Button Msg
        close =
            if (currentSelection model /= Nothing) && canOpenDialog model then
                Button.secondary "close" InspectorCloseClicked

            else
                Button.disabled "close"

        activity : TurnControls.Activity
        activity =
            if canOpenDialog model then
                turnActivity model

            else
                TurnControls.Locked
    in
    MobileBattlefield.toHtml
        { header =
            MobileBattlefield.topBar
                { surrender =
                    TurnControls.headerSurrender (surrenderState model)
                        |> H.map TurnControlsMsg
                , center =
                    GameMenu.panel
                        { enabled = canOpenDialog model
                        , turnNumber = displayedTurnNumber model
                        , mobile = True
                        }
                        |> H.map GameMenuMsg
                , submit =
                    TurnControls.headerSubmit activity (turnSubmitLabel model)
                        |> H.map TurnControlsMsg
                }
        , battlefield = battlefieldView model
        , hasSelection = currentSelection model /= Nothing
        , tab = mobilePanelTab model
        , panelHeader = mobilePanelHeader model
        , panel = mobileTaskPanel model
        , close =
            close
                |> Button.fullWidth
                |> Button.toHtml
        , notification = requestErrorCard model
        , focus =
            { loss = unitLoss model /= Nothing
            , combat = combatEncounter model /= Nothing
            , dying = deathInFocus model
            }
        , combatOverlay =
            PlaybackPresentation.combatOverlay
                { calibrations = CombatTheaterCalibrations.catalog
                , automaticallyClose = model.automaticallyCloseCombatTheater
                , mobile = True
                }
                model.map
                (playback model)
                |> H.map CombatTheaterMsg
        }


mobileOrdersAvailable : Model -> Bool
mobileOrdersAvailable model =
    case selectedUnit model of
        Just unit ->
            isOwnUnit model unit && not (planningLocked model)

        Nothing ->
            False


mobilePanelTab : Model -> MobileBattlefield.Tab
mobilePanelTab model =
    if mobileOrdersAvailable model then
        model.mobileTab

    else
        MobileBattlefield.Details


mobilePanelHeader : Model -> Html Msg
mobilePanelHeader model =
    if currentSelection model == Nothing then
        H.text ""

    else
        MobileBattlefield.panelHeader
            { tab = mobilePanelTab model
            , ordersAvailable = mobileOrdersAvailable model
            , onTabClick = MobileTabClicked
            , onTabNavigate = MobileTabNavigationPressed
            , onOrdersHelp = OrderMenuMsg OrderMenu.InfoClicked
            }


mobileTaskPanel : Model -> Html Msg
mobileTaskPanel model =
    let
        selectedTab : MobileBattlefield.Tab
        selectedTab =
            mobilePanelTab model

        tabs : List MobileBattlefield.Tab
        tabs =
            if mobileOrdersAvailable model then
                [ MobileBattlefield.Orders
                , MobileBattlefield.Details
                ]

            else
                [ MobileBattlefield.Details ]

        panel : MobileBattlefield.Tab -> Html Msg
        panel tab =
            let
                active : Bool
                active =
                    tab == selectedTab

                content : List (Html Msg)
                content =
                    if active then
                        case tab of
                            MobileBattlefield.Orders ->
                                [ mobileOrdersPanel model ]

                            MobileBattlefield.Details ->
                                [ selectionView
                                    Layout.Mobile
                                    model
                                ]

                    else
                        []
            in
            H.section
                [ A.id (MobileBattlefield.tabHtmlId tab ++ "-panel")
                , A.attribute "role" "tabpanel"
                , Aria.labelledBy (MobileBattlefield.tabHtmlId tab)
                , A.hidden (not active)
                ]
                content
    in
    if currentSelection model == Nothing then
        H.text ""

    else
        H.div
            []
            (List.map panel tabs)


mobileOrdersPanel : Model -> Html Msg
mobileOrdersPanel model =
    case orderMenuUnit model of
        Just unit ->
            OrderMenu.embedded model.depots model.map unit
                |> H.map OrderMenuMsg

        Nothing ->
            case selectedUnit model of
                Just unit ->
                    let
                        canCancelOrder : Bool
                        canCancelOrder =
                            not (planningLocked model) && isOwnUnit model unit

                        action : Html Msg
                        action =
                            if canRevokeOrder model unit then
                                Button.primary
                                    "revoke order"
                                    ClearMoveClicked
                                    |> Button.fullWidth
                                    |> Button.toHtml

                            else if canCancelOrder then
                                Button.secondary
                                    "cancel order"
                                    CancelOrderClicked
                                    |> Button.fullWidth
                                    |> Button.toHtml

                            else
                                H.text ""

                        choosingFacing : Bool
                        choosingFacing =
                            choosingDirection model
                                || choosingAmbush model
                                || choosingStandGround model

                        instruction : String
                        instruction =
                            if choosingFacing then
                                "choose a direction on the map"

                            else if choosingIndirectFire model then
                                "tap a target on the map"

                            else if pathPreview model /= Nothing then
                                "drag to trace a route, or tap a destination."

                            else
                                ""

                        context : Html Msg
                        context =
                            case unloadPlanning model.currentTurn.phase of
                                Just planning ->
                                    mobileUnloadPreview model.units planning

                                Nothing ->
                                    if String.isEmpty instruction then
                                        H.text ""

                                    else
                                        H.p
                                            []
                                            [ H.text instruction ]
                    in
                    H.div
                        [ A.css
                            [ S.col
                            , S.g2
                            ]
                        ]
                        [ context
                        , action
                        ]

                Nothing ->
                    H.p
                        []
                        [ H.text "tap a unit to plan its orders" ]


mobileUnloadPreview : List Unit -> UnloadPlanning -> Html Msg
mobileUnloadPreview units planning =
    let
        portrait : Maybe { image : Html Msg, name : String }
        portrait =
            case planning.cargo of
                UnloadCargo.Passenger id ->
                    units
                        |> ListUtil.find (\unit -> unit.id == id)
                        |> Maybe.map passengerPortrait

                UnloadCargo.Crate index ->
                    unloadingStock units planning.truck index
                        |> Maybe.map freightPortrait

        passengerPortrait : Unit -> { image : Html Msg, name : String }
        passengerPortrait unit =
            { image =
                unitThumbnail UnloadPortrait unit
            , name = Unit.name unit
            }

        freightPortrait : Supply.CargoStock -> { image : Html Msg, name : String }
        freightPortrait stock =
            { image =
                H.img
                    [ A.src (Supply.cargoImage stock.kind)
                    , A.alt ""
                    , A.css [ S.w12, S.hAuto, S.shrink0 ]
                    ]
                    []
            , name = Supply.cargoLabel stock.kind
            }

        order : PlannedOrder
        order =
            UnloadingTruck.toOrder planning.truck

        passengerCount : Int
        passengerCount =
            List.length (PlannedOrder.unloads order)

        freightCount : Int
        freightCount =
            List.length (PlannedOrder.crateUnloads order)

        current : Int
        current =
            1 + passengerCount + freightCount

        progress : String
        progress =
            "unloading "
                ++ String.fromInt current
                ++ " of "
                ++ String.fromInt (current + List.length planning.remaining)
    in
    case portrait of
        Just cargo ->
            H.div
                [ Aria.role Aria.Status
                , A.css
                    [ S.col
                    , S.g1
                    , S.p2
                    , S.bgNightwood3
                    , S.indentStrong
                    ]
                ]
                [ H.span
                    [ A.css [ S.textYellow5 ] ]
                    [ H.text progress ]
                , H.div
                    [ A.css
                        [ S.row
                        , S.itemsCenter
                        , S.g2
                        , S.textGray5
                        ]
                    ]
                    [ cargo.image
                    , H.text cargo.name
                    ]
                ]

        Nothing ->
            H.text ""


unitThumbnail : ThumbnailUse -> Unit -> Html msg
unitThumbnail use unit =
    let
        size : Style
        size =
            case use of
                UnloadPortrait ->
                    S.square12

                SubmissionPortrait ->
                    S.square8
    in
    Svg.svg
        [ SA.viewBox "0 0 16 16"
        , Aria.hidden True
        , SA.css
            [ size
            , S.shrink0
            ]
        ]
        [ UnitSprite.toSvg 0 unit ]


orderMenu : Model -> Html Msg
orderMenu model =
    let
        menuUnit : Maybe Unit
        menuUnit =
            if orderGuideOpen model then
                selectedUnit model

            else
                orderMenuUnit model
    in
    case menuUnit of
        Just unit ->
            case Unit.physicalPosition model.units unit of
                Just position ->
                    OrderMenu.toHtml
                        model.depots
                        model.map
                        (BattlefieldNavigation.camera model.navigation)
                        position
                        unit
                        |> H.map OrderMenuMsg

                Nothing ->
                    H.text ""

        Nothing ->
            H.text ""


selectionView : Layout -> Model -> Html Msg
selectionView layout model =
    case unloadPlanning model.currentTurn.phase of
        Just planning ->
            case planning.cargo of
                UnloadCargo.Crate index ->
                    unloadingStock model.units planning.truck index
                        |> Maybe.map (BattlefieldInspection.unloadingFreight index)
                        |> Maybe.withDefault (battlefieldSelectionView layout model)

                UnloadCargo.Passenger _ ->
                    battlefieldSelectionView layout model

        Nothing ->
            battlefieldSelectionView layout model


unloadingStock : List Unit -> UnloadingTruck -> Int -> Maybe Supply.CargoStock
unloadingStock units truck index =
    unloadingCargoStock units truck
        |> List.drop index
        |> List.head


unloadingCargoStock : List Unit -> UnloadingTruck -> List Supply.CargoStock
unloadingCargoStock units truck =
    let
        truckId : UnitId
        truckId =
            UnloadingTruck.unitId truck
    in
    units
        |> ListUtil.find (\unit -> unit.id == truckId)
        |> Maybe.andThen .resources
        |> Maybe.map .supplyCargo
        |> Maybe.withDefault []


battlefieldSelectionView : Layout -> Model -> Html Msg
battlefieldSelectionView layout model =
    let
        inspectedUnit : Maybe Unit
        inspectedUnit =
            case selectedUnit model of
                Just unit ->
                    Just unit

                Nothing ->
                    inspectionPosition model
                        |> Maybe.andThen (\coordinate -> ListUtil.find (\unit -> Unit.mapPosition unit == Just coordinate) model.units)

        unitContent : Unit -> { unit : Unit, content : List (Html Msg) }
        unitContent unit =
            let
                actions : List (Html Msg)
                actions =
                    if Maybe.map .id (selectedUnit model) == Just unit.id then
                        [ movementView model ]

                    else
                        []

                authoritativeUnit : Unit
                authoritativeUnit =
                    model.units
                        |> ListUtil.find (\original -> original.id == unit.id)
                        |> Maybe.withDefault unit

                canCancelOrder : Bool
                canCancelOrder =
                    (Maybe.map .id (selectedUnit model) == Just unit.id)
                        && ((pathPreview model /= Nothing)
                                || (choosingDirection model && not (choosingAmbush model))
                           )

                portraitAction : Maybe (UnitStatus.Action Msg)
                portraitAction =
                    if canRevokeOrder model unit then
                        Just (UnitStatus.RevokeOrder ClearMoveClicked)

                    else if canCancelOrder then
                        Just (UnitStatus.CancelOrder CancelOrderClicked)

                    else
                        Nothing

                content : List (Html Msg)
                content =
                    [ UnitStatus.toHtml
                        layout
                        { onHelp = InspectionHelpClicked }
                        (ownerName model unit |> Maybe.withDefault "")
                        authoritativeUnit
                        portraitAction
                    , BattlefieldInspection.cargo
                        { units = model.units
                        , ownPlayers = ownPlayerNumbers model
                        , onSelectPassenger = CargoUnitClicked
                        , onHelp = InspectionHelpClicked
                        }
                        unit
                    ]
                        ++ actions
            in
            { unit = unit, content = content }

        position : Maybe Coordinate
        position =
            case inspectedUnit of
                Just unit ->
                    Unit.physicalPosition model.units unit

                Nothing ->
                    inspectionPosition model
    in
    BattlefieldInspection.toHtml
        layout
        { onHelp = InspectionHelpClicked
        , map = model.map
        , depots = model.depots
        , supplyCrates = model.supplyCrates
        , visibleTiles = model.visibleTiles
        , position = position
        , unit = Maybe.map unitContent inspectedUnit
        }


movementView : Model -> Html Msg
movementView model =
    let
        details : List (Html Msg)
        details =
            case selectedUnit model of
                Just unit ->
                    if not (isOwnUnit model unit) then
                        []

                    else if model.currentTurn.outcome /= Nothing then
                        [ H.p
                            []
                            [ H.text "the game is over. the battlefield is available to inspect."
                            ]
                        ]

                    else if planningLocked model then
                        []

                    else if isChoosingUnload model then
                        []

                    else if Unit.carrierId unit /= Nothing then
                        transportDetails unit

                    else if choosingIndirectFire model then
                        indirectFireDetails unit

                    else if choosingAmbush model then
                        ambushDetails unit

                    else if choosingStandGround model then
                        [ H.p [] [ H.text "choose a stand ground direction on the map, or press an arrow key / wasd" ]
                        , H.p [] [ H.text "combat ready when attacked; does not fire" ]
                        , H.p [] [ H.text ("supplies: normal upkeep + " ++ String.fromInt unit.combatRules.readinessCost ++ " readiness") ]
                        ]

                    else if choosingDirection model then
                        [ H.p [] [ H.text "choose final attack direction around the destination. click to save, or press an arrow key or wasd." ]
                        ]

                    else
                        unitOrderView model unit

                Nothing ->
                    []

        feedback : List (Html Msg)
        feedback =
            if destinationFeedback model == DestinationUnavailable then
                [ H.p
                    [ Aria.role Aria.Status ]
                    [ H.text "that square cannot be a destination within this unit’s movement budget." ]
                ]

            else
                []

        dismountDetails : List (Html Msg)
        dismountDetails =
            case selectedUnit model of
                Just unit ->
                    if PlannedTransport.isDismounting model.units unit then
                        [ H.p
                            []
                            [ H.text "this infantry acts after unloading, with a fresh movement allowance. unloading and movement both consume supplies."
                            ]
                        ]

                    else
                        []

                Nothing ->
                    []

        content : List (Html Msg)
        content =
            dismountDetails ++ details ++ feedback
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        content


canRevokeOrder : Model -> Unit -> Bool
canRevokeOrder model unit =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map (OrderPlanning.canRevokeOrder model.map model.units (ownPlayerNumbers model) unit.id)
        |> Maybe.withDefault False


unitOrderView : Model -> Unit -> List (Html Msg)
unitOrderView model unit =
    let
        maybePlan : Maybe PlannedOrder
        maybePlan =
            ListUtil.find
                (\plan -> plan.unitId == unit.id)
                (plannedOrders model)
    in
    case ( pathPreview model, maybePlan ) of
        ( Just preview, _ ) ->
            let
                attackPlanning : Bool
                attackPlanning =
                    TurnLifecycle.planning model.currentTurn.phase
                        |> Maybe.andThen OrderPlanning.movementPlanning
                        |> Maybe.map (\planning -> planning.purpose == MovePlanning.AttackMove)
                        |> Maybe.withDefault False

                loadingDetails : List (Html Msg)
                loadingDetails =
                    if attackPlanning then
                        []

                    else
                        loadingNotice model unit preview.destination
            in
            loadingDetails

        ( Nothing, Just plan ) ->
            let
                unloadSummary : UnloadOrder -> Html Msg
                unloadSummary unload =
                    let
                        passengerName : String
                        passengerName =
                            ListUtil.find (\passenger -> passenger.id == unload.unitId) model.units
                                |> Maybe.map Unit.label
                                |> Maybe.withDefault "unit"
                    in
                    H.p []
                        [ H.text
                            ("unload "
                                ++ passengerName
                                ++ " "
                                ++ " at ("
                                ++ String.fromInt unload.destination.x
                                ++ ", "
                                ++ String.fromInt unload.destination.y
                                ++ ")"
                            )
                        ]

                unloadDetails : List (Html Msg)
                unloadDetails =
                    List.map unloadSummary (PlannedOrder.unloads plan)

                orderDetails : List (Html Msg)
                orderDetails =
                    let
                        showSummary : Bool
                        showSummary =
                            case plan.action of
                                PlannedOrder.Move _ ->
                                    List.isEmpty loadingDetails

                                PlannedOrder.Hold _ ->
                                    List.isEmpty loadingDetails

                                PlannedOrder.Unload _ ->
                                    List.isEmpty loadingDetails

                                _ ->
                                    True

                        chosenOrderText : String
                        chosenOrderText =
                            case plan.action of
                                PlannedOrder.SupplyTransfer supply ->
                                    "cargo run to ("
                                        ++ String.fromInt supply.destination.x
                                        ++ ", "
                                        ++ String.fromInt supply.destination.y
                                        ++ "): "
                                        ++ freightHandlingSummary supply.handling

                                PlannedOrder.IndirectFire fire ->
                                    "indirect fire: (" ++ String.fromInt fire.target.x ++ ", " ++ String.fromInt fire.target.y ++ ")"

                                PlannedOrder.StandGround facing ->
                                    "stand ground: " ++ Direction.label facing.direction

                                PlannedOrder.Sabotage _ ->
                                    "sabotage"

                                PlannedOrder.DigIn _ ->
                                    "dig in"

                                PlannedOrder.Hold _ ->
                                    "hold position"

                                PlannedOrder.Unload _ ->
                                    "hold position"

                                PlannedOrder.Ambush ambush ->
                                    "ambush: " ++ Direction.label ambush.direction

                                PlannedOrder.AttackMove attack ->
                                    "attack move: ("
                                        ++ String.fromInt attack.move.destination.x
                                        ++ ", "
                                        ++ String.fromInt attack.move.destination.y
                                        ++ ") · facing: "
                                        ++ Direction.label attack.direction
                                        ++ " · movement: "
                                        ++ Movement.pointsLabel attack.move.cost

                                PlannedOrder.Move movePlan ->
                                    if List.length movePlan.move.path <= 1 then
                                        "hold position"

                                    else
                                        [ plannedAction model unit movePlan.move
                                        , ": ("
                                        , String.fromInt movePlan.move.destination.x
                                        , ", "
                                        , String.fromInt movePlan.move.destination.y
                                        , ") · movement: "
                                        , Movement.pointsLabel movePlan.move.cost
                                        ]
                                            |> String.concat
                    in
                    if showSummary then
                        [ H.h3
                            []
                            [ H.text chosenOrderText ]
                        ]

                    else
                        []

                loadingDetails : List (Html Msg)
                loadingDetails =
                    case plan.action of
                        PlannedOrder.Move movePlan ->
                            loadingNotice model unit movePlan.move.destination

                        _ ->
                            if receivingLoad unit model then
                                loadingNotice model unit (PlannedOrder.destination plan)

                            else
                                []
            in
            orderDetails ++ loadingDetails ++ unloadDetails ++ ambushCosts unit plan

        ( Nothing, Nothing ) ->
            []


choosingAmbush : Model -> Bool
choosingAmbush model =
    case currentSelection model of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingDirection (DirectionPlanning.Stationary DirectionPlanning.AmbushPurpose _) ->
                    True

                _ ->
                    False

        _ ->
            False


choosingStandGround : Model -> Bool
choosingStandGround model =
    case currentSelection model of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingDirection (DirectionPlanning.Stationary DirectionPlanning.StandGroundPurpose _) ->
                    True

                _ ->
                    False

        _ ->
            False


unitShowsFacing : Model -> Unit -> Bool
unitShowsFacing model unit =
    let
        previewingFacing : Bool
        previewingFacing =
            (choosingAmbush model || choosingStandGround model)
                && (Maybe.map .unitId (rotationSelection model) == Just unit.id)

        stationaryFacingOrder : PlannedOrder -> Bool
        stationaryFacingOrder order =
            case order.action of
                PlannedOrder.Ambush _ ->
                    order.unitId == unit.id

                PlannedOrder.StandGround _ ->
                    order.unitId == unit.id

                _ ->
                    False

        stationaryFacingEvent : Turn.Event -> Bool
        stationaryFacingEvent event =
            (event.unitId == unit.id)
                && List.member event.kind [ TurnEventKind.Ambush, TurnEventKind.StandGround ]
    in
    case model.currentTurn.phase of
        TurnLifecycle.Playing _ ->
            model.currentTurn.resolution
                |> Maybe.map (\resolution -> List.any stationaryFacingEvent resolution.events)
                |> Maybe.withDefault False

        _ ->
            previewingFacing || List.any stationaryFacingOrder (plannedOrders model)


ambushCosts : Unit -> PlannedOrder -> List (Html Msg)
ambushCosts unit order =
    case order.action of
        PlannedOrder.IndirectFire _ ->
            indirectFireDetails unit

        PlannedOrder.Sabotage _ ->
            [ H.p
                []
                [ H.text "destroys the depot or fortress after combat if this infantry survives; no movement or firing"
                ]
            , H.p
                []
                [ H.text "supplies: normal upkeep"
                ]
            ]

        PlannedOrder.DigIn _ ->
            [ H.p [] [ H.text "entrenched after this turn; no movement or firing while digging" ]
            , H.p [] [ H.text ("supplies: normal upkeep + " ++ String.fromInt unit.combatRules.digInCost ++ " digging") ]
            ]

        PlannedOrder.StandGround _ ->
            [ H.p [] [ H.text "combat ready when attacked; does not fire" ]
            , H.p [] [ H.text ("supplies: normal upkeep + " ++ String.fromInt unit.combatRules.readinessCost ++ " readiness") ]
            ]

        PlannedOrder.Ambush _ ->
            List.drop 1 (ambushDetails unit)

        _ ->
            []


ambushDetails : Unit -> List (Html Msg)
ambushDetails unit =
    let
        rules : CombatRules.CombatRules
        rules =
            unit.combatRules
    in
    [ H.p
        []
        [ H.text "choose an ambush direction on the map, or press an arrow key / wasd"
        ]
    , H.p
        []
        [ H.text ("range: " ++ String.fromInt rules.range ++ " · base damage: " ++ String.fromInt rules.damage)
        ]
    , H.p
        []
        [ H.text ("supplies: normal upkeep + " ++ String.fromInt rules.readinessCost ++ " readiness + " ++ String.fromInt rules.shotCost ++ " per shot")
        ]
    ]


loadingNotice : Model -> Unit -> Coordinate -> List (Html Msg)
loadingNotice model unit destination =
    case PlannedTransport.loadingTarget model.units unit destination (plannedOrders model) of
        Just target ->
            let
                loading : { passenger : Unit, truck : Unit }
                loading =
                    if unit.kind == UnitKind.Truck then
                        { passenger = target, truck = unit }

                    else
                        { passenger = unit, truck = target }
            in
            [ LoadingNotice.toHtml loading ]

        Nothing ->
            []


transportDetails : Unit -> List (Html Msg)
transportDetails unit =
    let
        description : String
        description =
            if Unit.carrierId unit /= Nothing then
                "aboard a truck. select the truck and choose its move destination to unload passengers."

            else if unit.kind == UnitKind.Truck then
                "move onto allied infantry or a field gun to load it. the unit will hold. trucks carry two units."

            else if unit.kind == UnitKind.Tank then
                "tanks cannot board trucks."

            else
                "move onto an allied truck or its planned destination to board. trucks have two berths shared with supply crates and fuel drums."
    in
    [ H.p
        []
        [ H.text description
        ]
    ]


unloadChecklist : Model -> UnloadChoice -> Dialog Msg
unloadChecklist model choice =
    let
        mobile : Bool
        mobile =
            isMobileView model

        proceedButton : Html Msg
        proceedButton =
            if List.isEmpty choice.checked then
                Button.secondary "proceed without unloading" UnloadSkipped
                    |> Button.toHtml

            else
                Button.primary "choose unload squares" UnloadChoicesConfirmed
                    |> Button.toHtml
    in
    Dialog.make unloadDialogHtmlId
        "unload"
        EscapePressed
        [ H.div
            [ A.css
                [ S.col
                , S.when mobile
                    [ S.flex1
                    , S.minH0
                    , S.overflowAuto
                    ]
                ]
            ]
            [ Lazy.lazy7 unloadCargoChecklist
                model.map
                model.units
                model.players
                model.movementRules
                model.supplyCrates
                model.visibleTiles
                choice
            ]
        , H.form
            [ A.attribute "method" "dialog"
            , A.css [ S.when mobile [ S.shrink0 ] ]
            ]
            [ proceedButton ]
        ]
        |> Dialog.reference


unloadCargoChecklist :
    Map
    -> List Unit
    -> List Player
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Coordinate
    -> UnloadChoice
    -> Html Msg
unloadCargoChecklist map units players movementRules crates visibleTiles choice =
    let
        playerNumbers : List PlayerNumber
        playerNumbers =
            List.filter .isYou players |> List.map .playerNumber

        supplyCrates : List Supply.GroundCrate
        supplyCrates =
            visibleSupplyCrates visibleTiles crates

        unavailable : UnloadCargo -> Bool
        unavailable cargo =
            OrderPlanning.canSelectUnloadCargo
                map
                units
                playerNumbers
                movementRules
                supplyCrates
                cargo
                (OrderPlanning.ChoosingPassengers choice)
                |> IC.resolve unavailableResult

        unavailableResult : Maybe OrderPlanning.InvariantViolation -> Bool -> Bool
        unavailableResult violation available =
            (violation /= Nothing) || not available

        passengers : List Unit
        passengers =
            unloadingPassengers choice.truck units

        stock : List Supply.CargoStock
        stock =
            unloadingCargoStock units choice.truck

        unavailableCargo : List UnloadCargo
        unavailableCargo =
            List.filter unavailable
                (List.map (.id >> UnloadCargo.Passenger) passengers
                    ++ List.indexedMap (\index _ -> UnloadCargo.Crate index) stock
                )

        passengerCheckbox : Unit -> Html Msg
        passengerCheckbox unit =
            let
                cargo : UnloadCargo
                cargo =
                    UnloadCargo.Passenger unit.id
            in
            UnloadPassenger.toHtml
                { disabled = List.member cargo unavailableCargo
                , checked = List.member cargo choice.checked
                , onCheck = UnloadUnitToggled unit.id
                }
                unit

        choices : List (Html Msg)
        choices =
            passengerChoices ++ crateChoices

        passengerChoices : List (Html Msg)
        passengerChoices =
            List.map passengerCheckbox passengers

        crateChoices : List (Html Msg)
        crateChoices =
            List.indexedMap crateCheckbox stock

        crateCheckbox : Int -> Supply.CargoStock -> Html Msg
        crateCheckbox index crate =
            let
                label : String
                label =
                    Supply.cargoLabel crate.kind ++ " " ++ String.fromInt (index + 1)

                cargo : UnloadCargo
                cargo =
                    UnloadCargo.Crate index
            in
            Checkbox.new
                { label = label
                , checked = List.member cargo choice.checked
                , onCheck = UnloadCrateToggled index
                }
                |> Checkbox.disabled (List.member cargo unavailableCargo)
                |> Checkbox.card
                    [ H.img
                        [ A.src (Supply.cargoImage crate.kind)
                        , A.alt ""
                        , A.css
                            [ S.w20
                            , S.hAuto
                            , S.shrink0
                            ]
                        ]
                        []
                    , H.span
                        [ A.css
                            [ S.col
                            , S.g2
                            , S.minW0
                            ]
                        ]
                        [ H.span
                            [ A.css [ S.textGray5 ] ]
                            [ H.text label ]
                        , H.span
                            []
                            [ H.text (Supply.resourceLabel crate.kind ++ " " ++ String.fromInt crate.current ++ "/" ++ String.fromInt crate.maximum) ]
                        ]
                    ]

        unavailableContent : List (Html Msg)
        unavailableContent =
            if List.isEmpty unavailableCargo then
                []

            else
                [ H.p
                    [ A.css [ S.textGray4 ] ]
                    [ H.text "remaining cargo has no available unload space or insufficient supplies" ]
                ]

        cargoContent : List (Html Msg)
        cargoContent =
            cargoCards :: unavailableContent

        cargoCards : Html Msg
        cargoCards =
            H.div
                [ A.css
                    [ S.grid
                    , S.gridColumns "repeat(auto-fit, minmax(min(100%, 17rem), 1fr))"
                    , S.g3
                    ]
                ]
                choices
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        cargoContent


freightHandlingSummary : PlannedOrder.SupplyHandling -> String
freightHandlingSummary handling =
    case handling of
        PlannedOrder.PickingUpGroundFreight kind ->
            "pick up " ++ Supply.cargoLabel kind

        PlannedOrder.LoadingCrates count ->
            "load " ++ String.fromInt count

        PlannedOrder.UnloadingCrates exits ->
            "unload " ++ String.fromInt (List.length exits)


groundPickupDialog : Supply.GroundCrate -> Dialog Msg
groundPickupDialog freight =
    let
        label : String
        label =
            Supply.cargoLabel freight.stock.kind
    in
    Dialog.make groundPickupDialogHtmlId
        ("pick up " ++ label)
        EscapePressed
        [ H.p
            []
            [ H.text ("would you like this truck to pick up the " ++ label ++ " at its destination?")
            ]
        , Cargo.pickupPreview freight.stock
        , H.form
            [ A.attribute "method" "dialog"
            , A.css
                [ S.row
                , S.flexWrap
                , S.g3
                ]
            ]
            [ Button.primary "pick up" GroundFreightPickupClicked
                |> Button.toHtml
            , Button.secondary "leave on ground" DialogDismissed
                |> Button.toHtml
            ]
        ]


depotLoadingDialog : Model -> UnitId -> LoadingSource -> Dialog Msg
depotLoadingDialog model id source =
    let
        truck : Maybe Unit
        truck =
            ListUtil.find (\unit -> unit.id == id) model.units

        room : Int
        room =
            truck
                |> Maybe.map (depotLoadingRoom model)
                |> Maybe.withDefault 0

        cargoLabel : String
        cargoLabel =
            Supply.cargoPlural source.kind

        question : String
        question =
            case source.kind of
                ResourceKind.Supply ->
                    "how many crates would you like to load?"

                ResourceKind.Fuel ->
                    "how many drum loads should this truck take?"

        stock : Maybe Supply.Stock
        stock =
            source.stock

        resourceLabel : String
        resourceLabel =
            Supply.resourceLabel source.kind

        stockLabel : String
        stockLabel =
            case stock of
                Just known ->
                    String.fromInt known.current ++ " " ++ resourceLabel

                Nothing ->
                    "stock outside sight"

        capacity : Int
        capacity =
            Supply.cargoCapacity model.supplyRules source.kind

        loadAmount : Int -> Maybe Int
        loadAmount count =
            stock
                |> Maybe.map
                    (\known ->
                        min known.current (count * capacity)
                    )

        choice : Int -> Html Msg
        choice count =
            let
                buttonLabel : String
                buttonLabel =
                    if count == 0 then
                        "none"

                    else
                        String.fromInt count

                quantity : String
                quantity =
                    if count == 0 then
                        "—"

                    else
                        loadAmount count
                            |> Maybe.map String.fromInt
                            |> Maybe.withDefault "?"

                cargoName : String
                cargoName =
                    case source.kind of
                        ResourceKind.Supply ->
                            if count == 1 then
                                "supply crate"

                            else
                                "supply crates"

                        ResourceKind.Fuel ->
                            if count == 1 then
                                "fuel drum"

                            else
                                "fuel drums"

                quantityLabel : String
                quantityLabel =
                    case loadAmount count of
                        Just amount ->
                            String.fromInt amount ++ " " ++ resourceLabel

                        Nothing ->
                            "stock outside sight"

                accessibleLabel : String
                accessibleLabel =
                    if count == 0 then
                        "load none"

                    else
                        "load "
                            ++ String.fromInt count
                            ++ " "
                            ++ cargoName
                            ++ ", "
                            ++ quantityLabel

                berthFill : Int -> Html Msg
                berthFill index =
                    let
                        amount : Int
                        amount =
                            loadAmount count
                                |> Maybe.withDefault 0
                                |> (\total -> clamp 0 capacity (total - index * capacity))

                        percentage : Float
                        percentage =
                            100 * toFloat amount / toFloat capacity
                    in
                    H.div
                        [ A.css
                            [ S.flex1_1_0pct
                            , S.bgNightwood3
                            , S.h2
                            ]
                        ]
                        [ H.div
                            [ A.css
                                [ S.bgYellow4
                                , S.hFull
                                , S.widthPct percentage
                                ]
                            ]
                            []
                        ]

                berthFills : List (Html Msg)
                berthFills =
                    if (count > 0) && (stock /= Nothing) then
                        List.map berthFill [ 0, 1 ]

                    else
                        []
            in
            H.div
                [ A.css
                    [ S.col
                    , S.itemsCenter
                    , S.flex1_1_0pct
                    , S.minW0
                    , S.g3
                    ]
                ]
                [ Button.secondary buttonLabel (LoadCratesClicked id count)
                    |> Button.accessibleLabel accessibleLabel
                    |> Button.fullWidth
                    |> Button.toHtml
                , H.span
                    [ A.css
                        [ S.textGray5
                        , S.tabularNums
                        ]
                    ]
                    [ H.text quantity
                    ]
                , H.div
                    [ Aria.hidden True
                    , A.css
                        [ S.row
                        , S.g1
                        , S.wFull
                        , S.h2
                        ]
                    ]
                    berthFills
                ]

        stockDetails : List (Html Msg)
        stockDetails =
            if room == 0 then
                let
                    explanation : String
                    explanation =
                        case stock of
                            Just known ->
                                if known.current == 0 then
                                    "depot empty"

                                else
                                    "no cargo room"

                            Nothing ->
                                "no cargo room"
                in
                [ H.p
                    []
                    [ H.text explanation
                    ]
                ]

            else
                []

        actions : Html Msg
        actions =
            H.form
                [ A.attribute "method" "dialog"
                , A.css
                    [ S.row
                    , S.g3
                    ]
                ]
                (List.range 0 room
                    |> List.map choice
                )

        content : List (Html Msg)
        content =
            [ H.div
                [ A.css
                    [ S.row
                    , S.justifySpaceBetween
                    , S.flexWrap
                    , S.g2
                    ]
                ]
                [ H.span
                    []
                    [ H.text "depot"
                    ]
                , H.span
                    [ A.css
                        [ S.textGray5
                        , S.tabularNums
                        ]
                    ]
                    [ H.text stockLabel
                    ]
                ]
            , H.p
                []
                [ H.text question
                ]
            , actions
            ]
                ++ stockDetails
    in
    Dialog.make loadCratesDialogHtmlId
        ("load " ++ cargoLabel)
        EscapePressed
        content


chatDialog : Model -> () -> Maybe (Dialog Msg)
chatDialog model _ =
    case model.chat.panel of
        Chat.Composing composer ->
            ChatView.dialog
                { mobile = isMobileView model }
                model.chat
                composer
                |> Dialog.map ChatMsg
                |> Just

        _ ->
            Nothing


{-| Dialogs derive from the rotation notice, inactivity warnings, the welcome briefing, chat, inspector help, the game menu, order guide, turn introduction, playback loss, or the active planning workflow.
-}
dialog : Model -> Maybe (Dialog Msg)
dialog model =
    MaybeUtil.lazyFirst
        [ rotationDialog model
        , inactivityDialog model
        , welcomeBriefingDialog model
        , chatDialog model
        , inspectionHelpDialog model
        , gameMenuDialog model
        , orderGuideDialog model
        , introductionDialog model
        , lossDialog model
        , planningDialog model
        ]


rotationDialog : Model -> () -> Maybe (Dialog Msg)
rotationDialog model _ =
    let
        isPortrait : Bool
        isPortrait =
            model.shared.screenSize.height
                > model.shared.screenSize.width
    in
    if isMobileView model && isPortrait then
        Just (MobileBattlefield.portraitDialog RotationNoticeCanceled)

    else
        Nothing


inactivityDialogHtmlId : String
inactivityDialogHtmlId =
    "game-inactivity-warning"


inactivityDialog : Model -> () -> Maybe (Dialog Msg)
inactivityDialog model _ =
    let
        warning : Int -> Dialog Msg
        warning seconds =
            let
                failure : List (Html Msg)
                failure =
                    case Inactivity.error model.inactivity of
                        Just message ->
                            [ H.p
                                []
                                [ H.text ("couldn’t confirm activity: " ++ message)
                                ]
                            ]

                        Nothing ->
                            []

                button : Html Msg
                button =
                    if Inactivity.pending model.inactivity then
                        Button.disabled "confirming…"
                            |> Button.toHtml

                    else
                        Button.primary "i’m still here" StillHereClicked
                            |> Button.toHtml

                content : List (Html Msg)
                content =
                    [ H.p
                        []
                        [ H.text "are you still playing?"
                        ]
                    , H.p
                        [ A.attribute "role" "timer" ]
                        [ H.text ("you will lose due to inactivity in " ++ String.fromInt seconds ++ "s")
                        ]
                    , button
                    ]

                body : List (Html Msg)
                body =
                    content ++ failure
            in
            Dialog.make inactivityDialogHtmlId "inactivity warning" StillHereClicked body
    in
    if (model.currentTurn.outcome == Nothing) && inactivityTimerNeeded model then
        Inactivity.countdownSeconds model.shared.now model.inactivity |> Maybe.map warning

    else
        Nothing


welcomeBriefingDialog : Model -> () -> Maybe (Dialog Msg)
welcomeBriefingDialog model _ =
    if model.welcomeBriefingPending then
        Just (WelcomeBriefing.dialog { onClose = WelcomeBriefingDismissed })

    else
        Nothing


inspectionHelpDialog : Model -> () -> Maybe (Dialog Msg)
inspectionHelpDialog model _ =
    Maybe.map
        (InspectionHelp.dialog
            { mobile = isMobileView model
            , stats = model.unitStats
            , onClose = DialogDismissed
            }
        )
        model.inspectionHelp


gameMenuDialog : Model -> () -> Maybe (Dialog Msg)
gameMenuDialog model _ =
    case model.menu of
        MainMenu ->
            GameMenu.dialog
                { resigning = model.resigning
                , mobile = isMobileView model
                }
                |> Dialog.map GameMenuMsg
                |> Just

        ConfirmingResignation destination ->
            Just
                (GameMenu.resignationDialog { goingHome = destination == GoHome }
                    |> Dialog.map GameMenuMsg
                )

        FeedbackMenu ->
            FeedbackView.dialog
                { mobile = isMobileView model }
                model.feedback
                |> Dialog.map FeedbackMsg
                |> Just

        AboutMenu ->
            Just (About.dialog { onClose = GameMenuMsg GameMenu.CloseClicked })

        SettingsMenu tab ->
            Just
                (Settings.dialog
                    { tab = tab
                    , mobile = isMobileView model
                    , skipIntroduction = model.skipTurnIntroduction
                    , skipLosses = model.skipUnitLossDialogs
                    , skipOrdersWarning = model.skipUnplannedUnitsWarning
                    , mute = model.shared.audioMute
                    , volumes = model.shared.audioVolumes
                    }
                    |> Dialog.map SettingsMsg
                )

        MobileOrdersHelp ->
            Just (OrderGuide.dialog (GameMenuMsg GameMenu.CloseClicked))

        MenuClosed ->
            Nothing


orderGuideDialog : Model -> () -> Maybe (Dialog Msg)
orderGuideDialog model _ =
    if orderGuideOpen model then
        Just
            (OrderGuide.dialog DialogDismissed
                |> Dialog.onCancel EscapePressed
            )

    else
        Nothing


introductionDialog : Model -> () -> Maybe (Dialog Msg)
introductionDialog model _ =
    if showTurnIntroduction model then
        turnAnnouncement model
            |> Dialog.map TurnIntroductionMsg
            |> Just

    else
        Nothing


turnAnnouncement : Model -> Dialog TurnIntroduction.Msg
turnAnnouncement model =
    let
        victory : String -> PlayerNumber -> Dialog TurnIntroduction.Msg
        victory caption winner =
            let
                winnerName : String
                winnerName =
                    model.players
                        |> ListUtil.find (\player -> player.playerNumber == winner)
                        |> Maybe.map .name
                        |> Maybe.withDefault (PlayerNumber.label winner)
            in
            TurnIntroduction.conclusion
                { headline = winnerName ++ " wins"
                , caption = caption
                , previousTurn = model.currentTurn.resolution
                }
    in
    case model.currentTurn.outcome of
        Just (GameOutcome.Victory winner) ->
            victory "the opposing army has no surviving combat units" winner

        Just (GameOutcome.Resignation winner) ->
            victory "the game ended by surrender" winner

        Just (GameOutcome.Inactivity (Just winner)) ->
            let
                caption : String
                caption =
                    if List.member winner (ownPlayerNumbers model) then
                        "victory due to opponent inactivity"

                    else
                        "you lost due to inactivity"
            in
            victory caption winner

        Just (GameOutcome.Inactivity Nothing) ->
            TurnIntroduction.conclusion
                { headline = "draw"
                , caption = "both players were inactive"
                , previousTurn = model.currentTurn.resolution
                }

        Just GameOutcome.Draw ->
            TurnIntroduction.conclusion
                { headline = "draw"
                , caption = "neither army has surviving combat units"
                , previousTurn = model.currentTurn.resolution
                }

        Nothing ->
            TurnIntroduction.dialog
                { turnNumber = model.currentTurn.number
                , skipDialogs = model.skipTurnIntroduction
                , previousTurn = model.currentTurn.resolution
                , canReplay = CurrentTurn.canReplay model.currentTurn
                }


lossDialog : Model -> () -> Maybe (Dialog Msg)
lossDialog model _ =
    PlaybackPresentation.lossDialog
        { skipDialogs = model.skipUnitLossDialogs
        , players = model.players
        , ownPlayers = ownPlayerNumbers model
        }
        (playback model)
        |> Maybe.map
            (\notice ->
                notice
                    |> Dialog.map UnitDeathMsg
                    |> Dialog.onOpened (LossDialogOpened (Dialog.htmlId notice))
            )


planningDialog : Model -> () -> Maybe (Dialog Msg)
planningDialog model _ =
    case model.currentTurn.phase of
        TurnLifecycle.Planning (OrderPlanning.ConfirmingSubmission _) ->
            Just (submissionWarning model)

        TurnLifecycle.Planning (OrderPlanning.ChoosingPassengers choice) ->
            Just (unloadChecklist model choice)

        TurnLifecycle.Planning (OrderPlanning.ChoosingCrates id source _) ->
            Just (depotLoadingDialog model id source)

        TurnLifecycle.Planning (OrderPlanning.ChoosingGroundFreight _ freight _) ->
            Just (groundPickupDialog freight)

        _ ->
            Nothing


submissionWarning : Model -> Dialog Msg
submissionWarning model =
    let
        missingUnits : List Unit
        missingUnits =
            unitsWithoutOrders model

        missingCount : Int
        missingCount =
            List.length missingUnits

        mobile : Bool
        mobile =
            isMobileView model

        mobileSizing : S.Style
        mobileSizing =
            if mobile then
                S.batch
                    [ S.flex1
                    , S.minH0
                    ]

            else
                S.none

        listSizing : S.Style
        listSizing =
            if mobile then
                mobileSizing

            else
                S.maxH35Viewport

        unitRow : Unit -> Html Msg
        unitRow unit =
            H.li
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.g2
                    ]
                ]
                [ unitThumbnail SubmissionPortrait unit
                , H.text (Unit.name unit)
                ]

        warning : String
        warning =
            if missingCount == 1 then
                "1 unit has no orders. it will hold position if you submit this turn."

            else
                String.fromInt missingCount
                    ++ " units have no orders. they will hold position if you submit this turn."
    in
    Dialog.make partialOrdersDialogHtmlId
        "units without orders"
        SubmissionCancelled
        [ H.form
            [ A.attribute "method" "dialog"
            , A.css
                [ S.col
                , S.g3
                , mobileSizing
                ]
            ]
            [ H.p
                [ A.css [ S.shrink0 ] ]
                [ H.text warning ]
            , H.ul
                [ A.tabindex 0
                , Aria.role Aria.List
                , Aria.label "units that will hold position"
                , A.css
                    [ S.listNone
                    , S.m0
                    , S.p2
                    , S.bgNightwood3
                    , S.indentStrong
                    , S.textGray5
                    , S.overflowAuto
                    , listSizing
                    ]
                ]
                (List.map unitRow missingUnits)
            , H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.itemsCenter
                    , S.g3
                    , S.shrink0
                    ]
                ]
                [ Button.secondary "keep planning" SubmissionCancelled
                    |> Button.toHtml
                , Button.primary "submit anyway" SubmissionConfirmed
                    |> Button.toHtml
                , Checkbox.new
                    { label = "skip this dialog"
                    , checked = model.skipUnplannedUnitsWarning
                    , onCheck = SkipUnplannedUnitsWarningChanged
                    }
                    |> Checkbox.toHtml
                        [ H.text "skip this dialog" ]
                ]
            ]
        ]


surrenderState : Model -> TurnControls.SurrenderState
surrenderState model =
    if model.resigning then
        TurnControls.SurrenderPending

    else if canSurrender model then
        TurnControls.SurrenderAvailable

    else
        TurnControls.SurrenderUnavailable


turnSubmitLabel : Model -> String
turnSubmitLabel model =
    if model.currentTurn.outcome /= Nothing then
        "game over"

    else
        TurnLifecycle.toLabel model.currentTurn.phase


turnPanel : Model -> Html Msg
turnPanel model =
    let
        zoomPercent : Int
        zoomPercent =
            round ((BattlefieldNavigation.camera model.navigation).zoom * 100)
    in
    TurnControls.panel
        [ Lazy.lazy2 turnSubmit (turnActivity model) (turnSubmitLabel model)
        , Lazy.lazy viewControls zoomPercent
        , TurnControls.surrender (surrenderState model)
            |> H.map TurnControlsMsg
        ]


displayedTurnNumber : Model -> Int
displayedTurnNumber model =
    if
        (model.currentTurn.outcome /= Nothing)
            && not (GameOutcome.interruptsPlayback model.currentTurn.outcome)
    then
        model.currentTurn.number - 1

    else
        model.currentTurn.number


turnSubmit : TurnControls.Activity -> String -> Html Msg
turnSubmit activity submitLabel =
    TurnControls.submit activity submitLabel
        |> H.map TurnControlsMsg


requestErrorCard : Model -> Maybe (Html Msg)
requestErrorCard model =
    let
        details : Maybe RequestErrorDetails
        details =
            case model.currentTurn.error of
                Just (CurrentTurn.SubmissionError message) ->
                    Just
                        { title = "couldn’t submit turn"
                        , message = message
                        , guidance = "your orders are still here."
                        , retryEnabled = not (hasDialog model || planningLocked model)
                        }

                Just (CurrentTurn.PollError message) ->
                    Just
                        { title = "couldn’t update game"
                        , message = message
                        , guidance = "retrying automatically…"
                        , retryEnabled = not model.currentTurn.refreshing && (model.currentTurn.outcome == Nothing)
                        }

                Just (CurrentTurn.ResignationError message) ->
                    Just
                        { title = "couldn’t surrender"
                        , message = message
                        , guidance = "your surrender has not been confirmed."
                        , retryEnabled = canSurrender model
                        }

                _ ->
                    Nothing

        card : RequestErrorDetails -> Html Msg
        card failure =
            RequestError.toHtml
                { title = failure.title
                , message = failure.message
                , guidance = failure.guidance
                , retryEnabled = failure.retryEnabled
                , onRetry = RequestRetryClicked
                , onDismiss = RequestErrorDismissed
                }
    in
    case Maybe.map card details of
        Just notification ->
            Just notification

        Nothing ->
            if Chat.isOpen model.chat then
                Nothing

            else
                ChatView.notification model.chat |> Maybe.map (H.map ChatMsg)



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


keyCommands : Model -> KeyCmd Msg
keyCommands model =
    let
        orderShortcuts : KeyCmd Msg
        orderShortcuts =
            case orderMenuUnit model of
                Just unit ->
                    OrderMenu.keyCommands model.map model.depots unit
                        |> KeyCmd.map OrderMenuMsg

                Nothing ->
                    KeyCmd.none

        navigation : List (KeyCmd Msg)
        navigation =
            if hasDialog model then
                []

            else
                case currentSelection model of
                    Just (UnitSelection { interaction }) ->
                        case interaction of
                            ChoosingDirection _ ->
                                [ KeyCmd.leftGamerKeys (DirectionKeyPressed DirectionEnum.West)
                                , KeyCmd.rightGamerKeys (DirectionKeyPressed DirectionEnum.East)
                                , KeyCmd.upGamerKeys (DirectionKeyPressed DirectionEnum.North)
                                , KeyCmd.downGamerKeys (DirectionKeyPressed DirectionEnum.South)
                                ]

                            ChoosingMove _ ->
                                [ KeyCmd.leftGamerKeys (PathDirectionKeyPressed DirectionEnum.West)
                                , KeyCmd.rightGamerKeys (PathDirectionKeyPressed DirectionEnum.East)
                                , KeyCmd.upGamerKeys (PathDirectionKeyPressed DirectionEnum.North)
                                , KeyCmd.downGamerKeys (PathDirectionKeyPressed DirectionEnum.South)
                                , KeyCmd.enter PathEnterPressed
                                ]

                            ChoosingIndirectFire _ ->
                                []

                            OrderMenu _ ->
                                [ KeyCmd.upGamerKeys PreviousOrderPressed
                                , KeyCmd.downGamerKeys NextOrderPressed
                                ]

                    Just (Inspecting _) ->
                        panNavigation ()

                    Nothing ->
                        panNavigation ()

        camera : KeyCmd Msg
        camera =
            [ KeyCmd.plus ZoomInKeyPressed
            , KeyCmd.minus ZoomOutKeyPressed
            ]
                |> KeyCmd.batch

        submission : KeyCmd Msg
        submission =
            if canSubmitWithKeyboard model then
                KeyCmd.enter SubmitKeyPressed |> KeyCmd.cmd

            else
                KeyCmd.none

        unitSelection : KeyCmd Msg
        unitSelection =
            if hasDialog model || planningLocked model then
                KeyCmd.none

            else
                KeyCmd.period NextUnorderedUnitKeyPressed
    in
    if hasDialog model || combatEncounter model /= Nothing then
        KeyCmd.none

    else
        KeyCmd.batch
            [ KeyCmd.escape EscapePressed
            , orderShortcuts
            , camera
            , unitSelection
            , submission
            , KeyCmd.batch navigation
            ]


panNavigation : () -> List (KeyCmd Msg)
panNavigation _ =
    [ KeyCmd.leftGamerKeys PanLeftKeyPressed
    , KeyCmd.rightGamerKeys PanRightKeyPressed
    , KeyCmd.upGamerKeys PanUpKeyPressed
    , KeyCmd.downGamerKeys PanDownKeyPressed
    ]


chatShortcut : Model -> Sub Msg
chatShortcut model =
    if canOpenDialog model && not model.shared.devPanelOpen then
        Browser.Events.onKeyDown (Decode.map ChatMsg ChatView.openKeyDecoder)

    else
        Sub.none


{-| Only a press begun outside a dialog may advance combat on release.
-}
combatEnterShortcut : Model -> Sub Msg
combatEnterShortcut model =
    if not (hasDialog model) && (combatEncounter model /= Nothing) then
        let
            firstPress : Bool -> Decode.Decoder Msg
            firstPress repeated =
                if repeated then
                    Decode.fail "held enter key"

                else
                    Decode.at [ "target", "tagName" ] Decode.string
                        |> Decode.andThen outsideControl

            outsideControl : String -> Decode.Decoder Msg
            outsideControl tag =
                if List.member tag [ "INPUT", "TEXTAREA", "SELECT", "BUTTON" ] then
                    Decode.fail "control handles its own enter key"

                else
                    HtmlEvent.enter CombatEnterPressed
        in
        Browser.Events.onKeyDown
            (Decode.field "repeat" Decode.bool
                |> Decode.andThen firstPress
            )

    else
        Sub.none


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        reportTicks : Sub Msg
        reportTicks =
            if List.isEmpty model.planningReports.pending then
                Sub.none

            else
                Time.every 1000 PlanningErrorReportTick
    in
    Sub.batch
        [ chatShortcut model
        , combatEnterShortcut model
        , reportTicks
        , Time.every 1000 ChatPollElapsed
        , Time.every 400 AnimationTimerElapsed
        , CurrentTurn.subscriptions model.currentTurn
            |> Sub.map CurrentTurnMsg
        , BattlefieldNavigation.subscriptions model.navigation
            |> Sub.map BattlefieldNavigationMsg
        ]
