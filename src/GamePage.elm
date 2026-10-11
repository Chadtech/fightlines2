module GamePage exposing
    ( Flags
    , Model
    , Msg
    , dialog
    , init
    , keyCommands
    , load
    , loadFailedView
    , setShared
    , subscriptions
    , update
    , view
    )

import AnimationFrame
import Api.Enum.Direction as Facing exposing (Direction)
import Api.Enum.MapType
    exposing
        ( MapType
        )
import Api.Enum.Side
    exposing
        ( Side
        )
import Api.Enum.TurnEventKind as EventKind
import Api.Enum.UnitKind as UnitKind
import Api.Mutation
import Api.Object
import Api.Object.Depot as DepotApi
import Api.Object.GamePlayerView as PlayerView
import Api.Object.GameSnapshot as SnapshotApi
import Api.Object.MovementRule as MovementRuleApi
import Api.Object.Scenario as Scenario
import Api.Object.TerrainMovementCost as MovementCostApi
import Api.Query
import ApiRequest
import Browser.Events
import Camera exposing (Camera)
import Coordinate exposing (Coordinate)
import Css
import Css.Global
import Depot exposing (Depot)
import Direction
import Effect as E
    exposing
        ( Eff
        )
import GamePage.BattlefieldNavigation as BattlefieldNavigation
import GamePage.Selection
    exposing
        ( DestinationFeedback(..)
        , Inspection(..)
        , MovePlanning
        , Selection(..)
        , UnitInteraction(..)
        )
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Attributes as HA
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Events as HtmlEvents
import Html.Styled.Keyed as Keyed
import Json.Decode as Decode
import KeyCmd exposing (KeyCmd)
import ListUtil
import LobbyId
    exposing
        ( LobbyId
        )
import Map exposing (Map)
import Movement
import PlannedOrder
    exposing
        ( PlannedOrder
        , UnloadOrder
        )
import PlanningModel exposing (PlanningModel, UnloadChoice, UnloadPlanning)
import Point exposing (Point)
import Ports.Js.To as ToJs
import Shared
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as Ev
import Svg.Styled as StyledSvg
import Terrain
import Time
import Turn
import TurnLifecycle exposing (Phase)
import TurnPlayback
import Unit exposing (Unit)
import UnitCommand
import UnitId exposing (UnitId)
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Dialog as Dialog exposing (Dialog)
import View.RotationChoices as RotationChoices
import View.TerrainTile as TerrainTile
import View.UnitCargo as UnitCargo
import View.UnitCommands as UnitCommands
import View.UnitFacing as UnitFacing
import View.UnitSprite as UnitSprite
import View.UnitStatus as UnitStatus
import View.UnloadPassenger as UnloadPassenger



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { turnNumber : Int
    , opponentSubmitted : Bool
    , turnResolution : Maybe Turn.Resolution
    , phase : Phase
    , refreshing : Bool
    , turnError : Maybe String
    , shared : Shared.Model
    , name : String
    , mapType : MapType
    , players : List Player
    , map : Map
    , units : List Unit
    , depots : List Depot
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
    , visibleTiles : List Coordinate
    , movementRules : List Movement.Rule
    , turn : Turn.Snapshot
    , playbackFrames : List TurnPlayback.Frame
    }


type alias Player =
    { name : String
    , side : Side
    , isYou : Bool
    }


{-| An unload preview always connects the truck to one adjacent tile.
-}
type alias UnloadRoute =
    { origin : Coordinate
    , direction : Direction
    }


type alias RotationSelection =
    { unitId : UnitId
    , position : Coordinate
    , direction : Direction
    }


type Msg
    = BattlefieldNavigationMsg BattlefieldNavigation.Msg
    | UnitCommandsMsg UnitCommands.Msg
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
    | DirectionKeyPressed Direction
    | PathDirectionKeyPressed Direction
    | PathEnterPressed
    | ClearMoveClicked
    | CargoUnitClicked UnitId
    | UnloadUnitToggled UnitId Bool
    | UnloadChoicesConfirmed
    | UnloadSkipped
    | InspectClicked
    | EscapePressed
    | DialogDismissed
    | SubmissionConfirmed
    | SubmitTurnClicked
    | SubmitResponseReceived Int (ApiRequest.Response Snapshot)
    | PollTimerElapsed Time.Posix
    | PollResponseReceived (ApiRequest.Response Snapshot)
    | PlaybackFrameElapsed Float
    | RotationChoicesMsg RotationChoices.Msg
    | ClickedUnit UnitId { detail : Int }
    | PressedEnterOnUnit UnitId
    | PressedSpaceOnUnit UnitId
    | MouseOverUnit UnitId
    | ClickedDepot Coordinate { detail : Int }
    | PressedEnterOnDepot Coordinate
    | PressedSpaceOnDepot Coordinate
    | MouseOverDepot Coordinate
    | ClickedTile Coordinate { detail : Int }
    | PressedEnterOnTile Coordinate
    | PressedSpaceOnTile Coordinate
    | MouseOverTile Coordinate
    | MousePressed Point
    | WheelScrolled Point Float
    | HomePressed



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { snapshot : Snapshot }


init : Shared.Model -> Flags -> Model
init shared flags =
    { turnNumber = flags.snapshot.turn.number
    , opponentSubmitted = flags.snapshot.turn.opponentSubmitted
    , turnResolution = flags.snapshot.turn.resolution
    , phase =
        TurnLifecycle.observeSubmission
            flags.snapshot.turn.submitted
            (TurnLifecycle.Planning PlanningModel.init)
    , refreshing = False
    , turnError = Nothing
    , shared = shared
    , name = flags.snapshot.name
    , mapType = flags.snapshot.mapType
    , players = flags.snapshot.players
    , map = flags.snapshot.map
    , units = flags.snapshot.units
    , depots = flags.snapshot.depots
    , visibleTiles = flags.snapshot.visibleTiles
    , movementRules = flags.snapshot.movementRules
    , navigation = BattlefieldNavigation.init
    , frame = AnimationFrame.first
    }


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
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


mapPlanning : (PlanningModel -> PlanningModel) -> Model -> Model
mapPlanning transition model =
    { model | phase = TurnLifecycle.mapPlanning transition model.phase }


unloadChoice : Phase -> Maybe UnloadChoice
unloadChoice phase =
    TurnLifecycle.planning phase
        |> Maybe.andThen PlanningModel.unloadChoice


unloadPlanning : Phase -> Maybe UnloadPlanning
unloadPlanning phase =
    TurnLifecycle.planning phase |> Maybe.andThen PlanningModel.unloadPlanning


isChoosingUnload : Model -> Bool
isChoosingUnload model =
    unloadPlanning model.phase /= Nothing


openUnloadPrompt : Unit -> Movement.Option -> Model -> Model
openUnloadPrompt truck move model =
    if hasPassengers truck model then
        model
            |> mapPlanning (PlanningModel.startUnload truck.id move)

    else
        model


hasPassengers : Unit -> Model -> Bool
hasPassengers truck model =
    List.any (\passenger -> Unit.carrierId passenger == Just truck.id) model.units


holdPosition : Unit -> Model -> Model
holdPosition unit model =
    case holdOrder model.units unit of
        Just hold ->
            let
                next : Model
                next =
                    { model
                        | phase = TurnLifecycle.setOrders (hold :: List.filter (\plan -> plan.unitId /= unit.id) (plannedOrders model)) model.phase
                    }
                        |> inspectSelectedUnit
            in
            if hasPassengers unit model then
                next
                    |> mapPlanning (PlanningModel.startStationaryUnload unit.id (PlannedOrder.destination hold))

            else
                next

        Nothing ->
            model


dismissDialog : Model -> Model
dismissDialog model =
    model
        |> mapPlanning PlanningModel.dismissDialog


