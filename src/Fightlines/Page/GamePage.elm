module Fightlines.Page.GamePage exposing
    ( Flags
    , Model
    , Msg
    , dialog
    , init
    , keyCommands
    , load
    , movingVehicles
    , setDepots
    , setShared
    , setUnits
    , subscriptions
    , superUpdate
    , view
    )

import Api.Enum.Direction as DirectionEnum exposing (Direction)
import Api.Enum.PlayerNumber as PlayerNumberEnum exposing (PlayerNumber)
import Api.Enum.ResourceKind as ResourceKind
import Api.Enum.TurnEventKind as TurnEventKind
import Api.Enum.UnitKind as UnitKind
import Api.Mutation
import Api.Object
import Api.Object.GameSnapshot as SnapshotApi
import Api.Object.MovementRule as MovementRuleApi
import Api.Object.Scenario as Scenario
import Api.Object.TerrainMovementCost as MovementCostApi
import Api.Query
import Api.Scalar
    exposing
        ( MapId
        )
import ApiRequest
import Audio
import Browser.Dom
import Browser.Events
import Effect as E
    exposing
        ( Eff
        )
import Error exposing (Error)
import Fightlines.Route as Route
import Fightlines.Shared as Shared
import Fightlines.View.CommandGuide as CommandGuide
import Fightlines.View.CommandMenu as CommandMenu
import Fightlines.View.GameMenu as GameMenu
import Fightlines.View.TurnIntroduction as TurnIntroduction
import Fightlines.View.UnloadPassenger as UnloadPassenger
import Game.AnimationFrame as AnimationFrame
import Game.BackdropCalibration as BackdropCalibration
import Game.BattlefieldNavigation as BattlefieldNavigation
import Game.BattlefieldSnapshot as BattlefieldSnapshot exposing (Player)
import Game.Camera as Camera
import Game.CombatRules as CombatRules
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
import Game.Selection
    exposing
        ( Selection(..)
        , UnitInteraction(..)
        )
import Game.Supply as Supply
import Game.Terrain as Terrain
import Game.Turn as Turn
import Game.TurnLifecycle as TurnLifecycle exposing (Phase)
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.UnitCommand as UnitCommand
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnloadCargo as UnloadCargo exposing (UnloadCargo)
import Game.UnloadPlanning
    exposing
        ( UnloadChoice
        , UnloadPlanning
        )
import Game.UnloadingTruck as UnloadingTruck
import Game.View.Battlefield as Battlefield
    exposing
        ( UnloadRoute
        )
import Game.View.BattlefieldInspection as BattlefieldInspection
import Game.View.BattlefieldWorkspace as BattlefieldWorkspace
import Game.View.Cargo as Cargo
import Game.View.CombatTheater as CombatTheater
import Game.View.MovementRoute as MovementRoute
import Game.View.RotationChoices as RotationChoices
import Game.View.TurnControls as TurnControls
import Game.View.UnitDeath as UnitDeath
import Game.View.UnitStatus as UnitStatus
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Events as HtmlEvents
import Html.Styled.Lazy as Lazy
import InvariantCheck as IC exposing (InvariantCheck)
import Json.Decode as Decode
import Json.Encode as Encode
import KeyCmd exposing (KeyCmd)
import LobbyId
    exposing
        ( LobbyId
        )
import Ports.Js.To as ToJs
import Preference
import Style as S
import Time
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import Util.Maybe as MaybeUtil
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { currentTurn : CurrentTurn.Model
    , shared : Shared.Model
    , backdropCalibrations : List BackdropCalibration.Entry
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
    , battlefieldViewport : Maybe Camera.Viewport
    , frame : AnimationFrame.Frame
    , resigning : Bool
    , menuOpen : Bool
    }


type alias Snapshot =
    { battlefield : BattlefieldSnapshot.Snapshot
    , supplyRules : Supply.Rules
    , movementRules : List Movement.Rule
    , turn : Turn.Snapshot
    , playbackFrames : List TurnPlayback.Frame
    }


type ResignationDestination
    = RemainInGame
    | GoHome


type alias PollStatus =
    { number : Int
    , outcome : Maybe GameOutcome
    , submitted : Bool
    , opponentSubmitted : Bool
    }


type alias RotationSelection =
    { unitId : UnitId
    , position : Coordinate
    , direction : Direction
    }


type Msg
    = BattlefieldSizeReceived (Result Browser.Dom.Error Browser.Dom.Element)
    | InspectorSizeReceived Browser.Dom.Element (Result Browser.Dom.Error Browser.Dom.Element)
    | CameraReturnFinished
    | WindowResized
    | BattlefieldMsg Battlefield.Msg
    | BattlefieldNavigationMsg BattlefieldNavigation.Msg
    | CommandMenuMsg CommandMenu.Msg
    | GameMenuMsg GameMenu.Msg
    | PreviousCommandPressed
    | NextCommandPressed
    | CommandFocusCompleted (Result Browser.Dom.Error ())
    | PanLeftKeyPressed
    | PanRightKeyPressed
    | PanUpKeyPressed
    | PanDownKeyPressed
    | ZoomInKeyPressed
    | ZoomOutKeyPressed
    | AnimationTimerElapsed Time.Posix
    | TurnIntroductionMsg TurnIntroduction.Msg
    | UnitDeathMsg UnitDeath.Msg
    | CombatTheaterMsg CombatTheater.Msg
    | DirectionKeyPressed Direction
    | PathDirectionKeyPressed Direction
    | PathEnterPressed
    | NextUnorderedUnitKeyPressed
    | ClearMoveClicked
    | BackToCommandsClicked
    | CargoUnitClicked UnitId
    | LoadCratesClicked UnitId Int
    | GroundFreightPickupClicked
    | UnloadCrateToggled Int Bool
    | UnloadUnitToggled UnitId Bool
    | UnloadChoicesConfirmed
    | UnloadSkipped
    | InspectClicked
    | InspectorCloseClicked
    | EscapePressed
    | DialogDismissed
    | SubmissionCancelled
    | SubmissionConfirmed
    | SubmitKeyPressed
    | SubmissionEnterPressed
    | SkipUnplannedUnitsWarningChanged Bool
    | TurnControlsMsg TurnControls.Msg
    | SubmitResponseReceived Int (ApiRequest.Response Snapshot)
    | CurrentTurnMsg CurrentTurn.Msg
    | ResignResponseReceived ResignationDestination (ApiRequest.Response Snapshot)
    | PollStatusResponseReceived (ApiRequest.Response PollStatus)
    | PollResponseReceived (ApiRequest.Response Snapshot)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { snapshot : Snapshot
    , backdropCalibrations : List BackdropCalibration.Entry
    }


init : Shared.Model -> Flags -> ( Model, Eff Msg )
init shared flags =
    let
        ( automaticallyCloseCombatTheater, maybeError ) =
            PlaybackPresentation.loadPreference PlaybackPresentation.AutomaticallyCloseCombat shared.localStorage

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
            PlaybackPresentation.loadPreference PlaybackPresentation.SkipLossDialogs shared.localStorage

        model : Model
        model =
            { currentTurn = CurrentTurn.init (turnObservation flags.snapshot)
            , shared =
                shared
                    |> Shared.addError maybeError
                    |> Shared.addError lossPreferenceError
                    |> Shared.addError introductionPreferenceError
                    |> Shared.addError submissionPreferenceError
            , skipTurnIntroduction = skipTurnIntroduction
            , backdropCalibrations = flags.backdropCalibrations
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
            , navigation = BattlefieldNavigation.init
            , battlefieldViewport = Nothing
            , frame = AnimationFrame.first
            , resigning = False
            , menuOpen = False
            }

        eff : Eff Msg
        eff =
            if showTurnIntroduction model then
                E.toJs
                    (ToJs.OpenDialog
                        { htmlId = TurnIntroduction.dialogHtmlId }
                    )

            else
                E.none
    in
    ( model
    , E.batch
        [ eff
        , E.measure Battlefield.htmlId BattlefieldSizeReceived
        ]
    )


