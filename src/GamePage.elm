module GamePage exposing
    ( Flags
    , Model
    , Msg
    , dialog
    , init
    , keyCommands
    , load
    , setShared
    , subscriptions
    , superUpdate
    , view
    )

import AnimationFrame
import Api.Enum.Direction as DirectionEnum exposing (Direction)
import Api.Enum.MapTheme exposing (MapTheme)
import Api.Enum.MapType
    exposing
        ( MapType
        )
import Api.Enum.PlayerNumber
    exposing
        ( PlayerNumber
        )
import Api.Enum.SpriteFacing exposing (SpriteFacing)
import Api.Enum.Terrain exposing (Terrain)
import Api.Enum.TurnEventKind as TurnEventKind
import Api.Enum.UnitKind as UnitKind
import Api.Mutation
import Api.Object
import Api.Object.GamePlayerView as PlayerView
import Api.Object.GameSnapshot as SnapshotApi
import Api.Object.MovementRule as MovementRuleApi
import Api.Object.Scenario as Scenario
import Api.Object.TerrainMovementCost as MovementCostApi
import Api.Query
import ApiRequest
import Camera exposing (Camera)
import CombatRules
import Coordinate exposing (Coordinate)
import Css
import Css.Global
import Depot exposing (Depot)
import Direction
import Effect as E
    exposing
        ( Eff
        )
import Error exposing (Error)
import GamePage.BattlefieldNavigation as BattlefieldNavigation
import GamePage.CurrentTurn as CurrentTurn
import GamePage.OrderPlanning as OrderPlanning exposing (UnloadChoice, UnloadPlanning)
import GamePage.Selection
    exposing
        ( DestinationFeedback(..)
        , Inspection(..)
        , MovePlanning
        , Selection(..)
        , StationaryPurpose(..)
        , UnitInteraction(..)
        )
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Attributes as HA
import Html.Lazy as SvgLazy
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Events as HtmlEvents
import Html.Styled.Keyed as Keyed
import Html.Styled.Lazy as Lazy
import Json.Decode as Decode
import Json.Encode as Encode
import KeyCmd exposing (KeyCmd)
import LobbyId
    exposing
        ( LobbyId
        )
import LocalStorage
import Map exposing (Map)
import Movement
import PlannedOrder
    exposing
        ( PlannedOrder
        , UnloadOrder
        )
import Point exposing (Point)
import Ports.Js.To as ToJs
import Set exposing (Set)
import Shared
import Style as S
import Supply
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as Ev
import Svg.Keyed as SvgKeyed
import Svg.Styled as StyledSvg
import Time
import Turn
import TurnLifecycle exposing (Phase)
import TurnPlayback
import Unit exposing (Unit)
import UnitCommand
import UnitId exposing (UnitId)
import UnitLoss
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import Util.Maybe as MaybeUtil
import View.Ambush as Ambush
import View.Aria as Aria
import View.Button as Button
import View.CargoPassenger as CargoPassenger
import View.Checkbox as Checkbox
import View.CombatEffects as CombatEffects
import View.CombatTheater as CombatTheater
import View.CommandGuide as CommandGuide
import View.CommandMenu as CommandMenu
import View.DepotStatus as DepotStatus
import View.DepotStock as DepotStock
import View.Dialog as Dialog exposing (Dialog)
import View.MovementRoute as MovementRoute
import View.RotationChoices as RotationChoices
import View.SupplyCrate as SupplyCrate
import View.TargetSight as TargetSight
import View.TerrainInfo as TerrainInfo
import View.TerrainTile as TerrainTile
import View.TurnControls as TurnControls
import View.TurnIntroduction as TurnIntroduction
import View.UnitCargo as UnitCargo
import View.UnitDeath as UnitDeath
import View.UnitFacing as UnitFacing
import View.UnitSprite as UnitSprite
import View.UnitStatus as UnitStatus
import View.UnitWarnings as UnitWarnings
import View.UnloadPassenger as UnloadPassenger



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { currentTurn : CurrentTurn.Model
    , shared : Shared.Model
    , skipTurnIntroduction : Bool
    , skipUnitLossDialogs : Bool
    , automaticallyCloseCombatTheater : Bool
    , name : String
    , mapType : MapType
    , players : List Player
    , map : Map
    , units : List Unit
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    , supplyRules : Supply.Rules
    , visibleTiles : List Coordinate
    , movementRules : List Movement.Rule
    , navigation : BattlefieldNavigation.Model
    , frame : AnimationFrame.Frame
    }


type alias Snapshot =
    { name : String
    , mapType : MapType
    , players : List Player
    , map : Map
    , units : List Unit
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    , supplyRules : Supply.Rules
    , visibleTiles : List Coordinate
    , movementRules : List Movement.Rule
    , turn : Turn.Snapshot
    , playbackFrames : List TurnPlayback.Frame
    }


type alias Player =
    { name : String
    , playerNumber : PlayerNumber
    , isYou : Bool
    }


{-| An unload preview always connects the truck to one adjacent tile.
-}
type alias UnloadRoute =
    { origin : Coordinate
    , direction : Direction
    }


type BoardTargeting
    = InspectingBoard
    | ChoosingBoardDestination
    | ChoosingIndirectTarget


type alias RotationSelection =
    { unitId : UnitId
    , position : Coordinate
    , direction : Direction
    }


type Msg
    = BattlefieldNavigationMsg BattlefieldNavigation.Msg
    | CommandMenuMsg CommandMenu.Msg
    | PreviousCommandPressed
    | NextCommandPressed
    | CommandFocusCompleted
    | PanLeftClicked
    | PanRightClicked
    | PanUpClicked
    | PanDownClicked
    | PanLeftKeyPressed
    | PanRightKeyPressed
    | PanUpKeyPressed
    | PanDownKeyPressed
    | ZoomInClicked
    | ZoomOutClicked
    | ZoomInKeyPressed
    | ZoomOutKeyPressed
    | ResetViewClicked
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
    | UnloadCrateToggled Int Bool
    | UnloadUnitToggled UnitId Bool
    | UnloadChoicesConfirmed
    | UnloadSkipped
    | InspectClicked
    | EscapePressed
    | DialogDismissed
    | SubmissionConfirmed
    | SubmitKeyPressed
    | SubmissionEnterPressed
    | TurnControlsMsg TurnControls.Msg
    | SubmitResponseReceived Int (ApiRequest.Response Snapshot)
    | CurrentTurnMsg CurrentTurn.Msg
    | PollResponseReceived (ApiRequest.Response Snapshot)
    | RotationChoicesMsg RotationChoices.Msg
    | ClickedUnit UnitId { detail : Int }
    | PressedEnterOnUnit UnitId
    | PressedSpaceOnUnit UnitId
    | MouseOverUnit UnitId
    | ClickedDepot Coordinate { detail : Int }
    | PressedEnterOnDepot Coordinate
    | PressedSpaceOnDepot Coordinate
    | MouseOverDepot Coordinate
    | ClickedDepotStock Coordinate { detail : Int }
    | PressedEnterOnDepotStock Coordinate
    | PressedSpaceOnDepotStock Coordinate
    | ClickedTile Coordinate { detail : Int }
    | PressedEnterOnTile Coordinate
    | PressedSpaceOnTile Coordinate
    | FocusedBoardUnit UnitId
    | FocusedBoardTile Coordinate
    | TargetPreviewLeft
    | MouseOverTile Coordinate
    | MousePressed Point
    | WheelScrolled Point Float
    | HomePressed



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { snapshot : Snapshot }


init : Shared.Model -> Flags -> ( Model, Eff msg )
init shared flags =
    let
        loadPreference : String -> ( Bool, Maybe Error )
        loadPreference key =
            case LocalStorage.get shared.localStorage key Decode.bool of
                Ok saved ->
                    ( Maybe.withDefault False saved, Nothing )

                Err decodeError ->
                    let
                        error : Error
                        error =
                            Error.LocalStorageDecodeFailed
                                { key = key
                                , error = decodeError
                                }
                    in
                    ( False, Just error )

        ( automaticallyCloseCombatTheater, maybeError ) =
            loadPreference combatTheaterPreferenceKey

        ( skipTurnIntroduction, introductionPreferenceError ) =
            loadPreference turnIntroductionPreferenceKey

        ( skipLossDialogs, lossPreferenceError ) =
            loadPreference unitLossPreferenceKey

        model : Model
        model =
            { currentTurn = CurrentTurn.init flags.snapshot.turn
            , shared =
                shared
                    |> Shared.addError maybeError
                    |> Shared.addError lossPreferenceError
                    |> Shared.addError introductionPreferenceError
            , skipTurnIntroduction = skipTurnIntroduction
            , skipUnitLossDialogs = skipLossDialogs
            , automaticallyCloseCombatTheater = automaticallyCloseCombatTheater
            , name = flags.snapshot.name
            , mapType = flags.snapshot.mapType
            , players = flags.snapshot.players
            , map = flags.snapshot.map
            , units = flags.snapshot.units
            , depots = flags.snapshot.depots
            , supplyCrates = flags.snapshot.supplyCrates
            , supplyRules = flags.snapshot.supplyRules
            , visibleTiles = flags.snapshot.visibleTiles
            , movementRules = flags.snapshot.movementRules
            , navigation = BattlefieldNavigation.init
            , frame = AnimationFrame.first
            }

        eff : Eff msg
        eff =
            if showTurnIntroduction model then
                E.toJs
                    (ToJs.OpenDialog
                        { htmlId = TurnIntroduction.dialogHtmlId }
                    )

            else
                E.none
    in
    ( model, eff )


load : LobbyId -> Graphql.Http.Request Flags
load id =
    Api.Query.game
        { id = LobbyId.toString id }
        (SS.map Flags snapshotSelection)
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    case
        LocalStorage.get
            shared.localStorage
            turnIntroductionPreferenceKey
            Decode.bool
    of
        Ok saved ->
            { model | shared = shared, skipTurnIntroduction = Maybe.withDefault False saved }

        Err error ->
            { model
                | shared =
                    Shared.addError
                        (Just
                            (Error.LocalStorageDecodeFailed
                                { key = turnIntroductionPreferenceKey
                                , error = error
                                }
                            )
                        )
                        shared
            }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


turnIntroductionPreferenceKey : String
turnIntroductionPreferenceKey =
    "skipTurnIntroduction"


showTurnIntroduction : Model -> Bool
showTurnIntroduction model =
    not model.skipTurnIntroduction
        && CurrentTurn.introductionPending model.currentTurn


rememberCombatTheaterPreference : Bool -> Eff msg
rememberCombatTheaterPreference automaticallyClose =
    E.toJs
        (ToJs.SetLocalStorage
            { key = combatTheaterPreferenceKey
            , value = Encode.bool automaticallyClose
            }
        )


combatTheaterPreferenceKey : String
combatTheaterPreferenceKey =
    "automaticallyCloseCombatTheater"


{-| Save the chosen load count on an existing truck order, retaining its route and passenger exits.
-}
saveCrateLoading : UnitId -> Int -> OrderPlanning.Model -> OrderPlanning.Model
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

                Nothing ->
                    state

        _ ->
            state


depotLoadingRoom : Model -> Unit -> Int
depotLoadingRoom model unit =
    let
        passengers : Int
        passengers =
            List.filter
                (\passenger -> Unit.carrierId passenger == Just unit.id)
                model.units
                |> List.length

        crates : Int
        crates =
            unit.resources
                |> Maybe.map (.supplyCargo >> List.length)
                |> Maybe.withDefault 0

        incoming : Int
        incoming =
            OrderPlanning.boardingPassengers (planningContext model) unit.id (plannedOrders model)
                |> List.length

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
        (max 0 (unit.cargoCapacity - passengers - crates - incoming))


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