unloadOptions : Model -> PlanningModel -> UnitId -> List Movement.Option
unloadOptions model state passengerId =
    case PlanningModel.unloadPlanning state of
        Just planning ->
            let
                projectTruck : Unit -> Unit
                projectTruck unit =
                    if unit.id == planning.truck.truckId then
                        Unit.setOnMap (PlanningModel.truckDestination planning.truck) unit

                    else
                        unit

                projectedUnits : List Unit
                projectedUnits =
                    List.map projectTruck model.units

                next : Model
                next =
                    { model | phase = TurnLifecycle.Planning state }
            in
            case ListUtil.find (\unit -> unit.id == passengerId) projectedUnits of
                Just passenger ->
                    Movement.options (reservedDestinations passenger next) model.movementRules model.map projectedUnits passenger

                Nothing ->
                    []

        Nothing ->
            []


chooseUnloadSquare : Coordinate -> Model -> Model
chooseUnloadSquare destination model =
    model
        |> mapPlanning (PlanningModel.saveUnloadDestination (unloadOptions model) destination)


partialOrdersDialogHtmlId : String
partialOrdersDialogHtmlId =
    "submit-turn-warning"


hasDialog : Model -> Bool
hasDialog model =
    dialog model /= Nothing


plannedOrders : Model -> List PlannedOrder
plannedOrders model =
    TurnLifecycle.orders model.phase


playback : Model -> Maybe TurnPlayback.Playback
playback model =
    TurnLifecycle.playback model.phase


planningLocked : Model -> Bool
planningLocked model =
    TurnLifecycle.planningLocked model.phase


unitsWithoutOrders : Model -> List Unit
unitsWithoutOrders model =
    let
        missingOrder : Unit -> Bool
        missingOrder unit =
            isOwnUnit model unit && Unit.onBoard unit && not (List.any (\plan -> plan.unitId == unit.id) (plannedOrders model))
    in
    List.filter missingOrder model.units


readyToSubmit : Model -> Bool
readyToSubmit model =
    not (planningLocked model) && List.isEmpty (unitsWithoutOrders model)


submitTurn : LobbyId -> Model -> ( Model, Eff Msg )
submitTurn lobbyId model =
    let
        phase : Phase
        phase =
            TurnLifecycle.startSubmission model.turnNumber model.phase
    in
    case ( model.phase, phase ) of
        ( TurnLifecycle.Planning _, TurnLifecycle.Submitting _ ) ->
            ( { model | phase = phase, turnError = Nothing }
            , E.request (SubmitResponseReceived model.turnNumber) (submitRequest lobbyId model)
            )

        _ ->
            ( model, E.none )


unloadDialogHtmlId : String
unloadDialogHtmlId =
    "unload-passengers"


selectedUnit : Model -> Maybe Unit
selectedUnit model =
    case currentSelection model of
        Just (Inspecting (UnitInspection id)) ->
            ListUtil.find (\unit -> unit.id == id) model.units

        Just (UnitSelection selection) ->
            ListUtil.find (\unit -> unit.id == selection.id) model.units

        _ ->
            Nothing


selectedPosition : Model -> Maybe Coordinate
selectedPosition model =
    case unloadPlanning model.phase of
        Just planning ->
            Just (PlanningModel.truckDestination planning.truck)

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
    List.any
        (\player -> player.isYou && player.side == unit.side)
        model.players


applyCommand : UnitCommand.Command -> Model -> Model
applyCommand command model =
    case commandMenuUnit model of
        Just unit ->
            let
                canApply : Bool
                canApply =
                    isOwnUnit model unit
                        && not (planningLocked model)
                        && not (receivingLoad unit model)
                        && List.member command (UnitCommand.available unit)
                        && UnitCommand.isImplemented command
            in
            if canApply then
                case command of
                    UnitCommand.Move ->
                        beginMovement unit model

                    UnitCommand.Rotate ->
                        model
                            |> setUnitInteraction unit.id (ChoosingDirection (Maybe.withDefault Facing.North unit.direction))

                    UnitCommand.HoldPosition ->
                        holdPosition unit model

                    _ ->
                        model

            else
                model

        _ ->
            model


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
                    Direction.between (PlannedOrder.destination plan) unload.destination
                        |> Maybe.map withDirection
            in
            List.filterMap route (PlannedOrder.unloads plan)
    in
    List.concatMap truckUnloads (plannedOrders model)


focusedCommand : Model -> Maybe UnitCommands.MenuOption
focusedCommand model =
    case currentSelection model of
        Just (UnitSelection selection) ->
            case selection.interaction of
                CommandMenu focused ->
                    focused

                ChoosingMove _ ->
                    Nothing

                ChoosingDirection _ ->
                    Nothing

        _ ->
            Nothing


commandMenuUnit : Model -> Maybe Unit
commandMenuUnit model =
    case ( currentSelection model, hasDialog model ) of
        ( Just (UnitSelection { interaction }), False ) ->
            case interaction of
                CommandMenu _ ->
                    selectedUnit model

                _ ->
                    Nothing

        _ ->
            Nothing


holdOrder : List Unit -> Unit -> Maybe PlannedOrder
holdOrder units unit =
    Unit.physicalPosition units unit
        |> Maybe.map (\position -> { unitId = unit.id, action = PlannedOrder.Hold position })


submitRequest : LobbyId -> Model -> Graphql.Http.Request Snapshot
submitRequest lobbyId model =
    let
        missingOrder : Unit -> Bool
        missingOrder unit =
            isOwnUnit model unit && not (List.any (\plan -> plan.unitId == unit.id) (plannedOrders model))

        defaultHolds : List PlannedOrder
        defaultHolds =
            model.units |> List.filter missingOrder |> List.filterMap (holdOrder model.units)

        orders : List PlannedOrder
        orders =
            plannedOrders model ++ defaultHolds
    in
    Api.Mutation.submitTurn
        { id = LobbyId.toString lobbyId
        , turnNumber = model.turnNumber
        , orders = List.map PlannedOrder.toInput orders
        }
        snapshotSelection
        |> ApiRequest.mutationRequest


receiveSnapshot : Snapshot -> Model -> Model
receiveSnapshot snapshot model =
    if snapshot.turn.number < model.turnNumber then
        model

    else if snapshot.turn.number == model.turnNumber then
        let
            phase : Phase
            phase =
                if snapshot.turn.submitted then
                    TurnLifecycle.observeSubmission True model.phase

                else
                    model.phase

            next : Model
            next =
                { model
                    | opponentSubmitted = model.opponentSubmitted || snapshot.turn.opponentSubmitted
                    , turnResolution = snapshot.turn.resolution
                    , phase = phase
                }
        in
        if snapshot.turn.submitted then
            if isChoosingUnload model then
                clearSelection next

            else
                next

        else
            next

    else
        let
            frame : TurnPlayback.Frame
            frame =
                TurnPlayback.initial snapshot.playbackFrames { units = snapshot.units, visibleTiles = snapshot.visibleTiles }
        in
        { model
            | turnNumber = snapshot.turn.number
            , opponentSubmitted = snapshot.turn.opponentSubmitted
            , turnResolution = snapshot.turn.resolution
            , map = snapshot.map
            , units = frame.units
            , depots = snapshot.depots
            , visibleTiles = frame.visibleTiles
            , phase = TurnLifecycle.startTurn snapshot.turn.submitted snapshot.playbackFrames
            , turnError = Nothing
        }


traceTo : Coordinate -> Model -> Maybe Movement.Option
traceTo position model =
    case ( selectedUnit model, movementPlanning model ) of
        ( Just unit, Just planning ) ->
            if isOwnUnit model unit then
                Movement.preview model.movementRules model.map model.units unit planning.preview position

            else
                Nothing

        _ ->
            Nothing


