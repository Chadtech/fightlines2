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
import Api.Enum.MapType
    exposing
        ( MapType
        )
import Api.Enum.PlayerNumber
    exposing
        ( PlayerNumber
        )
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
        , FacingPurpose(..)
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
import Shared
import Style as S
import Supply
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as Ev
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
import View.DepotStatus as DepotStatus
import View.Dialog as Dialog exposing (Dialog)
import View.MovementRoute as MovementRoute
import View.RotationChoices as RotationChoices
import View.SupplyCrate as SupplyCrate
import View.TerrainInfo as TerrainInfo
import View.TerrainTile as TerrainTile
import View.TurnControls as TurnControls
import View.UnitCargo as UnitCargo
import View.UnitCommands as UnitCommands
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
    , side : PlayerNumber
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
    | UnitDeathMsg UnitDeath.Msg
    | CombatTheaterMsg CombatTheater.Msg
    | DirectionKeyPressed Direction
    | PathDirectionKeyPressed Direction
    | PathEnterPressed
    | NextUnorderedUnitKeyPressed
    | ClearMoveClicked
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

        ( skipLossDialogs, lossPreferenceError ) =
            loadPreference unitLossPreferenceKey
    in
    { currentTurn = CurrentTurn.init flags.snapshot.turn
    , shared =
        shared
            |> Shared.addError maybeError
            |> Shared.addError lossPreferenceError
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
    { model | shared = shared }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


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
            List.filter (\passenger -> Unit.carrierId passenger == Just unit.id) model.units
                |> List.length

        crates : Int
        crates =
            unit.resources
                |> Maybe.map (.supplyCargo >> List.length)
                |> Maybe.withDefault 0

        incoming : Int
        incoming =
            List.filter boardsTruck (plannedOrders model)
                |> List.length

        boardsTruck : PlannedOrder -> Bool
        boardsTruck order =
            (order.unitId /= unit.id)
                && PlannedOrder.isMoving order
                && (Just (PlannedOrder.destination order) == Unit.boardPosition unit)

        destination : Maybe Coordinate
        destination =
            plannedOrders model
                |> ListUtil.find (\order -> order.unitId == unit.id)
                |> Maybe.map PlannedOrder.destination

        pickup : Int
        pickup =
            destination
                |> Maybe.andThen
                    (\position ->
                        OrderPlanning.loadingTarget (planningContext model) unit position (plannedOrders model)
                    )
                |> Maybe.map (\_ -> 1)
                |> Maybe.withDefault 0

        depot : Maybe Depot
        depot =
            destination
                |> Maybe.andThen destinationDepot

        destinationDepot : Coordinate -> Maybe Depot
        destinationDepot position =
            ListUtil.find (\source -> source.position == position) model.depots

        stockLimit : Int
        stockLimit =
            case
                depot
                    |> Maybe.andThen .stock
            of
                Just stock ->
                    (stock.current + model.supplyRules.crateCapacity - 1) // model.supplyRules.crateCapacity

                Nothing ->
                    2
    in
    min stockLimit (max 0 (unit.cargoCapacity - passengers - crates - incoming - pickup))


planningContext : Model -> OrderPlanning.Context
planningContext model =
    { map = model.map
    , units = model.units
    , movementRules = model.movementRules
    , supplyCrates = model.supplyCrates
    , depots = model.depots
    , playerSides = List.filter .isYou model.players |> List.map .side
    }


mapPlanning : (OrderPlanning.Model -> OrderPlanning.Model) -> Model -> Model
mapPlanning transition model =
    { model | currentTurn = CurrentTurn.mapPlanning transition model.currentTurn }


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
    model
        |> mapPlanning (OrderPlanning.dismissDialog model.depots)


partialOrdersDialogHtmlId : String
partialOrdersDialogHtmlId =
    "submit-turn-warning"


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
            |> Maybe.map TurnPlayback.losses
            |> Maybe.andThen List.head


ownerName : Model -> Unit -> Maybe String
ownerName model unit =
    let
        ownsUnit : Player -> Bool
        ownsUnit player =
            player.side == unit.playerNumber
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
                    { model | shared = Shared.addError (Just (Error.UnitOwnerNotFound missing)) model.shared }

        Nothing ->
            model


activeDialogHtmlId : Model -> Maybe String
activeDialogHtmlId model =
    case unitLoss model of
        Just loss ->
            Just (UnitDeath.dialogHtmlId loss)

        Nothing ->
            cargoDialogHtmlId model.currentTurn.phase


combatExchange : Model -> Maybe TurnPlayback.Exchange
combatExchange model =
    playback model |> Maybe.andThen TurnPlayback.combat


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
                    Direction.between (PlannedOrder.destination plan) unload.destination
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
        |> Maybe.andThen (OrderPlanning.commandMenuUnit (planningContext model))


submitRequest : LobbyId -> Model -> Graphql.Http.Request Snapshot
submitRequest lobbyId model =
    let
        orders : List PlannedOrder
        orders =
            OrderPlanning.submissionOrders (planningContext model) (plannedOrders model)
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
                    { shots = []
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
    OrderPlanning.receivingLoad (planningContext model) unit (plannedOrders model)


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


saveRotation : Direction -> Model -> Model
saveRotation direction model =
    model
        |> mapPlanning
            (OrderPlanning.saveRotation (planningContext model) direction)


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

                CommandMenu _ ->
                    Nothing

                ChoosingMove _ ->
                    Nothing

        _ ->
            Nothing


previewRotation : Direction -> Model -> Model
previewRotation direction model =
    if BattlefieldNavigation.active model.navigation then
        model

    else
        model |> mapPlanning (OrderPlanning.previewRotation direction)


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
        |> SS.with (SnapshotApi.scenario (Scenario.depots Depot.selection))
        |> SS.with (SnapshotApi.scenario (Scenario.supplyCrates Supply.crateSelection))
        |> SS.with (SnapshotApi.scenario (Scenario.supplyRules Supply.rulesSelection))
        |> SS.with (SnapshotApi.visibleTiles Coordinate.selection)
        |> SS.with (SnapshotApi.movementRules movementRuleSelection)
        |> SS.with Turn.selection
        |> SS.with (TurnPlayback.selection Unit.selection Coordinate.selection)


destinationFeedback : Model -> DestinationFeedback
destinationFeedback model =
    TurnLifecycle.planning model.currentTurn.phase |> Maybe.map OrderPlanning.destinationFeedback |> Maybe.withDefault NoDestinationFeedback


pathPreview : Model -> Maybe Movement.Option
pathPreview model =
    TurnLifecycle.planning model.currentTurn.phase |> Maybe.andThen OrderPlanning.pathPreview


moveOptions : Model -> List Movement.Option
moveOptions model =
    TurnLifecycle.planning model.currentTurn.phase |> Maybe.map OrderPlanning.moveOptions |> Maybe.withDefault []


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
        model |> mapPlanning (OrderPlanning.selectTile (planningContext model) position)


previewTile : Coordinate -> Model -> Model
previewTile position model =
    if BattlefieldNavigation.active model.navigation && pathPreview model == Nothing then
        model

    else
        model |> mapPlanning (OrderPlanning.previewTile (planningContext model) position)


extendPath : Direction -> Model -> Model
extendPath direction model =
    if BattlefieldNavigation.active model.navigation then
        model

    else
        model |> mapPlanning (OrderPlanning.extendPath (planningContext model) direction)


confirmPath : Model -> Model
confirmPath model =
    model |> mapPlanning (OrderPlanning.confirmPath (planningContext model))


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
                        { htmlId = UnitCommands.optionHtmlId command }
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


preventDefault : Msg -> ( Msg, Bool )
preventDefault msg =
    ( msg, True )



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
                |> mapPlanning (OrderPlanning.toggleUnloadPassenger id checked)
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
                    (OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate index) checked)
                |> E.withOut

        CargoUnitClicked id ->
            model
                |> clearSelection
                |> selectUnit id
                |> E.withOut

        NextUnorderedUnitKeyPressed ->
            model
                |> mapPlanning (OrderPlanning.selectNextUnorderedUnit (planningContext model))
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
                |> E.withOut

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
                |> E.withOut

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
                |> E.withOut

        PressedSpaceOnUnit id ->
            model
                |> selectUnit id
                |> E.withOut

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
                |> E.withOut

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
                |> E.withOut

        PressedEnterOnDepot position ->
            model
                |> selectTile position
                |> E.withOut

        PressedSpaceOnDepot position ->
            model
                |> selectTile position
                |> E.withOut

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
                    if click.detail /= 0 && BattlefieldNavigation.suppressesClick model.navigation then
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
                        |> applyTurnSnapshot snapshot (CurrentTurn.pollSucceeded (turnObservation snapshot) model.currentTurn)
                        |> E.withOut

                Err error ->
                    { model | currentTurn = CurrentTurn.pollFailed (ApiRequest.errorMessage error) model.currentTurn }
                        |> E.withOut

        AnimationTimerElapsed _ ->
            if deathInFocus model || combatExchange model /= Nothing then
                model |> E.withOut

            else
                { model | frame = AnimationFrame.next model.frame }
                    |> E.withOut

        UnitDeathMsg lossMsg ->
            case lossMsg of
                UnitDeath.ContinueClicked unitId ->
                    let
                        currentTurn : CurrentTurn.Model
                        currentTurn =
                            model.currentTurn
                    in
                    { model | currentTurn = { currentTurn | phase = TurnLifecycle.acknowledgeLoss unitId currentTurn.phase } }
                        |> E.withOut

                UnitDeath.SkipDialogsChanged skip ->
                    ( { model | skipUnitLossDialogs = skip }
                    , E.toJs (ToJs.SetLocalStorage { key = unitLossPreferenceKey, value = Encode.bool skip })
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
    case model.currentTurn.phase of
        TurnLifecycle.Planning (OrderPlanning.OrdinaryPlanning { selection }) ->
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
    if planningLocked model || isChoosingUnload model || unloadChoice model.currentTurn.phase /= Nothing then
        model |> E.withOut

    else if List.isEmpty (unitsWithoutOrders model) then
        model
            |> submitTurn lobbyId

    else
        ( model
            |> mapPlanning OrderPlanning.showSubmissionWarning
        , E.toJs (ToJs.OpenDialog { htmlId = partialOrdersDialogHtmlId })
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
                |> E.withOut

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
    let
        hasUnitLoss : Bool
        hasUnitLoss =
            unitLoss model /= Nothing

        hasCombatExchange : Bool
        hasCombatExchange =
            combatExchange model /= Nothing

        interactionBlocked : Bool
        interactionBlocked =
            hasCombatExchange || hasUnitLoss

        animationClass : String
        animationClass =
            if hasUnitLoss then
                "fightlines-death-focus fightlines-loss-focus"

            else if hasCombatExchange then
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
                , Css.property "width" "min(18rem, 45vw)"
                ]
            ]
            [ selectionView model
            , panelFooter model
            ]
        ]
    , combatOverlay
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
                    let
                        unitPlayerName : String
                        unitPlayerName =
                            let
                                ownsUnit : Player -> Bool
                                ownsUnit player =
                                    player.side == unit.playerNumber
                            in
                            model.players
                                |> List.filter ownsUnit
                                |> List.head
                                |> Maybe.map .name
                                |> Maybe.withDefault ""
                    in
                    -- Changing units resets native details disclosures in the inspector.
                    [ Keyed.node "div"
                        []
                        [ ( UnitId.toString unit.id
                          , H.div
                                [ A.css
                                    [ S.col
                                    , S.g3
                                    ]
                                ]
                                [ UnitStatus.toHtml unitPlayerName unit
                                , cargoView model unit
                                , supplyControls model unit
                                , movementView model
                                , terrainView model
                                ]
                          )
                        ]
                    ]

                Nothing ->
                    case inspectionPosition model of
                        Just position ->
                            let
                                supplyDetails : List (Html Msg)
                                supplyDetails =
                                    case ListUtil.find (\depot -> depot.position == position) model.depots of
                                        Just depot ->
                                            [ DepotStatus.toHtml depot ]

                                        Nothing ->
                                            supplyCrateDetails model position

                                terrainDetails : List (Html Msg)
                                terrainDetails =
                                    [ terrainView model
                                    ]

                                tileContent : List (Html Msg)
                                tileContent =
                                    supplyDetails ++ terrainDetails

                                inspectionKey : String
                                inspectionKey =
                                    "tile:" ++ String.fromInt position.x ++ "," ++ String.fromInt position.y
                            in
                            [ Keyed.node "div"
                                []
                                [ ( inspectionKey
                                  , H.div
                                        [ A.css
                                            [ S.col
                                            , S.g3
                                            ]
                                        ]
                                        tileContent
                                  )
                                ]
                            ]

                        Nothing ->
                            []
    in
    H.section
        [ Aria.label "selection"
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
                                        "supply crate " ++ String.fromInt (index + 1)

                                    _ ->
                                        Unit.label unit
                        in
                        [ H.p
                            []
                            [ H.text ("choose an adjacent square to unload " ++ unloadingCargoLabel)
                            ]
                        , Button.secondary "skip remaining cargo" UnloadSkipped
                            |> Button.toHtml
                        ]

                    else if Unit.carrierId unit /= Nothing || receivingLoad unit model then
                        transportDetails model unit

                    else if choosingAmbush model then
                        ambushDetails unit

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
                    [ Button.secondary "back to commands" ClearMoveClicked
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
                                    "supply run to ("
                                        ++ String.fromInt supply.destination.x
                                        ++ ", "
                                        ++ String.fromInt supply.destination.y
                                        ++ "): load "
                                        ++ String.fromInt (PlannedOrder.loadingCrates supply)
                                        ++ " · unload "
                                        ++ String.fromInt (List.length (PlannedOrder.unloadingCrates supply))

                                PlannedOrder.Hold _ ->
                                    "hold position"

                                PlannedOrder.Unload _ ->
                                    "hold position"

                                PlannedOrder.Ambush ambush ->
                                    "ambush: " ++ Direction.label ambush.direction

                                PlannedOrder.Rotate rotation ->
                                    "rotate: " ++ Direction.label rotation.direction

                                PlannedOrder.AttackMove move ->
                                    "attack move: ("
                                        ++ String.fromInt move.destination.x
                                        ++ ", "
                                        ++ String.fromInt move.destination.y
                                        ++ ") · movement: "
                                        ++ Movement.pointsLabel move.cost

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


plannedAmbushFacing : Model -> Unit -> Unit
plannedAmbushFacing model unit =
    case ListUtil.find (\order -> order.unitId == unit.id) (plannedOrders model) of
        Just order ->
            case order.action of
                PlannedOrder.Ambush facing ->
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
                ChoosingDirection AmbushFacing _ ->
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
        [ H.text ("range: " ++ String.fromInt rules.range ++ " · damage: " ++ String.fromInt rules.damage)
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
                        "this move will board " ++ Unit.label target ++ ". the truck will hold position."
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


viewControls : Model -> Html Msg
viewControls model =
    let
        camera : Camera
        camera =
            BattlefieldNavigation.camera model.navigation
    in
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
                    [ H.text (String.fromInt (round (camera.zoom * 100)) ++ "%") ]
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
                  , TerrainInfo.toHtml (Map.terrainAt model.map coordinate)
                  )
                ]

        Nothing ->
            H.text ""


supplyControls : Model -> Unit -> Html Msg
supplyControls model unit =
    let
        crates : List Supply.Stock
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
                crateControls : Int -> Supply.Stock -> Html Msg
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
                                [ H.text ("crate " ++ String.fromInt (index + 1) ++ ": " ++ String.fromInt stock.current ++ "/" ++ String.fromInt stock.maximum ++ pending)
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
                        [ H.text "automatically refills nearby units before upkeep, while stock lasts"
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


supplyCrateDetails : Model -> Coordinate -> List (Html Msg)
supplyCrateDetails model position =
    let
        stockText : Supply.Stock -> String
        stockText stock =
            "supplies: " ++ String.fromInt stock.current ++ "/" ++ String.fromInt stock.maximum

        crates : List (Html Msg)
        crates =
            model.supplyCrates
                |> List.filter (\crate -> crate.position == position)
                |> List.map crateDetails

        crateDetails : Supply.GroundCrate -> Html Msg
        crateDetails crate =
            H.p
                []
                [ H.text ("supply crate · " ++ stockText crate.stock)
                ]

        hasSupplySource : Bool
        hasSupplySource =
            not (List.isEmpty crates)

        rules : List (Html Msg)
        rules =
            if hasSupplySource then
                [ H.p
                    []
                    [ H.text "refills units on or beside this square before upkeep, while stock lasts"
                    ]
                ]

            else
                []
    in
    crates ++ rules


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
                { checked = List.member (OrderPlanning.Passenger unit.id) choice.checked
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

        crateCheckbox : Int -> Supply.Stock -> Html Msg
        crateCheckbox index stock =
            let
                label : String
                label =
                    "supply crate " ++ String.fromInt (index + 1)
            in
            Checkbox.toHtml
                { label = label
                , checked = List.member (OrderPlanning.Crate index) choice.checked
                , onCheck = UnloadCrateToggled index
                }
                [ H.img
                    [ A.src "/assets/supply-crate-illustrated-v1.png"
                    , A.alt ""
                    , A.width 48
                    , A.height 48
                    ]
                    []
                , H.span
                    []
                    [ H.text (label ++ " · supplies " ++ String.fromInt stock.current ++ "/" ++ String.fromInt stock.maximum)
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
            choices ++ actionContent

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
        "load supply crates"
        DialogDismissed
        [ H.p
            []
            [ H.text "how many crates should the truck load from this depot?"
            ]
        , actions
        ]


{-| The active planning alternative determines the dialog; no dialog state is stored.
-}
dialog : Model -> Maybe (Dialog Msg)
dialog model =
    MaybeUtil.lazyFirst
        [ lossDialog model
        , planningDialog model
        ]


lossDialog : Model -> () -> Maybe (Dialog Msg)
lossDialog model _ =
    let
        notice : TurnPlayback.Loss -> Dialog Msg
        notice loss =
            UnitDeath.dialog
                { skipDialogs = model.skipUnitLossDialogs
                , isOwn = isOwnUnit model loss.unit
                , details = UnitLoss.resolve (ownerName model) loss
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
                , side = player.side
                , status = status
                }

        submitLocked : Bool
        submitLocked =
            planningLocked model || isChoosingUnload model

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

        submitButton : Html Msg
        submitButton =
            H.div
                [ A.css
                    [ S.col
                    , S.g2
                    , S.shrink0
                    ]
                ]
                [ H.p
                    []
                    [ H.text ("turn " ++ String.fromInt model.currentTurn.number) ]
                , TurnControls.submit activity submitLabel
                    |> H.map TurnControlsMsg
                ]

        errorDetails : List (Html Msg)
        errorDetails =
            case model.currentTurn.error of
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
                    (List.map playerRow model.players)
                ]
            ]

        feedbackContent : List (Html Msg)
        feedbackContent =
            content ++ errorDetails
    in
    TurnControls.panel
        [ submitButton
        , TurnControls.feedback feedbackContent
        , TurnControls.navigation (viewControls model)
        ]


battlefieldView : Model -> Html Msg
battlefieldView model =
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
                , Css.property "width" Camera.boardWidth
                , S.shrink0
                , Css.property "transform"
                    (Camera.transform camera)
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

        choosingDestination : Bool
        choosingDestination =
            pathPreview model /= Nothing || isChoosingUnload model

        reachable : List Coordinate
        reachable =
            List.map .destination (moveOptions model)

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
            if isChoosingUnload model then
                "unload at"

            else if attacking then
                "attack move to"

            else
                "move to"

        previewPurpose : MovementRoute.Purpose
        previewPurpose =
            if attacking then
                MovementRoute.Attack

            else
                MovementRoute.Travel

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

        crateReservation : PlannedOrder.CrateUnload -> Svg Msg
        crateReservation unload =
            at unload.destination
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
            at crate.position
                [ SupplyCrate.toSvg
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , Aria.svgRole Aria.Button
                    , Aria.svgLabel "supply crate"
                    , onClickWithDetail (ClickedTile crate.position)
                    , onBoardActivationKeyDown
                        { pressedEnter = PressedEnterOnTile crate.position
                        , pressedSpace = PressedSpaceOnTile crate.position
                        }
                    ]
                    []
                ]

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
                    , Aria.svgHidden True
                    ]
                    []
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , Aria.svgRole Aria.Button
                    , Aria.svgLabel "supply depot"
                    , Ev.onMouseOver (MouseOverDepot depot.position)
                    , onClickWithDetail (ClickedDepot depot.position)
                    , onBoardActivationKeyDown
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

        previewedUnit : Unit -> Unit
        previewedUnit unit =
            case rotationPreview of
                Just rotation ->
                    if rotation.unitId == unit.id then
                        Unit.faceDirection (Just rotation.direction) unit

                    else
                        plannedAmbushFacing model unit

                Nothing ->
                    plannedAmbushFacing model unit

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

        spotlightView : TurnPlayback.Exchange -> Svg Msg
        spotlightView exchange =
            if
                (playback model
                    |> Maybe.andThen TurnPlayback.panels
                    |> Maybe.map .mapView
                )
                    == Just TurnPlayback.SeeingMap
            then
                CombatEffects.mapPeek model.map exchange

            else
                CombatEffects.spotlight model.map exchange

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

                crateCount : Int
                crateCount =
                    if unit.kind == UnitKind.Truck then
                        Unit.crateCount unit

                    else
                        0

                cargoCount : Int
                cargoCount =
                    passengerCount + crateCount

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
                            ++ ", supply crates: "
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
                    if List.member unit.id orderedUnits then
                        "brightness(0.6)"

                    else
                        "none"

                previewUnit : Unit
                previewUnit =
                    previewedUnit unit

                transform : String
                transform =
                    unitTransform unit position
            in
            Svg.g
                [ SA.transform transform
                ]
                [ Svg.g
                    [ HA.style "filter" spriteFilter
                    ]
                    [ previewUnit
                        |> UnitSprite.toSvg
                            (AnimationFrame.unitColumn model.frame unit.id)
                        |> StyledSvg.toUnstyled
                    ]
                , UnitCargo.toSvg passengerCount
                    |> StyledSvg.toUnstyled
                , UnitCargo.supplyToSvg crateCount
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

        plannedPath : PlannedOrder -> List (Svg Msg)
        plannedPath order =
            let
                purpose : MovementRoute.Purpose
                purpose =
                    if PlannedOrder.isAttackMove order then
                        MovementRoute.Attack

                    else
                        MovementRoute.Travel
            in
            MovementRoute.planned purpose (PlannedOrder.path order)

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
                    MovementRoute.preview previewPurpose previewedPath
            in
            Svg.g
                [ SA.pointerEvents "none"
                , Aria.svgHidden True
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
                                ChoosingDirection AmbushFacing direction ->
                                    Unit.boardPosition unit
                                        |> Maybe.map (\position -> [ Ambush.coverage model.map position direction unit.combatRules ])
                                        |> Maybe.withDefault []

                                _ ->
                                    []

                        _ ->
                            []
            in
            List.filterMap saved (plannedOrders model) ++ preview

        shotOverlay : Svg Msg
        shotOverlay =
            case model.currentTurn.phase of
                TurnLifecycle.Playing playing ->
                    CombatEffects.impacts (TurnPlayback.visibleShots playing.animation)

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
            if choosingAmbush model then
                RotationChoices.ambushToSvg

            else
                RotationChoices.toSvg

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
        , Aria.svgRole Aria.Group
        , Aria.svgLabel "battlefield"
        ]
        (List.concat
            [ [ terrain, movementOverlay ]
            , List.map tileTarget positions
            , List.map depotView model.depots
            , List.map crateView model.supplyCrates
            , List.concatMap (PlannedOrder.crateUnloads >> List.map crateReservation) (plannedOrders model)
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
            , spotlightOverlay
            , lossOverlay
            ]
        )


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

                            ChoosingMove _ ->
                                [ leftKeys (PathDirectionKeyPressed DirectionEnum.West)
                                , rightKeys (PathDirectionKeyPressed DirectionEnum.East)
                                , upKeys (PathDirectionKeyPressed DirectionEnum.North)
                                , downKeys (PathDirectionKeyPressed DirectionEnum.South)
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
    if combatExchange model /= Nothing then
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