planningContext : Model -> OrderPlanning.Context
planningContext model =
    { map = model.map
    , units = model.units
    , movementRules = model.movementRules
    , supplyCrates = List.filter (\crate -> List.member crate.position model.visibleTiles) model.supplyCrates
    , depots = model.depots
    , playerNumbers = List.filter .isYou model.players |> List.map .playerNumber
    }


mapPlanning : (OrderPlanning.Model -> OrderPlanning.Model) -> Model -> Model
mapPlanning transition model =
    { model
        | currentTurn =
            CurrentTurn.mapPlanning transition model.currentTurn
    }


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
    if showTurnIntroduction model then
        { model | currentTurn = CurrentTurn.acknowledgeIntroduction model.currentTurn }

    else
        model |> mapPlanning (OrderPlanning.dismissDialog model.depots)


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


plannedOrders : Model -> List PlannedOrder
plannedOrders model =
    TurnLifecycle.orders model.currentTurn.phase


playback : Model -> Maybe TurnPlayback.Playback
playback model =
    TurnLifecycle.playback model.currentTurn.phase


unitLossPreferenceKey : String
unitLossPreferenceKey =
    "skipUnitLossDialogs"


unitLoss : Model -> Maybe TurnPlayback.Loss
unitLoss model =
    if model.skipUnitLossDialogs then
        Nothing

    else
        playback model
            |> Maybe.andThen TurnPlayback.lossEvent
            |> Maybe.map .loss


ownerName : Model -> Unit -> Maybe String
ownerName model unit =
    let
        ownsUnit : Player -> Bool
        ownsUnit player =
            player.playerNumber == unit.playerNumber
    in
    model.players
        |> ListUtil.find ownsUnit
        |> Maybe.map .name


{-| Called only after detecting a newly active dialog. Repeated playback ticks
and view rendering must not append the same loss error again.
-}
logNewLossError : Model -> Model
logNewLossError model =
    case unitLoss model of
        Just loss ->
            case UnitLoss.resolve (ownerName model) loss of
                Ok _ ->
                    model

                Err (UnitLoss.OwnerNotFound missing) ->
                    { model
                        | shared =
                            Shared.addError
                                (Just (Error.UnitOwnerNotFound missing))
                                model.shared
                    }

        Nothing ->
            model


activeDialogHtmlId : Model -> Maybe String
activeDialogHtmlId model =
    if commandGuideOpen model then
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
        (\unit -> Unit.onBoard unit && Unit.isDying unit)
        model.units


planningLocked : Model -> Bool
planningLocked model =
    TurnLifecycle.planningLocked model.currentTurn.phase


unitsWithoutOrders : Model -> List Unit
unitsWithoutOrders model =
    OrderPlanning.missingOrders (planningContext model) (plannedOrders model)


readyToSubmit : Model -> Bool
readyToSubmit model =
    not (planningLocked model) && List.isEmpty (unitsWithoutOrders model)


