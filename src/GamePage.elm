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
import Coordinate exposing (Coordinate)
import Css
import Depot
import Direction
import Drag exposing (Drag)
import Effect as E
    exposing
        ( Eff
        )
import GameBoard exposing (GameBoard)
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
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
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
import PlanningState exposing (PlanningState, UnloadChoice, UnloadPlanning)
import Point exposing (Point)
import Ports.Js.To as ToJs
import Shared
import Style as S
import Terrain
import Time
import Turn
import TurnLifecycle exposing (Phase)
import TurnPlayback
import Unit exposing (Unit)
import UnitCommand
import UnitId exposing (UnitId)
import View.BoardViewport as Viewport
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Dialog as Dialog exposing (Dialog)
import View.RotationChoices as RotationChoices
import View.UnitCommands as UnitCommands
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
    , board : GameBoard
    , visibleTiles : List Coordinate
    , movementRules : List Movement.Rule
    , offset : Point
    , zoom : Float
    , drag : Maybe Drag
    , suppressClick : Bool
    , frame : AnimationFrame.Frame
    }


type alias Snapshot =
    { name : String
    , mapType : MapType
    , players : List Player
    , board : GameBoard
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


type Msg
    = BoardMsg GameBoard.Msg
    | ViewportMsg Viewport.Msg
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
            (TurnLifecycle.Planning PlanningState.init)
    , refreshing = False
    , turnError = Nothing
    , shared = shared
    , name = flags.snapshot.name
    , mapType = flags.snapshot.mapType
    , players = flags.snapshot.players
    , board = flags.snapshot.board
    , visibleTiles = flags.snapshot.visibleTiles
    , movementRules = flags.snapshot.movementRules
    , offset = { x = 0, y = 0 }
    , zoom = 1
    , drag = Nothing
    , suppressClick = False
    , frame = AnimationFrame.first
    }


load : LobbyId -> Graphql.Http.Request Flags
load id =
    Api.Query.game { id = LobbyId.toString id } (SS.map Flags snapshotSelection)
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


currentSelection : Model -> Maybe Selection
currentSelection model =
    TurnLifecycle.selection model.phase


setSelection : Maybe Selection -> Model -> Model
setSelection selected model =
    { model | phase = TurnLifecycle.setSelection selected model.phase }


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


rotationSelection : Model -> Maybe GameBoard.RotationSelection
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
                    choosingDirection model && not (planningLocked model) && model.drag == Nothing
            in
            if canPreview then
                setSelection (Just (UnitSelection { selection | interaction = ChoosingDirection direction })) model

            else
                model

        _ ->
            model


loadSnapshot : LobbyId -> Graphql.Http.Request Snapshot
loadSnapshot id =
    Api.Query.game { id = LobbyId.toString id } snapshotSelection
        |> ApiRequest.queryRequest


panLeft : Model -> Model
panLeft model =
    { model | offset = { x = model.offset.x + 48, y = model.offset.y } }


panRight : Model -> Model
panRight model =
    { model | offset = { x = model.offset.x - 48, y = model.offset.y } }


panUp : Model -> Model
panUp model =
    { model | offset = { x = model.offset.x, y = model.offset.y + 48 } }


panDown : Model -> Model
panDown model =
    { model | offset = { x = model.offset.x, y = model.offset.y - 48 } }


zoomIn : Model -> Model
zoomIn model =
    zoomAt { x = 0, y = 0 } 1.25 model


zoomOut : Model -> Model
zoomOut model =
    zoomAt { x = 0, y = 0 } 0.8 model


pan : Point -> Model -> Model
pan point model =
    case model.drag of
        Nothing ->
            model

        Just drag ->
            let
                dx : Float
                dx =
                    point.x - (Drag.start drag).x

                dy : Float
                dy =
                    point.y - (Drag.start drag).y
            in
            -- Once a gesture becomes a drag, returning to its start cannot select a tile.
            if model.suppressClick || dx * dx + dy * dy >= 36 then
                { model
                    | offset = { x = (Drag.origin drag).x + dx, y = (Drag.origin drag).y + dy }
                    , suppressClick = True
                }

            else
                model