beginMovement : Unit -> Model -> Model
beginMovement unit model =
    case Unit.physicalPosition model.units unit of
        Just origin ->
            let
                planning : MovePlanning
                planning =
                    { preview = Movement.start origin
                    , options = Movement.options (reservedDestinations unit model) model.movementRules model.map model.units unit
                    , destinationFeedback = NoDestinationFeedback
                    }
            in
            model
                |> setUnitInteraction unit.id (ChoosingMove planning)

        Nothing ->
            model


boardingSpace : Unit -> Unit -> Model -> Bool
boardingSpace mover truck model =
    let
        alreadyAboard : Int
        alreadyAboard =
            List.length (List.filter (\unit -> Unit.carrierId unit == Just truck.id) model.units)

        boarding : PlannedOrder -> Bool
        boarding plan =
            plan.unitId /= mover.id && PlannedOrder.isMoving plan && Just (PlannedOrder.destination plan) == Unit.boardPosition truck

        truckMoving : Bool
        truckMoving =
            List.any (\plan -> plan.unitId == truck.id && PlannedOrder.isMoving plan) (plannedOrders model)

        fitsCargo : Bool
        fitsCargo =
            alreadyAboard + List.length (List.filter boarding (plannedOrders model)) < truck.cargoCapacity

        compatible : Bool
        compatible =
            Unit.boardPosition truck |> Maybe.andThen (Unit.loadingPartner model.units mover) |> (==) (Just truck)
    in
    compatible && not truckMoving && fitsCargo


plannedAction : Model -> Unit -> Movement.Option -> String
plannedAction model unit move =
    if Unit.carrierId unit /= Nothing && List.length move.path > 1 then
        "unload at"

    else if Unit.loadingPartner model.units unit move.destination /= Nothing then
        "load at"

    else
        "move to"


reservedDestinations : Unit -> Model -> List Coordinate
reservedDestinations unit model =
    let
        reserves : PlannedOrder -> Bool
        reserves plan =
            let
                partner : Maybe Unit
                partner =
                    Unit.loadingPartner model.units unit (PlannedOrder.destination plan)

                isWaitingPartner : Unit -> Bool
                isWaitingPartner target =
                    target.id == plan.unitId && not (receivingLoad target model && target.cargoCapacity == 0)

                waitingPartner : Bool
                waitingPartner =
                    not (PlannedOrder.isMoving plan) && (partner |> Maybe.map isWaitingPartner |> Maybe.withDefault False)

                boardingDestination : Bool
                boardingDestination =
                    partner |> Maybe.map (\target -> boardingSpace unit target model) |> Maybe.withDefault False
            in
            plan.unitId /= unit.id && not waitingPartner && not boardingDestination

        unavailableReceiver : Unit -> Bool
        unavailableReceiver target =
            target.id /= unit.id && receivingLoad target model && not (boardingSpace unit target model)

        unavailableReceivers : List Coordinate
        unavailableReceivers =
            model.units
                |> List.filter unavailableReceiver
                |> List.filterMap Unit.boardPosition

        savedDestinations : List Coordinate
        savedDestinations =
            List.map PlannedOrder.destination (List.filter reserves (plannedOrders model))
                ++ List.concatMap (PlannedOrder.unloads >> List.map .destination) (plannedOrders model)
    in
    savedDestinations ++ unavailableReceivers


receivingLoad : Unit -> Model -> Bool
receivingLoad unit model =
    let
        receives : PlannedOrder -> Bool
        receives plan =
            if not (PlannedOrder.isMoving plan) then
                False

            else
                case ListUtil.find (\mover -> mover.id == plan.unitId) model.units of
                    Just mover ->
                        if Unit.carrierId mover == Just unit.id then
                            True

                        else
                            Unit.loadingPartner model.units mover (PlannedOrder.destination plan) |> Maybe.map .id |> (==) (Just unit.id)

                    Nothing ->
                        False
    in
    List.any receives (plannedOrders model)


saveMove : Unit -> Movement.Option -> Model -> List PlannedOrder
saveMove unit move model =
    let
        receiver : Maybe Unit
        receiver =
            case Unit.carrierId unit of
                Just carrier ->
                    model.units
                        |> ListUtil.find
                            (\truck -> truck.id == carrier)

                Nothing ->
                    Unit.loadingPartner
                        model.units
                        unit
                        move.destination

        retained : List PlannedOrder
        retained =
            plannedOrders model
                |> List.filter
                    (\plan ->
                        (plan.unitId /= unit.id)
                            && (Just plan.unitId /= Maybe.map .id receiver)
                    )

        receiverHold : List PlannedOrder
        receiverHold =
            receiver
                |> Maybe.andThen (holdOrder model.units)
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    { unitId = unit.id, action = PlannedOrder.Move { move = move, unloads = [] } } :: receiverHold ++ retained


currentSelection : Model -> Maybe Selection
currentSelection model =
    TurnLifecycle.selection model.phase


setSelection : Maybe Selection -> Model -> Model
setSelection selected model =
    { model | phase = TurnLifecycle.setSelection selected model.phase }


setUnitInteraction : UnitId -> UnitInteraction -> Model -> Model
setUnitInteraction id interaction model =
    model
        |> setSelection (Just (UnitSelection { id = id, interaction = interaction }))


focusCommand : UnitCommands.MenuOption -> Model -> Model
focusCommand command model =
    case ( currentSelection model, commandMenuUnit model ) of
        ( Just (UnitSelection selection), Just _ ) ->
            case selection.interaction of
                CommandMenu _ ->
                    model
                        |> setUnitInteraction selection.id (CommandMenu (Just command))

                _ ->
                    model

        _ ->
            model


revokeSelectedOrder : Model -> Model
revokeSelectedOrder model =
    if planningLocked model then
        model

    else
        model
            |> mapPlanning
                (PlanningModel.setOrders
                    (plannedOrders model
                        |> List.filter
                            (\plan ->
                                Just plan.unitId /= Maybe.map .id (selectedUnit model)
                            )
                    )
                )
            |> restoreCommands


inspectSelectedUnit : Model -> Model
inspectSelectedUnit model =
    case selectedUnit model of
        Just unit ->
            setSelection (Just (Inspecting (UnitInspection unit.id))) model

        Nothing ->
            model


restoreCommands : Model -> Model
restoreCommands model =
    case selectedUnit model of
        Just unit ->
            setSelection (Just (unitSelection unit model)) model

        Nothing ->
            model


unitSelection : Unit -> Model -> Selection
unitSelection unit model =
    let
        hasOrder : Bool
        hasOrder =
            List.any (\order -> order.unitId == unit.id) (plannedOrders model)

        canChooseCommand : Bool
        canChooseCommand =
            isOwnUnit model unit
                && Unit.onBoard unit
                && not (planningLocked model)
                && not (receivingLoad unit model)
                && not hasOrder
    in
    if canChooseCommand then
        UnitSelection { id = unit.id, interaction = CommandMenu Nothing }

    else
        Inspecting (UnitInspection unit.id)


choosingDirection : Model -> Bool
choosingDirection model =
    case currentSelection model of
        Just (UnitSelection selection) ->
            case selection.interaction of
                ChoosingDirection _ ->
                    True

                CommandMenu _ ->
                    False

                ChoosingMove _ ->
                    False

        _ ->
            False


saveRotation : Direction -> Model -> Model
saveRotation direction model =
    case selectedUnit model of
        Just unit ->
            let
                canSave : Bool
                canSave =
                    choosingDirection model
                        && not (planningLocked model)
                        && isOwnUnit model unit
                        && not (receivingLoad unit model)
            in
            if canSave then
                case Unit.boardPosition unit of
                    Just position ->
                        let
                            rotation : PlannedOrder
                            rotation =
                                { unitId = unit.id
                                , action = PlannedOrder.Rotate { position = position, direction = direction }
                                }
                        in
                        { model
                            | phase = TurnLifecycle.setOrders (rotation :: List.filter (\plan -> plan.unitId /= unit.id) (plannedOrders model)) model.phase
                        }
                            |> inspectSelectedUnit

                    Nothing ->
                        model

            else
                model

        Nothing ->
            model