load : LobbyId -> Graphql.Http.Request Flags
load id =
    SS.succeed Flags
        |> SS.with (Api.Query.game { id = LobbyId.toString id } snapshotSelection)
        |> SS.with BackdropCalibration.catalogSelection
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setCurrentTurn : CurrentTurn.Model -> Model -> Model
setCurrentTurn currentTurn model =
    { model | currentTurn = currentTurn }


setMenuOpen : Bool -> Model -> Model
setMenuOpen menuOpen model =
    { model | menuOpen = menuOpen }


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


setVisibleTiles : List Coordinate -> Model -> Model
setVisibleTiles visibleTiles model =
    { model | visibleTiles = visibleTiles }


setNavigation : BattlefieldNavigation.Model -> Model -> Model
setNavigation navigation model =
    { model | navigation = navigation }


setResigning : Bool -> Model -> Model
setResigning resigning model =
    { model | resigning = resigning }


setBattlefieldViewport : Maybe Camera.Viewport -> Model -> Model
setBattlefieldViewport battlefieldViewport model =
    { model | battlefieldViewport = battlefieldViewport }


turnIntroductionPreferenceKey : String
turnIntroductionPreferenceKey =
    "skipTurnIntroduction"


unplannedUnitsWarningPreferenceKey : String
unplannedUnitsWarningPreferenceKey =
    "skipUnplannedUnitsWarning"


rememberPlaybackPreference : PlaybackPresentation.Preference -> Bool -> Eff msg
rememberPlaybackPreference preference enabled =
    PlaybackPresentation.encodePreference preference enabled
        |> ToJs.SetLocalStorage
        |> E.toJs


showTurnIntroduction : Model -> Bool
showTurnIntroduction model =
    (model.currentTurn.outcome /= Nothing || not model.skipTurnIntroduction)
        && CurrentTurn.introductionPending model.currentTurn


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
        depot : Maybe Depot
        depot =
            plannedDepot model unit.id

        stockLimit : Int
        stockLimit =
            case
                depot
                    |> Maybe.andThen .stock
            of
                Just stock ->
                    (stock.current + model.supplyRules.crateCapacity - 1)
                        // model.supplyRules.crateCapacity

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


visibleSupplyCrates : Model -> List Supply.GroundCrate
visibleSupplyCrates model =
    List.filter (\crate -> List.member crate.position model.visibleTiles) model.supplyCrates


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
        checked : InvariantCheck Error CurrentTurn.Model
        checked =
            CurrentTurn.mapPlanning transition model.currentTurn
                |> IC.mapError Error.OrderPlanningInvariantViolated

        applyChecked : Maybe Error -> CurrentTurn.Model -> Model
        applyChecked violation currentTurn =
            model
                |> setCurrentTurn currentTurn
                |> setShared (Shared.addError violation model.shared)
    in
    IC.resolve applyChecked checked


unloadChoice : Phase -> Maybe UnloadChoice
unloadChoice phase =
    TurnLifecycle.planning phase
        |> Maybe.andThen OrderPlanning.unloadChoice


unloadPlanning : Phase -> Maybe UnloadPlanning
unloadPlanning phase =
    TurnLifecycle.planning phase |> Maybe.andThen OrderPlanning.unloadPlanning


isChoosingUnload : Model -> Bool
isChoosingUnload model =
    unloadPlanning model.currentTurn.phase /= Nothing


dismissDialog : Model -> Model
dismissDialog model =
    if model.menuOpen then
        model
            |> setMenuOpen False

    else if showTurnIntroduction model then
        model
            |> setCurrentTurn (CurrentTurn.acknowledgeIntroduction model.currentTurn)

    else
        model
            |> mapPlanning
                (OrderPlanning.dismissDialog
                    >> OrderPlanning.promptDismountedCommands model.map model.units
                )


partialOrdersDialogHtmlId : String
partialOrdersDialogHtmlId =
    "submit-turn-warning"


commandGuideOpen : Model -> Bool
commandGuideOpen model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.commandGuideOpen
        |> Maybe.withDefault False


hasDialog : Model -> Bool
hasDialog model =
    dialog model /= Nothing


canOpenMenu : Model -> Bool
canOpenMenu model =
    not (hasDialog model) && (playback model == Nothing)


plannedOrders : Model -> List PlannedOrder
plannedOrders model =
    TurnLifecycle.orders model.currentTurn.phase


playback : Model -> Maybe TurnPlayback.Playback
playback model =
    TurnLifecycle.playback model.currentTurn.phase


movingVehicles : Model -> List Audio.MovingVehicle
movingVehicles model =
    PlaybackPresentation.movingVehicles
        { playback = playback model
        , paused = False
        , camera = playbackCamera model
        , skipLossDialogs = model.skipUnitLossDialogs
        }


unitLoss : Model -> Maybe TurnPlayback.Loss
unitLoss model =
    PlaybackPresentation.loss model.skipUnitLossDialogs (playback model)


ownerName : Model -> Unit -> Maybe String
ownerName model =
    PlaybackPresentation.ownerName model.players


{-| Record an error only if the active loss details cannot be resolved. Called
when a dialog becomes active so repeated ticks do not record it again.
-}
recordLossDetailsErrorIfPresent : Model -> Model
recordLossDetailsErrorIfPresent model =
    model
        |> setShared
            (Shared.addError
                (PlaybackPresentation.lossError model.players (unitLoss model))
                model.shared
            )


activeDialogHtmlId : Model -> Maybe String
activeDialogHtmlId model =
    if model.menuOpen then
        Just GameMenu.dialogHtmlId

    else if commandGuideOpen model then
        Just CommandGuide.dialogHtmlId

    else if showTurnIntroduction model then
        Just TurnIntroduction.dialogHtmlId

    else
        playbackDialogHtmlId model


playbackDialogHtmlId : Model -> Maybe String
playbackDialogHtmlId model =
    case unitLoss model of
        Just loss ->
            Just (UnitDeath.dialogHtmlId loss)

        Nothing ->
            cargoDialogHtmlId model.currentTurn.phase


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
    OrderPlanning.missingOrders model.map model.units (ownPlayerNumbers model) (plannedOrders model)


readyToSubmit : Model -> Bool
readyToSubmit model =
    not (planningLocked model) && List.isEmpty (unitsWithoutOrders model)


submitTurn : LobbyId -> Model -> ( Model, Eff Msg )
submitTurn lobbyId model =
    case CurrentTurn.startSubmission model.currentTurn of
        Just currentTurn ->
            (model
                |> setCurrentTurn currentTurn
            )
                |> E.withOut
                |> E.and
                    (E.request
                        (SubmitResponseReceived model.currentTurn.number)
                        (submitRequest lobbyId model)
                    )

        Nothing ->
            ( model, E.none )


unloadDialogHtmlId : String
unloadDialogHtmlId =
    "unload-passengers"


selectedUnit : Model -> Maybe Unit
selectedUnit model =
    OrderPlanning.selectedUnitFromSelection
        model.units
        (currentSelection model)
        |> Maybe.map
            (PlannedTransport.planningUnit
                model.map
                (plannedOrders model)
            )


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