zoomAt : Point -> Float -> Model -> Model
zoomAt anchor factor model =
    let
        zoom : Float
        zoom =
            clamp 0.35 3 (model.zoom * factor)

        ratio : Float
        ratio =
            zoom / model.zoom
    in
    { model
        | zoom = zoom
        , offset =
            { x = anchor.x - (anchor.x - model.offset.x) * ratio
            , y = anchor.y - (anchor.y - model.offset.y) * ratio
            }
        , drag = Nothing
    }


resetViewport : Model -> Model
resetViewport model =
    { model
        | offset = { x = 0, y = 0 }
        , zoom = 1
        , drag = Nothing
        , suppressClick = False
    }


snapshotSelection : SelectionSet Snapshot Api.Object.GameSnapshot
snapshotSelection =
    let
        boardSelection : SelectionSet GameBoard Api.Object.Scenario
        boardSelection =
            SS.succeed GameBoard.GameBoard
                |> SS.with (Scenario.map Map.selection)
                |> SS.with (Scenario.depots (SS.map Depot.Depot (DepotApi.position Coordinate.selection)))
                |> SS.with (Scenario.units Unit.selection)

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
        |> SS.with (SnapshotApi.scenario boardSelection)
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
                    setSelection
                        (Just (UnitSelection { selection | interaction = ChoosingMove { planning | destinationFeedback = feedback } }))
                        model

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
    case ListUtil.find (\unit -> unit.id == id) model.board.units of
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
                            if Movement.canStop (reservedDestinations unit model) model.board unit preview then
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
                    if model.drag /= Nothing then
                        model

                    else
                        case traceTo position model of
                            Just preview ->
                                setSelection
                                    (Just
                                        (UnitSelection
                                            { selection
                                                | interaction =
                                                    ChoosingMove
                                                        { planning
                                                            | preview = preview
                                                            , destinationFeedback = NoDestinationFeedback
                                                        }
                                            }
                                        )
                                    )
                                    model

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


