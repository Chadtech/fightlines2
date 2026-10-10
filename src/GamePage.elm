module GamePage exposing
    ( Flags
    , Model
    , Msg
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
import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.Aboard as AboardApi
import Api.Object.Coordinate as CoordinateApi
import Api.Object.Depot as DepotApi
import Api.Object.Fuel as FuelApi
import Api.Object.GamePlayerView as PlayerView
import Api.Object.GameSnapshot as SnapshotApi
import Api.Object.HitPoints as HitPointsApi
import Api.Object.Map as MapApi
import Api.Object.MovementRule as MovementRuleApi
import Api.Object.OnMap as OnMapApi
import Api.Object.Scenario as Scenario
import Api.Object.Supplies as SuppliesApi
import Api.Object.TerrainFeature as FeatureApi
import Api.Object.TerrainMovementCost as MovementCostApi
import Api.Object.Unit as UnitApi
import Api.Query
import Api.Union
import Api.Union.UnitLocation as LocationApi
import ApiRequest
import Browser.Events
import Coordinate
import Depot
import Direction
import Drag exposing (Drag)
import Effect as E
    exposing
        ( Eff
        )
import GameBoard
import Graphql.Http
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Keyed as Keyed
import Json.Decode as Decode
import KeyCmd
import ListUtil
import LobbyId
    exposing
        ( LobbyId
        )
import Map exposing (Map)
import Movement
import Point exposing (Point)
import Ports.Js.To as ToJs
import Shared
import Style as S
import Terrain
import TerrainFeature
import Time
import Turn
import Unit exposing (Unit)
import UnitCommand
import UnitId exposing (UnitId)
import View.BoardViewport as Viewport
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Dialog as DialogView
import View.GameBoard as Board
import View.GamePanel as GamePanel
import View.UnitCommands as UnitCommands
import View.UnitStatus as UnitStatus
import View.UnloadPassenger as UnloadPassenger



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { snapshot : Snapshot }


type alias Snapshot =
    { name : String
    , mapType : MapType
    , players : List Player
    , board : GameBoard.GameBoard
    , visibleTiles : List Coordinate.Coordinate
    , movementRules : List Movement.Rule
    , turn : Turn.Snapshot
    }


type alias Player =
    { name : String
    , side : Side
    , isYou : Bool
    }


type alias Model =
    { turn : Turn.Snapshot
    , dialog : Maybe Dialog
    , busy : Bool
    , refreshing : Bool
    , turnError : Maybe String
    , playback : Maybe Turn.Playback
    , shared : Shared.Model
    , name : String
    , mapType : MapType
    , players : List Player
    , board : GameBoard.GameBoard
    , visibleTiles : List Coordinate.Coordinate
    , movementRules : List Movement.Rule
    , pathPreview : Maybe Movement.Option
    , moveOptions : List Movement.Option
    , plannedMoves : List PlannedMove
    , movementStatus : MovementStatus
    , selected : Maybe Selection
    , offset : Point
    , zoom : Float
    , drag : Maybe Drag
    , suppressClick : Bool
    , frame : AnimationFrame.Frame
    }


type Selection
    = UnitSelection SelectedUnit
    | TileSelection Coordinate.Coordinate
    | UnloadSelection UnloadPlanning


type alias SelectedUnit =
    { id : UnitId
    , interaction : UnitInteraction
    }


type UnitInteraction
    = CommandMenu (Maybe UnitCommands.MenuOption)
    | ChoosingDirection


type alias UnloadPlanning =
    { truckId : UnitId
    , passengerId : UnitId
    , remaining : List UnitId
    }


type alias UnloadChoice =
    { truckId : UnitId
    , checked : List UnitId
    }


type alias UnloadOrder =
    { unitId : UnitId
    , destination : Coordinate.Coordinate
    }


type Dialog
    = PartialOrdersWarning
    | UnloadChecklist UnloadChoice


type MovementStatus
    = NoMovementStatus
    | PlannedMoveCleared
    | MovePlanned
    | DestinationUnavailable


movementStatusText : MovementStatus -> String
movementStatusText status =
    case status of
        NoMovementStatus ->
            ""

        PlannedMoveCleared ->
            "planned move cleared."

        MovePlanned ->
            "move planned."

        DestinationUnavailable ->
            "that square cannot be a destination within this unit’s movement budget."


type alias PlannedMove =
    { unitId : UnitId
    , move : Movement.Option
    , unloads : List UnloadOrder
    , direction : Maybe Direction
    }


type Msg
    = BoardMsg Board.Msg
    | ViewportMsg Viewport.Msg
    | UnitCommandsMsg UnitCommands.Msg
    | PanLeftClicked
    | PanRightClicked
    | PanUpClicked
    | PanDownClicked
    | ZoomInClicked
    | ZoomOutClicked
    | ResetViewClicked
    | AnimationTimerElapsed Time.Posix
    | DirectionClicked Direction
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
    | SubmitResponseReceived (ApiRequest.Response Snapshot)
    | PollTimerElapsed Time.Posix
    | PollResponseReceived (ApiRequest.Response Snapshot)
    | PlaybackFrameElapsed Float



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> Model
init shared flags =
    { turn = flags.snapshot.turn
    , dialog = Nothing
    , busy = False
    , refreshing = False
    , turnError = Nothing
    , playback = Nothing
    , shared = shared
    , name = flags.snapshot.name
    , mapType = flags.snapshot.mapType
    , players = flags.snapshot.players
    , board = flags.snapshot.board
    , visibleTiles = flags.snapshot.visibleTiles
    , movementRules = flags.snapshot.movementRules
    , pathPreview = Nothing
    , moveOptions = []
    , plannedMoves = []
    , movementStatus = NoMovementStatus
    , selected = Nothing
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


loadSnapshot : LobbyId -> Graphql.Http.Request Snapshot
loadSnapshot id =
    Api.Query.game { id = LobbyId.toString id } snapshotSelection
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


keyCommands : Model -> KeyCmd.KeyCmd Msg
keyCommands model =
    let
        navigation : List (KeyCmd.KeyCmd Msg)
        navigation =
            case commandMenuUnit model of
                Just _ ->
                    [ KeyCmd.leftArrow (UnitCommandsMsg UnitCommands.PreviousCommandPressed)
                    , KeyCmd.rightArrow (UnitCommandsMsg UnitCommands.NextCommandPressed)
                    , KeyCmd.upArrow (UnitCommandsMsg UnitCommands.PreviousCommandPressed)
                    , KeyCmd.downArrow (UnitCommandsMsg UnitCommands.NextCommandPressed)
                    ]

                Nothing ->
                    [ KeyCmd.leftArrow PanLeftClicked
                    , KeyCmd.rightArrow PanRightClicked
                    , KeyCmd.upArrow PanUpClicked
                    , KeyCmd.downArrow PanDownClicked
                    ]
    in
    KeyCmd.batch (KeyCmd.escape EscapePressed :: navigation)


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


updateViewport : Viewport.Msg -> Model -> Model
updateViewport viewportMsg model =
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

        Viewport.KeyPressed key ->
            case key of
                "+" ->
                    zoomIn model

                "=" ->
                    zoomIn model

                "-" ->
                    zoomOut model

                "Home" ->
                    resetViewport model

                _ ->
                    model


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
        locationSelection : SelectionSet Unit.Location Api.Union.UnitLocation
        locationSelection =
            LocationApi.fragments
                { onOnMap = SS.map Unit.OnMap (OnMapApi.position coordinateSelection)
                , onAboard = AboardApi.carrierId |> SS.mapOrFail UnitId.parse |> SS.map Unit.Aboard
                }

        boardSelection : SelectionSet GameBoard.GameBoard Api.Object.Scenario
        boardSelection =
            SS.map3 GameBoard.GameBoard
                (Scenario.map
                    (SS.map5 Map
                        MapApi.width
                        MapApi.height
                        MapApi.baseTile
                        MapApi.theme
                        (MapApi.features
                            (SS.map2
                                TerrainFeature.TerrainFeature
                                (FeatureApi.position coordinateSelection)
                                FeatureApi.terrain
                            )
                        )
                    )
                )
                (Scenario.depots (SS.map Depot.Depot (DepotApi.position coordinateSelection)))
                (Scenario.units
                    (SS.map8 Unit
                        (UnitApi.id |> SS.mapOrFail UnitId.parse)
                        UnitApi.side
                        UnitApi.kind
                        UnitApi.direction
                        (UnitApi.hitPoints (SS.map2 Unit.HitPoints HitPointsApi.current HitPointsApi.maximum))
                        (UnitApi.supplies (SS.map4 Unit.Supplies SuppliesApi.current SuppliesApi.maximum SuppliesApi.upkeepPerTurn SuppliesApi.movementPerTile))
                        (UnitApi.fuel (SS.map2 Unit.Fuel FuelApi.current FuelApi.maximum))
                        UnitApi.cargoCapacity
                        |> SS.with (UnitApi.location locationSelection)
                    )
                )
    in
    SS.map7 Snapshot
        SnapshotApi.name
        SnapshotApi.mapType
        (SnapshotApi.players
            (SS.map3
                Player
                PlayerView.name
                PlayerView.side
                PlayerView.isYou
            )
        )
        (SnapshotApi.scenario boardSelection)
        (SnapshotApi.visibleTiles coordinateSelection)
        (SnapshotApi.movementRules
            (SS.map3
                Movement.Rule
                MovementRuleApi.kind
                MovementRuleApi.budget
                (MovementRuleApi.terrainCosts
                    (SS.map2 Movement.TerrainCost MovementCostApi.terrain MovementCostApi.cost)
                )
            )
        )
        Turn.selection


coordinateSelection : SelectionSet Coordinate.Coordinate Api.Object.Coordinate
coordinateSelection =
    SS.map2 Coordinate.Coordinate CoordinateApi.x CoordinateApi.y


clearSelection : Model -> Model
clearSelection model =
    { model
        | selected = Nothing
        , moveOptions = []
        , pathPreview = Nothing
        , movementStatus = NoMovementStatus
    }


selectUnit : UnitId -> Model -> Model
selectUnit id model =
    case ListUtil.find (\unit -> unit.id == id) model.board.units of
        Nothing ->
            model

        Just unit ->
            let
                choosingOccupiedDestination : Bool
                choosingOccupiedDestination =
                    (model.pathPreview /= Nothing || isChoosingUnload model) && not (planningLocked model) && Maybe.map .id (selectedUnit model) /= Just id
            in
            if choosingOccupiedDestination then
                Unit.boardPosition unit |> Maybe.map (\position -> selectTile position model) |> Maybe.withDefault model

            else if Maybe.map .id (selectedUnit model) == Just id then
                clearSelection model

            else
                { model
                    | selected = Just (UnitSelection { id = id, interaction = CommandMenu Nothing })
                    , moveOptions = []
                    , pathPreview = Nothing
                    , movementStatus = NoMovementStatus
                }


selectTile : Coordinate.Coordinate -> Model -> Model
selectTile position model =
    case model.selected of
        Just (UnloadSelection planning) ->
            chooseUnloadSquare planning position model

        _ ->
            selectMovementTile position model


selectMovementTile : Coordinate.Coordinate -> Model -> Model
selectMovementTile position model =
    if planningLocked model then
        { model | selected = Just (TileSelection position) }

    else
        let
            notOwnUnit : () -> Model
            notOwnUnit _ =
                { model
                    | selected = Just (TileSelection position)
                    , moveOptions = []
                    , pathPreview = Nothing
                    , movementStatus = NoMovementStatus
                }
        in
        case selectedUnit model of
            Just unit ->
                if isOwnUnit model unit && model.pathPreview /= Nothing then
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
                                | plannedMoves = saveMove unit move model
                                , pathPreview = Nothing
                                , movementStatus = MovePlanned
                                , moveOptions = []
                                , dialog = unloadPrompt unit model
                            }

                        Nothing ->
                            { model | movementStatus = DestinationUnavailable }

                else
                    notOwnUnit ()

            Nothing ->
                notOwnUnit ()


previewTile : Coordinate.Coordinate -> Model -> Model
previewTile position model =
    if model.drag /= Nothing || model.pathPreview == Nothing then
        model

    else
        case traceTo position model of
            Just preview ->
                { model | pathPreview = Just preview, movementStatus = NoMovementStatus }

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
    case selectedUnit model of
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
                    E.focus { htmlId = UnitCommands.optionHtmlId command } (UnitCommandsMsg UnitCommands.CommandFocusCompleted)

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
            case model.dialog of
                Just (UnloadChecklist choice) ->
                    let
                        selectedIds : List UnitId
                        selectedIds =
                            if checked then
                                id :: List.filter ((/=) id) choice.checked

                            else
                                List.filter ((/=) id) choice.checked
                    in
                    ( { model | dialog = Just (UnloadChecklist { choice | checked = selectedIds }) }, E.none )

                _ ->
                    ( model, E.none )

        UnloadChoicesConfirmed ->
            case model.dialog of
                Just (UnloadChecklist choice) ->
                    beginUnloading choice.truckId (List.reverse choice.checked) { model | dialog = Nothing }
                        |> E.withOut

                _ ->
                    ( model, E.none )

        UnloadSkipped ->
            clearSelection { model | dialog = Nothing } |> E.withOut

        CargoUnitClicked id ->
            selectUnit id (clearSelection model) |> E.withOut

        BoardMsg boardMsg ->
            let
                next : Model
                next =
                    handleBoardMsg boardMsg model

                effect : Eff Msg
                effect =
                    case ( model.dialog, next.dialog ) of
                        ( Nothing, Just (UnloadChecklist _) ) ->
                            E.toJs (ToJs.OpenDialog { htmlId = unloadDialogId })

                        _ ->
                            E.none
            in
            ( next, effect )

        ViewportMsg viewportMsg ->
            ( updateViewport viewportMsg model, E.none )

        UnitCommandsMsg commandMsg ->
            case commandMsg of
                UnitCommands.MenuPressed ->
                    ( model, E.none )

                UnitCommands.CancelClicked ->
                    clearSelection model |> E.withOut

                UnitCommands.CommandFocused command ->
                    case model.selected of
                        Just (UnitSelection selection) ->
                            ( { model | selected = Just (UnitSelection { selection | interaction = CommandMenu (Just command) }) }, E.none )

                        _ ->
                            ( model, E.none )

                UnitCommands.PreviousCommandPressed ->
                    ( model, focusAdjacentCommand List.reverse (focusedCommand model) model )

                UnitCommands.NextCommandPressed ->
                    ( model, focusAdjacentCommand identity (focusedCommand model) model )

                UnitCommands.CommandPicked command ->
                    applyCommand lobbyId command model |> E.withOut

                UnitCommands.ArrowedUpCommandMenu current ->
                    ( model, focusAdjacentCommand List.reverse (Just current) model )

                UnitCommands.ArrowedDownCommandMenu current ->
                    ( model, focusAdjacentCommand identity (Just current) model )

                UnitCommands.CommandFocusCompleted ->
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

        ZoomInClicked ->
            zoomIn model
                |> E.withOut

        ZoomOutClicked ->
            zoomOut model
                |> E.withOut

        ResetViewClicked ->
            resetViewport model
                |> E.withOut

        DirectionClicked direction ->
            saveRotation direction model |> E.withOut

        ClearMoveClicked ->
            if planningLocked model then
                ( model, E.none )

            else
                ( { model
                    | selected = resetCommandMenu model.selected
                    , plannedMoves = List.filter (\plan -> Just plan.unitId /= Maybe.map .id (selectedUnit model)) model.plannedMoves
                    , pathPreview = Nothing
                    , moveOptions = []
                    , movementStatus = PlannedMoveCleared
                  }
                , E.none
                )

        InspectClicked ->
            clearSelection model
                |> E.withOut

        EscapePressed ->
            case model.dialog of
                Just _ ->
                    ( { model | dialog = Nothing }, E.none )

                Nothing ->
                    clearSelection model |> E.withOut

        SubmitTurnClicked ->
            if planningLocked model || isChoosingUnload model then
                ( model, E.none )

            else if List.isEmpty (unitsWithoutOrders model) then
                submitTurn lobbyId model

            else
                ( { model | dialog = Just PartialOrdersWarning }
                , E.toJs (ToJs.OpenDialog { htmlId = partialOrdersDialogId })
                )

        DialogDismissed ->
            ( { model | dialog = Nothing }, E.none )

        SubmissionConfirmed ->
            if model.dialog == Just PartialOrdersWarning && not (planningLocked model) then
                submitTurn lobbyId model

            else
                ( model, E.none )

        SubmitResponseReceived result ->
            case result of
                Ok snapshot ->
                    { model | busy = False, turnError = Nothing }
                        |> receiveSnapshot snapshot
                        |> E.withOut

                Err error ->
                    ( { model | busy = False, turnError = Just (ApiRequest.errorMessage error) }, E.none )

        PollTimerElapsed _ ->
            if model.refreshing || model.busy || model.playback /= Nothing then
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
            case model.playback of
                Nothing ->
                    ( model, E.none )

                Just playback ->
                    let
                        ( remaining, board ) =
                            Turn.tick (min 50 delta) playback model.board
                    in
                    ( { model | playback = remaining, board = board }, E.none )

        AnimationTimerElapsed _ ->
            ( { model | frame = AnimationFrame.next model.frame }
            , E.none
            )


handleBoardMsg : Board.Msg -> Model -> Model
handleBoardMsg boardMsg model =
    case boardMsg of
        Board.ClickedUnit id click ->
            if click.detail /= 0 && model.suppressClick then
                model

            else
                selectUnit id model

        Board.PressedEnterOnUnit id ->
            selectUnit id model

        Board.PressedSpaceOnUnit id ->
            selectUnit id model

        Board.MouseOverUnit id ->
            if planningLocked model then
                model

            else
                model.board.units
                    |> ListUtil.find (\unit -> unit.id == id)
                    |> Maybe.andThen Unit.boardPosition
                    |> Maybe.map (\position -> previewTile position model)
                    |> Maybe.withDefault model

        Board.ClickedDepot position click ->
            if click.detail /= 0 && model.suppressClick then
                model

            else
                selectTile position model

        Board.PressedEnterOnDepot position ->
            selectTile position model

        Board.PressedSpaceOnDepot position ->
            selectTile position model

        Board.MouseOverDepot position ->
            if planningLocked model then
                model

            else
                previewTile position model

        Board.ClickedTile position click ->
            if click.detail /= 0 && model.suppressClick then
                model

            else
                selectTile position model

        Board.PressedEnterOnTile position ->
            selectTile position model

        Board.PressedSpaceOnTile position ->
            selectTile position model

        Board.MouseOverTile position ->
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
                (Board.toHtml
                    { frame = model.frame
                    , visibleTiles = model.visibleTiles
                    , moving = Turn.movingPosition model.playback
                    , selected = selectedPosition model
                    , reachable =
                        if model.pathPreview == Nothing && not (isChoosingUnload model) then
                            []

                        else
                            List.map .destination model.moveOptions
                    , paths = List.map (.move >> .path) model.plannedMoves
                    , unloads = plannedUnloadRoutes model
                    , previewPath = model.pathPreview |> Maybe.map .path |> Maybe.withDefault []
                    }
                    model.board
                    |> H.map BoardMsg
                )
                (commandMenu model)
            , turnPanel model
            ]
        , GamePanel.toHtml
            [ selectionView model
            , panelFooter model
            ]
        ]
    , dialogView model
    ]