rotationSelection : Model -> Maybe RotationSelection
rotationSelection model =
    case ( currentSelection model, selectedUnit model ) of
        ( Just (UnitSelection selection), Just unit ) ->
            case selection.interaction of
                ChoosingDirection direction ->
                    Unit.boardPosition unit
                        |> Maybe.map (\position -> { unitId = unit.id, position = position, direction = direction })

                CommandMenu _ ->
                    Nothing

                ChoosingMove _ ->
                    Nothing

        _ ->
            Nothing


previewRotation : Direction -> Model -> Model
previewRotation direction model =
    case currentSelection model of
        Just (UnitSelection selection) ->
            let
                canPreview : Bool
                canPreview =
                    choosingDirection model && not (planningLocked model) && not (BattlefieldNavigation.active model.navigation)
            in
            if canPreview then
                model
                    |> setUnitInteraction selection.id (ChoosingDirection direction)

            else
                model

        _ ->
            model


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
                |> SS.with PlayerView.side
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
        |> SS.with (SnapshotApi.scenario (Scenario.depots (SS.map Depot (DepotApi.position Coordinate.selection))))
        |> SS.with (SnapshotApi.visibleTiles Coordinate.selection)
        |> SS.with (SnapshotApi.movementRules movementRuleSelection)
        |> SS.with Turn.selection
        |> SS.with (TurnPlayback.selection Unit.selection Coordinate.selection)


movementPlanning : Model -> Maybe MovePlanning
movementPlanning model =
    case currentSelection model of
        Just (UnitSelection selection) ->
            case selection.interaction of
                ChoosingMove planning ->
                    Just planning

                _ ->
                    Nothing

        _ ->
            Nothing


destinationFeedback : Model -> DestinationFeedback
destinationFeedback model =
    case unloadPlanning model.phase of
        Just planning ->
            planning.destinationFeedback

        Nothing ->
            movementPlanning model
                |> Maybe.map .destinationFeedback
                |> Maybe.withDefault NoDestinationFeedback


setMoveDestinationFeedback : DestinationFeedback -> Model -> Model
setMoveDestinationFeedback feedback model =
    case currentSelection model of
        Just (UnitSelection selection) ->
            case selection.interaction of
                ChoosingMove planning ->
                    model
                        |> setUnitInteraction selection.id (ChoosingMove { planning | destinationFeedback = feedback })

                _ ->
                    model

        _ ->
            model


pathPreview : Model -> Maybe Movement.Option
pathPreview model =
    Maybe.map .preview (movementPlanning model)


moveOptions : Model -> List Movement.Option
moveOptions model =
    case unloadPlanning model.phase of
        Just planning ->
            planning.options

        _ ->
            movementPlanning model
                |> Maybe.map .options
                |> Maybe.withDefault []


clearSelection : Model -> Model
clearSelection model =
    setSelection Nothing model


selectUnit : UnitId -> Model -> Model
selectUnit id model =
    case ListUtil.find (\unit -> unit.id == id) model.units of
        Nothing ->
            model

        Just unit ->
            let
                choosingOccupiedDestination : Bool
                choosingOccupiedDestination =
                    (pathPreview model /= Nothing || isChoosingUnload model) && not (planningLocked model) && Maybe.map .id (selectedUnit model) /= Just id
            in
            if choosingOccupiedDestination then
                Unit.boardPosition unit |> Maybe.map (\position -> selectTile position model) |> Maybe.withDefault model

            else if Maybe.map .id (selectedUnit model) == Just id then
                clearSelection model

            else
                setSelection (Just (unitSelection unit model)) model


selectTile : Coordinate -> Model -> Model
selectTile position model =
    case unloadPlanning model.phase of
        Just _ ->
            chooseUnloadSquare position model

        _ ->
            selectMovementTile position model


selectMovementTile : Coordinate -> Model -> Model
selectMovementTile position model =
    if planningLocked model then
        setSelection (Just (Inspecting (TileInspection position))) model

    else
        let
            notOwnUnit : () -> Model
            notOwnUnit _ =
                setSelection (Just (Inspecting (TileInspection position))) model
        in
        case selectedUnit model of
            Just unit ->
                if isOwnUnit model unit && pathPreview model /= Nothing then
                    let
                        destinationOption : Movement.Option -> Maybe Movement.Option
                        destinationOption preview =
                            if Movement.canStop (reservedDestinations unit model) model.units unit preview then
                                Just preview

                            else
                                Nothing
                    in
                    case traceTo position model |> Maybe.andThen destinationOption of
                        Just move ->
                            { model
                                | phase = TurnLifecycle.setOrders (saveMove unit move model) model.phase
                            }
                                |> inspectSelectedUnit
                                |> openUnloadPrompt unit move

                        Nothing ->
                            setMoveDestinationFeedback DestinationUnavailable model

                else
                    notOwnUnit ()

            Nothing ->
                notOwnUnit ()


previewTile : Coordinate -> Model -> Model
previewTile position model =
    case currentSelection model of
        Just (UnitSelection selection) ->
            case selection.interaction of
                ChoosingMove planning ->
                    if BattlefieldNavigation.active model.navigation then
                        model

                    else
                        case traceTo position model of
                            Just preview ->
                                model
                                    |> setUnitInteraction selection.id
                                        (ChoosingMove
                                            { planning
                                                | preview = preview
                                                , destinationFeedback = NoDestinationFeedback
                                            }
                                        )

                            Nothing ->
                                model

                _ ->
                    model

        _ ->
            model


extendPath : Direction -> Model -> Model
extendPath direction model =
    case pathPreview model of
        Just preview ->
            previewTile (Direction.step preview.destination direction) model

        Nothing ->
            model


confirmPath : Model -> Model
confirmPath model =
    case pathPreview model of
        Just preview ->
            selectMovementTile preview.destination model

        Nothing ->
            model


focusAdjacentCommand :
    (List UnitCommands.MenuOption -> List UnitCommands.MenuOption)
    -> Maybe UnitCommands.MenuOption
    -> Model
    -> Eff Msg
focusAdjacentCommand orderCommands current model =
    let
        afterCurrent : List UnitCommands.MenuOption -> List UnitCommands.MenuOption
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
                commands : List UnitCommands.MenuOption
                commands =
                    UnitCommands.enabledOptions unit
                        |> orderCommands

                adjacent : Maybe UnitCommands.MenuOption
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
                        { htmlId = UnitCommands.optionHtmlId command }
                        CommandFocusCompleted

                Nothing ->
                    E.none

        Nothing ->
            E.none


mapNavigation : (BattlefieldNavigation.Model -> BattlefieldNavigation.Model) -> Model -> Model
mapNavigation change model =
    { model | navigation = change model.navigation }


finishBoardInteraction : Model -> Model -> ( Model, Eff Msg )
finishBoardInteraction previous next =
    let
        effect : Eff Msg
        effect =
            case ( unloadChoice previous.phase, unloadChoice next.phase ) of
                ( Nothing, Just _ ) ->
                    E.toJs (ToJs.OpenDialog { htmlId = unloadDialogHtmlId })

                _ ->
                    E.none
    in
    ( next, effect )


onKeyDown : { pressedEnter : msg, pressedSpace : msg } -> Svg.Attribute msg
onKeyDown messages =
    Ev.preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    case key of
                        "Enter" ->
                            Decode.succeed ( messages.pressedEnter, True )

                        " " ->
                            Decode.succeed ( messages.pressedSpace, True )

                        _ ->
                            Decode.fail "not Enter or Space"
                )
        )