applyCommand : UnitCommand.Command -> Model -> Model
applyCommand command model =
    model
        |> mapCheckedPlanning
            (OrderPlanning.applyCommand
                model.map
                model.units
                (ownPlayerNumbers model)
                model.movementRules
                (visibleSupplyCrates model)
                model.depots
                command
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


focusedCommand : Model -> Maybe UnitCommand.MenuOption
focusedCommand model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.andThen OrderPlanning.focusedCommand


commandMenuUnit : Model -> Maybe Unit
commandMenuUnit model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.andThen
            (OrderPlanning.commandMenuUnit model.map model.units)


submitRequest : LobbyId -> Model -> Graphql.Http.Request Snapshot
submitRequest lobbyId model =
    let
        orders : List PlannedOrder
        orders =
            OrderPlanning.submissionOrders
                model.map
                model.units
                (ownPlayerNumbers model)
                (plannedOrders model)
    in
    Api.Mutation.submitTurn
        { id = LobbyId.toString lobbyId
        , turnNumber = model.currentTurn.number
        , orders = List.map PlannedOrder.toInput orders
        }
        snapshotSelection
        |> ApiRequest.mutationRequest


turnObservation : Snapshot -> CurrentTurn.Observation
turnObservation snapshot =
    { turn = snapshot.turn
    , playbackFrames = snapshot.playbackFrames
    }


applyTurnSnapshot : Snapshot -> CurrentTurn.Model -> Model -> ( Model, Eff Msg )
applyTurnSnapshot snapshot currentTurn model =
    let
        next : Model
        next =
            reconcileTurnSnapshot snapshot currentTurn model
    in
    case ( playback model, playback next ) of
        ( Nothing, Just _ ) ->
            startPlayback next

        ( Just _, Nothing ) ->
            finishPlayback model next

        _ ->
            next
                |> closeMenuForTurnIntroduction
                |> E.withOut


reconcileTurnSnapshot : Snapshot -> CurrentTurn.Model -> Model -> Model
reconcileTurnSnapshot snapshot currentTurn model =
    let
        next : Model
        next =
            model
                |> setCurrentTurn currentTurn
    in
    if model.currentTurn.outcome /= Nothing then
        next

    else if GameOutcome.isResignation currentTurn.outcome then
        next
            |> setMap snapshot.battlefield.map
            |> setDepots snapshot.battlefield.depots
            |> setSupplyCrates snapshot.battlefield.supplyCrates
            |> setUnits snapshot.battlefield.units
            |> setVisibleTiles snapshot.battlefield.visibleTiles
            |> setMenuOpen False
            |> setNavigation (BattlefieldNavigation.finishReturn model.navigation)

    else if currentTurn.number > model.currentTurn.number then
        let
            frame : TurnPlayback.Frame
            frame =
                TurnPlayback.initial snapshot.playbackFrames
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
        in
        { next | supplyRules = snapshot.supplyRules }
            |> setMap snapshot.battlefield.map
            |> setDepots frame.depots
            |> setSupplyCrates frame.supplyCrates
            |> setUnits frame.units
            |> setVisibleTiles frame.visibleTiles

    else
        next


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


focusCommand : UnitCommand.MenuOption -> Model -> Model
focusCommand command model =
    model
        |> mapPlanning
            (OrderPlanning.focusCommand model.map model.units command)


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

                CommandMenu _ ->
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
    let
        selection : SelectionSet PollStatus Api.Object.GameSnapshot
        selection =
            SS.succeed PollStatus
                |> SS.with SnapshotApi.turnNumber
                |> SS.with (SnapshotApi.outcome GameOutcome.selection)
                |> SS.with SnapshotApi.submitted
                |> SS.with SnapshotApi.opponentSubmitted
    in
    Api.Query.game { id = LobbyId.toString id } selection
        |> ApiRequest.queryRequest


snapshotSelection : SelectionSet Snapshot Api.Object.GameSnapshot
snapshotSelection =
    let
        terrainCostSelection : SelectionSet Movement.TerrainCost Api.Object.TerrainMovementCost
        terrainCostSelection =
            SS.succeed Movement.TerrainCost
                |> SS.with (SS.map Terrain.fromApi MovementCostApi.terrain)
                |> SS.with MovementCostApi.cost

        movementRuleSelection : SelectionSet Movement.Rule Api.Object.MovementRule
        movementRuleSelection =
            SS.succeed Movement.Rule
                |> SS.with MovementRuleApi.kind
                |> SS.with MovementRuleApi.budget
                |> SS.with (MovementRuleApi.terrainCosts terrainCostSelection)
                |> SS.with MovementRuleApi.roadFuelPerTile
                |> SS.with MovementRuleApi.roadFuelPerCargoSlot
    in
    SS.succeed Snapshot
        |> SS.with BattlefieldSnapshot.selection
        |> SS.with (SnapshotApi.scenario (Scenario.supplyRules Supply.rulesSelection))
        |> SS.with (SnapshotApi.movementRules movementRuleSelection)
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
                    (visibleSupplyCrates model)
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
                    (visibleSupplyCrates model)
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
                (visibleSupplyCrates model)
                model.depots
            )


focusAdjacentCommand :
    (List UnitCommand.MenuOption -> List UnitCommand.MenuOption)
    -> Maybe UnitCommand.MenuOption
    -> Model
    -> Eff Msg
focusAdjacentCommand orderCommands current model =
    let
        afterCurrent : List UnitCommand.MenuOption -> List UnitCommand.MenuOption
        afterCurrent remaining =
            case remaining of
                [] ->
                    []

                command :: rest ->
                    if Just command == current then
                        rest

                    else
                        afterCurrent rest
    in
    case commandMenuUnit model of
        Just unit ->
            let
                commands : List UnitCommand.MenuOption
                commands =
                    UnitCommand.enabledOptions model.map model.depots unit
                        |> orderCommands

                adjacent : Maybe UnitCommand.MenuOption
                adjacent =
                    case afterCurrent commands |> List.head of
                        Just command ->
                            Just command

                        Nothing ->
                            List.head commands
            in
            case adjacent of
                Just command ->
                    E.focus
                        { htmlId = CommandMenu.optionHtmlId command }
                        CommandFocusCompleted

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


cargoDialogHtmlId : TurnLifecycle.Phase -> Maybe String
cargoDialogHtmlId phase =
    case phase of
        TurnLifecycle.Planning (OrderPlanning.ChoosingCrates _ _ _) ->
            Just loadCratesDialogHtmlId

        TurnLifecycle.Planning (OrderPlanning.ChoosingGroundFreight _ _ _) ->
            Just groundPickupDialogHtmlId

        TurnLifecycle.Planning (OrderPlanning.ChoosingPassengers _) ->
            Just unloadDialogHtmlId

        _ ->
            Nothing


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
            let
                next : Model
                next =
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
            in
            next

        Battlefield.ClickedUnit id click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        selectUnit id model
            in
            next

        Battlefield.PressedEnterOnUnit id ->
            let
                next : Model
                next =
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
            in
            next

        Battlefield.PressedSpaceOnUnit id ->
            model
                |> selectUnit id

        Battlefield.MouseOverUnit id ->
            previewUnit id model

        Battlefield.ClickedDepot position click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        selectTile position model
            in
            next

        Battlefield.PressedEnterOnDepot position ->
            model
                |> selectTile position

        Battlefield.PressedSpaceOnDepot position ->
            model
                |> selectTile position

        Battlefield.MouseOverDepot position ->
            let
                next : Model
                next =
                    if planningLocked model then
                        model

                    else
                        previewTile position model
            in
            next

        Battlefield.ClickedDepotStock position click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        inspectDepot position model
            in
            next

        Battlefield.PressedEnterOnDepotStock position ->
            inspectDepot position model

        Battlefield.PressedSpaceOnDepotStock position ->
            inspectDepot position model

        Battlefield.ClickedTile position click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        selectTile position model
            in
            next

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
            let
                next : Model
                next =
                    if planningLocked model then
                        model

                    else
                        previewTile position model
            in
            next

        Battlefield.MousePressed point ->
            model
                |> mapNavigation (BattlefieldNavigation.press point)

        Battlefield.WheelScrolled anchor delta ->
            model
                |> mapNavigation (BattlefieldNavigation.scroll anchor delta)

        Battlefield.HomePressed ->
            model
                |> mapNavigation BattlefieldNavigation.resetViewport


resignGame : LobbyId -> ResignationDestination -> Model -> ( Model, Eff Msg )
resignGame lobbyId destination model =
    let
        canResign : Bool
        canResign =
            model.menuOpen && not model.resigning && (model.currentTurn.outcome == Nothing)
    in
    if canResign then
        ( model
            |> setResigning True
        , Api.Mutation.resignGame { id = LobbyId.toString lobbyId } snapshotSelection
            |> ApiRequest.mutationRequest
            |> E.request (ResignResponseReceived destination)
        )

    else
        E.withOut model


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
                    PlaybackPresentation.frameCamera viewport model.map (BattlefieldNavigation.camera model.navigation) playing.animation playing.camera

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
    case model.currentTurn.phase of
        TurnLifecycle.Playing playing ->
            playing.camera

        _ ->
            Nothing


