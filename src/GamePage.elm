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
import Api.Enum.MapType
    exposing
        ( MapType
        )
import Api.Enum.Side
    exposing
        ( Side
        )
import Api.Enum.TurnEventKind as EventKind
import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.Coordinate as CoordinateApi
import Api.Object.Depot as DepotApi
import Api.Object.Fuel as FuelApi
import Api.Object.GamePlayerView as PlayerView
import Api.Object.GameSnapshot as SnapshotApi
import Api.Object.HitPoints as HitPointsApi
import Api.Object.Map as MapApi
import Api.Object.MovementRule as MovementRuleApi
import Api.Object.Scenario as Scenario
import Api.Object.Supplies as SuppliesApi
import Api.Object.TerrainFeature as FeatureApi
import Api.Object.TerrainMovementCost as MovementCostApi
import Api.Object.Unit as UnitApi
import Api.Query
import ApiRequest
import Browser.Events
import Coordinate
import Depot
import Drag exposing (Drag)
import Effect as E
    exposing
        ( Eff
        )
import GameBoard
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Keyed as Keyed
import Json.Decode as Decode
import KeyCmd
import LobbyId
    exposing
        ( LobbyId
        )
import Map
import Movement
import Point exposing (Point)
import Ports.Js.To as ToJs
import Shared
import Style as S
import Terrain
import TerrainFeature
import Time
import Turn
import Unit
import UnitCommand
import UnitId
import View.BoardViewport as Viewport
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Dialog as DialogView
import View.GameBoard as Board
import View.GamePanel as GamePanel
import View.UnitCommands as UnitCommands
import View.UnitStatus as UnitStatus



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


type alias SelectedUnit =
    { id : UnitId.UnitId
    , commands : UnitCommands.State
    }