submitTurn : LobbyId -> Model -> ( Model, Eff Msg )
submitTurn lobbyId model =
    case CurrentTurn.startSubmission model.currentTurn of
        Just currentTurn ->
            ( { model | currentTurn = currentTurn }
            , E.request
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
        (planningContext model)
        (currentSelection model)


selectedPosition : Model -> Maybe Coordinate
selectedPosition model =
    case unloadPlanning model.currentTurn.phase of
        Just planning ->
            Just (OrderPlanning.truckDestination planning.truck)

        Nothing ->
            inspectionPosition model


inspectionPosition : Model -> Maybe Coordinate
inspectionPosition model =
    case currentSelection model of
        Just (Inspecting (TileInspection position)) ->
            Just position

        Just (Inspecting (UnitInspection _)) ->
            Maybe.andThen Unit.boardPosition (selectedUnit model)

        Just (UnitSelection _) ->
            Maybe.andThen Unit.boardPosition (selectedUnit model)

        Nothing ->
            Nothing


isOwnUnit : Model -> Unit -> Bool
isOwnUnit model unit =
    OrderPlanning.isOwnUnit (planningContext model) unit


applyCommand : UnitCommand.Command -> Model -> Model
applyCommand command model =
    model
        |> mapPlanning
            (OrderPlanning.applyCommand (planningContext model) command)


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
                            { origin = PlannedOrder.destination plan
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
            (OrderPlanning.commandMenuUnit (planningContext model))


submitRequest : LobbyId -> Model -> Graphql.Http.Request Snapshot
submitRequest lobbyId model =
    let
        orders : List PlannedOrder
        orders =
            OrderPlanning.submissionOrders
                (planningContext model)
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


applyTurnSnapshot : Snapshot -> CurrentTurn.Model -> Model -> Model
applyTurnSnapshot snapshot currentTurn model =
    let
        next : Model
        next =
            { model | currentTurn = currentTurn }
    in
    if currentTurn.number > model.currentTurn.number then
        let
            frame : TurnPlayback.Frame
            frame =
                TurnPlayback.initial snapshot.playbackFrames
                    { departures = []
                    , indirectImpacts = []
                    , shots = []
                    , durationMs = 180
                    , units = snapshot.units
                    , visibleTiles = snapshot.visibleTiles
                    , depots = snapshot.depots
                    , supplyCrates = snapshot.supplyCrates
                    }
        in
        { next
            | map = snapshot.map
            , depots = frame.depots
            , supplyCrates = frame.supplyCrates
            , supplyRules = snapshot.supplyRules
            , units = frame.units
            , visibleTiles = frame.visibleTiles
        }

    else
        next


plannedAction : Model -> Unit -> Movement.Option -> String
plannedAction model unit move =
    if Unit.carrierId unit /= Nothing && List.length move.path > 1 then
        "unload at"

    else if
        OrderPlanning.loadingTarget
            (planningContext model)
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
    OrderPlanning.receivingLoad
        (planningContext model)
        unit
        (plannedOrders model)


currentSelection : Model -> Maybe Selection
currentSelection model =
    TurnLifecycle.selection model.currentTurn.phase


setSelection : Maybe Selection -> Model -> Model
setSelection selected model =
    { model | currentTurn = CurrentTurn.setSelection selected model.currentTurn }


focusCommand : UnitCommand.MenuOption -> Model -> Model
focusCommand command model =
    model
        |> mapPlanning
            (OrderPlanning.focusCommand (planningContext model) command)


revokeSelectedOrder : Model -> Model
revokeSelectedOrder model =
    model
        |> mapPlanning
            (OrderPlanning.revokeSelectedOrder (planningContext model))


choosingDirection : Model -> Bool
choosingDirection model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.choosingDirection
        |> Maybe.withDefault False


saveDirection : Direction -> Model -> Model
saveDirection direction model =
    model
        |> mapPlanning
            (OrderPlanning.saveDirection (planningContext model) direction)


rotationSelection : Model -> Maybe RotationSelection
rotationSelection model =
    case ( currentSelection model, selectedUnit model ) of
        ( Just (UnitSelection selection), Just unit ) ->
            case selection.interaction of
                ChoosingDirection _ direction ->
                    Unit.boardPosition unit
                        |> Maybe.map
                            (\position ->
                                { unitId = unit.id
                                , position = position
                                , direction = direction
                                }
                            )

                ChoosingAttackDirection move direction ->
                    Just { unitId = unit.id, position = move.destination, direction = direction }

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


snapshotSelection : SelectionSet Snapshot Api.Object.GameSnapshot
snapshotSelection =
    let
        playerSelection : SelectionSet Player Api.Object.GamePlayerView
        playerSelection =
            SS.succeed Player
                |> SS.with PlayerView.name
                |> SS.with PlayerView.playerNumber
                |> SS.with PlayerView.isYou

        terrainCostSelection : SelectionSet Movement.TerrainCost Api.Object.TerrainMovementCost
        terrainCostSelection =
            SS.succeed Movement.TerrainCost
                |> SS.with MovementCostApi.terrain
                |> SS.with MovementCostApi.cost

        movementRuleSelection : SelectionSet Movement.Rule Api.Object.MovementRule
        movementRuleSelection =
            SS.succeed Movement.Rule
                |> SS.with MovementRuleApi.kind
                |> SS.with MovementRuleApi.budget
                |> SS.with (MovementRuleApi.terrainCosts terrainCostSelection)
    in
    SS.succeed Snapshot
        |> SS.with SnapshotApi.name
        |> SS.with SnapshotApi.mapType
        |> SS.with (SnapshotApi.players playerSelection)
        |> SS.with (SnapshotApi.scenario (Scenario.map Map.selection))
        |> SS.with (SnapshotApi.scenario (Scenario.units Unit.selection))
        |> SS.with (SnapshotApi.scenario (Scenario.depots Depot.selection))
        |> SS.with (SnapshotApi.scenario (Scenario.supplyCrates Supply.crateSelection))
        |> SS.with (SnapshotApi.scenario (Scenario.supplyRules Supply.rulesSelection))
        |> SS.with (SnapshotApi.visibleTiles Coordinate.selection)
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


moveOptions : Model -> List Movement.Option
moveOptions model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.moveOptions
        |> Maybe.withDefault []


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
        model |> mapPlanning (OrderPlanning.selectUnit (planningContext model) id)


selectTile : Coordinate -> Model -> Model
selectTile position model =
    if planningLocked model then
        setSelection (Just (Inspecting (TileInspection position))) model

    else
        model
            |> mapPlanning (OrderPlanning.selectTile (planningContext model) position)


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
            |> Maybe.andThen Unit.boardPosition
            |> Maybe.map (\position -> previewTile position model)
            |> Maybe.withDefault model


previewTile : Coordinate -> Model -> Model
previewTile position model =
    if BattlefieldNavigation.active model.navigation && pathPreview model == Nothing then
        model

    else
        model
            |> mapPlanning (OrderPlanning.previewTile (planningContext model) position)


extendPath : Direction -> Model -> Model
extendPath direction model =
    if BattlefieldNavigation.active model.navigation then
        model

    else
        model
            |> mapPlanning (OrderPlanning.extendPath (planningContext model) direction)


confirmPath : Model -> Model
confirmPath model =
    model
        |> mapPlanning (OrderPlanning.confirmPath (planningContext model))


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
                    UnitCommand.enabledOptions unit
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
    { model | navigation = change model.navigation }


cargoDialogHtmlId : TurnLifecycle.Phase -> Maybe String
cargoDialogHtmlId phase =
    case phase of
        TurnLifecycle.Planning (OrderPlanning.ChoosingCrates _ _) ->
            Just loadCratesDialogHtmlId

        TurnLifecycle.Planning (OrderPlanning.ChoosingPassengers _) ->
            Just unloadDialogHtmlId

        _ ->
            Nothing


loadCratesDialogHtmlId : String
loadCratesDialogHtmlId =
    "load-supply-crates-dialog"


mousePressedDecoder : Decode.Decoder Msg
mousePressedDecoder =
    Decode.field "button" Decode.int
        |> Decode.andThen primaryMousePressed


primaryMousePressed : Int -> Decode.Decoder Msg
primaryMousePressed button =
    if button == 0 then
        Decode.map MousePressed Point.decoder

    else
        Decode.fail "only the primary button pans"


type alias WheelEvent =
    { pointer : Point
    , viewportSize : Point
    , delta : Float
    }


wheelScrolledDecoder : Decode.Decoder Msg
wheelScrolledDecoder =
    let
        wheelScrolled : WheelEvent -> Msg
        wheelScrolled event =
            WheelScrolled
                { x = event.pointer.x - event.viewportSize.x / 2
                , y = event.pointer.y - event.viewportSize.y / 2
                }
                event.delta
    in
    Decode.map3 WheelEvent
        Point.decoder
        viewportSizeDecoder
        wheelDeltaDecoder
        |> Decode.map wheelScrolled


viewportSizeDecoder : Decode.Decoder Point
viewportSizeDecoder =
    Decode.map2 Point
        (Decode.at [ "currentTarget", "clientWidth" ] Decode.float)
        (Decode.at [ "currentTarget", "clientHeight" ] Decode.float)


wheelDeltaDecoder : Decode.Decoder Float
wheelDeltaDecoder =
    Decode.map2 normalizeWheelDelta
        (Decode.field "deltaMode" Decode.int)
        (Decode.field "deltaY" Decode.float)


normalizeWheelDelta : Int -> Float -> Float
normalizeWheelDelta mode delta =
    case mode of
        1 ->
            delta * 16

        2 ->
            delta * 800

        _ ->
            delta


navigationKeyDecoder : Decode.Decoder Msg
navigationKeyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen navigationKeyPressed


navigationKeyPressed : String -> Decode.Decoder Msg
navigationKeyPressed key =
    if key == "Home" then
        Decode.succeed HomePressed

    else
        Decode.fail "not a navigation key"


suppressesBattlefieldClick : { detail : Int } -> Model -> Bool
suppressesBattlefieldClick click model =
    (click.detail /= 0)
        && BattlefieldNavigation.suppressesClick model.navigation


preventDefault : Msg -> ( Msg, Bool )
preventDefault msg =
    ( msg, True )


choosingIndirectFire : Model -> Bool
choosingIndirectFire model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map OrderPlanning.choosingIndirectFire
        |> Maybe.withDefault False


indirectTargets : Model -> List Coordinate
indirectTargets model =
    TurnLifecycle.planning model.currentTurn.phase
        |> Maybe.map (OrderPlanning.indirectTargets (planningContext model))
        |> Maybe.withDefault []


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



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


superUpdate : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
superUpdate lobbyId msg model =
    case update lobbyId msg model of
        ( next, effect ) ->
            let
                previousDialogHtmlId : Maybe String
                previousDialogHtmlId =
                    activeDialogHtmlId model

                nextDialogHtmlId : Maybe String
                nextDialogHtmlId =
                    activeDialogHtmlId next
            in
            case nextDialogHtmlId of
                Just htmlId ->
                    if nextDialogHtmlId /= previousDialogHtmlId then
                        ( logNewLossError next
                        , E.batch
                            [ effect
                            , E.toJs (ToJs.OpenDialog { htmlId = htmlId })
                            ]
                        )

                    else
                        ( next, effect )

                Nothing ->
                    ( next, effect )


update : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
update lobbyId msg model =
    case msg of
        PanLeftClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panLeft
                |> E.withOut

        PanRightClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panRight
                |> E.withOut

        PanUpClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panUp
                |> E.withOut

        PanDownClicked ->
            model
                |> mapNavigation BattlefieldNavigation.panDown
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

        ZoomInClicked ->
            model
                |> mapNavigation BattlefieldNavigation.zoomIn
                |> E.withOut

        ZoomOutClicked ->
            model
                |> mapNavigation BattlefieldNavigation.zoomOut
                |> E.withOut

        ZoomInKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.zoomIn
                |> E.withOut

        ZoomOutKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.zoomOut
                |> E.withOut

        ResetViewClicked ->
            model
                |> mapNavigation BattlefieldNavigation.resetViewport
                |> E.withOut

        HomePressed ->
            model
                |> mapNavigation BattlefieldNavigation.resetViewport
                |> E.withOut

        MousePressed point ->
            model
                |> mapNavigation (BattlefieldNavigation.press point)
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

        WheelScrolled anchor delta ->
            model
                |> mapNavigation (BattlefieldNavigation.scroll anchor delta)
                |> E.withOut

        UnloadUnitToggled id checked ->
            model
                |> mapPlanning
                    (OrderPlanning.toggleAvailableUnloadCargo
                        (planningContext model)
                        (OrderPlanning.Passenger id)
                        checked
                    )
                |> E.withOut

        UnloadChoicesConfirmed ->
            model
                |> mapPlanning (OrderPlanning.confirmPassengers (planningContext model))
                |> E.withOut

        UnloadSkipped ->
            model
                |> mapPlanning (OrderPlanning.skipUnloading (planningContext model))
                |> E.withOut

        LoadCratesClicked id count ->
            case
                ListUtil.find
                    (\unit -> unit.id == id && isOwnUnit model unit)
                    model.units
            of
                Just _ ->
                    model
                        |> mapPlanning
                            (OrderPlanning.dismissDialog model.depots
                                >> saveCrateLoading id count
                            )
                        |> E.withOut

                Nothing ->
                    model
                        |> E.withOut

        UnloadCrateToggled index checked ->
            model
                |> mapPlanning
                    (OrderPlanning.toggleAvailableUnloadCargo
                        (planningContext model)
                        (OrderPlanning.Crate index)
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
                    (OrderPlanning.selectNextUnorderedUnit (planningContext model))
                |> E.withOut

        RotationChoicesMsg rotationMsg ->
            let
                next : Model
                next =
                    case rotationMsg of
                        RotationChoices.MouseMovedOverDirection direction ->
                            previewDirection direction model

                        RotationChoices.ClickedDirection direction ->
                            if BattlefieldNavigation.suppressesClick model.navigation then
                                model

                            else
                                saveDirection direction model
            in
            next
                |> E.withOut

        ClickedUnit id click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        selectUnit id model
            in
            next
                |> E.withOut

        PressedEnterOnUnit id ->
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
                |> E.withOut

        PressedSpaceOnUnit id ->
            model
                |> selectUnit id
                |> E.withOut

        MouseOverUnit id ->
            previewUnit id model |> E.withOut

        FocusedBoardUnit id ->
            if choosingIndirectFire model then
                previewUnit id model |> E.withOut

            else
                model |> E.withOut

        ClickedDepot position click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        selectTile position model
            in
            next
                |> E.withOut

        PressedEnterOnDepot position ->
            model
                |> selectTile position
                |> E.withOut

        PressedSpaceOnDepot position ->
            model
                |> selectTile position
                |> E.withOut

        ClickedDepotStock position click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        inspectDepot position model
            in
            next |> E.withOut

        PressedEnterOnDepotStock position ->
            inspectDepot position model |> E.withOut

        PressedSpaceOnDepotStock position ->
            inspectDepot position model |> E.withOut

        MouseOverDepot position ->
            let
                next : Model
                next =
                    if planningLocked model then
                        model

                    else
                        previewTile position model
            in
            next
                |> E.withOut

        ClickedTile position click ->
            let
                next : Model
                next =
                    if suppressesBattlefieldClick click model then
                        model

                    else
                        selectTile position model
            in
            next
                |> E.withOut

        PressedEnterOnTile position ->
            model
                |> selectTile position
                |> E.withOut

        PressedSpaceOnTile position ->
            model
                |> selectTile position
                |> E.withOut

        FocusedBoardTile position ->
            if choosingIndirectFire model then
                previewTile position model |> E.withOut

            else
                model |> E.withOut

        TargetPreviewLeft ->
            mapPlanning OrderPlanning.clearTargetPreview model |> E.withOut

        MouseOverTile position ->
            let
                next : Model
                next =
                    if planningLocked model then
                        model

                    else
                        previewTile position model
            in
            next
                |> E.withOut

        CommandMenuMsg commandMsg ->
            model
                |> handleCommandMsg commandMsg

        PreviousCommandPressed ->
            ( model, focusAdjacentCommand List.reverse (focusedCommand model) model )

        NextCommandPressed ->
            ( model, focusAdjacentCommand identity (focusedCommand model) model )

        CommandFocusCompleted ->
            model |> E.withOut

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
                |> mapPlanning (OrderPlanning.restoreCommands (planningContext model))
                |> E.withOut

        ClearMoveClicked ->
            model
                |> revokeSelectedOrder
                |> E.withOut

        InspectClicked ->
            model
                |> clearSelection
                |> E.withOut

        EscapePressed ->
            if hasDialog model then
                model
                    |> dismissDialog
                    |> E.withOut

            else
                model
                    |> clearSelection
                    |> E.withOut

        TurnControlsMsg turnControlsMsg ->
            handleTurnControlsMsg lobbyId turnControlsMsg model

        DialogDismissed ->
            model
                |> dismissDialog
                |> E.withOut

        SubmitKeyPressed ->
            if canSubmitWithKeyboard model then
                requestSubmission lobbyId model

            else
                model |> E.withOut

        SubmissionConfirmed ->
            confirmSubmission lobbyId model

        SubmissionEnterPressed ->
            confirmSubmission lobbyId model

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
                        |> E.withOut

                Err error ->
                    { model | currentTurn = CurrentTurn.submissionFailed turnNumber (ApiRequest.errorMessage error) model.currentTurn }
                        |> E.withOut

        CurrentTurnMsg turnMsg ->
            handleCurrentTurnMsg lobbyId turnMsg model

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
                        |> E.withOut

                Err error ->
                    { model | currentTurn = CurrentTurn.pollFailed (ApiRequest.errorMessage error) model.currentTurn }
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
                    { model | currentTurn = CurrentTurn.acknowledgeIntroduction model.currentTurn } |> E.withOut

                TurnIntroduction.SkipDialogsChanged skip ->
                    ( { model
                        | skipTurnIntroduction = skip
                        , currentTurn = CurrentTurn.acknowledgeIntroduction model.currentTurn
                      }
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
                    { model
                        | currentTurn =
                            { currentTurn
                                | phase =
                                    TurnLifecycle.acknowledgeLoss
                                        unitId
                                        currentTurn.phase
                            }
                    }
                        |> E.withOut

                UnitDeath.SkipDialogsChanged skip ->
                    ( { model | skipUnitLossDialogs = skip }
                    , E.toJs
                        (ToJs.SetLocalStorage
                            { key = unitLossPreferenceKey
                            , value = Encode.bool skip
                            }
                        )
                    )

        CombatTheaterMsg panelMsg ->
            case panelMsg of
                CombatTheater.AutomaticallyCloseChanged automaticallyClose ->
                    ( { model | automaticallyCloseCombatTheater = automaticallyClose }
                    , rememberCombatTheaterPreference automaticallyClose
                    )

                CombatTheater.ContinueClicked ->
                    continueCombat model
                        |> E.withOut

                CombatTheater.SeeMapPressed ->
                    setCombatMapView TurnPlayback.SeeingMap model |> E.withOut

                CombatTheater.SeeMapReleased ->
                    setCombatMapView TurnPlayback.CardVisible model |> E.withOut


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

    else if List.isEmpty (unitsWithoutOrders model) then
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
            if currentTurn.refreshing || not (TurnLifecycle.canPoll currentTurn.phase) then
                model |> E.withOut

            else
                ( { model | currentTurn = { currentTurn | refreshing = True } }
                , E.request PollResponseReceived (loadSnapshot lobbyId)
                )

        CurrentTurn.PlaybackFrameElapsed delta ->
            let
                advance : Float -> Phase -> Maybe { phase : Phase, frame : TurnPlayback.Frame }
                advance =
                    if model.skipUnitLossDialogs then
                        TurnLifecycle.tick

                    else
                        TurnLifecycle.tickUntilLoss
            in
            case advance delta currentTurn.phase of
                Just next ->
                    applyPlaybackFrame next model
                        |> automaticallyContinueCombat
                        |> E.withOut

                Nothing ->
                    model |> E.withOut

        CurrentTurn.CombatEnterReleased ->
            continueCombat model
                |> E.withOut

        CurrentTurn.CombatSeeMapReleased ->
            setCombatMapView TurnPlayback.CardVisible model
                |> E.withOut


automaticallyContinueCombat : Model -> Model
automaticallyContinueCombat model =
    let
        ready : Bool
        ready =
            playback model
                |> Maybe.andThen TurnPlayback.panels
                |> Maybe.map CombatTheater.readyToAutomaticallyClose
                |> Maybe.withDefault False
    in
    if model.automaticallyCloseCombatTheater && ready then
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
    { model
        | currentTurn =
            { currentTurn
                | phase =
                    TurnLifecycle.setCombatMapView mapView currentTurn.phase
            }
    }


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
    { model
        | currentTurn = { currentTurn | phase = next.phase }
        , depots = next.frame.depots
        , supplyCrates = next.frame.supplyCrates
        , units = next.frame.units
        , visibleTiles = next.frame.visibleTiles
    }


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
                    |> mapPlanning (OrderPlanning.openCommandGuide (planningContext model))
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


view : Model -> List (Html Msg)
view model =
    let
        hasUnitLoss : Bool
        hasUnitLoss =
            unitLoss model /= Nothing

        hasCombatEncounter : Bool
        hasCombatEncounter =
            combatEncounter model /= Nothing

        interactionBlocked : Bool
        interactionBlocked =
            hasCombatEncounter || hasUnitLoss

        animationClass : String
        animationClass =
            if hasUnitLoss then
                "fightlines-death-focus fightlines-loss-focus"

            else if hasCombatEncounter then
                "fightlines-combat-focus"

            else if deathInFocus model then
                "fightlines-death-focus"

            else
                ""

        combatAttributes : List (H.Attribute Msg)
        combatAttributes =
            if interactionBlocked then
                [ A.attribute "inert" "" ]

            else
                []

        workspaceAttributes : List (H.Attribute Msg)
        workspaceAttributes =
            [ A.class animationClass
            , A.css
                [ S.fixed
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.row
                ]
            ]

        combatOverlay : Html Msg
        combatOverlay =
            playback model
                |> Maybe.andThen TurnPlayback.panels
                |> Maybe.map (CombatTheater.toHtml { automaticallyClose = model.automaticallyCloseCombatTheater } model.map)
                |> Maybe.map (H.map CombatTheaterMsg)
                |> Maybe.withDefault (H.text "")
    in
    [ H.div
        (workspaceAttributes ++ combatAttributes)
        [ H.div
            [ A.css
                [ S.relative
                , S.flex1
                , S.minW0
                , S.hFull
                , S.col
                ]
            ]
            [ battlefieldView model
            , H.div
                [ A.attribute "data-loss-dim" ""
                ]
                [ turnPanel model
                ]
            ]
        , H.aside
            [ A.attribute "data-loss-dim" ""
            , Aria.label "game panel"
            , A.css
                [ S.bgGray1
                , S.outdentLeft
                , S.col
                , S.justifySpaceBetween
                , S.g3
                , S.p3
                , S.shrink0
                , S.hFull
                , S.overflowAuto
                , S.wrapAnywhere
                , S.widthMinRemVw 18 45
                ]
            ]
            [ selectionView model
            , Lazy.lazy panelFooter (currentSelection model /= Nothing)
            ]
        ]
    , combatOverlay
    ]


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
                        |> Maybe.andThen (\coordinate -> ListUtil.find (\unit -> Unit.boardPosition unit == Just coordinate) model.units)

        position : Maybe Coordinate
        position =
            case inspectedUnit of
                Just unit ->
                    Unit.physicalPosition model.units unit

                Nothing ->
                    inspectionPosition model

        unitRows : List ( String, Html Msg )
        unitRows =
            case inspectedUnit of
                Just unit ->
                    let
                        unitPlayerName : String
                        unitPlayerName =
                            model.players
                                |> ListUtil.find (\player -> player.playerNumber == unit.playerNumber)
                                |> Maybe.map .name
                                |> Maybe.withDefault ""

                        actions : List (Html Msg)
                        actions =
                            if Maybe.map .id (selectedUnit model) == Just unit.id then
                                [ movementView model ]

                            else
                                []

                        contents : List (Html Msg)
                        contents =
                            [ UnitStatus.toHtml unitPlayerName unit
                            , cargoView model unit
                            , supplyControls model unit
                            ]
                                ++ actions
                    in
                    [ ( UnitId.toString unit.id, inspectionRow (Unit.label unit) contents ) ]

                Nothing ->
                    []

        tileRows : List ( String, Html Msg )
        tileRows =
            case position of
                Just coordinate ->
                    let
                        coordinateKey : String
                        coordinateKey =
                            String.fromInt coordinate.x ++ "," ++ String.fromInt coordinate.y

                        depotRows : List ( String, Html Msg )
                        depotRows =
                            model.depots
                                |> List.filter (\depot -> depot.position == coordinate)
                                |> List.map depotRow

                        depotRow : Depot -> ( String, Html Msg )
                        depotRow depot =
                            ( "depot:" ++ coordinateKey
                            , inspectionRow (Depot.label depot) [ DepotStatus.toHtml depot ]
                            )

                        crateRows : List ( String, Html Msg )
                        crateRows =
                            model.supplyCrates
                                |> List.filter (\crate -> crate.position == coordinate)
                                |> List.indexedMap crateRow

                        crateRow : Int -> Supply.GroundCrate -> ( String, Html Msg )
                        crateRow index crate =
                            ( "crate:" ++ coordinateKey ++ ":" ++ Supply.cargoLabel crate.stock.kind ++ ":" ++ String.fromInt index
                            , inspectionRow (Supply.cargoLabel crate.stock.kind)
                                [ SupplyCrate.toHtml { lastSeen = not (List.member coordinate model.visibleTiles) } crate.stock ]
                            )

                        terrainRows : List ( String, Html Msg )
                        terrainRows =
                            [ ( "terrain:" ++ coordinateKey
                              , inspectionRow "terrain" [ terrainView model ]
                              )
                            ]
                    in
                    depotRows ++ crateRows ++ terrainRows

                Nothing ->
                    []

        rows : List ( String, Html Msg )
        rows =
            unitRows ++ tileRows
    in
    Keyed.node "section"
        [ Aria.label "selection"
        , A.css
            [ S.col
            , S.g3
            , S.shrink0
            ]
        ]
        rows


inspectionRow : String -> List (Html Msg) -> Html Msg
inspectionRow label contents =
    H.section
        [ Aria.label label
        , A.css
            [ S.col
            , S.g3
            , S.shrink0
            , S.borderB
            , S.borderGray2
            , S.pb2
            ]
        ]
        contents


panelFooter : Bool -> Html Msg
panelFooter hasSelection =
    let
        hint : String
        hint =
            if not hasSelection then
                "select a unit, depot or tile to inspect"

            else
                "esc to clear selection"
    in
    H.footer
        [ A.css
            [ S.col
            , S.g3
            , S.shrink0
            ]
        ]
        [ H.p
            [ A.css
                [ S.borderT
                , S.borderGray2
                , S.pt3
                , S.textGray4
                ]
            ]
            [ H.text hint
            ]
        ]


movementView : Model -> Html Msg
movementView model =
    let
        details : List (Html Msg)
        details =
            case selectedUnit model of
                Just unit ->
                    if not (isOwnUnit model unit) then
                        []

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
                                    Just (OrderPlanning.Crate index) ->
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

        content : List (Html Msg)
        content =
            details ++ feedback
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        content


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
                        |> Maybe.map (\planning -> planning.purpose == GamePage.Selection.AttackMove)
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
                                        ++ "): load "
                                        ++ String.fromInt (PlannedOrder.loadingCrates supply)
                                        ++ " · unload "
                                        ++ String.fromInt (List.length (PlannedOrder.unloadingCrates supply))

                                PlannedOrder.IndirectFire fire ->
                                    "indirect fire: (" ++ String.fromInt fire.target.x ++ ", " ++ String.fromInt fire.target.y ++ ")"

                                PlannedOrder.StandGround facing ->
                                    "stand ground: " ++ Direction.label facing.direction

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
                    , Button.primary "revoke order" ClearMoveClicked
                        |> Button.toHtml
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


plannedStationaryFacing : Model -> Unit -> Unit
plannedStationaryFacing model unit =
    case ListUtil.find (\order -> order.unitId == unit.id) (plannedOrders model) of
        Just order ->
            case order.action of
                PlannedOrder.Ambush facing ->
                    Unit.faceDirection (Just facing.direction) unit

                PlannedOrder.StandGround facing ->
                    Unit.faceDirection (Just facing.direction) unit

                _ ->
                    unit

        Nothing ->
            unit


choosingAmbush : Model -> Bool
choosingAmbush model =
    case currentSelection model of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingDirection AmbushPurpose _ ->
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
                ChoosingDirection StandGroundPurpose _ ->
                    True

                _ ->
                    False

        _ ->
            False


unitIsAmbushing : Model -> Unit -> Bool
unitIsAmbushing model unit =
    let
        previewingAmbush : Bool
        previewingAmbush =
            choosingAmbush model && Maybe.map .unitId (rotationSelection model) == Just unit.id

        ambushOrder : PlannedOrder -> Bool
        ambushOrder order =
            case order.action of
                PlannedOrder.Ambush _ ->
                    order.unitId == unit.id

                _ ->
                    False

        ambushEvent : Turn.Event -> Bool
        ambushEvent event =
            event.unitId == unit.id && event.kind == TurnEventKind.Ambush
    in
    case model.currentTurn.phase of
        TurnLifecycle.Playing _ ->
            model.currentTurn.resolution
                |> Maybe.map (\resolution -> List.any ambushEvent resolution.events)
                |> Maybe.withDefault False

        _ ->
            previewingAmbush || List.any ambushOrder (plannedOrders model)


ambushCosts : Unit -> PlannedOrder -> List (Html Msg)
ambushCosts unit order =
    case order.action of
        PlannedOrder.IndirectFire _ ->
            indirectFireDetails unit

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
    case OrderPlanning.loadingTarget (planningContext model) unit destination (plannedOrders model) of
        Just target ->
            let
                notice : String
                notice =
                    if unit.kind == UnitKind.Truck then
                        "this move will pick up " ++ Unit.label target ++ " into this truck. the passenger will hold position."

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


viewControls : Int -> Html Msg
viewControls zoomPercent =
    H.section
        [ Aria.label "view controls"
        , A.css
            [ S.row
            , S.flexWrap
            , S.itemsCenter
            , S.g3
            ]
        ]
        [ H.div
            [ Aria.role Aria.Group
            , Aria.label "pan map"
            , A.css
                [ S.col
                , S.itemsCenter
                , S.g1
                ]
            ]
            [ panButton "↑" "pan up" PanUpClicked
            , H.div
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.g1
                    ]
                ]
                [ panButton "←" "pan left" PanLeftClicked
                , H.span
                    []
                    [ H.text "pan" ]
                , panButton "→" "pan right" PanRightClicked
                ]
            , panButton "↓" "pan down" PanDownClicked
            ]
        , H.div
            [ Aria.role Aria.Group
            , Aria.label "zoom map"
            , A.css
                [ S.col
                , S.itemsCenter
                , S.g1
                ]
            ]
            [ H.span
                []
                [ H.text "zoom" ]
            , H.div
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.g2
                    ]
                ]
                [ Button.secondary "−" ZoomOutClicked
                    |> Button.accessibleLabel "zoom out"
                    |> Button.toHtml
                , H.span
                    []
                    [ H.text (String.fromInt zoomPercent ++ "%") ]
                , Button.secondary "+" ZoomInClicked
                    |> Button.accessibleLabel "zoom in"
                    |> Button.toHtml
                ]
            , Button.secondary "reset view" ResetViewClicked
                |> Button.toHtml
            ]
        ]


