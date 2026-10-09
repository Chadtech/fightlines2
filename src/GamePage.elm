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
import Api.Object
import Api.Object.Coordinate as CoordinateApi
import Api.Object.Depot as DepotApi
import Api.Object.GamePlayerView as PlayerView
import Api.Object.GameSnapshot as Snapshot
import Api.Object.Map as MapApi
import Api.Object.MovementRule as MovementRuleApi
import Api.Object.Scenario as Scenario
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
import Route
import Shared
import Style as S
import Terrain
import TerrainFeature
import Time
import Unit
import UnitId
import View.BoardViewport as Viewport
import View.Button as Button
import View.Card as Card
import View.GameBoard as Board
import View.GamePanel as GamePanel
import View.UnitStatus as UnitStatus



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { name : String
    , mapType : MapType
    , players : List Player
    , board : GameBoard.GameBoard
    , movementRules : List Movement.Rule
    }


type alias Player =
    { name : String
    , side : Side
    , isYou : Bool
    }


type alias Model =
    { shared : Shared.Model
    , name : String
    , mapType : MapType
    , players : List Player
    , board : GameBoard.GameBoard
    , movementRules : List Movement.Rule
    , pathPreview : Maybe Movement.Option
    , moveOptions : List Movement.Option
    , plannedMoves : List PlannedMove
    , movementStatus : MovementStatus
    , selected : Maybe Coordinate.Coordinate
    , offset : Point
    , zoom : Float
    , drag : Maybe Drag
    , suppressClick : Bool
    , frame : AnimationFrame.Frame
    }


type MovementStatus
    = NoMovementStatus
    | PlannedMoveCleared
    | PathRestarted
    | MovePlanned
    | DestinationUnavailable