onClickWithDetail : ({ detail : Int } -> msg) -> Svg.Attribute msg
onClickWithDetail toMsg =
    Ev.on "click"
        (Decode.field "detail" Decode.int
            |> Decode.map (\detail -> toMsg { detail = detail })
        )


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


preventDefault : Msg -> ( Msg, Bool )
preventDefault msg =
    ( msg, True )



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


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
            model
                |> mapNavigation (BattlefieldNavigation.update navigationMsg)
                |> E.withOut

        WheelScrolled anchor delta ->
            model
                |> mapNavigation (BattlefieldNavigation.scroll anchor delta)
                |> E.withOut

        UnloadUnitToggled id checked ->
            model
                |> mapPlanning (PlanningModel.toggleUnloadPassenger id checked)
                |> E.withOut

        UnloadChoicesConfirmed ->
            model
                |> mapPlanning (PlanningModel.confirmUnloadPassengers (unloadOptions model))
                |> E.withOut

        UnloadSkipped ->
            model
                |> dismissDialog
                |> clearSelection
                |> E.withOut

        CargoUnitClicked id ->
            model
                |> clearSelection
                |> selectUnit id
                |> E.withOut

        RotationChoicesMsg rotationMsg ->
            let
                next : Model
                next =
                    case rotationMsg of
                        RotationChoices.MouseMovedOverDirection direction ->
                            previewRotation direction model

                        RotationChoices.ClickedDirection direction ->
                            if BattlefieldNavigation.suppressesClick model.navigation then
                                model

                            else
                                saveRotation direction model
            in
            next
                |> finishBoardInteraction model

        ClickedUnit id click ->
            let
                next : Model
                next =
                    if click.detail /= 0 && BattlefieldNavigation.suppressesClick model.navigation then
                        model

                    else
                        selectUnit id model
            in
            next
                |> finishBoardInteraction model

        PressedEnterOnUnit id ->
            let
                next : Model
                next =
                    let
                        confirmsSelectedUnitPreview : Bool
                        confirmsSelectedUnitPreview =
                            pathPreview model /= Nothing && Maybe.map .id (selectedUnit model) == Just id
                    in
                    if confirmsSelectedUnitPreview then
                        confirmPath model

                    else
                        selectUnit id model
            in
            next
                |> finishBoardInteraction model

        PressedSpaceOnUnit id ->
            model
                |> selectUnit id
                |> finishBoardInteraction model

        MouseOverUnit id ->
            let
                next : Model
                next =
                    if planningLocked model then
                        model

                    else
                        model.units
                            |> ListUtil.find (\unit -> unit.id == id)
                            |> Maybe.andThen Unit.boardPosition
                            |> Maybe.map (\position -> previewTile position model)
                            |> Maybe.withDefault model
            in
            next
                |> finishBoardInteraction model

        ClickedDepot position click ->
            let
                next : Model
                next =
                    if click.detail /= 0 && BattlefieldNavigation.suppressesClick model.navigation then
                        model

                    else
                        selectTile position model
            in
            next
                |> finishBoardInteraction model

        PressedEnterOnDepot position ->
            model
                |> selectTile position
                |> finishBoardInteraction model

        PressedSpaceOnDepot position ->
            model
                |> selectTile position
                |> finishBoardInteraction model

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
                |> finishBoardInteraction model

        ClickedTile position click ->
            let
                next : Model
                next =
                    if click.detail /= 0 && BattlefieldNavigation.suppressesClick model.navigation then
                        model

                    else
                        selectTile position model
            in
            next
                |> finishBoardInteraction model

        PressedEnterOnTile position ->
            model
                |> selectTile position
                |> finishBoardInteraction model

        PressedSpaceOnTile position ->
            model
                |> selectTile position
                |> finishBoardInteraction model

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
                |> finishBoardInteraction model

        UnitCommandsMsg commandMsg ->
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
                |> saveRotation direction
                |> E.withOut

        PathDirectionKeyPressed direction ->
            model
                |> extendPath direction
                |> E.withOut

        PathEnterPressed ->
            model
                |> confirmPath
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

        SubmitTurnClicked ->
            if planningLocked model || isChoosingUnload model || unloadChoice model.phase /= Nothing then
                model |> E.withOut

            else if List.isEmpty (unitsWithoutOrders model) then
                model
                    |> submitTurn lobbyId

            else
                ( model
                    |> mapPlanning PlanningModel.showSubmissionWarning
                , E.toJs (ToJs.OpenDialog { htmlId = partialOrdersDialogHtmlId })
                )

        DialogDismissed ->
            model
                |> dismissDialog
                |> E.withOut

        SubmissionConfirmed ->
            case model.phase of
                TurnLifecycle.Planning (PlanningModel.ConfirmingSubmission _) ->
                    model
                        |> submitTurn lobbyId

                _ ->
                    model |> E.withOut

        SubmitResponseReceived turnNumber result ->
            if turnNumber /= model.turnNumber then
                model |> E.withOut

            else
                case result of
                    Ok snapshot ->
                        { model
                            | phase = TurnLifecycle.finishSubmission turnNumber model.phase
                            , turnError = Nothing
                        }
                            |> receiveSnapshot snapshot
                            |> E.withOut

                    Err error ->
                        case model.phase of
                            TurnLifecycle.Submitting _ ->
                                { model
                                    | phase = TurnLifecycle.finishSubmission turnNumber model.phase
                                    , turnError = Just (ApiRequest.errorMessage error)
                                }
                                    |> E.withOut

                            _ ->
                                model |> E.withOut

        PollTimerElapsed _ ->
            if model.refreshing || not (TurnLifecycle.canPoll model.phase) then
                model |> E.withOut

            else
                ( { model | refreshing = True }
                , E.request PollResponseReceived (loadSnapshot lobbyId)
                )

        PollResponseReceived result ->
            case result of
                Ok snapshot ->
                    { model | refreshing = False }
                        |> receiveSnapshot snapshot
                        |> E.withOut

                Err error ->
                    { model
                        | refreshing = False
                        , turnError = Just (ApiRequest.errorMessage error)
                    }
                        |> E.withOut

        PlaybackFrameElapsed delta ->
            case TurnLifecycle.tick delta model.phase of
                Just next ->
                    { model
                        | phase = next.phase
                        , units = next.frame.units
                        , visibleTiles = next.frame.visibleTiles
                    }
                        |> E.withOut

                Nothing ->
                    model |> E.withOut

        AnimationTimerElapsed _ ->
            { model | frame = AnimationFrame.next model.frame }
                |> E.withOut


handleCommandMsg : UnitCommands.Msg -> Model -> ( Model, Eff Msg )
handleCommandMsg commandMsg model =
    case commandMsg of
        UnitCommands.MenuPressed ->
            model |> E.withOut

        UnitCommands.CancelClicked ->
            model
                |> clearSelection
                |> E.withOut

        UnitCommands.CommandFocused command ->
            model
                |> focusCommand command
                |> E.withOut

        UnitCommands.CommandPicked command ->
            model
                |> applyCommand command
                |> finishBoardInteraction model

        UnitCommands.ArrowedUpCommandMenu current ->
            ( model
            , focusAdjacentCommand List.reverse (Just current) model
            )

        UnitCommands.ArrowedDownCommandMenu current ->
            ( model
            , focusAdjacentCommand identity (Just current) model
            )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.fixed
            , S.top0
            , S.bottom0
            , S.left0
            , S.right0
            , S.row
            ]
        ]
        [ H.div
            [ A.css
                [ S.relative
                , S.flex1
                , S.minW0
                , S.hFull
                , S.col
                ]
            ]
            [ boardView model
            , turnPanel model
            ]
        , H.aside
            [ A.attribute "aria-label" "game panel"
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
                , Css.property "width" "min(18rem, 45vw)"
                ]
            ]
            [ selectionView model
            , panelFooter model
            ]
        ]
    ]