focusAdjacentCommand : (List UnitCommands.MenuOption -> List UnitCommands.MenuOption) -> Maybe UnitCommands.MenuOption -> Model -> Eff Msg
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



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
update lobbyId msg model =
    case msg of
        UnloadUnitToggled id checked ->
            ( { model | phase = TurnLifecycle.mapPlanning (PlanningState.toggleUnloadPassenger id checked) model.phase }, E.none )

        UnloadChoicesConfirmed ->
            ( { model | phase = TurnLifecycle.mapPlanning (PlanningState.confirmUnloadPassengers (unloadOptions model)) model.phase }, E.none )

        UnloadSkipped ->
            clearSelection (dismissDialog model) |> E.withOut

        CargoUnitClicked id ->
            selectUnit id (clearSelection model) |> E.withOut

        BoardMsg boardMsg ->
            let
                next : Model
                next =
                    handleBoardMsg boardMsg model

                effect : Eff Msg
                effect =
                    case ( unloadChoice model.phase, unloadChoice next.phase ) of
                        ( Nothing, Just _ ) ->
                            E.toJs (ToJs.OpenDialog { htmlId = unloadDialogId })

                        _ ->
                            E.none
            in
            ( next, effect )

        ViewportMsg viewportMsg ->
            ( handleViewportMsg viewportMsg model, E.none )

        UnitCommandsMsg commandMsg ->
            case commandMsg of
                UnitCommands.MenuPressed ->
                    ( model, E.none )

                UnitCommands.CancelClicked ->
                    clearSelection model |> E.withOut

                UnitCommands.CommandFocused command ->
                    case ( currentSelection model, commandMenuUnit model ) of
                        ( Just (UnitSelection selection), Just _ ) ->
                            case selection.interaction of
                                CommandMenu _ ->
                                    ( setSelection (Just (UnitSelection { selection | interaction = CommandMenu (Just command) })) model, E.none )

                                _ ->
                                    ( model, E.none )

                        _ ->
                            ( model, E.none )

                UnitCommands.CommandPicked command ->
                    applyCommand lobbyId command model |> E.withOut

                UnitCommands.ArrowedUpCommandMenu current ->
                    ( model, focusAdjacentCommand List.reverse (Just current) model )

                UnitCommands.ArrowedDownCommandMenu current ->
                    ( model, focusAdjacentCommand identity (Just current) model )

        PreviousCommandPressed ->
            ( model, focusAdjacentCommand List.reverse (focusedCommand model) model )

        NextCommandPressed ->
            ( model, focusAdjacentCommand identity (focusedCommand model) model )

        CommandFocusCompleted ->
            ( model, E.none )

        PanLeftClicked ->
            panLeft model
                |> E.withOut

        PanRightClicked ->
            panRight model
                |> E.withOut

        PanUpClicked ->
            panUp model
                |> E.withOut

        PanDownClicked ->
            panDown model
                |> E.withOut

        PanLeftKeyPressed ->
            panLeft model
                |> E.withOut

        PanRightKeyPressed ->
            panRight model
                |> E.withOut

        PanUpKeyPressed ->
            panUp model
                |> E.withOut

        PanDownKeyPressed ->
            panDown model
                |> E.withOut

        ZoomInClicked ->
            zoomIn model
                |> E.withOut

        ZoomOutClicked ->
            zoomOut model
                |> E.withOut

        ZoomInKeyPressed ->
            zoomIn model
                |> E.withOut

        ZoomOutKeyPressed ->
            zoomOut model
                |> E.withOut

        ResetViewClicked ->
            resetViewport model
                |> E.withOut

        DirectionKeyPressed direction ->
            saveRotation direction model |> E.withOut

        PathDirectionKeyPressed direction ->
            extendPath direction model |> E.withOut

        PathEnterPressed ->
            confirmPath model |> E.withOut

        ClearMoveClicked ->
            if planningLocked model then
                ( model, E.none )

            else
                ( { model
                    | phase = TurnLifecycle.setOrders (List.filter (\plan -> Just plan.unitId /= Maybe.map .id (selectedUnit model)) (plannedOrders model)) model.phase
                  }
                    |> restoreCommands
                , E.none
                )

        InspectClicked ->
            clearSelection model
                |> E.withOut

        EscapePressed ->
            if hasDialog model then
                ( dismissDialog model, E.none )

            else
                clearSelection model |> E.withOut

        SubmitTurnClicked ->
            if planningLocked model || isChoosingUnload model || unloadChoice model.phase /= Nothing then
                ( model, E.none )

            else if List.isEmpty (unitsWithoutOrders model) then
                submitTurn lobbyId model

            else
                ( { model | phase = TurnLifecycle.mapPlanning PlanningState.showSubmissionWarning model.phase }
                , E.toJs (ToJs.OpenDialog { htmlId = partialOrdersDialogId })
                )

        DialogDismissed ->
            ( dismissDialog model, E.none )

        SubmissionConfirmed ->
            case model.phase of
                TurnLifecycle.Planning (PlanningState.ConfirmingSubmission _) ->
                    submitTurn lobbyId model

                _ ->
                    ( model, E.none )

        SubmitResponseReceived turnNumber result ->
            if turnNumber /= model.turnNumber then
                ( model, E.none )

            else
                case result of
                    Ok snapshot ->
                        { model | phase = TurnLifecycle.finishSubmission turnNumber model.phase, turnError = Nothing }
                            |> receiveSnapshot snapshot
                            |> E.withOut

                    Err error ->
                        case model.phase of
                            TurnLifecycle.Submitting _ ->
                                ( { model
                                    | phase = TurnLifecycle.finishSubmission turnNumber model.phase
                                    , turnError = Just (ApiRequest.errorMessage error)
                                  }
                                , E.none
                                )

                            _ ->
                                ( model, E.none )

        PollTimerElapsed _ ->
            if model.refreshing || not (TurnLifecycle.canPoll model.phase) then
                ( model, E.none )

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
                    ( { model
                        | refreshing = False
                        , turnError = Just (ApiRequest.errorMessage error)
                      }
                    , E.none
                    )

        PlaybackFrameElapsed delta ->
            case TurnLifecycle.tick delta model.phase of
                Just next ->
                    ( { model
                        | phase = next.phase
                        , board = GameBoard.setUnits next.frame.units model.board
                        , visibleTiles = next.frame.visibleTiles
                      }
                    , E.none
                    )

                Nothing ->
                    ( model, E.none )

        AnimationTimerElapsed _ ->
            ( { model | frame = AnimationFrame.next model.frame }
            , E.none
            )