movementStatusText : MovementStatus -> String
movementStatusText status =
    case status of
        NoMovementStatus ->
            ""

        PlannedMoveCleared ->
            "planned move cleared."

        PathRestarted ->
            "trace a new path from the unit."

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
    | AnimationTimerElapsed Time.Posix
    | ClearMoveClicked
    | InspectClicked
    | RestartPathClicked
    | EscapePressed



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> Model
init shared flags =
    { shared = shared
    , name = flags.name
    , mapType = flags.mapType
    , players = flags.players
    , board = flags.board
    , movementRules = flags.movementRules
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
    let
        selection : SelectionSet Flags Api.Object.GameSnapshot
        selection =
            SS.map5 Flags
                Snapshot.name
                Snapshot.mapType
                (Snapshot.players (SS.map3 Player PlayerView.name PlayerView.side PlayerView.isYou))
                (Snapshot.scenario boardSelection)
                (Snapshot.movementRules
                    (SS.map3 Movement.Rule
                        MovementRuleApi.kind
                        MovementRuleApi.budget
                        (MovementRuleApi.terrainCosts (SS.map2 Movement.TerrainCost MovementCostApi.terrain MovementCostApi.cost))
                    )
                )
    in
    Api.Query.game { id = LobbyId.toString id } selection
        |> ApiRequest.queryRequest


boardSelection : SelectionSet GameBoard.GameBoard Api.Object.Scenario
boardSelection =
    SS.map3 GameBoard.GameBoard
        (Scenario.map
            (SS.map4 Map.Map
                MapApi.width
                MapApi.height
                MapApi.baseTile
                (MapApi.features (SS.map2 TerrainFeature.TerrainFeature (FeatureApi.position coordinateSelection) FeatureApi.terrain))
            )
        )
        (Scenario.depots (SS.map Depot.Depot (DepotApi.position coordinateSelection)))
        (Scenario.units
            (SS.map4 Unit.Unit
                (UnitApi.id |> SS.mapOrFail UnitId.parse)
                UnitApi.side
                UnitApi.kind
                (UnitApi.position coordinateSelection)
            )
        )


coordinateSelection : SelectionSet Coordinate.Coordinate Api.Object.Coordinate
coordinateSelection =
    SS.map2 Coordinate.Coordinate CoordinateApi.x CoordinateApi.y


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        BoardMsg boardMsg ->
            updateBoard boardMsg model

        ViewportMsg viewportMsg ->
            ( updateViewport viewportMsg model, E.none )

        ClearMoveClicked ->
            ( { model
                | plannedMoves = List.filter (\plan -> Just plan.unitId /= Maybe.map .id (selectedUnit model)) model.plannedMoves
                , pathPreview = selectedUnit model |> Maybe.map Movement.start
                , movementStatus = PlannedMoveCleared
              }
            , E.none
            )

        RestartPathClicked ->
            ( { model
                | pathPreview = selectedUnit model |> Maybe.map Movement.start
                , movementStatus = PathRestarted
              }
            , E.none
            )

        InspectClicked ->
            clearSelection model

        EscapePressed ->
            clearSelection model

        AnimationTimerElapsed _ ->
            ( { model | frame = AnimationFrame.next model.frame }, E.none )


clearSelection : Model -> ( Model, Eff Msg )
clearSelection model =
    ( { model
        | selected = Nothing
        , moveOptions = []
        , pathPreview = Nothing
        , movementStatus = NoMovementStatus
      }
    , E.none
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 400 AnimationTimerElapsed
        , viewportSubscriptions model
        ]



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


keyCommands : Model -> KeyCmd.KeyCmd Msg
keyCommands _ =
    KeyCmd.escape EscapePressed


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



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
        [ Viewport.toHtml ViewportMsg
            model
            (Board.toHtml BoardMsg
                { frame = model.frame
                , selected = model.selected
                , reachable =
                    if model.pathPreview == Nothing then
                        []

                    else
                        List.map .destination model.moveOptions
                , paths = List.map (.move >> .path) model.plannedMoves
                , previewPath = model.pathPreview |> Maybe.map .path |> Maybe.withDefault []
                }
                model.board
            )
        , GamePanel.toHtml
            [ selectionView model
            , viewControls model
            ]
        ]
    ]


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
    model.board.units
        |> List.filter (\unit -> Just unit.position == model.selected)
        |> List.head


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
                                [ H.p
                                    []
                                    [ H.text
                                        ("movement budget: "
                                            ++ budget
                                            ++ (if model.pathPreview == Nothing then
                                                    ". move saved."

                                                else
                                                    ". hover to trace a path; click to save it."
                                               )
                                        )
                                    ]
                                , H.p
                                    []
                                    [ H.text
                                        (if model.pathPreview == Nothing then
                                            "restart path to resume drawing, or click a new destination."

                                         else
                                            "retrace to shorten. if the route exceeds the budget, an affordable route is chosen."
                                        )
                                    ]
                                , H.p
                                    []
                                    [ H.text
                                        (model.pathPreview
                                            |> Maybe.map (\preview -> "preview cost: " ++ Movement.pointsLabel preview.cost ++ "/" ++ budget)
                                            |> Maybe.withDefault ""
                                        )
                                    ]
                                , Button.secondary "restart path" RestartPathClicked
                                    |> Button.toHtml
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
                        pathDetails ++ plannedDetails

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
            , H.p
                []
                [ H.text (String.fromInt (List.length model.plannedMoves) ++ " planned moves · local drafts; refresh clears them.")
                ]
            , Button.secondary "inspect tiles" InspectClicked
                |> Button.toHtml
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
            [ S.col
            , S.g3
            ]
        ]
        [ H.h2
            []
            [ H.text "view"
            ]
        , H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.itemsCenter
                , S.g2
                ]
            ]
            [ Button.secondary "−" (ViewportMsg Viewport.ZoomOutClicked)
                |> Button.toHtml
            , H.span
                []
                [ H.text (String.fromInt (round (model.zoom * 100)) ++ "%")
                ]
            , Button.secondary "+" (ViewportMsg Viewport.ZoomInClicked)
                |> Button.toHtml
            , Button.secondary "reset view" (ViewportMsg Viewport.ResetClicked)
                |> Button.toHtml
            ]
        , H.p
            []
            [ H.text "drag to pan · scroll to zoom · click to inspect"
            ]
        ]


selectionText : Model -> String
selectionText model =
    case model.selected of
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