commandMenu : Model -> Html Msg
commandMenu model =
    case commandMenuUnit model of
        Just unit ->
            case Unit.physicalPosition model.units unit of
                Just position ->
                    UnitCommands.toHtml
                        model.map
                        (BattlefieldNavigation.camera model.navigation)
                        position
                        unit
                        |> H.map UnitCommandsMsg

                Nothing ->
                    H.text ""

        Nothing ->
            H.text ""


selectionView : Model -> Html Msg
selectionView model =
    let
        content : List (Html Msg)
        content =
            case selectedUnit model of
                Just unit ->
                    [ Keyed.node "div"
                        []
                        [ ( UnitId.toString unit.id
                          , H.div
                                [ A.css
                                    [ S.col
                                    , S.g3
                                    ]
                                ]
                                [ UnitStatus.toHtml unit
                                , cargoView model unit
                                , movementView model
                                ]
                          )
                        ]
                    ]

                Nothing ->
                    case selectedPosition model of
                        Just _ ->
                            [ H.h2
                                []
                                [ H.text (selectionText model)
                                ]
                            ]

                        Nothing ->
                            []
    in
    H.section
        [ A.attribute "aria-label" "selection"
        , A.css
            [ S.col
            , S.g3
            , S.shrink0
            ]
        ]
        content


panelFooter : Model -> Html Msg
panelFooter model =
    let
        hint : String
        hint =
            if currentSelection model == Nothing then
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
        [ resolutionSummary model
        , H.p
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
                        [ H.p [] [ H.text ("choose an adjacent square to unload " ++ Unit.label unit) ]
                        , Button.secondary "skip remaining units" UnloadSkipped |> Button.toHtml
                        ]

                    else if Unit.carrierId unit /= Nothing || receivingLoad unit model then
                        transportDetails model unit

                    else if choosingDirection model then
                        [ H.p [] [ H.text "point around the unit to preview its facing. click to save, or press an arrow key or wasd." ]
                        ]

                    else
                        unitOrderView model unit

                Nothing ->
                    []

        feedback : List (Html Msg)
        feedback =
            if destinationFeedback model == DestinationUnavailable then
                [ H.p
                    [ A.attribute "role" "status" ]
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
            in
            [ H.p
                []
                [ H.text "choose a destination on the map"
                ]
            , H.p
                []
                [ H.text ("movement: " ++ Movement.pointsLabel preview.cost ++ " / " ++ budget)
                ]
            , Button.secondary "back to commands" ClearMoveClicked
                |> Button.toHtml
            ]

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
                                PlannedOrder.Hold _ ->
                                    "hold position"

                                PlannedOrder.Unload _ ->
                                    "hold position"

                                PlannedOrder.Rotate rotation ->
                                    "rotate: " ++ Direction.label rotation.direction

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
                    , Button.secondary "revoke order" ClearMoveClicked
                        |> Button.toHtml
                    ]
            in
            orderDetails ++ unloadDetails

        ( Nothing, Nothing ) ->
            []


viewControls : Model -> Html Msg
viewControls model =
    let
        camera : Camera
        camera =
            BattlefieldNavigation.camera model.navigation
    in
    H.section
        [ A.attribute "aria-label" "view controls"
        , A.css
            [ S.row
            , S.flexWrap
            , S.itemsCenter
            , S.g2
            ]
        ]
        [ H.div
            [ A.attribute "role" "group"
            , A.attribute "aria-label" "pan map"
            , A.css
                [ S.row
                , S.itemsCenter
                , S.g1
                ]
            ]
            [ H.span
                []
                [ H.text "pan"
                ]
            , panButton "←" "pan left" PanLeftClicked
            , panButton "↑" "pan up" PanUpClicked
            , panButton "↓" "pan down" PanDownClicked
            , panButton "→" "pan right" PanRightClicked
            ]
        , H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.itemsCenter
                , S.g2
                ]
            ]
            [ H.span
                []
                [ H.text "zoom"
                ]
            , Button.secondary "−" ZoomOutClicked
                |> Button.toHtml
            , H.span
                []
                [ H.text (String.fromInt (round (camera.zoom * 100)) ++ "%")
                ]
            , Button.secondary "+" ZoomInClicked
                |> Button.toHtml
            , Button.secondary "reset view" ResetViewClicked
                |> Button.toHtml
            ]
        ]


panButton : String -> String -> Msg -> Html Msg
panButton arrow label msg =
    Button.secondary arrow msg
        |> Button.accessibleLabel label
        |> Button.toHtml


selectionText : Model -> String
selectionText model =
    case selectedPosition model of
        Nothing ->
            ""

        Just position ->
            if
                List.any
                    (\depot ->
                        depot.position == position
                    )
                    model.depots
            then
                "supply depot"

            else
                Terrain.label (Map.terrainAt model.map position)


loadFailedView :
    Graphql.Http.Error Flags
    -> { retry : msg, returnHome : msg }
    -> List (Html msg)
loadFailedView error events =
    let
        message : String
        message =
            ApiRequest.errorMessage error
    in
    [ H.div
        [ A.css
            [ S.flex1
            , S.col
            , S.itemsCenter
            , S.justifyCenter
            ]
        ]
        [ [ H.p
                [ A.attribute "role" "status"
                ]
                [ H.text message
                ]
          , H.div
                [ A.css
                    [ S.row
                    , S.g2
                    , S.flexWrap
                    ]
                ]
                [ Button.primary "return home" events.returnHome
                    |> Button.toHtml
                , Button.secondary "retry" events.retry
                    |> Button.toHtml
                ]
          ]
            |> Card.toHtml
                (Card.compactForm
                    |> Card.withHeader (CardHeader.simple "lobby unavailable")
                )
        ]
    ]


cargoView : Model -> Unit -> Html Msg
cargoView model unit =
    let
        cargo : List Unit
        cargo =
            List.filter (\passenger -> Unit.carrierId passenger == Just unit.id) model.units

        passengerButton : Unit -> Html Msg
        passengerButton passenger =
            Button.secondary ("cargo: " ++ Unit.label passenger) (CargoUnitClicked passenger.id)
                |> Button.toHtml

        cargoSummary : Html Msg
        cargoSummary =
            H.p
                []
                [ H.text ("cargo: " ++ String.fromInt (List.length cargo) ++ "/" ++ String.fromInt unit.cargoCapacity)
                ]

        cargoContents : List (Html Msg)
        cargoContents =
            cargoSummary :: List.map passengerButton cargo
    in
    if unit.cargoCapacity > 0 then
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
                "holding for loading or unloading. revoke the other unit's order before changing this order."

            else if Unit.carrierId unit /= Nothing then
                "aboard a truck. select the truck and choose its move destination to unload passengers."

            else if unit.kind == UnitKind.Truck then
                "move onto allied infantry or a field gun to load it. the unit will hold. trucks carry two units."

            else if unit.kind == UnitKind.Tank then
                "tanks cannot board trucks."

            else
                "move onto an allied truck with room to board. the truck will hold. trucks carry two units."
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

        passengerCheckbox : Unit -> Html Msg
        passengerCheckbox unit =
            UnloadPassenger.toHtml
                { checked = List.member unit.id choice.checked
                , onCheck = UnloadUnitToggled unit.id
                }
                unit

        choices : List (Html Msg)
        choices =
            List.map passengerCheckbox passengers

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
                [ A.attribute "method" "dialog" ]
                [ proceedButton ]

        content : List (Html Msg)
        content =
            choices ++ [ actions ]
    in
    Dialog.make unloadDialogHtmlId "unload" DialogDismissed content