panButton : String -> String -> Msg -> Html Msg
panButton arrow label msg =
    Button.secondary arrow msg
        |> Button.accessibleLabel label
        |> Button.toHtml


terrainView : Model -> Html Msg
terrainView model =
    let
        position : Maybe Coordinate
        position =
            case selectedUnit model of
                Just unit ->
                    Unit.physicalPosition model.units unit

                Nothing ->
                    inspectionPosition model
    in
    case position of
        Just coordinate ->
            Keyed.node "div"
                []
                [ ( String.fromInt coordinate.x ++ "," ++ String.fromInt coordinate.y
                  , TerrainInfo.toHtml model.map.theme (Map.terrainAt model.map coordinate)
                  )
                ]

        Nothing ->
            H.text ""


supplyControls : Model -> Unit -> Html Msg
supplyControls model unit =
    let
        crates : List Supply.CargoStock
        crates =
            unit.resources
                |> Maybe.map .supplyCargo
                |> Maybe.withDefault []

        unloads : List PlannedOrder.CrateUnload
        unloads =
            plannedOrders model
                |> ListUtil.find (\order -> order.unitId == unit.id)
                |> Maybe.map PlannedOrder.crateUnloads
                |> Maybe.withDefault []

        contents : List (Html Msg)
        contents =
            let
                crateControls : Int -> Supply.CargoStock -> Html Msg
                crateControls index stock =
                    let
                        selectedExit : Maybe Coordinate
                        selectedExit =
                            ListUtil.find (\unload -> unload.cargoIndex == index) unloads
                                |> Maybe.map .destination

                        pending : String
                        pending =
                            selectedExit
                                |> Maybe.map unloadDescription
                                |> Maybe.withDefault ""

                        unloadDescription : Coordinate -> String
                        unloadDescription exit =
                            " · unload at ("
                                ++ String.fromInt exit.x
                                ++ ", "
                                ++ String.fromInt exit.y
                                ++ ")"

                        crateContents : List (Html Msg)
                        crateContents =
                            [ H.p
                                []
                                [ H.text (Supply.cargoLabel stock.kind ++ " " ++ String.fromInt (index + 1) ++ ": " ++ String.fromInt stock.current ++ "/" ++ String.fromInt stock.maximum ++ pending)
                                ]
                            ]
                    in
                    H.div
                        [ A.css
                            [ S.col
                            , S.g1
                            ]
                        ]
                        crateContents

                replenishmentNote : Html Msg
                replenishmentNote =
                    H.p
                        []
                        [ H.text "supplies refill provisions; fuel drums refill vehicles before upkeep, while stock lasts"
                        ]

                crateRows : List (Html Msg)
                crateRows =
                    List.indexedMap crateControls crates
            in
            replenishmentNote :: crateRows

        canInspectSupplyCargo : Bool
        canInspectSupplyCargo =
            isOwnUnit model unit && unit.kind == UnitKind.Truck
    in
    if canInspectSupplyCargo then
        H.div
            [ A.css
                [ S.col
                , S.g2
                ]
            ]
            contents

    else
        H.text ""