remeasureWorkspace : Model -> ( Model, Eff Msg )
remeasureWorkspace model =
    ( model
        |> setBattlefieldViewport Nothing
    , E.measure Battlefield.htmlId BattlefieldSizeReceived
    )


{-| Selection changes the inspector inset; turn controls and errors can change
the height available to the battlefield. Playback start requests its own fresh
measurement, so this check does not request a second one for that transition.
-}
withLayoutMeasurement : Model -> Model -> ( Model, Eff Msg )
withLayoutMeasurement previous next =
    let
        playbackStarted : Bool
        playbackStarted =
            (playback previous == Nothing) && (playback next /= Nothing)

        layoutChanged : Bool
        layoutChanged =
            ((currentSelection previous == Nothing) /= (currentSelection next == Nothing))
                || (turnActivity previous /= turnActivity next)
                || (previous.currentTurn.error /= next.currentTurn.error)
                || (previous.currentTurn.outcome /= next.currentTurn.outcome)
    in
    if layoutChanged && not playbackStarted then
        remeasureWorkspace next

    else
        E.withOut next


closeMenuForTurnIntroduction : Model -> Model
closeMenuForTurnIntroduction model =
    if showTurnIntroduction model then
        model
            |> setMenuOpen False

    else
        model


startPlayback : Model -> ( Model, Eff Msg )
startPlayback model =
    remeasureWorkspace
        (model
            |> setMenuOpen False
        )


finishPlayback : Model -> Model -> ( Model, Eff Msg )
finishPlayback previous next =
    let
        ( returned, cameraEffect ) =
            if playbackCamera previous /= Nothing then
                ( next
                    |> setNavigation (BattlefieldNavigation.startReturn next.navigation)
                , E.after PlaybackPresentation.cameraPanDurationMs CameraReturnFinished
                )

            else
                E.withOut next
    in
    returned
        |> closeMenuForTurnIntroduction
        |> E.with cameraEffect


presentPlaybackTransition : Model -> Model -> ( Model, Eff Msg )
presentPlaybackTransition previous next =
    case ( playback previous, playback next ) of
        ( Just _, Nothing ) ->
            finishPlayback previous next

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



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


{-| Check layout changes, add UI audio feedback, and synchronize native dialogs.
Gameplay transitions own their other effects in `update` and its helpers.
-}
superUpdate : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
superUpdate lobbyId msg model =
    let
        ( next, effect ) =
            model
                |> update lobbyId msg
                |> E.andThen (withLayoutMeasurement model)
                |> E.and (E.audio (playAudio msg model))
    in
    case activeDialogHtmlId next of
        Just htmlId ->
            if activeDialogHtmlId model /= Just htmlId then
                ( recordLossDetailsErrorIfPresent next
                , E.batch [ effect, E.toJs (ToJs.OpenDialog { htmlId = htmlId }) ]
                )

            else
                ( next, effect )

        Nothing ->
            ( next, effect )


update : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
update lobbyId msg model =
    case msg of
        GameMenuMsg menuMsg ->
            handleGameMenuMsg lobbyId menuMsg model

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
                                    Route.pushUrl Route.Home
                    in
                    (model
                        |> setResigning False
                    )
                        |> applyTurnSnapshot snapshot
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
                        |> setMenuOpen False
                        |> setCurrentTurn
                            (currentTurn
                                |> CurrentTurn.setError
                                    (Just (ApiRequest.errorMessage error))
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
                    ( model, E.measure BattlefieldWorkspace.inspectorHtmlId (InspectorSizeReceived battlefield) )

                Err error ->
                    (model
                        |> setShared (Shared.addError (Just (Error.BattlefieldMeasurementFailed error)) model.shared)
                    )
                        |> E.withOut

        InspectorSizeReceived battlefield result ->
            case result of
                Ok inspector ->
                    let
                        viewport : Camera.Viewport
                        viewport =
                            BattlefieldWorkspace.viewport
                                { battlefield = battlefield
                                , inspector = inspector
                                }
                    in
                    (model
                        |> setBattlefieldViewport (Just viewport)
                    )
                        |> updatePlaybackCamera
                        |> E.withOut

                Err error ->
                    (model
                        |> setShared (Shared.addError (Just (Error.BattlefieldMeasurementFailed error)) model.shared)
                    )
                        |> E.withOut

        WindowResized ->
            ( model, E.measure Battlefield.htmlId BattlefieldSizeReceived )

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
            if pathPreview model /= Nothing then
                let
                    next : Model -> Model
                    next =
                        case navigationMsg of
                            BattlefieldNavigation.MouseReleased _ ->
                                if BattlefieldNavigation.suppressesClick traced.navigation then
                                    confirmPath

                                else
                                    identity

                            _ ->
                                identity
                in
                traced
                    |> next
                    |> E.withOut

            else
                traced
                    |> E.withOut

        UnloadUnitToggled id checked ->
            model
                |> mapCheckedPlanning
                    (OrderPlanning.toggleAvailableUnloadCargo
                        model.map
                        model.units
                        (ownPlayerNumbers model)
                        model.movementRules
                        (visibleSupplyCrates model)
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
                        (visibleSupplyCrates model)
                        model.depots
                    )
                |> E.withOut

        UnloadSkipped ->
            model
                |> mapPlanning
                    (OrderPlanning.skipUnloading
                        model.map
                        model.units
                        (visibleSupplyCrates model)
                        model.depots
                    )
                |> E.withOut

        GroundFreightPickupClicked ->
            model
                |> mapCheckedPlanning
                    (OrderPlanning.confirmGroundPickup
                        >> IC.map (OrderPlanning.promptDismountedCommands model.map model.units)
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
                                >> IC.map (OrderPlanning.promptDismountedCommands model.map model.units)
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
                        (visibleSupplyCrates model)
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

        CommandMenuMsg commandMsg ->
            model
                |> handleCommandMsg commandMsg

        PreviousCommandPressed ->
            ( model, focusAdjacentCommand List.reverse (focusedCommand model) model )

        NextCommandPressed ->
            ( model, focusAdjacentCommand identity (focusedCommand model) model )

        CommandFocusCompleted result ->
            recordFocusResult result model |> E.withOut

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

        BackToCommandsClicked ->
            model
                |> mapCheckedPlanning
                    (OrderPlanning.restoreCommands
                        model.map
                        model.units
                        (ownPlayerNumbers model)
                    )
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

        EscapePressed ->
            if model.menuOpen || showTurnIntroduction model then
                model
                    |> dismissDialog
                    |> E.withOut

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

        DialogDismissed ->
            model
                |> dismissDialog
                |> E.withOut

        SubmissionCancelled ->
            case model.currentTurn.phase of
                TurnLifecycle.Planning (OrderPlanning.ConfirmingSubmission _) ->
                    dismissDialog model |> E.withOut

                _ ->
                    E.withOut model

        SubmitKeyPressed ->
            if canSubmitWithKeyboard model then
                requestSubmission lobbyId model

            else
                model |> E.withOut

        SubmissionConfirmed ->
            confirmSubmission lobbyId model

        SubmissionEnterPressed ->
            confirmSubmission lobbyId model

        SkipUnplannedUnitsWarningChanged skip ->
            ( { model | skipUnplannedUnitsWarning = skip }
            , E.toJs
                (ToJs.SetLocalStorage
                    { key = unplannedUnitsWarningPreferenceKey
                    , value = Encode.bool skip
                    }
                )
            )

        SubmitResponseReceived turnNumber result ->
            case result of
                Ok snapshot ->
                    model
                        |> applyTurnSnapshot
                            snapshot
                            (CurrentTurn.submissionSucceeded
                                turnNumber
                                (turnObservation snapshot)
                                model.currentTurn
                            )

                Err error ->
                    (model
                        |> setCurrentTurn (CurrentTurn.submissionFailed turnNumber (ApiRequest.errorMessage error) model.currentTurn)
                    )
                        |> E.withOut

        CurrentTurnMsg turnMsg ->
            handleCurrentTurnMsg lobbyId turnMsg model

        PollStatusResponseReceived result ->
            case result of
                Ok status ->
                    let
                        currentTurn : CurrentTurn.Model
                        currentTurn =
                            model.currentTurn

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
                        ( model, E.request PollResponseReceived (loadSnapshot lobbyId) )

                    else
                        (model
                            |> setCurrentTurn (CurrentTurn.pollSucceeded observation currentTurn)
                        )
                            |> E.withOut

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
                            snapshot
                            (CurrentTurn.pollSucceeded
                                (turnObservation snapshot)
                                model.currentTurn
                            )

                Err error ->
                    (model
                        |> setCurrentTurn (CurrentTurn.pollFailed (ApiRequest.errorMessage error) model.currentTurn)
                    )
                        |> E.withOut

        AnimationTimerElapsed _ ->
            if deathInFocus model || combatEncounter model /= Nothing then
                model |> E.withOut

            else
                { model | frame = AnimationFrame.next model.frame }
                    |> E.withOut

        TurnIntroductionMsg introMsg ->
            case introMsg of
                TurnIntroduction.BeginClicked ->
                    (model
                        |> setCurrentTurn (CurrentTurn.acknowledgeIntroduction model.currentTurn)
                    )
                        |> E.withOut

                TurnIntroduction.ReplayClicked ->
                    if showTurnIntroduction model then
                        case CurrentTurn.replay model.currentTurn of
                            Just replay ->
                                applyPlaybackFrame
                                    { phase = replay.currentTurn.phase, frame = replay.frame }
                                    (model
                                        |> setCurrentTurn replay.currentTurn
                                    )
                                    |> startPlayback

                            Nothing ->
                                model |> E.withOut

                    else
                        model |> E.withOut

                TurnIntroduction.BattlefieldViewClicked ->
                    (model
                        |> setCurrentTurn (CurrentTurn.acknowledgeIntroduction model.currentTurn)
                    )
                        |> E.withOut

                TurnIntroduction.SkipDialogsChanged skip ->
                    ( { model | skipTurnIntroduction = skip }
                        |> setCurrentTurn (CurrentTurn.acknowledgeIntroduction model.currentTurn)
                    , E.toJs (ToJs.SetLocalStorage { key = turnIntroductionPreferenceKey, value = Encode.bool skip })
                    )

        UnitDeathMsg lossMsg ->
            case lossMsg of
                UnitDeath.ContinueClicked unitId ->
                    let
                        currentTurn : CurrentTurn.Model
                        currentTurn =
                            model.currentTurn
                    in
                    (model
                        |> setCurrentTurn
                            (currentTurn
                                |> CurrentTurn.setPhase
                                    (TurnLifecycle.acknowledgeLoss
                                        unitId
                                        currentTurn.phase
                                    )
                            )
                    )
                        |> presentPlaybackTransition model

                UnitDeath.SkipDialogsChanged skip ->
                    ( { model | skipUnitLossDialogs = skip }
                    , rememberPlaybackPreference PlaybackPresentation.SkipLossDialogs skip
                    )

        CombatTheaterMsg panelMsg ->
            case panelMsg of
                CombatTheater.AutomaticallyCloseChanged automaticallyClose ->
                    ( { model | automaticallyCloseCombatTheater = automaticallyClose }
                    , rememberPlaybackPreference PlaybackPresentation.AutomaticallyCloseCombat automaticallyClose
                    )

                CombatTheater.ContinueClicked ->
                    continueCombat model
                        |> presentPlaybackTransition model

                CombatTheater.SeeMapPressed ->
                    setCombatMapView TurnPlayback.SeeingMap model |> E.withOut

                CombatTheater.SeeMapReleased ->
                    setCombatMapView TurnPlayback.CardVisible model |> E.withOut


{-| Classify message intent for UI feedback. Continuous input and background
work stay silent; focus and release notifications do not duplicate an action cue.
Clicks ignored after panning also stay silent.
-}
playAudio : Msg -> Model -> Audio.Event
playAudio msg model =
    case msg of
        BattlefieldSizeReceived _ ->
            Audio.none

        InspectorSizeReceived _ _ ->
            Audio.none

        CameraReturnFinished ->
            Audio.none

        WindowResized ->
            Audio.none

        BattlefieldMsg battlefieldMsg ->
            case battlefieldMsg of
                Battlefield.PanLeftClicked ->
                    Audio.uiAffirm

                Battlefield.PanRightClicked ->
                    Audio.uiAffirm

                Battlefield.PanUpClicked ->
                    Audio.uiAffirm

                Battlefield.PanDownClicked ->
                    Audio.uiAffirm

                Battlefield.ZoomInClicked ->
                    Audio.uiAffirm

                Battlefield.ZoomOutClicked ->
                    Audio.uiAffirm

                Battlefield.ResetViewClicked ->
                    Audio.uiAffirm

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
                                Audio.uiConfirm

                        RotationChoices.DirectionActivationKeyPressed _ ->
                            Audio.uiConfirm

                Battlefield.ClickedUnit _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnUnit _ ->
                    Audio.uiAffirm

                Battlefield.PressedSpaceOnUnit _ ->
                    Audio.uiAffirm

                Battlefield.MouseOverUnit _ ->
                    Audio.none

                Battlefield.ClickedDepot _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnDepot _ ->
                    Audio.uiAffirm

                Battlefield.PressedSpaceOnDepot _ ->
                    Audio.uiAffirm

                Battlefield.MouseOverDepot _ ->
                    Audio.none

                Battlefield.ClickedDepotStock _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnDepotStock _ ->
                    Audio.uiAffirm

                Battlefield.PressedSpaceOnDepotStock _ ->
                    Audio.uiAffirm

                Battlefield.ClickedTile _ click ->
                    battlefieldClickAudio click model

                Battlefield.PressedEnterOnTile _ ->
                    Audio.uiAffirm

                Battlefield.PressedSpaceOnTile _ ->
                    Audio.uiAffirm

                Battlefield.FocusedBoardUnit _ ->
                    Audio.none

                Battlefield.FocusedBoardTile _ ->
                    Audio.none

                Battlefield.TargetPreviewLeft ->
                    Audio.none

                Battlefield.MouseOverTile _ ->
                    Audio.none

                Battlefield.MousePressed _ ->
                    Audio.none

                Battlefield.WheelScrolled _ _ ->
                    Audio.none

                Battlefield.HomePressed ->
                    Audio.uiAffirm

        BattlefieldNavigationMsg navigationMsg ->
            case navigationMsg of
                BattlefieldNavigation.MouseMoved _ _ ->
                    Audio.none

                BattlefieldNavigation.MouseReleased _ ->
                    Audio.none

                BattlefieldNavigation.WindowVisibilityChanged _ ->
                    Audio.none

        CommandMenuMsg commandMsg ->
            case commandMsg of
                CommandMenu.MenuPressed ->
                    Audio.none

                CommandMenu.InfoClicked ->
                    Audio.uiAffirm

                CommandMenu.CancelClicked ->
                    Audio.uiCancel

                CommandMenu.CommandFocused _ ->
                    Audio.none

                CommandMenu.CommandPicked command ->
                    case command of
                        UnitCommand.StandGround ->
                            Audio.uiAffirm

                        UnitCommand.HoldPosition ->
                            Audio.uiConfirm

                        UnitCommand.Move ->
                            Audio.uiAffirm

                        UnitCommand.AttackMove ->
                            Audio.uiAffirm

                        UnitCommand.IndirectFire ->
                            Audio.uiAffirm

                        UnitCommand.Sabotage ->
                            Audio.uiConfirm

                        UnitCommand.DigIn ->
                            Audio.uiConfirm

                        UnitCommand.Ambush ->
                            Audio.uiAffirm

                CommandMenu.ArrowedUpCommandMenu _ ->
                    Audio.uiAffirm

                CommandMenu.ArrowedDownCommandMenu _ ->
                    Audio.uiAffirm

        GameMenuMsg menuMsg ->
            case menuMsg of
                GameMenu.OpenClicked ->
                    Audio.uiAffirm

                GameMenu.CloseClicked ->
                    Audio.uiCancel

                GameMenu.FocusReturned _ ->
                    Audio.none

                GameMenu.ResignClicked ->
                    Audio.uiConfirm

                GameMenu.HomeClicked ->
                    Audio.uiConfirm

        PreviousCommandPressed ->
            Audio.uiAffirm

        NextCommandPressed ->
            Audio.uiAffirm

        CommandFocusCompleted _ ->
            Audio.none

        PanLeftKeyPressed ->
            Audio.uiAffirm

        PanRightKeyPressed ->
            Audio.uiAffirm

        PanUpKeyPressed ->
            Audio.uiAffirm

        PanDownKeyPressed ->
            Audio.uiAffirm

        ZoomInKeyPressed ->
            Audio.uiAffirm

        ZoomOutKeyPressed ->
            Audio.uiAffirm

        AnimationTimerElapsed _ ->
            Audio.none

        TurnIntroductionMsg introMsg ->
            case introMsg of
                TurnIntroduction.BeginClicked ->
                    Audio.uiConfirm

                TurnIntroduction.ReplayClicked ->
                    Audio.uiAffirm

                TurnIntroduction.BattlefieldViewClicked ->
                    Audio.uiConfirm

                TurnIntroduction.SkipDialogsChanged _ ->
                    Audio.uiAffirm

        UnitDeathMsg lossMsg ->
            case lossMsg of
                UnitDeath.ContinueClicked _ ->
                    Audio.uiConfirm

                UnitDeath.SkipDialogsChanged _ ->
                    Audio.uiAffirm

        CombatTheaterMsg theaterMsg ->
            case theaterMsg of
                CombatTheater.ContinueClicked ->
                    Audio.uiConfirm

                CombatTheater.SeeMapPressed ->
                    Audio.uiAffirm

                CombatTheater.SeeMapReleased ->
                    Audio.none

                CombatTheater.AutomaticallyCloseChanged _ ->
                    Audio.uiAffirm

        DirectionKeyPressed _ ->
            Audio.uiConfirm

        PathDirectionKeyPressed _ ->
            Audio.uiAffirm

        PathEnterPressed ->
            Audio.uiConfirm

        NextUnorderedUnitKeyPressed ->
            Audio.uiAffirm

        ClearMoveClicked ->
            Audio.uiAffirm

        BackToCommandsClicked ->
            Audio.uiCancel

        CargoUnitClicked _ ->
            Audio.uiAffirm

        LoadCratesClicked _ count ->
            if count == 0 then
                Audio.uiCancel

            else
                Audio.uiConfirm

        GroundFreightPickupClicked ->
            Audio.uiConfirm

        UnloadCrateToggled _ checked ->
            if checked then
                Audio.uiAffirm

            else
                Audio.uiCancel

        UnloadUnitToggled _ checked ->
            if checked then
                Audio.uiAffirm

            else
                Audio.uiCancel

        UnloadChoicesConfirmed ->
            Audio.uiConfirm

        UnloadSkipped ->
            Audio.uiCancel

        InspectClicked ->
            Audio.uiCancel

        InspectorCloseClicked ->
            Audio.uiCancel

        EscapePressed ->
            Audio.uiCancel

        DialogDismissed ->
            Audio.uiCancel

        SubmissionCancelled ->
            Audio.uiCancel

        SubmissionConfirmed ->
            Audio.uiConfirm

        SubmitKeyPressed ->
            Audio.uiConfirm

        SubmissionEnterPressed ->
            Audio.uiConfirm

        SkipUnplannedUnitsWarningChanged _ ->
            Audio.uiAffirm

        TurnControlsMsg turnControlsMsg ->
            case turnControlsMsg of
                TurnControls.SubmitClicked ->
                    Audio.uiConfirm

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
                            Audio.uiConfirm

                        PlaybackPresentation.CombatSeeMapReleased ->
                            Audio.none

        ResignResponseReceived _ _ ->
            Audio.none

        PollStatusResponseReceived _ ->
            Audio.none

        PollResponseReceived _ ->
            Audio.none


battlefieldClickAudio : { detail : Int } -> Model -> Audio.Event
battlefieldClickAudio click model =
    if suppressesBattlefieldClick click model then
        Audio.none

    else
        Audio.uiAffirm


handleGameMenuMsg : LobbyId -> GameMenu.Msg -> Model -> ( Model, Eff Msg )
handleGameMenuMsg lobbyId msg model =
    case msg of
        GameMenu.OpenClicked ->
            if canOpenMenu model then
                ( model
                    |> setMenuOpen True
                , E.none
                )

            else
                E.withOut model

        GameMenu.CloseClicked ->
            ( model
                |> setMenuOpen False
            , E.focus
                { htmlId = GameMenu.buttonHtmlId
                }
                (GameMenu.FocusReturned >> GameMenuMsg)
            )

        GameMenu.ResignClicked ->
            resignGame lobbyId RemainInGame model

        GameMenu.HomeClicked ->
            if not model.menuOpen || model.resigning then
                E.withOut model

            else if model.currentTurn.outcome /= Nothing then
                ( model, Route.pushUrl Route.Home )

            else
                resignGame lobbyId GoHome model

        GameMenu.FocusReturned result ->
            E.withOut (recordFocusResult result model)


handleTurnControlsMsg : LobbyId -> TurnControls.Msg -> Model -> ( Model, Eff Msg )
handleTurnControlsMsg lobbyId msg model =
    case msg of
        TurnControls.SubmitClicked ->
            requestSubmission lobbyId model


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
            model |> E.withOut


requestSubmission : LobbyId -> Model -> ( Model, Eff Msg )
requestSubmission lobbyId model =
    if
        planningLocked model
            || isChoosingUnload model
            || (unloadChoice model.currentTurn.phase /= Nothing)
    then
        model |> E.withOut

    else if model.skipUnplannedUnitsWarning || List.isEmpty (unitsWithoutOrders model) then
        model
            |> submitTurn lobbyId

    else
        ( model
            |> mapPlanning OrderPlanning.showSubmissionWarning
        , E.toJs
            (ToJs.OpenDialog { htmlId = partialOrdersDialogHtmlId })
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
            if currentTurn.outcome /= Nothing || currentTurn.refreshing then
                model |> E.withOut

            else
                ( model
                    |> setCurrentTurn
                        (currentTurn
                            |> CurrentTurn.setRefreshing
                                True
                        )
                , E.request PollStatusResponseReceived (pollRequest lobbyId)
                )

        CurrentTurn.GotPlaybackPresentationMsg playbackMsg ->
            case playbackMsg of
                PlaybackPresentation.FrameElapsed delta ->
                    advanceCurrentPlayback delta model

                PlaybackPresentation.CombatEnterReleased ->
                    continueCombat model
                        |> presentPlaybackTransition model

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
            model |> E.withOut


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
                        |> presentPlaybackTransition model

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
            model |> E.withOut


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


handleCommandMsg : CommandMenu.Msg -> Model -> ( Model, Eff Msg )
handleCommandMsg commandMsg model =
    case commandMsg of
        CommandMenu.MenuPressed ->
            model |> E.withOut

        CommandMenu.InfoClicked ->
            if hasDialog model then
                model |> E.withOut

            else
                model
                    |> mapPlanning (OrderPlanning.openCommandGuide model.map model.units (ownPlayerNumbers model))
                    |> E.withOut

        CommandMenu.CancelClicked ->
            model
                |> clearSelection
                |> E.withOut

        CommandMenu.CommandFocused command ->
            model
                |> focusCommand command
                |> E.withOut

        CommandMenu.CommandPicked command ->
            model
                |> applyCommand command
                |> E.withOut

        CommandMenu.ArrowedUpCommandMenu current ->
            ( model
            , focusAdjacentCommand List.reverse (Just current) model
            )

        CommandMenu.ArrowedDownCommandMenu current ->
            ( model
            , focusAdjacentCommand identity (Just current) model
            )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


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
        , commandMenu model
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

                        CommandMenu _ ->
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


view : Model -> List (Html Msg)
view model =
    BattlefieldWorkspace.toHtml
        { loss = unitLoss model /= Nothing
        , combat = combatEncounter model /= Nothing
        , dying = deathInFocus model
        , battlefield = battlefieldView model
        , header =
            GameMenu.panel
                { enabled = canOpenMenu model
                , turnNumber = displayedTurnNumber model
                }
                |> H.map GameMenuMsg
                |> Just
        , controls = turnPanel model
        , inspection = selectionView model
        , hasSelection = currentSelection model /= Nothing
        , onCloseInspection = InspectorCloseClicked
        , combatOverlay =
            PlaybackPresentation.combatOverlay
                model.backdropCalibrations
                model.automaticallyCloseCombatTheater
                model.map
                (playback model)
                |> H.map CombatTheaterMsg
        }


commandMenu : Model -> Html Msg
commandMenu model =
    let
        menuUnit : Maybe Unit
        menuUnit =
            if commandGuideOpen model then
                selectedUnit model

            else
                commandMenuUnit model
    in
    case menuUnit of
        Just unit ->
            case Unit.physicalPosition model.units unit of
                Just position ->
                    CommandMenu.toHtml
                        model.depots
                        model.map
                        (BattlefieldNavigation.camera model.navigation)
                        position
                        unit
                        |> H.map CommandMenuMsg

                Nothing ->
                    H.text ""

        Nothing ->
            H.text ""


selectionView : Model -> Html Msg
selectionView model =
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

                revoke : Maybe Msg
                revoke =
                    if canRevokeOrder model unit then
                        Just ClearMoveClicked

                    else
                        Nothing

                content : List (Html Msg)
                content =
                    [ UnitStatus.toHtml
                        (ownerName model unit |> Maybe.withDefault "")
                        authoritativeUnit
                        revoke
                    , BattlefieldInspection.cargo
                        { units = model.units
                        , ownPlayers = ownPlayerNumbers model
                        , orders = plannedOrders model
                        , onSelectPassenger = CargoUnitClicked
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
        { map = model.map
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
                        [ H.p
                            []
                            [ H.text "orders are locked while waiting or playing the turn."
                            ]
                        ]

                    else if isChoosingUnload model then
                        let
                            unloadingCargoLabel : String
                            unloadingCargoLabel =
                                case
                                    unloadPlanning model.currentTurn.phase
                                        |> Maybe.map .cargo
                                of
                                    Just (UnloadCargo.Crate index) ->
                                        "cargo " ++ String.fromInt (index + 1)

                                    _ ->
                                        Unit.label unit
                        in
                        [ H.p
                            []
                            [ H.text ("choose an adjacent square to unload " ++ unloadingCargoLabel)
                            ]
                        , Button.primary "skip remaining cargo" UnloadSkipped
                            |> Button.toHtml
                        ]

                    else if Unit.carrierId unit /= Nothing then
                        transportDetails model unit

                    else if receivingLoad unit model then
                        let
                            orderDetails : List (Html Msg)
                            orderDetails =
                                unitOrderView model unit

                            cargoDetails : List (Html Msg)
                            cargoDetails =
                                transportDetails model unit
                        in
                        orderDetails ++ cargoDetails

                    else if choosingIndirectFire model then
                        indirectFireDetails unit

                    else if choosingAmbush model then
                        ambushDetails unit

                    else if choosingStandGround model then
                        [ H.p [] [ H.text "choose a stand ground direction on the map, or press an arrow key / wasd" ]
                        , H.p [] [ H.text "combat ready when attacked; does not fire" ]
                        , H.p [] [ H.text ("supplies: normal upkeep + " ++ String.fromInt unit.combatRules.readinessCost ++ " readiness") ]
                        , Button.primary "back to commands" BackToCommandsClicked
                            |> Button.toHtml
                        ]

                    else if choosingDirection model then
                        [ H.p [] [ H.text "choose final attack direction around the destination. click to save, or press an arrow key or wasd." ]
                        , Button.primary "back to commands" BackToCommandsClicked
                            |> Button.toHtml
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
                budget : String
                budget =
                    let
                        ruleAppliesToUnit : Movement.Rule -> Bool
                        ruleAppliesToUnit rule =
                            rule.kind == unit.kind
                    in
                    model.movementRules
                        |> ListUtil.find ruleAppliesToUnit
                        |> Maybe.map (.budget >> Movement.pointsLabel)
                        |> Maybe.withDefault "?"

                previewDetails : List (Html Msg)
                previewDetails =
                    [ H.p
                        []
                        [ H.text "choose a destination on the map"
                        ]
                    , H.p
                        []
                        [ H.text ("movement: " ++ Movement.pointsLabel preview.cost ++ " / " ++ budget)
                        ]
                    ]

                attackPlanning : Bool
                attackPlanning =
                    TurnLifecycle.planning model.currentTurn.phase
                        |> Maybe.andThen OrderPlanning.movementPlanning
                        |> Maybe.map (\planning -> planning.purpose == MovePlanning.AttackMove)
                        |> Maybe.withDefault False

                loadingDetails : List (Html Msg)
                loadingDetails =
                    if attackPlanning then
                        [ H.p [] [ H.text "stops at the first enemy and attacks. allies are passable." ] ]

                    else
                        loadingNotice model unit preview.destination

                controls : List (Html Msg)
                controls =
                    [ Button.primary "back to commands" BackToCommandsClicked
                        |> Button.toHtml
                    ]
            in
            previewDetails ++ loadingDetails ++ controls

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
                    [ H.h3 [] [ H.text chosenOrderText ]
                    ]

                loadingDetails : List (Html Msg)
                loadingDetails =
                    case plan.action of
                        PlannedOrder.Move movePlan ->
                            loadingNotice model unit movePlan.move.destination

                        _ ->
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
                notice : String
                notice =
                    if unit.kind == UnitKind.Truck then
                        "this move will pick up " ++ Unit.label target ++ " into this truck when both units reach the destination."

                    else
                        "this move will board " ++ Unit.label target ++ " when both units reach the destination."
            in
            [ H.p
                [ Aria.role Aria.Status
                , A.css
                    [ S.bgYellow2
                    , S.textGray5
                    , S.p2
                    ]
                ]
                [ H.text notice ]
            ]

        Nothing ->
            []


transportDetails : Model -> Unit -> List (Html Msg)
transportDetails model unit =
    let
        description : String
        description =
            if receivingLoad unit model then
                "receiving cargo at the planned destination. revoking this order also clears dependent boarding moves."

            else if Unit.carrierId unit /= Nothing then
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
        passengers : List Unit
        passengers =
            List.filter (\unit -> Unit.carrierId unit == Just (UnloadingTruck.unitId choice.truck)) model.units

        unavailable : UnloadCargo -> Bool
        unavailable cargo =
            OrderPlanning.canSelectUnloadCargo
                model.map
                model.units
                (ownPlayerNumbers model)
                model.movementRules
                (visibleSupplyCrates model)
                cargo
                (OrderPlanning.ChoosingPassengers choice)
                |> IC.resolve unavailableResult

        unavailableResult : Maybe OrderPlanning.InvariantViolation -> Bool -> Bool
        unavailableResult violation available =
            case violation of
                Just _ ->
                    True

                Nothing ->
                    not available

        passengerCheckbox : Unit -> Html Msg
        passengerCheckbox unit =
            UnloadPassenger.toHtml
                { disabled = unavailable (UnloadCargo.Passenger unit.id)
                , checked = List.member (UnloadCargo.Passenger unit.id) choice.checked
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
            model.units
                |> ListUtil.find (\unit -> unit.id == UnloadingTruck.unitId choice.truck)
                |> Maybe.andThen .resources
                |> Maybe.map (.supplyCargo >> List.indexedMap crateCheckbox)
                |> Maybe.withDefault []

        crateCheckbox : Int -> Supply.CargoStock -> Html Msg
        crateCheckbox index stock =
            let
                label : String
                label =
                    Supply.cargoLabel stock.kind ++ " " ++ String.fromInt (index + 1)
            in
            Checkbox.new
                { label = label
                , checked = List.member (UnloadCargo.Crate index) choice.checked
                , onCheck = UnloadCrateToggled index
                }
                |> Checkbox.disabled (unavailable (UnloadCargo.Crate index))
                |> Checkbox.toHtml
                    [ H.img
                        [ A.src (Supply.cargoImage stock.kind)
                        , A.alt ""
                        , A.width 48
                        , A.height 48
                        ]
                        []
                    , H.span
                        []
                        [ H.text (label ++ " · " ++ Supply.resourceLabel stock.kind ++ " " ++ String.fromInt stock.current ++ "/" ++ String.fromInt stock.maximum)
                        ]
                    ]

        proceedButton : Html Msg
        proceedButton =
            if List.isEmpty choice.checked then
                Button.secondary "proceed without unloading" UnloadSkipped
                    |> Button.toHtml

            else
                Button.primary "choose unload squares" UnloadChoicesConfirmed
                    |> Button.toHtml

        actions : Html Msg
        actions =
            H.form
                [ A.attribute "method" "dialog"
                ]
                [ proceedButton
                ]

        content : List (Html Msg)
        content =
            choices ++ unavailableContent ++ actionContent

        unavailableContent : List (Html Msg)
        unavailableContent =
            let
                hasUnavailable : Bool
                hasUnavailable =
                    List.any (\unit -> unavailable (UnloadCargo.Passenger unit.id)) passengers
                        || (model.units
                                |> ListUtil.find
                                    (\unit -> unit.id == UnloadingTruck.unitId choice.truck)
                                |> Maybe.map
                                    (\truck ->
                                        List.range 0 (Unit.freightCount truck - 1)
                                            |> List.any (UnloadCargo.Crate >> unavailable)
                                    )
                                |> Maybe.withDefault False
                           )
            in
            if hasUnavailable then
                [ H.p
                    [ A.css [ S.textGray4 ] ]
                    [ H.text "remaining cargo has no available unload space or insufficient supplies" ]
                ]

            else
                []

        actionContent : List (Html Msg)
        actionContent =
            [ actions
            ]
    in
    Dialog.make unloadDialogHtmlId "unload" EscapePressed content


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

        loadAmount : Int -> Maybe Int
        loadAmount count =
            stock
                |> Maybe.map
                    (\known ->
                        min known.current (count * model.supplyRules.crateCapacity)
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
                                |> (\total -> clamp 0 model.supplyRules.crateCapacity (total - index * model.supplyRules.crateCapacity))

                        percentage : Float
                        percentage =
                            100 * toFloat amount / toFloat model.supplyRules.crateCapacity
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


{-| Dialogs derive from the game menu, command guide, turn introduction, playback loss, or the active planning workflow.
-}
dialog : Model -> Maybe (Dialog Msg)
dialog model =
    MaybeUtil.lazyFirst
        [ gameMenuDialog model
        , commandGuideDialog model
        , introductionDialog model
        , lossDialog model
        , planningDialog model
        ]


gameMenuDialog : Model -> () -> Maybe (Dialog Msg)
gameMenuDialog model _ =
    let
        status : GameMenu.Status
        status =
            if model.resigning then
                GameMenu.Resigning

            else if model.currentTurn.outcome == Nothing then
                GameMenu.ActiveGame

            else
                GameMenu.FinishedGame
    in
    if model.menuOpen then
        Just
            (GameMenu.dialog status
                |> Dialog.map GameMenuMsg
            )

    else
        Nothing


commandGuideDialog : Model -> () -> Maybe (Dialog Msg)
commandGuideDialog model _ =
    if commandGuideOpen model then
        Just
            (CommandGuide.dialog DialogDismissed
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
            victory "the game ended by resignation" winner

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
        |> Maybe.map (Dialog.map UnitDeathMsg)


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
        missingCount : Int
        missingCount =
            List.length (unitsWithoutOrders model)

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
        [ H.p
            []
            [ H.text warning
            ]
        , H.form
            [ A.attribute "method" "dialog"
            , HtmlEvents.custom "keydown"
                (HtmlEvent.enter
                    { message = SubmissionEnterPressed
                    , stopPropagation = True
                    , preventDefault = True
                    }
                )
            , A.css
                [ S.row
                , S.flexWrap
                , S.itemsCenter
                , S.g3
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


turnPanel : Model -> Html Msg
turnPanel model =
    let
        ownStatus : String
        ownStatus =
            case model.currentTurn.phase of
                TurnLifecycle.Playing _ ->
                    "submitted plan"

                TurnLifecycle.WaitingForOpponent _ ->
                    "submitted plan"

                _ ->
                    "planning"

        submitLabel : String
        submitLabel =
            if model.currentTurn.outcome /= Nothing then
                "game over"

            else
                TurnLifecycle.toLabel model.currentTurn.phase

        opponentStatus : String
        opponentStatus =
            case model.currentTurn.phase of
                TurnLifecycle.Playing _ ->
                    "submitted plan"

                _ ->
                    if model.currentTurn.opponentSubmitted then
                        "submitted plan"

                    else
                        "planning"

        zoomPercent : Int
        zoomPercent =
            round ((BattlefieldNavigation.camera model.navigation).zoom * 100)
    in
    TurnControls.panel
        [ Lazy.lazy2 turnSubmit (turnActivity model) submitLabel
        , Lazy.lazy5 turnFeedback model.players ownStatus opponentStatus model.currentTurn.outcome model.currentTurn.error
        , Lazy.lazy viewControls zoomPercent
        ]


displayedTurnNumber : Model -> Int
displayedTurnNumber model =
    if (model.currentTurn.outcome /= Nothing) && not (GameOutcome.isResignation model.currentTurn.outcome) then
        model.currentTurn.number - 1

    else
        model.currentTurn.number


turnSubmit : TurnControls.Activity -> String -> Html Msg
turnSubmit activity submitLabel =
    TurnControls.submit activity submitLabel
        |> H.map TurnControlsMsg


turnFeedback :
    List Player
    -> String
    -> String
    -> Maybe GameOutcome
    -> Maybe String
    -> Html Msg
turnFeedback players ownStatus opponentStatus outcome error =
    let
        playerRow : Player -> Html Msg
        playerRow player =
            let
                status : String
                status =
                    case outcome of
                        Just (GameOutcome.Victory winner) ->
                            if player.playerNumber == winner then
                                "won"

                            else
                                "lost"

                        Just (GameOutcome.Resignation winner) ->
                            if player.playerNumber == winner then
                                "won"

                            else
                                "resigned"

                        Just GameOutcome.Draw ->
                            "draw"

                        Nothing ->
                            if player.isYou then
                                ownStatus

                            else
                                opponentStatus
            in
            TurnControls.playerRow
                { name = player.name
                , playerNumber = player.playerNumber
                , status = status
                }

        errorDetails : List (Html Msg)
        errorDetails =
            case error of
                Nothing ->
                    []

                Just message ->
                    [ H.p [ Aria.role Aria.Alert ] [ H.text message ] ]

        content : List (Html Msg)
        content =
            [ H.div
                [ Aria.role Aria.Status ]
                [ H.ul
                    [ Aria.label "player statuses"
                    , Aria.role Aria.List
                    , A.css
                        [ S.col
                        , S.listNone
                        ]
                    ]
                    (List.map playerRow players)
                ]
            ]

        feedbackContent : List (Html Msg)
        feedbackContent =
            content ++ errorDetails
    in
    TurnControls.feedback feedbackContent



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


keyCommands : Model -> KeyCmd Msg
keyCommands model =
    let
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

                            CommandMenu _ ->
                                [ KeyCmd.upGamerKeys PreviousCommandPressed
                                , KeyCmd.downGamerKeys NextCommandPressed
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


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize (\_ _ -> WindowResized)
        , Time.every 400 AnimationTimerElapsed
        , CurrentTurn.subscriptions model.currentTurn
            |> Sub.map CurrentTurnMsg
        , BattlefieldNavigation.subscriptions model.navigation
            |> Sub.map BattlefieldNavigationMsg
        ]