handleViewportMsg : Viewport.Msg -> Model -> Model
handleViewportMsg viewportMsg model =
    case viewportMsg of
        Viewport.MousePressed point ->
            { model
                | drag = Just (Drag.startAt { start = point, origin = model.offset })
                , suppressClick = False
            }

        Viewport.MouseMoved point buttons ->
            if buttons == 0 then
                { model | drag = Nothing }

            else
                pan point model

        Viewport.MouseReleased point ->
            let
                moved : Model
                moved =
                    pan point model
            in
            { moved | drag = Nothing }

        Viewport.WindowVisibilityChanged _ ->
            { model | drag = Nothing }

        Viewport.WheelScrolled anchor delta ->
            zoomAt anchor (e ^ (negate (clamp -100 100 delta) * 0.002)) model

        Viewport.HomePressed ->
            resetViewport model


handleBoardMsg : GameBoard.Msg -> Model -> Model
handleBoardMsg boardMsg model =
    case boardMsg of
        GameBoard.RotationChoicesMsg rotationMsg ->
            case rotationMsg of
                RotationChoices.MouseMovedOverDirection direction ->
                    previewRotation direction model

                RotationChoices.ClickedDirection direction ->
                    if model.suppressClick then
                        model

                    else
                        saveRotation direction model

        GameBoard.ClickedUnit id click ->
            if click.detail /= 0 && model.suppressClick then
                model

            else
                selectUnit id model

        GameBoard.PressedEnterOnUnit id ->
            let
                confirmsSelectedUnitPreview : Bool
                confirmsSelectedUnitPreview =
                    pathPreview model /= Nothing && Maybe.map .id (selectedUnit model) == Just id
            in
            if confirmsSelectedUnitPreview then
                confirmPath model

            else
                selectUnit id model

        GameBoard.PressedSpaceOnUnit id ->
            selectUnit id model

        GameBoard.MouseOverUnit id ->
            if planningLocked model then
                model

            else
                model.board.units
                    |> ListUtil.find (\unit -> unit.id == id)
                    |> Maybe.andThen Unit.boardPosition
                    |> Maybe.map (\position -> previewTile position model)
                    |> Maybe.withDefault model

        GameBoard.ClickedDepot position click ->
            if click.detail /= 0 && model.suppressClick then
                model

            else
                selectTile position model

        GameBoard.PressedEnterOnDepot position ->
            selectTile position model

        GameBoard.PressedSpaceOnDepot position ->
            selectTile position model

        GameBoard.MouseOverDepot position ->
            if planningLocked model then
                model

            else
                previewTile position model

        GameBoard.ClickedTile position click ->
            if click.detail /= 0 && model.suppressClick then
                model

            else
                selectTile position model

        GameBoard.PressedEnterOnTile position ->
            selectTile position model

        GameBoard.PressedSpaceOnTile position ->
            selectTile position model

        GameBoard.MouseOverTile position ->
            if planningLocked model then
                model

            else
                previewTile position model



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
            [ Viewport.toHtml ViewportMsg
                model
                (GameBoard.toHtml
                    { frame = model.frame
                    , rotation = rotationSelection model
                    , visibleTiles = model.visibleTiles
                    , choosingDestination = pathPreview model /= Nothing || isChoosingUnload model
                    , moving = TurnPlayback.movingPositions (playback model)
                    , selected = selectedPosition model
                    , reachable = List.map .destination (moveOptions model)
                    , paths = List.map PlannedOrder.path (plannedOrders model)
                    , orderedUnits = List.map .unitId (plannedOrders model)
                    , unloads = plannedUnloadRoutes model
                    , previewPath = pathPreview model |> Maybe.map .path |> Maybe.withDefault []
                    }
                    model.board
                    |> H.map BoardMsg
                )
                (commandMenu model)
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


plannedUnloadRoutes : Model -> List GameBoard.UnloadRoute
plannedUnloadRoutes model =
    let
        truckUnloads : PlannedOrder -> List GameBoard.UnloadRoute
        truckUnloads plan =
            let
                route : UnloadOrder -> Maybe GameBoard.UnloadRoute
                route unload =
                    let
                        withDirection : Direction -> GameBoard.UnloadRoute
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


commandMenu : Model -> Html Msg
commandMenu model =
    case commandMenuUnit model of
        Just unit ->
            case Unit.physicalPosition model.board.units unit of
                Just position ->
                    UnitCommands.toHtml model.board.map { offset = model.offset, zoom = model.zoom } position unit
                        |> H.map UnitCommandsMsg

                Nothing ->
                    H.text ""

        Nothing ->
            H.text ""


applyCommand : LobbyId -> UnitCommand.Command -> Model -> Model
applyCommand lobbyId command model =
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
                        setSelection
                            (Just (UnitSelection { id = unit.id, interaction = ChoosingDirection (Maybe.withDefault Facing.North unit.direction) }))
                            model

                    UnitCommand.HoldPosition ->
                        case holdOrder model.board.units unit of
                            Just hold ->
                                { model
                                    | phase = TurnLifecycle.setOrders (hold :: List.filter (\plan -> plan.unitId /= unit.id) (plannedOrders model)) model.phase
                                }
                                    |> inspectSelectedUnit

                            Nothing ->
                                model

                    _ ->
                        model

            else
                model

        _ ->
            model


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


selectedUnit : Model -> Maybe Unit
selectedUnit model =
    case currentSelection model of
        Just (Inspecting (UnitInspection id)) ->
            ListUtil.find (\unit -> unit.id == id) model.board.units

        Just (UnitSelection selection) ->
            ListUtil.find (\unit -> unit.id == selection.id) model.board.units

        _ ->
            Nothing


selectedPosition : Model -> Maybe Coordinate
selectedPosition model =
    case unloadPlanning model.phase of
        Just planning ->
            Just planning.truck.plan.move.destination

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
    List.any (\player -> player.isYou && player.side == unit.side) model.players


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

        planned : Maybe PlannedOrder
        planned =
            ListUtil.find (\plan -> plan.unitId == unit.id) (plannedOrders model)
    in
    case ( pathPreview model, planned ) of
        ( Just preview, _ ) ->
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
                            ListUtil.find (\passenger -> passenger.id == unload.unitId) model.board.units
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
                    [ H.h3 [] [ H.text (chosenOrderText model unit plan) ]
                    , Button.secondary "revoke order" ClearMoveClicked |> Button.toHtml
                    ]
            in
            orderDetails ++ unloadDetails

        ( Nothing, Nothing ) ->
            []


chosenOrderText : Model -> Unit -> PlannedOrder -> String
chosenOrderText model unit order =
    case order.action of
        PlannedOrder.Hold _ ->
            "hold position"

        PlannedOrder.Rotate rotation ->
            "rotate: " ++ Direction.label rotation.direction

        PlannedOrder.Move plan ->
            if List.length plan.move.path <= 1 then
                "hold position"

            else
                plannedAction model unit plan.move
                    ++ ": ("
                    ++ String.fromInt plan.move.destination.x
                    ++ ", "
                    ++ String.fromInt plan.move.destination.y
                    ++ ") · movement: "
                    ++ Movement.pointsLabel plan.move.cost


viewControls : Model -> Html Msg
viewControls model =
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
                [ H.text (String.fromInt (round (model.zoom * 100)) ++ "%")
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
            if List.any (\depot -> depot.position == position) model.board.depots then
                "supply depot"

            else
                Terrain.label (Map.terrainAt model.board.map position)


loadFailedView : Graphql.Http.Error Flags -> { retry : msg, returnHome : msg } -> List (Html msg)
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


viewportSubscriptions : Model -> Sub Msg
viewportSubscriptions model =
    case model.drag of
        Nothing ->
            Sub.none

        Just _ ->
            Sub.batch
                [ Browser.Events.onMouseMove
                    (Decode.map2 (\point buttons -> ViewportMsg (Viewport.MouseMoved point buttons)) Point.decoder (Decode.field "buttons" Decode.int))
                , Browser.Events.onMouseUp (Decode.map (Viewport.MouseReleased >> ViewportMsg) Point.decoder)
                , Browser.Events.onVisibilityChange (Viewport.WindowVisibilityChanged >> ViewportMsg)
                ]


traceTo : Coordinate -> Model -> Maybe Movement.Option
traceTo position model =
    case ( selectedUnit model, movementPlanning model ) of
        ( Just unit, Just planning ) ->
            if isOwnUnit model unit then
                Movement.preview model.movementRules model.board unit planning.preview position

            else
                Nothing

        _ ->
            Nothing


beginMovement : Unit -> Model -> Model
beginMovement unit model =
    case Unit.physicalPosition model.board.units unit of
        Just origin ->
            let
                planning : MovePlanning
                planning =
                    { preview = Movement.start origin
                    , options = Movement.options (reservedDestinations unit model) model.movementRules model.board unit
                    , destinationFeedback = NoDestinationFeedback
                    }
            in
            setSelection (Just (UnitSelection { id = unit.id, interaction = ChoosingMove planning }))
                model

        Nothing ->
            model


boardingSpace : Unit -> Unit -> Model -> Bool
boardingSpace mover truck model =
    let
        alreadyAboard : Int
        alreadyAboard =
            List.length (List.filter (\unit -> Unit.carrierId unit == Just truck.id) model.board.units)

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
            Unit.boardPosition truck |> Maybe.andThen (Unit.loadingPartner model.board.units mover) |> (==) (Just truck)
    in
    compatible && not truckMoving && fitsCargo


plannedAction : Model -> Unit -> Movement.Option -> String
plannedAction model unit move =
    if Unit.carrierId unit /= Nothing && List.length move.path > 1 then
        "unload at"

    else if Unit.loadingPartner model.board.units unit move.destination /= Nothing then
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
                    Unit.loadingPartner model.board.units unit (PlannedOrder.destination plan)

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
            model.board.units
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
                case ListUtil.find (\mover -> mover.id == plan.unitId) model.board.units of
                    Just mover ->
                        if Unit.carrierId mover == Just unit.id then
                            True

                        else
                            Unit.loadingPartner model.board.units mover (PlannedOrder.destination plan) |> Maybe.map .id |> (==) (Just unit.id)

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
                    model.board.units |> ListUtil.find (\truck -> truck.id == carrier)

                Nothing ->
                    Unit.loadingPartner model.board.units unit move.destination

        retained : List PlannedOrder
        retained =
            plannedOrders model |> List.filter (\plan -> plan.unitId /= unit.id && Just plan.unitId /= Maybe.map .id receiver)

        receiverHold : List PlannedOrder
        receiverHold =
            receiver |> Maybe.andThen (holdOrder model.board.units) |> Maybe.map List.singleton |> Maybe.withDefault []
    in
    { unitId = unit.id, action = PlannedOrder.Move { move = move, unloads = [] } } :: receiverHold ++ retained


cargoView : Model -> Unit -> Html Msg
cargoView model unit =
    let
        cargo : List Unit
        cargo =
            List.filter (\passenger -> Unit.carrierId passenger == Just unit.id) model.board.units

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
    List.filter missingOrder model.board.units


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


unloadDialogId : String
unloadDialogId =
    "unload-passengers"


unloadChecklist : Model -> UnloadChoice -> Dialog Msg
unloadChecklist model choice =
    let
        passengers : List Unit
        passengers =
            List.filter (\unit -> Unit.carrierId unit == Just choice.truck.truckId) model.board.units

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
    Dialog.make unloadDialogId "unload" DialogDismissed content


unloadChoice : Phase -> Maybe UnloadChoice
unloadChoice phase =
    TurnLifecycle.planning phase |> Maybe.andThen PlanningState.unloadChoice


unloadPlanning : Phase -> Maybe UnloadPlanning
unloadPlanning phase =
    TurnLifecycle.planning phase |> Maybe.andThen PlanningState.unloadPlanning


isChoosingUnload : Model -> Bool
isChoosingUnload model =
    unloadPlanning model.phase /= Nothing


openUnloadPrompt : Unit -> Movement.Option -> Model -> Model
openUnloadPrompt truck move model =
    let
        hasPassengers : Bool
        hasPassengers =
            List.any (\passenger -> Unit.carrierId passenger == Just truck.id) model.board.units
    in
    if hasPassengers then
        { model
            | phase =
                TurnLifecycle.mapPlanning
                    (PlanningState.startUnload truck.id move)
                    model.phase
        }

    else
        model


dismissDialog : Model -> Model
dismissDialog model =
    { model
        | phase = TurnLifecycle.mapPlanning PlanningState.dismissDialog model.phase
    }


unloadOptions : Model -> PlanningState -> UnitId -> List Movement.Option
unloadOptions model state passengerId =
    case PlanningState.unloadPlanning state of
        Just planning ->
            let
                projectTruck : Unit -> Unit
                projectTruck unit =
                    if unit.id == planning.truck.truckId then
                        Unit.setOnMap planning.truck.plan.move.destination unit

                    else
                        unit

                projected : GameBoard
                projected =
                    { map = model.board.map, units = List.map projectTruck model.board.units, depots = model.board.depots }

                next : Model
                next =
                    { model | phase = TurnLifecycle.Planning state }
            in
            case ListUtil.find (\unit -> unit.id == passengerId) projected.units of
                Just passenger ->
                    Movement.options (reservedDestinations passenger next) model.movementRules projected passenger

                Nothing ->
                    []

        Nothing ->
            []


chooseUnloadSquare : Coordinate -> Model -> Model
chooseUnloadSquare destination model =
    { model
        | phase =
            TurnLifecycle.mapPlanning
                (PlanningState.saveUnloadDestination (unloadOptions model) destination)
                model.phase
    }


partialOrdersDialogId : String
partialOrdersDialogId =
    "submit-turn-warning"


hasDialog : Model -> Bool
hasDialog model =
    dialog model /= Nothing


{-| The active planning alternative determines the dialog; no dialog state is stored.
-}
dialog : Model -> Maybe (Dialog Msg)
dialog model =
    case model.phase of
        TurnLifecycle.Planning (PlanningState.ConfirmingSubmission _) ->
            Just (submissionWarning model)

        TurnLifecycle.Planning (PlanningState.ChoosingPassengers choice) ->
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
    Dialog.make partialOrdersDialogId
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
            model.board.units |> List.filter missingOrder |> List.filterMap (holdOrder model.board.units)

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
                TurnPlayback.initial snapshot.playbackFrames { units = snapshot.board.units, visibleTiles = snapshot.visibleTiles }
        in
        { model
            | turnNumber = snapshot.turn.number
            , opponentSubmitted = snapshot.turn.opponentSubmitted
            , turnResolution = snapshot.turn.resolution
            , board = GameBoard.setUnits frame.units snapshot.board
            , visibleTiles = frame.visibleTiles
            , phase = TurnLifecycle.startTurn snapshot.turn.submitted snapshot.playbackFrames
            , turnError = Nothing
        }


turnPanel : Model -> Html Msg
turnPanel model =
    let
        ownCount : Int
        ownCount =
            List.length (List.filter (\unit -> isOwnUnit model unit && Unit.onBoard unit) model.board.units)

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
            [ viewControls model ]
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
        , viewportSubscriptions model
        ]