loadFailedView : LobbyId -> Graphql.Http.Error Flags -> msg -> List (Html msg)
loadFailedView id error retryMsg =
    let
        message : String
        message =
            ApiRequest.errorMessage error
    in
    [ [ H.p
            [ A.attribute "role" "status"
            ]
            [ H.text message
            ]
      , H.a
            [ A.href (Route.toString (Route.Lobby id))
            , A.css
                [ S.link
                ]
            ]
            [ H.text "return to lobby"
            ]
      , Button.secondary "retry" retryMsg
            |> Button.toHtml
      ]
        |> Card.toHtml Card.simple
    ]


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

        Viewport.ZoomInClicked ->
            zoomAt { x = 0, y = 0 } 1.25 model

        Viewport.ZoomOutClicked ->
            zoomAt { x = 0, y = 0 } 0.8 model

        Viewport.ResetClicked ->
            resetViewport model

        Viewport.KeyPressed key ->
            case key of
                "+" ->
                    updateViewport Viewport.ZoomInClicked model

                "=" ->
                    updateViewport Viewport.ZoomInClicked model

                "-" ->
                    updateViewport Viewport.ZoomOutClicked model

                "Home" ->
                    resetViewport model

                "ArrowLeft" ->
                    { model | offset = { x = model.offset.x + 48, y = model.offset.y } }

                "ArrowRight" ->
                    { model | offset = { x = model.offset.x - 48, y = model.offset.y } }

                "ArrowUp" ->
                    { model | offset = { x = model.offset.x, y = model.offset.y + 48 } }

                "ArrowDown" ->
                    { model | offset = { x = model.offset.x, y = model.offset.y - 48 } }

                _ ->
                    model


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
    { model | offset = { x = 0, y = 0 }, zoom = 1, drag = Nothing, suppressClick = False }


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


updateBoard : Board.Msg -> Model -> ( Model, Eff Msg )
updateBoard boardMsg model =
    case boardMsg of
        Board.UnitMouseClicked id ->
            if model.suppressClick then
                ( model, E.none )

            else
                updateBoard (Board.UnitClicked id) model

        Board.TileMouseClicked position ->
            if model.suppressClick then
                ( model, E.none )

            else
                updateBoard (Board.TileClicked position) model

        Board.TileHovered position ->
            if model.drag /= Nothing || model.pathPreview == Nothing then
                ( model, E.none )

            else
                case traceTo position model of
                    Just preview ->
                        ( { model | pathPreview = Just preview, movementStatus = NoMovementStatus }, E.none )

                    Nothing ->
                        ( model, E.none )

        Board.UnitClicked id ->
            if Maybe.map .id (selectedUnit model) == Just id then
                update InspectClicked model

            else
                ( { model
                    | selected =
                        model.board.units
                            |> List.filter (\unit -> unit.id == id)
                            |> List.head
                            |> Maybe.map .position
                    , moveOptions =
                        model.board.units
                            |> List.filter (\unit -> unit.id == id && isOwnUnit model unit)
                            |> List.head
                            |> Maybe.map (\unit -> Movement.options (reservedDestinations unit model) model.movementRules model.board unit)
                            |> Maybe.withDefault []
                    , pathPreview =
                        model.board.units
                            |> List.filter (\unit -> unit.id == id && isOwnUnit model unit)
                            |> List.head
                            |> Maybe.map Movement.start
                    , movementStatus = NoMovementStatus
                  }
                , E.none
                )

        Board.TileClicked position ->
            case selectedUnit model of
                Just unit ->
                    if isOwnUnit model unit then
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
                                ( { model
                                    | plannedMoves = { unitId = unit.id, move = move } :: List.filter (\plan -> plan.unitId /= unit.id) model.plannedMoves
                                    , pathPreview = Nothing
                                    , movementStatus = MovePlanned
                                  }
                                , E.none
                                )

                            Nothing ->
                                ( { model | movementStatus = DestinationUnavailable }, E.none )

                    else
                        ( { model
                            | selected = Just position
                            , moveOptions = []
                            , pathPreview = Nothing
                            , movementStatus = NoMovementStatus
                          }
                        , E.none
                        )

                Nothing ->
                    ( { model
                        | selected = Just position
                        , moveOptions = []
                        , pathPreview = Nothing
                        , movementStatus = NoMovementStatus
                      }
                    , E.none
                    )


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