{-| The active planning alternative determines the dialog; no dialog state is stored.
-}
dialog : Model -> Maybe (Dialog Msg)
dialog model =
    case model.phase of
        TurnLifecycle.Planning (PlanningModel.ConfirmingSubmission _) ->
            Just (submissionWarning model)

        TurnLifecycle.Planning (PlanningModel.ChoosingPassengers choice) ->
            Just (unloadChecklist model choice)

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
        ownCount : Int
        ownCount =
            List.length (List.filter (\unit -> isOwnUnit model unit && Unit.onBoard unit) model.units)

        status : String
        status =
            case model.phase of
                TurnLifecycle.Playing _ ->
                    "playing turn " ++ String.fromInt (model.turnNumber - 1)

                TurnLifecycle.Submitting _ ->
                    "submitting orders…"

                TurnLifecycle.WaitingForOpponent _ ->
                    "orders submitted"

                TurnLifecycle.Planning _ ->
                    String.fromInt (ownCount - List.length (unitsWithoutOrders model))
                        ++ "/"
                        ++ String.fromInt ownCount
                        ++ " units ready"

        submitLabel : String
        submitLabel =
            TurnLifecycle.toLabel model.phase

        opponentStatus : String
        opponentStatus =
            case model.phase of
                TurnLifecycle.WaitingForOpponent _ ->
                    "waiting for the other player"

                _ ->
                    if model.opponentSubmitted then
                        "other player: submitted"

                    else
                        "other player: planning"

        submitLocked : Bool
        submitLocked =
            planningLocked model || isChoosingUnload model

        submitAction : Button.Button Msg
        submitAction =
            if submitLocked then
                Button.disabled submitLabel

            else if readyToSubmit model then
                Button.primary submitLabel SubmitTurnClicked

            else
                Button.secondary submitLabel SubmitTurnClicked

        submitButton : Html Msg
        submitButton =
            submitAction
                |> Button.large
                |> Button.toHtml

        errorDetails : List (Html Msg)
        errorDetails =
            case model.turnError of
                Nothing ->
                    []

                Just message ->
                    [ H.p [ A.attribute "role" "alert" ] [ H.text message ] ]

        content : List (Html Msg)
        content =
            [ H.p [ A.attribute "role" "status" ]
                [ H.text ("turn " ++ String.fromInt model.turnNumber ++ " · " ++ status) ]
            , H.p [] [ H.text opponentStatus ]
            ]
    in
    H.section
        [ A.attribute "aria-label" "game controls"
        , A.css
            [ S.bgGray1
            , S.outdentTopRight
            , S.absolute
            , S.bottom0
            , S.left0
            , S.z1
            , S.p3
            , S.g3
            , S.col
            , S.justifySpaceBetween
            , S.shrink0
            , S.wrapAnywhere
            , S.w120
            , S.maxWFull
            , S.h40
            , S.belowWidth 640 [ S.h80 ]
            ]
        ]
        [ H.div
            [ A.css [ S.row, S.flexWrap, S.itemsStart, S.g3 ] ]
            [ submitButton
            , H.div
                [ A.css
                    [ S.flex1
                    , S.minW0
                    , S.overflowAuto
                    , S.maxH18
                    , S.belowWidth 640 [ S.basisFull, S.maxH24 ]
                    ]
                ]
                [ H.div
                    [ A.css [ S.col, S.g2 ] ]
                    (content ++ errorDetails)
                ]
            ]
        , H.div
            [ A.css [ S.borderT, S.borderGray2, S.pt3 ] ]
            [ viewControls model
            ]
        ]


resolutionSummary : Model -> Html Msg
resolutionSummary model =
    let
        summary : String
        summary =
            case model.turnResolution of
                Nothing ->
                    ""

                Just resolution ->
                    let
                        conflicts : Int
                        conflicts =
                            List.length (List.filter (\event -> event.kind == EventKind.DestinationConflict) resolution.events)
                    in
                    if conflicts > 0 then
                        "turn " ++ String.fromInt resolution.number ++ ": " ++ String.fromInt conflicts ++ " units held because opposing destinations matched."

                    else
                        ""
    in
    H.p
        []
        [ H.text summary ]


boardView : Model -> Html Msg
boardView model =
    let
        camera : Camera
        camera =
            BattlefieldNavigation.camera model.navigation

        cursorStyle : Css.Style
        cursorStyle =
            if BattlefieldNavigation.active model.navigation then
                Css.cursor Css.grabbing

            else
                Css.cursor Css.grab
    in
    H.div
        [ A.attribute "tabindex" "0"
        , A.attribute "aria-label" "battlefield navigation"
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
            , Css.property "container-type" "size"
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
                , Css.property "width" "min(80%, 76vh)"
                , S.shrink0
                , Css.property "transform"
                    ("translate(" ++ String.fromFloat camera.offset.x ++ "px, " ++ String.fromFloat camera.offset.y ++ "px) scale(" ++ String.fromFloat camera.zoom ++ ")")
                ]
            ]
            [ boardHtml model
            ]
        , commandMenu model
        ]


at : Coordinate -> List (Svg msg) -> Svg msg
at position children =
    Svg.g
        [ SA.transform ("translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")")
        ]
        children