plannedUnloadRoutes : Model -> List Board.UnloadRoute
plannedUnloadRoutes model =
    let
        truckUnloads : PlannedMove -> List Board.UnloadRoute
        truckUnloads plan =
            let
                route : UnloadOrder -> Maybe Board.UnloadRoute
                route unload =
                    let
                        withDirection : Direction -> Board.UnloadRoute
                        withDirection direction =
                            { origin = plan.move.destination
                            , direction = direction
                            }
                    in
                    Direction.between plan.move.destination unload.destination
                        |> Maybe.map withDirection
            in
            List.filterMap route plan.unloads
    in
    List.concatMap truckUnloads model.plannedMoves


focusedCommand : Model -> Maybe UnitCommands.MenuOption
focusedCommand model =
    case model.selected of
        Just (UnitSelection selection) ->
            case selection.interaction of
                CommandMenu focused ->
                    focused

                ChoosingDirection ->
                    Nothing

        _ ->
            Nothing


commandMenuUnit : Model -> Maybe Unit
commandMenuUnit model =
    case selectedUnit model of
        Just unit ->
            let
                hasOrder : Bool
                hasOrder =
                    List.any (\plan -> plan.unitId == unit.id) model.plannedMoves

                canChooseCommand : Bool
                canChooseCommand =
                    isOwnUnit model unit
                        && Unit.onBoard unit
                        && not (planningLocked model)
                        && not (receivingLoad unit model)
                        && (model.pathPreview == Nothing)
                        && (model.dialog == Nothing)
                        && not (choosingDirection model)
                        && not hasOrder
            in
            if canChooseCommand then
                Just unit

            else
                Nothing

        Nothing ->
            Nothing