cargoView : Model -> Unit -> Html Msg
cargoView model unit =
    let
        cargo : List Unit
        cargo =
            List.filter (\passenger -> Unit.carrierId passenger == Just unit.id) model.units

        passengerRow : Unit -> Html Msg
        passengerRow passenger =
            CargoPassenger.toHtml
                { onSelect = CargoUnitClicked passenger.id }
                passenger

        passengerList : List (Html Msg)
        passengerList =
            if List.isEmpty cargo then
                []

            else
                [ H.div
                    [ A.css
                        [ S.col
                        , S.g2
                        , S.p2
                        , S.bgNightwood3
                        , S.indentStrong
                        ]
                    ]
                    (List.map passengerRow cargo)
                ]

        cargoSummary : Html Msg
        cargoSummary =
            H.p
                []
                [ H.text ("cargo: " ++ String.fromInt (List.length cargo + Unit.crateCount unit) ++ "/" ++ String.fromInt unit.cargoCapacity)
                ]

        cargoContents : List (Html Msg)
        cargoContents =
            cargoSummary :: passengerList

        canInspectCargo : Bool
        canInspectCargo =
            isOwnUnit model unit && unit.cargoCapacity > 0
    in
    if canInspectCargo then
        H.div
            [ A.css
                [ S.col
                , S.g2
                ]
            ]
            cargoContents

    else
        H.text ""


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
            List.filter (\unit -> Unit.carrierId unit == Just choice.truck.truckId) model.units

        unavailable : OrderPlanning.Cargo -> Bool
        unavailable cargo =
            not (OrderPlanning.canSelectUnloadCargo (planningContext model) cargo (OrderPlanning.ChoosingPassengers choice))

        passengerCheckbox : Unit -> Html Msg
        passengerCheckbox unit =
            UnloadPassenger.toHtml
                { disabled = unavailable (OrderPlanning.Passenger unit.id)
                , checked = List.member (OrderPlanning.Passenger unit.id) choice.checked
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
                |> ListUtil.find (\unit -> unit.id == choice.truck.truckId)
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
            Checkbox.toHtmlDisabled (unavailable (OrderPlanning.Crate index))
                { label = label
                , checked = List.member (OrderPlanning.Crate index) choice.checked
                , onCheck = UnloadCrateToggled index
                }
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
                    List.any (\unit -> unavailable (OrderPlanning.Passenger unit.id)) passengers
                        || (model.units
                                |> ListUtil.find
                                    (\unit -> unit.id == choice.truck.truckId)
                                |> Maybe.map
                                    (\truck ->
                                        List.range 0 (Unit.crateCount truck - 1)
                                            |> List.any (OrderPlanning.Crate >> unavailable)
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
    Dialog.make unloadDialogHtmlId "unload" DialogDismissed content


depotLoadingDialog : Model -> UnitId -> Dialog Msg
depotLoadingDialog model id =
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
            plannedDepot model id
                |> Maybe.map (.kind >> Supply.cargoPlural)
                |> Maybe.withDefault "cargo"

        choice : Int -> Html Msg
        choice count =
            if count > room then
                Button.disabled (String.fromInt count)
                    |> Button.toHtml

            else
                Button.secondary (String.fromInt count) (LoadCratesClicked id count)
                    |> Button.toHtml

        actions : Html Msg
        actions =
            H.form
                [ A.attribute "method" "dialog"
                , A.css
                    [ S.row
                    , S.g2
                    ]
                ]
                (List.range 0 2
                    |> List.map choice
                )
    in
    Dialog.make loadCratesDialogHtmlId
        ("load " ++ cargoLabel)
        DialogDismissed
        [ H.p
            []
            [ H.text "how many loads should the truck take from this depot?"
            ]
        , actions
        ]


{-| Dialogs derive from the command guide, turn introduction, playback loss, or the active planning workflow.
-}
dialog : Model -> Maybe (Dialog Msg)
dialog model =
    MaybeUtil.lazyFirst
        [ commandGuideDialog model
        , introductionDialog model
        , lossDialog model
        , planningDialog model
        ]


commandGuideDialog : Model -> () -> Maybe (Dialog Msg)
commandGuideDialog model _ =
    if commandGuideOpen model then
        Just (CommandGuide.dialog DialogDismissed)

    else
        Nothing


introductionDialog : Model -> () -> Maybe (Dialog Msg)
introductionDialog model _ =
    if showTurnIntroduction model then
        TurnIntroduction.dialog { turnNumber = model.currentTurn.number, skipDialogs = model.skipTurnIntroduction, previousTurn = model.currentTurn.resolution }
            |> Dialog.map TurnIntroductionMsg
            |> Just

    else
        Nothing


lossDialog : Model -> () -> Maybe (Dialog Msg)
lossDialog model _ =
    let
        notice : TurnPlayback.Loss -> Dialog Msg
        notice loss =
            UnitDeath.dialog
                { skipDialogs = model.skipUnitLossDialogs
                , isOwn = isOwnUnit model loss.unit
                , details = UnitLoss.resolve (ownerName model) loss
                , passengers =
                    playback model
                        |> Maybe.andThen TurnPlayback.lossEvent
                        |> Maybe.map .passengers
                        |> Maybe.withDefault []
                }
                loss
                |> Dialog.map UnitDeathMsg
    in
    unitLoss model
        |> Maybe.map notice


planningDialog : Model -> () -> Maybe (Dialog Msg)
planningDialog model _ =
    case model.currentTurn.phase of
        TurnLifecycle.Planning (OrderPlanning.ConfirmingSubmission _) ->
            Just (submissionWarning model)

        TurnLifecycle.Planning (OrderPlanning.ChoosingPassengers choice) ->
            Just (unloadChecklist model choice)

        TurnLifecycle.Planning (OrderPlanning.ChoosingCrates id _) ->
            Just (depotLoadingDialog model id)

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
        DialogDismissed
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
                , S.g3
                ]
            ]
            [ Button.secondary "keep planning" DialogDismissed
                |> Button.toHtml
            , Button.primary "submit anyway" SubmissionConfirmed
                |> Button.toHtml
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

        submitLocked : Bool
        submitLocked =
            planningLocked model || isChoosingUnload model || choosingDirection model

        activity : TurnControls.Activity
        activity =
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

        zoomPercent : Int
        zoomPercent =
            round ((BattlefieldNavigation.camera model.navigation).zoom * 100)
    in
    TurnControls.panel
        [ Lazy.lazy3 turnSubmit model.currentTurn.number activity submitLabel
        , Lazy.lazy4 turnFeedback model.players ownStatus opponentStatus model.currentTurn.error
        , TurnControls.navigation (Lazy.lazy viewControls zoomPercent)
        ]


turnSubmit : Int -> TurnControls.Activity -> String -> Html Msg
turnSubmit number activity submitLabel =
    H.div
        [ A.css
            [ S.col
            , S.g2
            , S.shrink0
            ]
        ]
        [ H.p
            []
            [ H.text ("turn " ++ String.fromInt number) ]
        , TurnControls.submit activity submitLabel
            |> H.map TurnControlsMsg
        ]


turnFeedback : List Player -> String -> String -> Maybe String -> Html Msg
turnFeedback players ownStatus opponentStatus error =
    let
        playerRow : Player -> Html Msg
        playerRow player =
            let
                status : String
                status =
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
                        , S.g2
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


battlefieldView : Model -> Html Msg
battlefieldView model =
    let
        camera : Camera
        camera =
            BattlefieldNavigation.camera model.navigation

        cameraTransform : String
        cameraTransform =
            case playback model of
                Just playing ->
                    Camera.focusTransform model.map (TurnPlayback.focusPositions playing) camera

                Nothing ->
                    Camera.transform camera

        cursorStyle : Css.Style
        cursorStyle =
            if BattlefieldNavigation.active model.navigation then
                S.grabbingCursor

            else if choosingIndirectFire model then
                S.crosshairCursor

            else
                S.grabCursor
    in
    H.div
        [ A.attribute "tabindex" "0"
        , Aria.label "battlefield navigation"
        , A.css
            [ S.relative
            , S.flex1
            , S.minW0
            , S.hFull
            , S.row
            , S.itemsCenter
            , S.justifyCenter
            , S.overflowHidden
            , S.userSelectNone
            , S.containerSize
            , cursorStyle
            ]
        , HtmlEvents.on "mousedown" mousePressedDecoder
        , HtmlEvents.preventDefaultOn "wheel"
            (Decode.map preventDefault wheelScrolledDecoder)
        , HtmlEvents.preventDefaultOn "keydown"
            (Decode.map preventDefault navigationKeyDecoder)
        ]
        [ H.div
            [ A.css
                [ S.relative
                , S.widthValue Camera.boardWidth
                , S.shrink0
                , S.transform
                    cameraTransform
                , Css.Global.descendants
                    [ Css.Global.selector "rect"
                        [ S.outlineNone
                        , S.focusVisible
                            [ S.outlineYellow5HalfPixel
                            , S.outlineOffsetNeg1
                            , S.rounded0
                            ]
                        ]
                    ]
                ]
            ]
            [ boardSvg model
                |> H.fromUnstyled
            ]
        , commandMenu model
        ]


at : Coordinate -> List (Svg msg) -> Svg msg
at position children =
    Svg.g
        [ SA.transform ("translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")")
        ]
        children


boardSvg : Model -> Svg Msg
boardSvg model =
    let
        rotationPreview : Maybe RotationSelection
        rotationPreview =
            rotationSelection model

        visibleTiles : List Coordinate
        visibleTiles =
            model.visibleTiles

        visiblePositions : Set Coordinate.Key
        visiblePositions =
            Set.fromList (List.map Coordinate.key visibleTiles)

        choosingDestination : Bool
        choosingDestination =
            pathPreview model /= Nothing || isChoosingUnload model || choosingIndirectFire model

        targeting : BoardTargeting
        targeting =
            if choosingIndirectFire model then
                ChoosingIndirectTarget

            else if choosingDestination then
                ChoosingBoardDestination

            else
                InspectingBoard

        options : List Movement.Option
        options =
            moveOptions model

        indirectRange : Int
        indirectRange =
            if choosingIndirectFire model then
                selectedUnit model
                    |> Maybe.map (.combatRules >> .indirectRange)
                    |> Maybe.withDefault 0

            else
                0

        indirectOrigin : Coordinate
        indirectOrigin =
            if choosingIndirectFire model then
                selectedPosition model |> Maybe.withDefault inactiveTargetOrigin

            else
                inactiveTargetOrigin

        reachable : List Coordinate
        reachable =
            List.map .destination options ++ indirectTargets model

        reachablePositions : Set Coordinate.Key
        reachablePositions =
            Set.fromList (List.map Coordinate.key reachable)

        paths : List PlannedOrder
        paths =
            plannedOrders model

        attacking : Bool
        attacking =
            TurnLifecycle.planning model.currentTurn.phase
                |> Maybe.andThen OrderPlanning.movementPlanning
                |> Maybe.map (\planning -> planning.purpose == GamePage.Selection.AttackMove)
                |> Maybe.withDefault False

        destinationAction : String
        destinationAction =
            if choosingIndirectFire model then
                "fire indirectly at"

            else if isChoosingUnload model then
                "unload at"

            else if attacking then
                "attack move to"

            else
                "move to"

        previewPurpose : MovementRoute.Purpose
        previewPurpose =
            case currentSelection model of
                Just (UnitSelection { interaction }) ->
                    case interaction of
                        ChoosingAttackDirection _ direction ->
                            MovementRoute.DirectedAttack direction

                        _ ->
                            if attacking then
                                MovementRoute.Attack

                            else
                                MovementRoute.Travel

                _ ->
                    MovementRoute.Travel

        orderedUnits : List UnitId
        orderedUnits =
            List.map .unitId (plannedOrders model)

        unloads : List UnloadRoute
        unloads =
            plannedUnloadRoutes model

        previewedPath : List Coordinate
        previewedPath =
            case currentSelection model of
                Just (UnitSelection { interaction }) ->
                    case interaction of
                        ChoosingAttackDirection move _ ->
                            move.path

                        _ ->
                            pathPreview model |> Maybe.map .path |> Maybe.withDefault []

                _ ->
                    []

        movingPositions : List { unitId : UnitId, position : Point }
        movingPositions =
            TurnPlayback.movingPositions (playback model)

        selected : Maybe Coordinate
        selected =
            selectedPosition model

        terrain : Svg Msg
        terrain =
            let
                destinationSelection : Maybe Coordinate
                destinationSelection =
                    if choosingDestination then
                        selected

                    else
                        Nothing
            in
            -- Unwrap Maybe before lazy: its wrapper may be fresh, while the
            -- coordinate stored in selection or unit location is persistent.
            case destinationSelection of
                Just position ->
                    SvgLazy.lazy7 selectedTerrainLayer
                        model.map
                        visibleTiles
                        options
                        indirectOrigin
                        indirectRange
                        targeting
                        position

                Nothing ->
                    SvgLazy.lazy6 unselectedTerrainLayer
                        model.map
                        visibleTiles
                        options
                        indirectOrigin
                        indirectRange
                        targeting

        terrainFilter : Coordinate -> String
        terrainFilter =
            boardTileFilter visiblePositions choosingDestination reachablePositions selected

        targetOutline : Coordinate -> Svg Msg
        targetOutline destination =
            at destination
                [ Svg.rect
                    [ SA.x "1"
                    , SA.y "1"
                    , SA.width "14"
                    , SA.height "14"
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "0.5"
                    , SA.strokeDasharray "1 1"
                    , SA.pointerEvents "none"
                    , Aria.svgHidden True
                    ]
                    []
                ]

        crateView : Supply.GroundCrate -> Svg Msg
        crateView crate =
            SvgLazy.lazy3 boardCrate
                (terrainFilter crate.position)
                (Set.member (Coordinate.key crate.position) visiblePositions)
                crate

        depotView : Depot -> Svg Msg
        depotView depot =
            SvgLazy.lazy2 boardDepot (terrainFilter depot.position) depot

        depotStockView : Depot -> Maybe (Svg Msg)
        depotStockView depot =
            let
                stockView : Supply.Stock -> Svg Msg
                stockView stock =
                    at depot.position
                        [ DepotStock.toSvg stock |> StyledSvg.toUnstyled
                        , Svg.rect
                            [ SA.x "0.4"
                            , SA.y "12.4"
                            , SA.width "15.2"
                            , SA.height "3.4"
                            , SA.fill "transparent"
                            , SA.class "fightlines-depot-stock-target"
                            , HA.style "--depot-focus-color" S.yellow5Str
                            , HA.attribute "tabindex" "0"
                            , Aria.svgRole Aria.Button
                            , Aria.svgLabel (DepotStock.label depot stock)
                            , Ev.onMouseOver (MouseOverDepot depot.position)
                            , Ev.on "focus" (Decode.succeed (FocusedBoardTile depot.position))
                            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
                            , onClickWithDetail (ClickedDepotStock depot.position)
                            , onBoardActivationKeyDown
                                { pressedEnter = PressedEnterOnDepotStock depot.position
                                , pressedSpace = PressedSpaceOnDepotStock depot.position
                                }
                            ]
                            [ Svg.title [] [ Svg.text (DepotStock.label depot stock) ]
                            ]
                        ]
            in
            Maybe.map stockView depot.stock

        previewedUnit : Unit -> Unit
        previewedUnit unit =
            case rotationPreview of
                Just rotation ->
                    if rotation.unitId == unit.id then
                        Unit.faceDirection (Just rotation.direction) unit

                    else
                        plannedStationaryFacing model unit

                Nothing ->
                    plannedStationaryFacing model unit

        unitTransform : Unit -> Coordinate -> String
        unitTransform unit position =
            case
                ListUtil.find
                    (\moving -> moving.unitId == unit.id)
                    movingPositions
            of
                Just moving ->
                    "translate("
                        ++ String.fromFloat (moving.position.x * 16)
                        ++ " "
                        ++ String.fromFloat (moving.position.y * 16)
                        ++ ")"

                Nothing ->
                    "translate("
                        ++ String.fromInt (position.x * 16)
                        ++ " "
                        ++ String.fromInt (position.y * 16)
                        ++ ")"

        facingView : Unit -> Maybe (Svg Msg)
        facingView unit =
            let
                facingClass : String
                facingClass =
                    if Maybe.map .unitId rotationPreview == Just unit.id then
                        "fightlines-rotation-preview"

                    else
                        ""

                markerAt : Coordinate -> Svg Msg
                markerAt position =
                    Svg.g
                        [ SA.transform (unitTransform unit position)
                        , SA.opacity (String.fromFloat (TurnPlayback.unitOpacity (playback model) unit.id))
                        , SA.class facingClass
                        , SA.pointerEvents "none"
                        ]
                        [ UnitFacing.toSvg (selected == Just position) (previewedUnit unit)
                            |> StyledSvg.toUnstyled
                        ]
            in
            if unitIsAmbushing model unit then
                Unit.boardPosition unit |> Maybe.map markerAt

            else
                Nothing

        facingOverlay : List (Svg Msg)
        facingOverlay =
            List.filterMap facingView model.units

        spotlightOverlay : List (Svg Msg)
        spotlightOverlay =
            playback model
                |> Maybe.andThen TurnPlayback.spotlight
                |> Maybe.map (spotlightView >> List.singleton)
                |> Maybe.withDefault []

        spotlightView : List Coordinate -> Svg Msg
        spotlightView positions =
            if
                (playback model
                    |> Maybe.andThen TurnPlayback.panels
                    |> Maybe.map .mapView
                )
                    == Just TurnPlayback.SeeingMap
            then
                CombatEffects.mapPeek model.map positions

            else
                CombatEffects.spotlight model.map positions

        lossSpotlight : TurnPlayback.Loss -> List (Svg Msg)
        lossSpotlight loss =
            [ UnitDeath.spotlight model.map model.units loss
                |> StyledSvg.toUnstyled
            ]

        lossOverlay : List (Svg Msg)
        lossOverlay =
            unitLoss model
                |> Maybe.map lossSpotlight
                |> Maybe.withDefault []

        unitView : Unit -> Coordinate -> Svg Msg
        unitView unit position =
            let
                aboardThisTruck : Unit -> Bool
                aboardThisTruck passenger =
                    Unit.carrierId passenger == Just unit.id

                passengerCount : Int
                passengerCount =
                    if unit.kind == UnitKind.Truck then
                        List.length (List.filter aboardThisTruck model.units)

                    else
                        0
            in
            Svg.g
                [ SA.opacity (String.fromFloat (TurnPlayback.unitOpacity (playback model) unit.id)) ]
                [ SvgLazy.lazy6 boardUnit
                    unit
                    (previewedUnit unit).spriteFacing
                    (unitTransform unit position)
                    (List.member unit.id orderedUnits)
                    passengerCount
                    (AnimationFrame.unitColumn model.frame unit.id)
                ]

        pathPoint : Coordinate -> String
        pathPoint position =
            String.fromInt (position.x * 16 + 8)
                ++ ","
                ++ String.fromInt (position.y * 16 + 8)

        pathPoints : List Coordinate -> String
        pathPoints path =
            path
                |> List.map pathPoint
                |> String.join " "

        unloadRoute : UnloadRoute -> Svg Msg
        unloadRoute route =
            let
                destination : Coordinate
                destination =
                    Direction.step route.origin route.direction
            in
            Svg.g
                []
                [ Svg.polyline
                    [ SA.points (pathPoints [ route.origin, destination ])
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "1.25"
                    ]
                    []
                , at destination
                    [ Svg.polygon
                        [ SA.points "8,5 11,8 8,11 5,8"
                        , SA.fill S.nightwood2Str
                        , SA.stroke S.yellow5Str
                        , SA.strokeWidth "1.25"
                        ]
                        []
                    ]
                ]

        unloadOverlay : Svg Msg
        unloadOverlay =
            Svg.g
                [ SA.pointerEvents "none"
                , Aria.svgHidden True
                , HA.attribute "data-planned-unloads" (String.fromInt (List.length unloads))
                ]
                (List.map unloadRoute unloads)

        ambushCoverage : List (Svg Msg)
        ambushCoverage =
            let
                saved : PlannedOrder -> Maybe (Svg Msg)
                saved order =
                    case order.action of
                        PlannedOrder.Ambush facing ->
                            ListUtil.find (\unit -> unit.id == order.unitId) model.units
                                |> Maybe.map (\unit -> Ambush.coverage model.map facing.position facing.direction unit.combatRules)

                        _ ->
                            Nothing

                preview : List (Svg Msg)
                preview =
                    case ( currentSelection model, selectedUnit model ) of
                        ( Just (UnitSelection { interaction }), Just unit ) ->
                            case interaction of
                                ChoosingDirection AmbushPurpose direction ->
                                    Unit.boardPosition unit
                                        |> Maybe.map (\position -> [ Ambush.coverage model.map position direction unit.combatRules ])
                                        |> Maybe.withDefault []

                                _ ->
                                    []

                        _ ->
                            []
            in
            List.filterMap saved (plannedOrders model) ++ preview

        targetPreview : List (Svg Msg)
        targetPreview =
            TurnLifecycle.planning model.currentTurn.phase
                |> Maybe.andThen OrderPlanning.indirectTargetPreview
                |> Maybe.map (\position -> [ at position [ TargetSight.toSvg TargetSight.Preview ] ])
                |> Maybe.withDefault []

        indirectFireOverlay : Svg Msg
        indirectFireOverlay =
            let
                targetMarker : PlannedOrder -> Maybe ( String, Svg Msg )
                targetMarker order =
                    case order.action of
                        PlannedOrder.IndirectFire fire ->
                            let
                                sightState : TargetSight.State
                                sightState =
                                    if Maybe.map .id (selectedUnit model) == Just order.unitId then
                                        TargetSight.Saved

                                    else
                                        TargetSight.SavedInactive
                            in
                            Just
                                ( UnitId.toString order.unitId ++ ":" ++ String.fromInt fire.target.x ++ "," ++ String.fromInt fire.target.y
                                , at fire.target [ TargetSight.toSvg sightState ]
                                )

                        _ ->
                            Nothing
            in
            SvgKeyed.node "g"
                [ Aria.svgHidden True
                , SA.pointerEvents "none"
                ]
                (List.filterMap targetMarker paths)

        shotOverlay : Svg Msg
        shotOverlay =
            case model.currentTurn.phase of
                TurnLifecycle.Playing playing ->
                    CombatEffects.impacts
                        (TurnPlayback.visibleIndirectImpacts playing.animation)
                        model.units
                        (TurnPlayback.visibleShots playing.animation)

                _ ->
                    Svg.text ""

        rotationOverlay : List (Svg Msg)
        rotationOverlay =
            case rotationPreview of
                Just rotation ->
                    [ directionChoices model.map rotation.position rotation.direction
                        |> Svg.map RotationChoicesMsg
                    ]

                Nothing ->
                    []

        directionChoices : Map -> Coordinate -> Direction -> Svg RotationChoices.Msg
        directionChoices =
            RotationChoices.ambushToSvg

        selection : List (Svg Msg)
        selection =
            selected
                |> Maybe.map selectionMarker
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    Svg.svg
        [ SA.viewBox
            ("0 0 "
                ++ String.fromInt (model.map.width * 16)
                ++ " "
                ++ String.fromInt (model.map.height * 16)
            )
        , SA.width "100%"
        , HA.style "display" "block"
        , Aria.svgRole Aria.Group
        , Aria.svgLabel "battlefield"
        , Ev.on "mouseleave" (Decode.succeed TargetPreviewLeft)
        ]
        (List.concat
            [ [ terrain
              , SvgLazy.lazy8 movementLayer
                    model.map
                    options
                    indirectOrigin
                    indirectRange
                    targeting
                    paths
                    previewPurpose
                    previewedPath
              ]
            , [ SvgLazy.lazy6 tileTargets
                    model.map
                    options
                    indirectOrigin
                    indirectRange
                    targeting
                    destinationAction
              ]
            , List.map depotView model.depots
            , List.map crateView model.supplyCrates
            , List.concatMap (PlannedOrder.crateUnloads >> List.map (.destination >> targetOutline)) (plannedOrders model)
            , List.filterMap
                (\unit ->
                    Unit.boardPosition unit
                        |> Maybe.map (unitView unit)
                )
                model.units
            , ambushCoverage
            , [ unloadOverlay, shotOverlay ]
            , selection
            , rotationOverlay
            , facingOverlay
            , List.filterMap depotStockView model.depots
            , [ indirectFireOverlay ]
            , targetPreview
            , spotlightOverlay
            , lossOverlay
            ]
        )


{-| Map.positions allocates coordinates each view; compare their components at lazy boundaries.
-}
boardTileTarget : String -> Bool -> Int -> Int -> Svg Msg
boardTileTarget destinationAction reachable x y =
    let
        position : Coordinate
        position =
            { x = x, y = y }

        baseAttributes : List (Svg.Attribute Msg)
        baseAttributes =
            [ SA.width "16"
            , SA.height "16"
            , SA.fill "transparent"
            , SA.stroke S.nightwood2Str
            , SA.strokeOpacity "0.22"
            , SA.strokeWidth "0.25"
            , Ev.onMouseOver (MouseOverTile position)
            , Ev.on "focus" (Decode.succeed (FocusedBoardTile position))
            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
            , onClickWithDetail (ClickedTile position)
            ]

        movementAttributes : List (Svg.Attribute Msg)
        movementAttributes =
            if reachable then
                [ HA.attribute "tabindex" "0"
                , Aria.svgRole Aria.Button
                , Aria.svgLabel
                    (destinationAction
                        ++ " ("
                        ++ String.fromInt position.x
                        ++ ", "
                        ++ String.fromInt position.y
                        ++ ")"
                    )
                , onBoardActivationKeyDown
                    { pressedEnter = PressedEnterOnTile position
                    , pressedSpace = PressedSpaceOnTile position
                    }
                ]

            else
                []
    in
    at position
        [ Svg.rect
            (baseAttributes ++ movementAttributes)
            []
        ]


boardCrate : String -> Bool -> Supply.GroundCrate -> Svg Msg
boardCrate filter visible crate =
    let
        label : String
        label =
            if visible then
                Supply.cargoLabel crate.stock.kind

            else
                Supply.cargoLabel crate.stock.kind ++ " · last seen"
    in
    at crate.position
        [ Svg.g
            [ HA.style "filter" filter ]
            [ SupplyCrate.toSvg crate.stock.kind ]
        , Svg.rect
            [ SA.width "16"
            , SA.height "16"
            , SA.fill "transparent"
            , HA.attribute "tabindex" "0"
            , Aria.svgRole Aria.Button
            , Aria.svgLabel label
            , Ev.onMouseOver (MouseOverTile crate.position)
            , Ev.on "focus" (Decode.succeed (FocusedBoardTile crate.position))
            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
            , onClickWithDetail (ClickedTile crate.position)
            , onBoardActivationKeyDown
                { pressedEnter = PressedEnterOnTile crate.position
                , pressedSpace = PressedSpaceOnTile crate.position
                }
            ]
            []
        ]


boardDepot : String -> Depot -> Svg Msg
boardDepot filter depot =
    at depot.position
        [ Svg.image
            [ SA.width "16"
            , SA.height "16"
            , SA.xlinkHref (Depot.image depot)
            , HA.style "filter" filter
            , HA.style "image-rendering" "auto"
            , SA.pointerEvents "none"
            , Aria.svgHidden True
            ]
            []
        , Svg.rect
            [ SA.width "16"
            , SA.height "16"
            , SA.fill "transparent"
            , HA.attribute "tabindex" "0"
            , Aria.svgRole Aria.Button
            , Aria.svgLabel (Depot.label depot)
            , Ev.onMouseOver (MouseOverDepot depot.position)
            , Ev.on "focus" (Decode.succeed (FocusedBoardTile depot.position))
            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
            , onClickWithDetail (ClickedDepot depot.position)
            , onBoardActivationKeyDown
                { pressedEnter = PressedEnterOnDepot depot.position
                , pressedSpace = PressedSpaceOnDepot depot.position
                }
            ]
            [ Svg.title
                []
                [ Svg.text (Depot.label depot)
                ]
            ]
        ]


boardUnit : Unit -> SpriteFacing -> String -> Bool -> Int -> Int -> Svg Msg
boardUnit unit facing transform ordered passengerCount column =
    let
        crateCount : Int
        crateCount =
            if unit.kind == UnitKind.Truck then
                Unit.crateCount unit

            else
                0

        cargoCount : Int
        cargoCount =
            passengerCount + crateCount

        freight : List Supply.CargoStock
        freight =
            unit.resources
                |> Maybe.map .supplyCargo
                |> Maybe.withDefault []

        cargoLabel : String
        cargoLabel =
            if cargoCount > 0 then
                Unit.label unit
                    ++ ", cargo: "
                    ++ String.fromInt cargoCount
                    ++ " / "
                    ++ String.fromInt unit.cargoCapacity
                    ++ ", passengers: "
                    ++ String.fromInt passengerCount
                    ++ ", freight: "
                    ++ String.fromInt crateCount

            else
                Unit.label unit

        warningLabel : String
        warningLabel =
            UnitWarnings.label unit

        accessibleLabel : String
        accessibleLabel =
            if String.isEmpty warningLabel then
                cargoLabel

            else
                cargoLabel ++ ", " ++ warningLabel

        spriteFilter : String
        spriteFilter =
            if ordered then
                "brightness(0.6)"

            else
                "none"
    in
    Svg.g
        [ SA.transform transform
        ]
        [ Svg.g
            [ HA.style "filter" spriteFilter
            ]
            [ { unit | spriteFacing = facing }
                |> UnitSprite.toSvg
                    column
                |> StyledSvg.toUnstyled
            ]
        , UnitCargo.toSvg passengerCount
            |> StyledSvg.toUnstyled
        , UnitCargo.freightToSvg freight
            |> StyledSvg.toUnstyled
        , UnitWarnings.toSvg unit
            |> StyledSvg.toUnstyled
        , UnitDeath.toSvg unit
            |> StyledSvg.toUnstyled
        , Svg.rect
            [ SA.width "16"
            , SA.height "16"
            , SA.fill "transparent"
            , HA.attribute "tabindex" "0"
            , Aria.svgRole Aria.Button
            , Aria.svgLabel accessibleLabel
            , Ev.onMouseOver (MouseOverUnit unit.id)
            , Ev.on "focus" (Decode.succeed (FocusedBoardUnit unit.id))
            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
            , onClickWithDetail (ClickedUnit unit.id)
            , onBoardActivationKeyDown
                { pressedEnter = PressedEnterOnUnit unit.id
                , pressedSpace = PressedSpaceOnUnit unit.id
                }
            ]
            [ Svg.title
                []
                [ Svg.text accessibleLabel
                ]
            ]
        ]


boardTerrainTile : Map -> String -> Bool -> Int -> Int -> Svg Msg
boardTerrainTile map filter visible x y =
    let
        position : Coordinate
        position =
            { x = x, y = y }

        fogAttributes : List (Svg.Attribute Msg)
        fogAttributes =
            if visible then
                []

            else
                [ HA.attribute "data-fog" "unseen"
                ]

        appearanceAttributes : List (Svg.Attribute Msg)
        appearanceAttributes =
            [ HA.style "filter" filter
            , SA.pointerEvents "none"
            ]
    in
    Svg.g
        (appearanceAttributes ++ fogAttributes)
        [ at position
            [ SvgLazy.lazy2 terrainArtwork map.theme (Map.terrainAt map position)
            ]
        ]


{-| A shared origin keeps the inactive targeting argument stable as well.
Its coordinates are ignored unless indirect targeting is enabled.
-}
inactiveTargetOrigin : Coordinate
inactiveTargetOrigin =
    { x = 0, y = 0 }


boardIndirectTargets : Map -> Coordinate -> Int -> BoardTargeting -> List Coordinate
boardIndirectTargets map origin range targeting =
    if targeting == ChoosingIndirectTarget then
        OrderPlanning.indirectTargetsInRange map origin range

    else
        []


boardTileFilter : Set Coordinate.Key -> Bool -> Set Coordinate.Key -> Maybe Coordinate -> Coordinate -> String
boardTileFilter visiblePositions choosingDestination reachablePositions selected position =
    let
        visibilityFilters : List String
        visibilityFilters =
            if Set.member (Coordinate.key position) visiblePositions then
                []

            else
                [ "saturate(0.18) brightness(0.58)" ]

        unavailable : Bool
        unavailable =
            choosingDestination
                && not (Set.member (Coordinate.key position) reachablePositions)
                && selected
                /= Just position

        destinationFilters : List String
        destinationFilters =
            if unavailable then
                [ "brightness(0.6)" ]

            else
                []

        filters : List String
        filters =
            visibilityFilters ++ destinationFilters
    in
    if List.isEmpty filters then
        "none"

    else
        String.join " " filters


{-| Keep only persistent inputs at lazy boundaries. In particular, mapping options
into reachable coordinates here avoids allocating a new list on every idle tick
or camera update. Playback clocks and sprite frames never invalidate terrain.
-}
selectedTerrainLayer : Map -> List Coordinate -> List Movement.Option -> Coordinate -> Int -> BoardTargeting -> Coordinate -> Svg Msg
selectedTerrainLayer map visibleTiles options origin range targeting selected =
    terrainLayer map visibleTiles options (boardIndirectTargets map origin range targeting) (targeting /= InspectingBoard) (Just selected)


unselectedTerrainLayer : Map -> List Coordinate -> List Movement.Option -> Coordinate -> Int -> BoardTargeting -> Svg Msg
unselectedTerrainLayer map visibleTiles options origin range targeting =
    terrainLayer map visibleTiles options (boardIndirectTargets map origin range targeting) (targeting /= InspectingBoard) Nothing


terrainLayer : Map -> List Coordinate -> List Movement.Option -> List Coordinate -> Bool -> Maybe Coordinate -> Svg Msg
terrainLayer map visibleTiles options indirect choosingDestination selected =
    let
        reachable : List Coordinate
        reachable =
            List.map .destination options ++ indirect

        visiblePositions : Set Coordinate.Key
        visiblePositions =
            Set.fromList (List.map Coordinate.key visibleTiles)

        reachablePositions : Set Coordinate.Key
        reachablePositions =
            Set.fromList (List.map Coordinate.key reachable)

        terrainFilter : Coordinate -> String
        terrainFilter =
            boardTileFilter visiblePositions choosingDestination reachablePositions selected

        terrainTile : Coordinate -> Svg Msg
        terrainTile position =
            SvgLazy.lazy5 boardTerrainTile map (terrainFilter position) (Set.member (Coordinate.key position) visiblePositions) position.x position.y
    in
    Svg.g
        [ HA.style "image-rendering" "auto"
        ]
        (List.map terrainTile (Map.positions map))


{-| Fog and destination changes only rebuild tile treatment; the underlying
artwork depends on the two terrain enums, which compare by reference as well.
-}
terrainArtwork : MapTheme -> Terrain -> Svg Msg
terrainArtwork theme terrain =
    TerrainTile.toSvg
        { theme = theme
        , terrain = terrain
        }
        |> StyledSvg.toUnstyled


tileTargets :
    Map
    -> List Movement.Option
    -> Coordinate
    -> Int
    -> BoardTargeting
    -> String
    -> Svg Msg
tileTargets map options origin range targeting destinationAction =
    let
        reachable : List Coordinate
        reachable =
            List.map .destination options ++ boardIndirectTargets map origin range targeting

        reachablePositions : Set Coordinate.Key
        reachablePositions =
            Set.fromList (List.map Coordinate.key reachable)

        tileTarget : Coordinate -> Svg Msg
        tileTarget position =
            SvgLazy.lazy4 boardTileTarget destinationAction (Set.member (Coordinate.key position) reachablePositions) position.x position.y
    in
    Svg.g
        []
        (List.map tileTarget (Map.positions map))


movementLayer :
    Map
    -> List Movement.Option
    -> Coordinate
    -> Int
    -> BoardTargeting
    -> List PlannedOrder
    -> MovementRoute.Purpose
    -> List Coordinate
    -> Svg Msg
movementLayer map options origin range targeting paths previewPurpose previewedPath =
    let
        reachable : List Coordinate
        reachable =
            List.map .destination options ++ boardIndirectTargets map origin range targeting

        reachableTile : Coordinate -> Svg Msg
        reachableTile position =
            at position
                [ Svg.rect
                    [ SA.x "1"
                    , SA.y "1"
                    , SA.width "14"
                    , SA.height "14"
                    , SA.fill S.yellow5Str
                    , SA.fillOpacity "0.12"
                    , SA.stroke S.yellow5Str
                    , SA.strokeOpacity "0.65"
                    , SA.strokeWidth "0.5"
                    ]
                    []
                ]

        plannedPath : PlannedOrder -> List (Svg Msg)
        plannedPath order =
            let
                purpose : MovementRoute.Purpose
                purpose =
                    case order.action of
                        PlannedOrder.AttackMove attack ->
                            MovementRoute.DirectedAttack attack.direction

                        _ ->
                            MovementRoute.Travel
            in
            MovementRoute.planned purpose (PlannedOrder.path order)

        overlay : Svg Msg
        overlay =
            let
                reachableTiles : List (Svg Msg)
                reachableTiles =
                    List.map reachableTile reachable

                plannedPaths : List (Svg Msg)
                plannedPaths =
                    List.concatMap plannedPath paths

                preview : List (Svg Msg)
                preview =
                    MovementRoute.preview previewPurpose previewedPath
            in
            Svg.g
                [ SA.pointerEvents "none"
                , Aria.svgHidden True
                ]
                (reachableTiles ++ plannedPaths ++ preview)
    in
    overlay


{-| Enter and Space activate a focused board object. Reserve Meta/Ctrl chords
for shortcuts on every platform, including the window's submit command.
-}
onBoardActivationKeyDown : { pressedEnter : msg, pressedSpace : msg } -> Svg.Attribute msg
onBoardActivationKeyDown messages =
    let
        shortcutModifier : Decode.Decoder Bool
        shortcutModifier =
            Decode.map2 (||)
                (Decode.field "metaKey" Decode.bool)
                (Decode.field "ctrlKey" Decode.bool)

        activateWithoutShortcut : Bool -> Decode.Decoder ( msg, Bool )
        activateWithoutShortcut shortcutModifierPressed =
            if shortcutModifierPressed then
                Decode.fail "shortcut chords do not activate board objects"

            else
                Decode.oneOf
                    [ HtmlEvent.enter ( messages.pressedEnter, True )
                    , HtmlEvent.key " " ( messages.pressedSpace, True )
                    ]
    in
    Ev.preventDefaultOn "keydown"
        (shortcutModifier |> Decode.andThen activateWithoutShortcut)


onClickWithDetail : ({ detail : Int } -> msg) -> Svg.Attribute msg
onClickWithDetail toMsg =
    Ev.on "click"
        (Decode.field "detail" Decode.int
            |> Decode.map (\detail -> toMsg { detail = detail })
        )


selectionMarker : Coordinate -> Svg Msg
selectionMarker position =
    at position
        [ Svg.rect
            [ SA.x "0.75"
            , SA.y "0.75"
            , SA.width "14.5"
            , SA.height "14.5"
            , SA.fill "none"
            , SA.stroke S.yellow5Str
            , SA.strokeOpacity "0.8"
            , SA.strokeWidth "0.5"
            , SA.pointerEvents "none"
            , Aria.svgHidden True
            ]
            []
        ]



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
                            ChoosingDirection _ _ ->
                                [ leftKeys (DirectionKeyPressed DirectionEnum.West)
                                , rightKeys (DirectionKeyPressed DirectionEnum.East)
                                , upKeys (DirectionKeyPressed DirectionEnum.North)
                                , downKeys (DirectionKeyPressed DirectionEnum.South)
                                ]

                            ChoosingAttackDirection _ _ ->
                                [ leftKeys (DirectionKeyPressed DirectionEnum.West)
                                , rightKeys (DirectionKeyPressed DirectionEnum.East)
                                , upKeys (DirectionKeyPressed DirectionEnum.North)
                                , downKeys (DirectionKeyPressed DirectionEnum.South)
                                ]

                            ChoosingMove _ ->
                                [ leftKeys (PathDirectionKeyPressed DirectionEnum.West)
                                , rightKeys (PathDirectionKeyPressed DirectionEnum.East)
                                , upKeys (PathDirectionKeyPressed DirectionEnum.North)
                                , downKeys (PathDirectionKeyPressed DirectionEnum.South)
                                , KeyCmd.enter PathEnterPressed
                                ]

                            ChoosingIndirectFire _ ->
                                []

                            CommandMenu _ ->
                                [ upKeys PreviousCommandPressed
                                , downKeys NextCommandPressed
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


leftKeys : msg -> KeyCmd msg
leftKeys msg =
    KeyCmd.batch
        [ KeyCmd.leftArrow msg
        , KeyCmd.a msg
        ]


rightKeys : msg -> KeyCmd msg
rightKeys msg =
    KeyCmd.batch
        [ KeyCmd.rightArrow msg
        , KeyCmd.d msg
        ]


upKeys : msg -> KeyCmd msg
upKeys msg =
    KeyCmd.batch
        [ KeyCmd.upArrow msg
        , KeyCmd.w msg
        ]


downKeys : msg -> KeyCmd msg
downKeys msg =
    KeyCmd.batch
        [ KeyCmd.downArrow msg
        , KeyCmd.s msg
        ]


panNavigation : () -> List (KeyCmd Msg)
panNavigation _ =
    [ leftKeys PanLeftKeyPressed
    , rightKeys PanRightKeyPressed
    , upKeys PanUpKeyPressed
    , downKeys PanDownKeyPressed
    ]


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 400 AnimationTimerElapsed
        , CurrentTurn.subscriptions model.currentTurn
            |> Sub.map CurrentTurnMsg
        , BattlefieldNavigation.subscriptions model.navigation
            |> Sub.map BattlefieldNavigationMsg
        ]
