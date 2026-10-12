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
    , update
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
import KeyCmd exposing (KeyCmd)
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
import Point exposing (Point)
import Ports.Js.To as ToJs
import Shared
import Style as S
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
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import View.Ambush as Ambush
import View.Aria as Aria
import View.Button as Button
import View.CombatEffects as CombatEffects
import View.CombatTheater as CombatTheater
import View.Dialog as Dialog exposing (Dialog)
import View.RotationChoices as RotationChoices
import View.TerrainInfo as TerrainInfo
import View.TerrainTile as TerrainTile
import View.TurnControls as TurnControls
import View.UnitCargo as UnitCargo
import View.UnitCommands as UnitCommands
import View.UnitDeath as UnitDeath
import View.UnitFacing as UnitFacing
import View.UnitSprite as UnitSprite
import View.UnitStatus as UnitStatus
import View.UnloadPassenger as UnloadPassenger



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { currentTurn : CurrentTurn.Model
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
    | CombatTheaterMsg CombatTheater.Msg
    | DirectionKeyPressed Direction
    | PathDirectionKeyPressed Direction
    | PathEnterPressed
    | NextUnorderedUnitKeyPressed
    | ClearMoveClicked
    | CargoUnitClicked UnitId
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
    { currentTurn = CurrentTurn.init flags.snapshot.turn
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


planningContext : Model -> OrderPlanning.Context
planningContext model =
    { map = model.map
    , units = model.units
    , movementRules = model.movementRules
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
        |> mapPlanning OrderPlanning.dismissDialog


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


combatExchange : Model -> Maybe TurnPlayback.Exchange
combatExchange model =
    playback model |> Maybe.andThen TurnPlayback.combat


deathInFocus : Model -> Bool
deathInFocus model =
    List.any (\unit -> Unit.onBoard unit && Unit.isDying unit) model.units


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
            , E.request (SubmitResponseReceived model.currentTurn.number) (submitRequest lobbyId model)
            )

        Nothing ->
            ( model, E.none )


unloadDialogHtmlId : String
unloadDialogHtmlId =
    "unload-passengers"


selectedUnit : Model -> Maybe Unit
selectedUnit model =
    OrderPlanning.selectedUnitFromSelection (planningContext model) (currentSelection model)


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
    TurnLifecycle.planning model.currentTurn.phase |> Maybe.andThen OrderPlanning.focusedCommand


commandMenuUnit : Model -> Maybe Unit
commandMenuUnit model =
    TurnLifecycle.planning model.currentTurn.phase |> Maybe.andThen (OrderPlanning.commandMenuUnit (planningContext model))


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
                TurnPlayback.initial snapshot.playbackFrames { shots = [], durationMs = 180, units = snapshot.units, visibleTiles = snapshot.visibleTiles }
        in
        { next
            | map = snapshot.map
            , depots = snapshot.depots
            , units = frame.units
            , visibleTiles = frame.visibleTiles
        }

    else
        next


plannedAction : Model -> Unit -> Movement.Option -> String
plannedAction model unit move =
    if Unit.carrierId unit /= Nothing && List.length move.path > 1 then
        "unload at"

    else if OrderPlanning.loadingTarget (planningContext model) unit move.destination (plannedOrders model) /= Nothing then
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
    model |> mapPlanning (OrderPlanning.focusCommand (planningContext model) command)


revokeSelectedOrder : Model -> Model
revokeSelectedOrder model =
    model |> mapPlanning (OrderPlanning.revokeSelectedOrder (planningContext model))


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
                        |> Maybe.map (\position -> { unitId = unit.id, position = position, direction = direction })

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
        |> SS.with (SnapshotApi.scenario (Scenario.depots (SS.map Depot (DepotApi.position Coordinate.selection))))
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
    if BattlefieldNavigation.active model.navigation then
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


finishBoardInteraction : Model -> Model -> ( Model, Eff Msg )
finishBoardInteraction previous next =
    let
        effect : Eff Msg
        effect =
            case ( unloadChoice previous.currentTurn.phase, unloadChoice next.currentTurn.phase ) of
                ( Nothing, Just _ ) ->
                    E.toJs (ToJs.OpenDialog { htmlId = unloadDialogHtmlId })

                _ ->
                    E.none
    in
    ( next, effect )


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
                |> mapPlanning (OrderPlanning.toggleUnloadPassenger id checked)
                |> E.withOut

        UnloadChoicesConfirmed ->
            model
                |> mapPlanning (OrderPlanning.confirmPassengers (planningContext model))
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

        NextUnorderedUnitKeyPressed ->
            model
                |> mapPlanning (OrderPlanning.selectNextUnorderedUnit (planningContext model))
                |> finishBoardInteraction model

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

        CombatTheaterMsg panelMsg ->
            case panelMsg of
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
            case TurnLifecycle.tick delta currentTurn.phase of
                Just next ->
                    applyPlaybackFrame next model
                        |> E.withOut

                Nothing ->
                    model |> E.withOut

        CurrentTurn.CombatEnterReleased ->
            continueCombat model
                |> E.withOut

        CurrentTurn.CombatSeeMapReleased ->
            setCombatMapView TurnPlayback.CardVisible model
                |> E.withOut


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
    { model | currentTurn = { currentTurn | phase = TurnLifecycle.setCombatMapView mapView currentTurn.phase } }


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
    let
        animationClass : String
        animationClass =
            if combatExchange model /= Nothing then
                "fightlines-combat-focus"

            else if deathInFocus model then
                "fightlines-death-focus"

            else
                ""

        combatAttributes : List (H.Attribute Msg)
        combatAttributes =
            if combatExchange model /= Nothing then
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
                |> Maybe.map (CombatTheater.toHtml model.map)
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
            [ boardView model
            , turnPanel model
            ]
        , H.aside
            [ Aria.label "game panel"
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
                                [ UnitStatus.toHtml (unitPlayerName model unit) unit
                                , cargoView model unit
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
                                hasDepot : Bool
                                hasDepot =
                                    List.any (\depot -> depot.position == position) model.depots

                                depotTitle : List (Html Msg)
                                depotTitle =
                                    if hasDepot then
                                        [ H.h2
                                            []
                                            [ H.text "supply depot" ]
                                        ]

                                    else
                                        []

                                tileContent : List (Html Msg)
                                tileContent =
                                    depotTitle ++ [ terrainView model ]
                            in
                            tileContent

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


unitPlayerName : Model -> Unit -> String
unitPlayerName model unit =
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
                        [ H.p [] [ H.text ("choose an adjacent square to unload " ++ Unit.label unit) ]
                        , Button.secondary "skip remaining units" UnloadSkipped |> Button.toHtml
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

                loadingDetails : List (Html Msg)
                loadingDetails =
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
                                PlannedOrder.Hold _ ->
                                    "hold position"

                                PlannedOrder.Unload _ ->
                                    "hold position"

                                PlannedOrder.Ambush ambush ->
                                    "ambush: " ++ Direction.label ambush.direction

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
    case model.currentTurn.phase of
        TurnLifecycle.Planning (OrderPlanning.ConfirmingSubmission _) ->
            Just (submissionWarning model)

        TurnLifecycle.Planning (OrderPlanning.ChoosingPassengers choice) ->
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
                        , Aria.svgRole Aria.Button
                        , Aria.svgLabel ("move to (" ++ String.fromInt position.x ++ ", " ++ String.fromInt position.y ++ ")")
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
                        Unit.label unit
                            ++ ", cargo: "
                            ++ String.fromInt passengerCount
                            ++ " / "
                            ++ String.fromInt unit.cargoCapacity

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
            , Aria.svgRole Aria.Group
            , Aria.svgLabel "battlefield"
            ]
            (List.concat
                [ [ terrain, movementOverlay ]
                , List.map tileTarget positions
                , List.map depotView model.depots
                , List.filterMap (\unit -> Unit.boardPosition unit |> Maybe.map (unitView unit)) model.units
                , ambushCoverage
                , [ unloadOverlay, shotOverlay ]
                , selection
                , rotationOverlay
                , facingOverlay
                , spotlightOverlay
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