commandMenu : Model -> Html Msg
commandMenu model =
    case commandMenuUnit model of
        Just unit ->
            case Unit.physicalPosition model.board.units unit of
                Just position ->
                    UnitCommands.toHtml model.board.map model.zoom position unit
                        |> H.map UnitCommandsMsg

                Nothing ->
                    H.text ""

        Nothing ->
            H.text ""


applyCommand : LobbyId -> UnitCommand.Command -> Model -> Model
applyCommand lobbyId command model =
    case selectedUnit model of
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
                        { model | selected = Just (UnitSelection { id = unit.id, interaction = ChoosingDirection }), pathPreview = Nothing, moveOptions = [] }

                    UnitCommand.HoldPosition ->
                        case holdOrder model.board.units unit of
                            Just hold ->
                                { model
                                    | plannedMoves = hold :: List.filter (\plan -> plan.unitId /= unit.id) model.plannedMoves
                                    , pathPreview = Nothing
                                    , moveOptions = []
                                    , movementStatus = MovePlanned
                                }

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
            if model.selected == Nothing then
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
    case model.selected of
        Just (UnitSelection selection) ->
            ListUtil.find (\unit -> unit.id == selection.id) model.board.units

        Just (UnloadSelection planning) ->
            ListUtil.find (\unit -> unit.id == planning.passengerId) model.board.units

        _ ->
            Nothing