boardHtml : Model -> Html Msg
boardHtml model =
    let
        rotationPreview : Maybe RotationSelection
        rotationPreview =
            rotationSelection model

        visibleTiles : List Coordinate
        visibleTiles =
            model.visibleTiles

        choosingDestination : Bool
        choosingDestination =
            pathPreview model /= Nothing || isChoosingUnload model

        reachable : List Coordinate
        reachable =
            List.map .destination (moveOptions model)

        paths : List (List Coordinate)
        paths =
            List.map PlannedOrder.path (plannedOrders model)

        orderedUnits : List UnitId
        orderedUnits =
            List.map .unitId (plannedOrders model)

        unloads : List UnloadRoute
        unloads =
            plannedUnloadRoutes model

        previewedPath : List Coordinate
        previewedPath =
            pathPreview model |> Maybe.map .path |> Maybe.withDefault []

        movingPositions : List { unitId : UnitId, position : Point }
        movingPositions =
            TurnPlayback.movingPositions (playback model)

        selected : Maybe Coordinate
        selected =
            selectedPosition model

        tileTarget : Coordinate -> Svg Msg
        tileTarget position =
            let
                baseAttributes : List (Svg.Attribute Msg)
                baseAttributes =
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , SA.stroke S.nightwood2Str
                    , SA.strokeOpacity "0.22"
                    , SA.strokeWidth "0.25"
                    , Ev.onMouseOver (MouseOverTile position)
                    , onClickWithDetail (ClickedTile position)
                    ]

                movementAttributes : List (Svg.Attribute Msg)
                movementAttributes =
                    if List.member position reachable then
                        [ HA.attribute "tabindex" "0"
                        , HA.attribute "role" "button"
                        , HA.attribute "aria-label" ("move to (" ++ String.fromInt position.x ++ ", " ++ String.fromInt position.y ++ ")")
                        , onKeyDown
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

        terrainFilter : Coordinate -> String
        terrainFilter position =
            let
                visibilityFilters : List String
                visibilityFilters =
                    if List.member position visibleTiles then
                        []

                    else
                        [ "saturate(0.18) brightness(0.58)" ]

                unavailable : Bool
                unavailable =
                    choosingDestination
                        && not (List.member position reachable)
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

        depotView : Depot -> Svg Msg
        depotView depot =
            at depot.position
                [ Svg.image
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.xlinkHref "/assets/supply-depot-illustrated-v1.png"
                    , HA.style "filter" (terrainFilter depot.position)
                    , HA.style "image-rendering" "auto"
                    , SA.pointerEvents "none"
                    , HA.attribute "aria-hidden" "true"
                    ]
                    []
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , HA.attribute "role" "button"
                    , HA.attribute "aria-label" "supply depot"
                    , Ev.onMouseOver (MouseOverDepot depot.position)
                    , onClickWithDetail (ClickedDepot depot.position)
                    , onKeyDown
                        { pressedEnter = PressedEnterOnDepot depot.position
                        , pressedSpace = PressedSpaceOnDepot depot.position
                        }
                    ]
                    [ Svg.title
                        []
                        [ Svg.text "supply depot"
                        ]
                    ]
                ]

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

                accessibleLabel : String
                accessibleLabel =
                    if passengerCount > 0 then
                        Unit.label unit ++ ", cargo: " ++ String.fromInt passengerCount ++ " / " ++ String.fromInt unit.cargoCapacity

                    else
                        Unit.label unit

                spriteFilter : String
                spriteFilter =
                    if List.member unit.id orderedUnits then
                        "brightness(0.6)"

                    else
                        "none"

                previewUnit : Unit
                previewUnit =
                    case rotationPreview of
                        Just rotation ->
                            if rotation.unitId == unit.id then
                                { unit | direction = Just rotation.direction }

                            else
                                unit

                        Nothing ->
                            unit

                facingClass : String
                facingClass =
                    if Maybe.map .unitId rotationPreview == Just unit.id then
                        "fightlines-rotation-preview"

                    else
                        ""

                transform : String
                transform =
                    case ListUtil.find (\moving -> moving.unitId == unit.id) movingPositions of
                        Just moving ->
                            "translate(" ++ String.fromFloat (moving.position.x * 16) ++ " " ++ String.fromFloat (moving.position.y * 16) ++ ")"

                        Nothing ->
                            "translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")"
            in
            Svg.g
                [ SA.transform transform
                , SA.class facingClass
                ]
                [ Svg.g
                    [ HA.style "filter" spriteFilter
                    ]
                    [ UnitSprite.toSvg (AnimationFrame.unitColumn model.frame unit.id) unit
                        |> StyledSvg.toUnstyled
                    ]
                , UnitFacing.toSvg (selected == Just position) previewUnit
                    |> StyledSvg.toUnstyled
                , UnitCargo.toSvg passengerCount
                    |> StyledSvg.toUnstyled
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , HA.attribute "role" "button"
                    , HA.attribute "aria-label" accessibleLabel
                    , Ev.onMouseOver (MouseOverUnit unit.id)
                    , onClickWithDetail (ClickedUnit unit.id)
                    , onKeyDown
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

        positions : List Coordinate
        positions =
            Map.positions model.map

        terrainTile : Coordinate -> Svg Msg
        terrainTile position =
            let
                fogAttributes : List (Svg.Attribute Msg)
                fogAttributes =
                    if List.member position visibleTiles then
                        []

                    else
                        [ HA.attribute "data-fog" "unseen"
                        ]

                appearanceAttributes : List (Svg.Attribute Msg)
                appearanceAttributes =
                    [ HA.style "filter" (terrainFilter position)
                    , SA.pointerEvents "none"
                    ]
            in
            Svg.g
                (appearanceAttributes ++ fogAttributes)
                [ at position
                    [ TerrainTile.toSvg
                        { theme = model.map.theme
                        , terrain = Map.terrainAt model.map position
                        }
                        |> StyledSvg.toUnstyled
                    ]
                ]

        terrain : Svg Msg
        terrain =
            Svg.g
                [ HA.style "image-rendering" "auto"
                ]
                (List.map terrainTile positions)

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

        destinationMarker : Coordinate -> Svg Msg
        destinationMarker position =
            at position
                [ Svg.circle
                    [ SA.cx "8"
                    , SA.cy "8"
                    , SA.r "2"
                    , SA.fill S.yellow5Str
                    ]
                    []
                ]

        plannedPath : List Coordinate -> List (Svg Msg)
        plannedPath path =
            let
                route : List (Svg Msg)
                route =
                    [ Svg.polyline
                        [ SA.points (pathPoints path)
                        , SA.fill "none"
                        , SA.stroke S.yellow5Str
                        , SA.strokeWidth "1.25"
                        , SA.strokeDasharray "2 1"
                        ]
                        []
                    ]

                destination : List (Svg Msg)
                destination =
                    path
                        |> List.reverse
                        |> List.head
                        |> Maybe.map destinationMarker
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []
            in
            route ++ destination

        previewPath : List Coordinate -> List (Svg Msg)
        previewPath path =
            if List.length path > 1 then
                [ Svg.polyline
                    [ SA.points (pathPoints path)
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "1.5"
                    ]
                    []
                ]

            else
                []

        movementOverlay : Svg Msg
        movementOverlay =
            let
                reachableTiles : List (Svg Msg)
                reachableTiles =
                    List.map reachableTile reachable

                plannedPaths : List (Svg Msg)
                plannedPaths =
                    List.concatMap plannedPath paths

                preview : List (Svg Msg)
                preview =
                    previewPath previewedPath
            in
            Svg.g
                [ SA.pointerEvents "none"
                , HA.attribute "aria-hidden" "true"
                ]
                (reachableTiles ++ plannedPaths ++ preview)

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
                , HA.attribute "aria-hidden" "true"
                , HA.attribute "data-planned-unloads" (String.fromInt (List.length unloads))
                ]
                (List.map unloadRoute unloads)

        rotationOverlay : List (Svg Msg)
        rotationOverlay =
            case rotationPreview of
                Just rotation ->
                    [ RotationChoices.toSvg model.map rotation.position rotation.direction
                        |> Svg.map RotationChoicesMsg
                    ]

                Nothing ->
                    []

        selection : List (Svg Msg)
        selection =
            selected
                |> Maybe.map selectionMarker
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    H.div
        [ A.css
            [ S.wFull
            , Css.Global.descendants
                [ Css.Global.selector "rect[role=button]"
                    [ Css.outline Css.none
                    , Css.pseudoClass "focus-visible"
                        [ Css.property "outline" ("0.5px solid " ++ S.yellow5Str)
                        , Css.property "outline-offset" "-1px"
                        , Css.property "border-radius" "0"
                        ]
                    ]
                ]
            ]
        ]
        [ Svg.svg
            [ SA.viewBox ("0 0 " ++ String.fromInt (model.map.width * 16) ++ " " ++ String.fromInt (model.map.height * 16))
            , SA.width "100%"
            , HA.attribute "role" "group"
            , HA.attribute "aria-label" "battlefield"
            ]
            (List.concat
                [ [ terrain, movementOverlay ]
                , List.map tileTarget positions
                , List.map depotView model.depots
                , List.filterMap (\unit -> Unit.boardPosition unit |> Maybe.map (unitView unit)) model.units
                , [ unloadOverlay ]
                , selection
                , rotationOverlay
                ]
            )
            |> H.fromUnstyled
        ]


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
            , HA.attribute "aria-hidden" "true"
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
                            ChoosingDirection _ ->
                                [ leftKeys (DirectionKeyPressed Facing.West)
                                , rightKeys (DirectionKeyPressed Facing.East)
                                , upKeys (DirectionKeyPressed Facing.North)
                                , downKeys (DirectionKeyPressed Facing.South)
                                ]

                            ChoosingMove _ ->
                                [ leftKeys (PathDirectionKeyPressed Facing.West)
                                , rightKeys (PathDirectionKeyPressed Facing.East)
                                , upKeys (PathDirectionKeyPressed Facing.North)
                                , downKeys (PathDirectionKeyPressed Facing.South)
                                , KeyCmd.enter PathEnterPressed
                                ]

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
    in
    KeyCmd.batch
        [ KeyCmd.escape EscapePressed
        , camera
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
        , Time.every 2000 PollTimerElapsed
        , if playback model /= Nothing then
            Browser.Events.onAnimationFrameDelta PlaybackFrameElapsed

          else
            Sub.none
        , BattlefieldNavigation.subscriptions model.navigation
            |> Sub.map BattlefieldNavigationMsg
        ]