type Dialog
    = PartialOrdersWarning


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
    { unitId : UnitId.UnitId
    , move : Movement.Option
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
    | ClearMoveClicked
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
keyCommands _ =
    KeyCmd.batch
        [ KeyCmd.escape EscapePressed
        , KeyCmd.leftArrow PanLeftClicked
        , KeyCmd.rightArrow PanRightClicked
        , KeyCmd.upArrow PanUpClicked
        , KeyCmd.downArrow PanDownClicked
        ]


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
        boardSelection : SelectionSet GameBoard.GameBoard Api.Object.Scenario
        boardSelection =
            SS.map3 GameBoard.GameBoard
                (Scenario.map
                    (SS.map4 Map.Map
                        MapApi.width
                        MapApi.height
                        MapApi.baseTile
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
                    (SS.map8 Unit.Unit
                        (UnitApi.id |> SS.mapOrFail UnitId.parse)
                        UnitApi.side
                        UnitApi.kind
                        UnitApi.direction
                        (UnitApi.hitPoints (SS.map2 Unit.HitPoints HitPointsApi.current HitPointsApi.maximum))
                        (UnitApi.supplies (SS.map4 Unit.Supplies SuppliesApi.current SuppliesApi.maximum SuppliesApi.upkeepPerTurn SuppliesApi.movementPerTile))
                        (UnitApi.fuel (SS.map2 Unit.Fuel FuelApi.current FuelApi.maximum))
                        (UnitApi.position coordinateSelection)
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


selectUnit : UnitId.UnitId -> Model -> Model
selectUnit id model =
    case List.filter (\unit -> unit.id == id) model.board.units |> List.head of
        Nothing ->
            model

        Just unit ->
            if not (planningLocked model) && Maybe.map .id (selectedUnit model) == Just id && commandMenuState model == UnitCommands.Open then
                clearSelection model

            else
                let
                    commands : UnitCommands.State
                    commands =
                        if isOwnUnit model unit && not (planningLocked model) then
                            UnitCommands.Open

                        else
                            UnitCommands.Closed
                in
                { model
                    | selected = Just (UnitSelection { id = id, commands = commands })
                    , moveOptions = []
                    , pathPreview = Nothing
                    , movementStatus = NoMovementStatus
                }


selectTile : Coordinate.Coordinate -> Model -> Model
selectTile position model =
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
                            if Movement.canStop (reservedDestinations unit model) model.board preview then
                                Just preview

                            else
                                Nothing
                    in
                    case traceTo position model |> Maybe.andThen destinationOption of
                        Just move ->
                            { model
                                | plannedMoves = { unitId = unit.id, move = move } :: List.filter (\plan -> plan.unitId /= unit.id) model.plannedMoves
                                , pathPreview = Nothing
                                , movementStatus = MovePlanned
                            }
                                |> setCommandMenuState UnitCommands.Closed

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



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : LobbyId -> Msg -> Model -> ( Model, Eff Msg )
update lobbyId msg model =
    case msg of
        BoardMsg boardMsg ->
            handleBoardMsg boardMsg model
                |> E.withOut

        ViewportMsg viewportMsg ->
            ( updateViewport viewportMsg model, E.none )

        UnitCommandsMsg commandMsg ->
            handleUnitCommands lobbyId commandMsg model
                |> E.withOut

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

        ClearMoveClicked ->
            if planningLocked model then
                ( model, E.none )

            else
                ( { model
                    | plannedMoves = List.filter (\plan -> Just plan.unitId /= Maybe.map .id (selectedUnit model)) model.plannedMoves
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
                    if commandMenuState model == UnitCommands.Open then
                        ( setCommandMenuState UnitCommands.Closed model, E.none )

                    else
                        clearSelection model
                            |> E.withOut

        SubmitTurnClicked ->
            if planningLocked model then
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
                    |> List.filter (\unit -> unit.id == id)
                    |> List.head
                    |> Maybe.map (\unit -> previewTile unit.position model)
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
                        if model.pathPreview == Nothing then
                            []

                        else
                            List.map .destination model.moveOptions
                    , paths = List.map (.move >> .path) model.plannedMoves
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
            , resolutionSummary model
            ]
        ]
    , dialogView model
    ]


applyCommand : LobbyId -> UnitCommand.Command -> Model -> Model
applyCommand lobbyId command model =
    case selectedUnit model of
        Just unit ->
            if isOwnUnit model unit && not (planningLocked model) && List.member command (UnitCommand.available unit.kind) && UnitCommand.isImplemented command then
                case command of
                    UnitCommand.Move ->
                        { model
                            | pathPreview = Just (Movement.start unit)
                            , moveOptions = Movement.options (reservedDestinations unit model) model.movementRules model.board unit
                            , movementStatus = NoMovementStatus
                        }
                            |> setCommandMenuState UnitCommands.Closed

                    UnitCommand.HoldPosition ->
                        { model
                            | plannedMoves = { unitId = unit.id, move = Movement.start unit } :: List.filter (\plan -> plan.unitId /= unit.id) model.plannedMoves
                            , pathPreview = Nothing
                            , moveOptions = []
                            , movementStatus = MovePlanned
                        }
                            |> setCommandMenuState UnitCommands.Closed

                    _ ->
                        model

            else
                model

        _ ->
            model


commandMenu : Model -> Html Msg
commandMenu model =
    case ( selectedUnit model, commandMenuState model ) of
        ( Just unit, UnitCommands.Open ) ->
            if isOwnUnit model unit && not (planningLocked model) then
                UnitCommands.toHtml model.board.map model.zoom unit
                    |> H.map UnitCommandsMsg

            else
                H.text ""

        _ ->
            H.text ""


selectionView : Model -> Html Msg
selectionView model =
    H.section
        [ A.attribute "aria-label" "selection"
        , A.css
            [ S.col
            , S.g3
            ]
        ]
        [ H.h2
            []
            [ H.text "unit status"
            ]
        , case selectedUnit model of
            Just unit ->
                Keyed.node "div"
                    []
                    [ ( UnitId.toString unit.id, UnitStatus.toHtml unit )
                    ]

            Nothing ->
                H.p
                    [ A.attribute "role" "status"
                    ]
                    [ H.text (selectionText model)
                    ]
        , movementView model
        ]


selectedUnit : Model -> Maybe Unit.Unit
selectedUnit model =
    case model.selected of
        Just (UnitSelection selection) ->
            List.filter (\unit -> unit.id == selection.id) model.board.units
                |> List.head

        _ ->
            Nothing


selectedPosition : Model -> Maybe Coordinate.Coordinate
selectedPosition model =
    case model.selected of
        Just (TileSelection position) ->
            Just position

        Just (UnitSelection _) ->
            Maybe.map .position (selectedUnit model)

        Nothing ->
            Nothing


commandMenuState : Model -> UnitCommands.State
commandMenuState model =
    case model.selected of
        Just (UnitSelection selection) ->
            selection.commands

        _ ->
            UnitCommands.Closed


setCommandMenuState : UnitCommands.State -> Model -> Model
setCommandMenuState commands model =
    case model.selected of
        Just (UnitSelection selection) ->
            { model | selected = Just (UnitSelection { selection | commands = commands }) }

        _ ->
            model


handleUnitCommands : LobbyId -> UnitCommands.Msg -> Model -> Model
handleUnitCommands lobbyId msg model =
    case msg of
        UnitCommands.CommandPicked command ->
            applyCommand lobbyId command model

        UnitCommands.CancelClicked ->
            setCommandMenuState UnitCommands.Closed model

        UnitCommands.MenuPressed ->
            model


isOwnUnit : Model -> Unit.Unit -> Bool
isOwnUnit model unit =
    List.any (\player -> player.isYou && player.side == unit.side) model.players


movementView : Model -> Html Msg
movementView model =
    let
        details : List (Html Msg)
        details =
            case selectedUnit model of
                Just unit ->
                    if isOwnUnit model unit then
                        let
                            budget : String
                            budget =
                                model.movementRules
                                    |> List.filter (\rule -> rule.kind == unit.kind)
                                    |> List.head
                                    |> Maybe.map (.budget >> Movement.pointsLabel)
                                    |> Maybe.withDefault "?"

                            planned : Maybe PlannedMove
                            planned =
                                model.plannedMoves
                                    |> List.filter (\plan -> plan.unitId == unit.id)
                                    |> List.head

                            pathDetails : List (Html Msg)
                            pathDetails =
                                case model.pathPreview of
                                    Nothing ->
                                        [ H.p
                                            []
                                            [ H.text ("movement budget: " ++ budget ++ ". choose move to plan a destination.")
                                            ]
                                        ]

                                    Just preview ->
                                        [ H.p
                                            []
                                            [ H.text ("movement budget: " ++ budget ++ ". hover to trace a path; click to save it.")
                                            ]
                                        , H.p
                                            []
                                            [ H.text "retrace to shorten. if the route exceeds the budget, an affordable route is chosen."
                                            ]
                                        , H.p
                                            []
                                            [ H.text ("preview cost: " ++ Movement.pointsLabel preview.cost ++ "/" ++ budget)
                                            ]
                                        ]

                            fuelDetails : List (Html Msg)
                            fuelDetails =
                                case unit.fuel of
                                    Nothing ->
                                        []

                                    Just fuel ->
                                        [ H.p
                                            []
                                            [ H.text ("fuel permits up to " ++ String.fromInt fuel.current ++ " tiles. each tile uses 1 fuel; terrain also spends movement points. end on your home depot to refill.")
                                            ]
                                        ]

                            supplyMovementText : String
                            supplyMovementText =
                                case Unit.supplyMovementLimit unit.supplies of
                                    Nothing ->
                                        "movement uses no supplies."

                                    Just limit ->
                                        "supplies permit up to " ++ String.fromInt limit ++ " tiles after upkeep."

                            supplyDetails : List (Html Msg)
                            supplyDetails =
                                [ H.p
                                    []
                                    [ H.text ("supplies: " ++ String.fromInt unit.supplies.upkeepPerTurn ++ " upkeep per turn; " ++ String.fromInt unit.supplies.movementPerTile ++ " per tile. " ++ supplyMovementText ++ " supplies cannot be replenished yet.")
                                    ]
                                ]

                            plannedDetails : List (Html Msg)
                            plannedDetails =
                                case planned of
                                    Nothing ->
                                        []

                                    Just plan ->
                                        [ H.p
                                            []
                                            [ H.text ("planned destination: (" ++ String.fromInt plan.move.destination.x ++ ", " ++ String.fromInt plan.move.destination.y ++ ") · cost: " ++ Movement.pointsLabel plan.move.cost ++ "/" ++ budget)
                                            ]
                                        , Button.secondary "clear move" ClearMoveClicked
                                            |> Button.toHtml
                                        ]
                        in
                        if planningLocked model then
                            [ H.p [] [ H.text "orders are locked while waiting or playing the turn." ] ]

                        else
                            List.concat [ pathDetails, fuelDetails, supplyDetails, plannedDetails ]

                    else
                        [ H.p
                            []
                            [ H.text "this unit belongs to the other player."
                            ]
                        ]

                Nothing ->
                    []

        statusDetails : List (Html Msg)
        statusDetails =
            [ H.p
                [ A.attribute "role" "status"
                ]
                [ H.text (movementStatusText model.movementStatus)
                ]
            ]
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        (details ++ statusDetails)


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
            "select a unit, depot or tile to inspect it."

        Just position ->
            let
                coordinate =
                    " at (" ++ String.fromInt position.x ++ ", " ++ String.fromInt position.y ++ ")"

                unit =
                    model.board.units |> List.filter (\item -> item.position == position) |> List.head

                depot =
                    model.board.depots |> List.filter (\item -> item.position == position) |> List.head
            in
            case unit of
                Just item ->
                    Unit.label item ++ coordinate

                Nothing ->
                    case depot of
                        Just _ ->
                            "supply depot" ++ coordinate

                        Nothing ->
                            Terrain.label (Map.terrainAt model.board.map position) ++ coordinate


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
        previewForUnit : Unit.Unit -> Maybe Movement.Option
        previewForUnit unit =
            if isOwnUnit model unit then
                Movement.preview model.movementRules
                    model.board
                    unit
                    (model.pathPreview |> Maybe.withDefault (Movement.start unit))
                    position

            else
                Nothing
    in
    selectedUnit model
        |> Maybe.andThen previewForUnit


reservedDestinations : Unit.Unit -> Model -> List Coordinate.Coordinate
reservedDestinations unit model =
    model.plannedMoves
        |> List.filter (\plan -> plan.unitId /= unit.id)
        |> List.map (.move >> .destination)


planningLocked : Model -> Bool
planningLocked model =
    model.busy || model.turn.submitted || model.playback /= Nothing


unitsWithoutOrders : Model -> List Unit.Unit
unitsWithoutOrders model =
    let
        missingOrder : Unit.Unit -> Bool
        missingOrder unit =
            isOwnUnit model unit && not (List.any (\plan -> plan.unitId == unit.id) model.plannedMoves)
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


submitRequest : LobbyId -> Model -> Graphql.Http.Request Snapshot
submitRequest lobbyId model =
    let
        hold : Unit.Unit -> PlannedMove
        hold unit =
            { unitId = unit.id, move = Movement.start unit }

        orders : List PlannedMove
        orders =
            model.plannedMoves ++ List.map hold (unitsWithoutOrders model)

        order : PlannedMove -> Api.InputObject.MoveOrderInput
        order plan =
            Api.InputObject.buildMoveOrderInput
                { unitId = UnitId.toString plan.unitId
                , path = List.map Api.InputObject.buildCoordinateInput plan.move.path
                }
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
            List.length (List.filter (isOwnUnit model) model.board.units)

        status : String
        status =
            if model.playback /= Nothing then
                "playing turn " ++ String.fromInt (model.turn.number - 1)

            else if model.busy then
                "submitting orders…"

            else if model.turn.submitted then
                "orders submitted"

            else
                String.fromInt (List.length model.plannedMoves)
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
                |> Button.disabled (planningLocked model)
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