selectedPosition : Model -> Maybe Coordinate.Coordinate
selectedPosition model =
    case model.selected of
        Just (TileSelection position) ->
            Just position

        Just (UnitSelection _) ->
            Maybe.andThen Unit.boardPosition (selectedUnit model)

        Just (UnloadSelection planning) ->
            truckDestination planning.truckId model

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
                        directionChoices

                    else
                        unitOrderView model unit

                Nothing ->
                    []

        feedback : List (Html Msg)
        feedback =
            if model.movementStatus == DestinationUnavailable then
                [ H.p
                    [ A.attribute "role" "status" ]
                    [ H.text (movementStatusText model.movementStatus) ]
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

        planned : Maybe PlannedMove
        planned =
            ListUtil.find (\plan -> plan.unitId == unit.id) model.plannedMoves
    in
    case ( model.pathPreview, planned ) of
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
                    List.map unloadSummary plan.unloads

                orderDetails : List (Html Msg)
                orderDetails =
                    [ H.h3 [] [ H.text (chosenOrderText model unit plan) ]
                    , Button.secondary "revoke order" ClearMoveClicked |> Button.toHtml
                    ]
            in
            orderDetails ++ unloadDetails

        ( Nothing, Nothing ) ->
            []


chosenOrderText : Model -> Unit -> PlannedMove -> String
chosenOrderText model unit plan =
    let
        move : Movement.Option
        move =
            plan.move
    in
    if plan.direction /= Nothing then
        "rotate: " ++ (plan.direction |> Maybe.map Direction.label |> Maybe.withDefault "")

    else if List.length move.path <= 1 then
        "hold position"

    else
        plannedAction model unit move
            ++ ": ("
            ++ String.fromInt move.destination.x
            ++ ", "
            ++ String.fromInt move.destination.y
            ++ ") · movement: "
            ++ Movement.pointsLabel move.cost


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


traceTo : Coordinate.Coordinate -> Model -> Maybe Movement.Option
traceTo position model =
    let
        previewForUnit : Unit -> Maybe Movement.Option
        previewForUnit unit =
            if isOwnUnit model unit then
                Unit.physicalPosition model.board.units unit
                    |> Maybe.andThen
                        (\origin ->
                            Movement.preview model.movementRules
                                model.board
                                unit
                                (model.pathPreview |> Maybe.withDefault (Movement.start origin))
                                position
                        )

            else
                Nothing
    in
    selectedUnit model
        |> Maybe.andThen previewForUnit


beginMovement : Unit -> Model -> Model
beginMovement unit model =
    { model
        | pathPreview = Unit.physicalPosition model.board.units unit |> Maybe.map Movement.start
        , moveOptions = Movement.options (reservedDestinations unit model) model.movementRules model.board unit
        , movementStatus = NoMovementStatus
    }


boardingSpace : Unit -> Unit -> Model -> Bool
boardingSpace mover truck model =
    let
        alreadyAboard : Int
        alreadyAboard =
            List.length (List.filter (\unit -> Unit.carrierId unit == Just truck.id) model.board.units)

        boarding : PlannedMove -> Bool
        boarding plan =
            plan.unitId /= mover.id && List.length plan.move.path > 1 && Just plan.move.destination == Unit.boardPosition truck

        truckMoving : Bool
        truckMoving =
            List.any (\plan -> plan.unitId == truck.id && List.length plan.move.path > 1) model.plannedMoves

        fitsCargo : Bool
        fitsCargo =
            alreadyAboard + List.length (List.filter boarding model.plannedMoves) < truck.cargoCapacity

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


reservedDestinations : Unit -> Model -> List Coordinate.Coordinate
reservedDestinations unit model =
    let
        reserves : PlannedMove -> Bool
        reserves plan =
            let
                partner : Maybe Unit
                partner =
                    Unit.loadingPartner model.board.units unit plan.move.destination

                isWaitingPartner : Unit -> Bool
                isWaitingPartner target =
                    target.id == plan.unitId && not (receivingLoad target model && target.cargoCapacity == 0)

                waitingPartner : Bool
                waitingPartner =
                    List.length plan.move.path == 1 && (partner |> Maybe.map isWaitingPartner |> Maybe.withDefault False)

                boardingDestination : Bool
                boardingDestination =
                    partner |> Maybe.map (\target -> boardingSpace unit target model) |> Maybe.withDefault False
            in
            plan.unitId /= unit.id && not waitingPartner && not boardingDestination

        unavailableReceiver : Unit -> Bool
        unavailableReceiver target =
            target.id /= unit.id && receivingLoad target model && not (boardingSpace unit target model)

        unavailableReceivers : List Coordinate.Coordinate
        unavailableReceivers =
            model.board.units
                |> List.filter unavailableReceiver
                |> List.filterMap Unit.boardPosition

        savedDestinations : List Coordinate.Coordinate
        savedDestinations =
            List.map (.move >> .destination) (List.filter reserves model.plannedMoves)
                ++ List.concatMap (.unloads >> List.map .destination) model.plannedMoves
    in
    savedDestinations ++ unavailableReceivers


receivingLoad : Unit -> Model -> Bool
receivingLoad unit model =
    let
        receives : PlannedMove -> Bool
        receives plan =
            if List.length plan.move.path <= 1 then
                False

            else
                case ListUtil.find (\mover -> mover.id == plan.unitId) model.board.units of
                    Just mover ->
                        if Unit.carrierId mover == Just unit.id then
                            True

                        else
                            Unit.loadingPartner model.board.units mover plan.move.destination |> Maybe.map .id |> (==) (Just unit.id)

                    Nothing ->
                        False
    in
    List.any receives model.plannedMoves


saveMove : Unit -> Movement.Option -> Model -> List PlannedMove
saveMove unit move model =
    let
        receiver : Maybe Unit
        receiver =
            case Unit.carrierId unit of
                Just carrier ->
                    model.board.units |> ListUtil.find (\truck -> truck.id == carrier)

                Nothing ->
                    Unit.loadingPartner model.board.units unit move.destination

        retained : List PlannedMove
        retained =
            model.plannedMoves |> List.filter (\plan -> plan.unitId /= unit.id && Just plan.unitId /= Maybe.map .id receiver)

        receiverHold : List PlannedMove
        receiverHold =
            receiver |> Maybe.andThen (holdOrder model.board.units) |> Maybe.map List.singleton |> Maybe.withDefault []
    in
    { unitId = unit.id, move = move, unloads = [], direction = Nothing } :: receiverHold ++ retained


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


planningLocked : Model -> Bool
planningLocked model =
    model.busy || model.turn.submitted || model.playback /= Nothing


unitsWithoutOrders : Model -> List Unit
unitsWithoutOrders model =
    let
        missingOrder : Unit -> Bool
        missingOrder unit =
            isOwnUnit model unit && Unit.onBoard unit && not (List.any (\plan -> plan.unitId == unit.id) model.plannedMoves)
    in
    List.filter missingOrder model.board.units


readyToSubmit : Model -> Bool
readyToSubmit model =
    not (planningLocked model) && List.isEmpty (unitsWithoutOrders model)


submitTurn : LobbyId -> Model -> ( Model, Eff Msg )
submitTurn lobbyId model =
    ( { model | busy = True, dialog = Nothing, turnError = Nothing, pathPreview = Nothing, moveOptions = [] }
    , E.request SubmitResponseReceived (submitRequest lobbyId model)
    )


unloadPrompt : Unit -> Model -> Maybe Dialog
unloadPrompt truck model =
    let
        hasPassengers : Bool
        hasPassengers =
            List.any (\passenger -> Unit.carrierId passenger == Just truck.id) model.board.units
    in
    if hasPassengers then
        Just (UnloadChecklist { truckId = truck.id, checked = [] })

    else
        Nothing


unloadDialogId : String
unloadDialogId =
    "unload-passengers"


unloadChecklist : Model -> UnloadChoice -> Html Msg
unloadChecklist model choice =
    let
        passengers : List Unit
        passengers =
            List.filter (\unit -> Unit.carrierId unit == Just choice.truckId) model.board.units

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
    DialogView.modal unloadDialogId "unload" DialogDismissed content


isChoosingUnload : Model -> Bool
isChoosingUnload model =
    case model.selected of
        Just (UnloadSelection _) ->
            True

        _ ->
            False


truckDestination : UnitId -> Model -> Maybe Coordinate.Coordinate
truckDestination truckId model =
    model.plannedMoves
        |> ListUtil.find (\plan -> plan.unitId == truckId)
        |> Maybe.map (.move >> .destination)


beginUnloading : UnitId -> List UnitId -> Model -> Model
beginUnloading truckId passengers model =
    case passengers of
        [] ->
            { model | selected = Just (UnitSelection { id = truckId, interaction = CommandMenu Nothing }), moveOptions = [] }

        passengerId :: remaining ->
            let
                planning : UnloadPlanning
                planning =
                    { truckId = truckId, passengerId = passengerId, remaining = remaining }
            in
            { model | selected = Just (UnloadSelection planning), moveOptions = unloadOptions planning model }


unloadOptions : UnloadPlanning -> Model -> List Movement.Option
unloadOptions planning model =
    let
        projectTruck : Unit -> Unit
        projectTruck unit =
            if unit.id == planning.truckId then
                truckDestination planning.truckId model
                    |> Maybe.map (\position -> { unit | location = Unit.OnMap position })
                    |> Maybe.withDefault unit

            else
                unit

        projected : GameBoard.GameBoard
        projected =
            { map = model.board.map, units = List.map projectTruck model.board.units, depots = model.board.depots }
    in
    case ListUtil.find (\unit -> unit.id == planning.passengerId) projected.units of
        Just passenger ->
            Movement.options (reservedDestinations passenger model) model.movementRules projected passenger

        Nothing ->
            []


chooseUnloadSquare : UnloadPlanning -> Coordinate.Coordinate -> Model -> Model
chooseUnloadSquare planning destination model =
    if planningLocked model then
        model

    else if List.any (\option -> option.destination == destination) model.moveOptions then
        let
            addUnload : PlannedMove -> PlannedMove
            addUnload plan =
                if plan.unitId == planning.truckId then
                    { plan | unloads = plan.unloads ++ [ { unitId = planning.passengerId, destination = destination } ] }

                else
                    plan

            next : Model
            next =
                { model | plannedMoves = List.map addUnload model.plannedMoves }
        in
        beginUnloading planning.truckId planning.remaining next

    else
        { model | movementStatus = DestinationUnavailable }


partialOrdersDialogId : String
partialOrdersDialogId =
    "submit-turn-warning"


dialogView : Model -> Html Msg
dialogView model =
    case model.dialog of
        Nothing ->
            H.text ""

        Just PartialOrdersWarning ->
            submissionWarning model

        Just (UnloadChecklist choice) ->
            unloadChecklist model choice


submissionWarning : Model -> Html Msg
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
    DialogView.modal partialOrdersDialogId
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


holdOrder : List Unit -> Unit -> Maybe PlannedMove
holdOrder units unit =
    Unit.physicalPosition units unit
        |> Maybe.map (\position -> { unitId = unit.id, move = Movement.start position, unloads = [], direction = Nothing })


submitRequest : LobbyId -> Model -> Graphql.Http.Request Snapshot
submitRequest lobbyId model =
    let
        missingOrder : Unit -> Bool
        missingOrder unit =
            isOwnUnit model unit && not (List.any (\plan -> plan.unitId == unit.id) model.plannedMoves)

        defaultHolds : List PlannedMove
        defaultHolds =
            model.board.units |> List.filter missingOrder |> List.filterMap (holdOrder model.board.units)

        orders : List PlannedMove
        orders =
            model.plannedMoves ++ defaultHolds

        unloadInput : UnloadOrder -> Api.InputObject.UnloadOrderInput
        unloadInput unload =
            Api.InputObject.buildUnloadOrderInput
                { unitId = UnitId.toString unload.unitId
                , destination = Api.InputObject.buildCoordinateInput unload.destination
                }

        order : PlannedMove -> Api.InputObject.MoveOrderInput
        order plan =
            Api.InputObject.buildMoveOrderInput
                { unitId = UnitId.toString plan.unitId
                , path = List.map Api.InputObject.buildCoordinateInput plan.move.path
                }
                (\optionals -> { optionals | unloads = Present (List.map unloadInput plan.unloads), direction = Maybe.map Present plan.direction |> Maybe.withDefault Absent })
    in
    Api.Mutation.submitTurn
        { id = LobbyId.toString lobbyId
        , turnNumber = model.turn.number
        , orders = List.map order orders
        }
        snapshotSelection
        |> ApiRequest.mutationRequest


receiveSnapshot : Snapshot -> Model -> Model
receiveSnapshot snapshot model =
    if snapshot.turn.number < model.turn.number then
        model

    else if snapshot.turn.number == model.turn.number then
        let
            turn : Turn.Snapshot
            turn =
                snapshot.turn
        in
        { model | turn = { turn | submitted = model.turn.submitted || turn.submitted, opponentSubmitted = model.turn.opponentSubmitted || turn.opponentSubmitted } }

    else
        { model
            | dialog = Nothing
            , turn = snapshot.turn
            , board = Turn.rewind snapshot.turn snapshot.board
            , visibleTiles = snapshot.visibleTiles
            , playback = Turn.start snapshot.turn
            , plannedMoves = []
            , selected = Nothing
            , moveOptions = []
            , pathPreview = Nothing
            , movementStatus = NoMovementStatus
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
            if model.playback /= Nothing then
                "playing turn " ++ String.fromInt (model.turn.number - 1)

            else if model.busy then
                "submitting orders…"

            else if model.turn.submitted then
                "orders submitted"

            else
                String.fromInt (ownCount - List.length (unitsWithoutOrders model))
                    ++ "/"
                    ++ String.fromInt ownCount
                    ++ " units ready"

        submitButton : Html Msg
        submitButton =
            (if readyToSubmit model then
                Button.primary "submit turn" SubmitTurnClicked

             else
                Button.secondary "submit turn" SubmitTurnClicked
            )
                |> Button.disabled (planningLocked model || isChoosingUnload model)
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
                [ H.text ("turn " ++ String.fromInt model.turn.number ++ " · " ++ status) ]
            , H.p []
                [ H.text
                    (if model.turn.submitted then
                        "waiting for the other player"

                     else if model.turn.opponentSubmitted then
                        "other player: submitted"

                     else
                        "other player: planning"
                    )
                ]
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
            case model.turn.resolution of
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


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 400 AnimationTimerElapsed
        , Time.every 2000 PollTimerElapsed
        , if model.playback /= Nothing then
            Browser.Events.onAnimationFrameDelta PlaybackFrameElapsed

          else
            Sub.none
        , viewportSubscriptions model
        ]


resetCommandMenu : Maybe Selection -> Maybe Selection
resetCommandMenu selection =
    case selection of
        Just (UnitSelection unit) ->
            Just (UnitSelection { unit | interaction = CommandMenu Nothing })

        _ ->
            selection


choosingDirection : Model -> Bool
choosingDirection model =
    case model.selected of
        Just (UnitSelection selection) ->
            selection.interaction == ChoosingDirection

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
                case holdOrder model.board.units unit of
                    Just hold ->
                        { model | plannedMoves = { hold | direction = Just direction } :: List.filter (\plan -> plan.unitId /= unit.id) model.plannedMoves, selected = resetCommandMenu model.selected }

                    Nothing ->
                        model

            else
                model

        Nothing ->
            model


directionChoices : List (Html Msg)
directionChoices =
    let
        choice : Direction -> Html Msg
        choice direction =
            Button.secondary (Direction.label direction) (DirectionClicked direction)
                |> Button.toHtml
    in
    [ H.p [] [ H.text "choose a facing" ]
    , H.div [ A.css [ S.row, S.flexWrap, S.g2 ] ] (List.map choice [ Facing.North, Facing.East, Facing.South, Facing.West ])
    , Button.secondary "back to commands" ClearMoveClicked |> Button.toHtml
    ]
