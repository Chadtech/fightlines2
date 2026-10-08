module GamePage exposing
    ( Flags
    , Model
    , Msg
    , init
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
import Api.Object.Scenario as Scenario
import Api.Object.TerrainFeature as FeatureApi
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
import Json.Decode as Decode
import LobbyId
    exposing
        ( LobbyId
        )
import Map
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



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { name : String
    , mapType : MapType
    , players : List Player
    , board : GameBoard.GameBoard
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
    , selected : Maybe Coordinate.Coordinate
    , offset : Point
    , zoom : Float
    , drag : Maybe Drag
    , suppressClick : Bool
    , frame : AnimationFrame.Frame
    }


type Msg
    = BoardMsg Board.Msg
    | ViewportMsg Viewport.Msg
    | AnimationTimerElapsed Time.Posix



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
            SS.map4 Flags
                Snapshot.name
                Snapshot.mapType
                (Snapshot.players (SS.map3 Player PlayerView.name PlayerView.side PlayerView.isYou))
                (Snapshot.scenario boardSelection)
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

        AnimationTimerElapsed _ ->
            ( { model | frame = AnimationFrame.next model.frame }, E.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 400 AnimationTimerElapsed
        , viewportSubscriptions model
        ]



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


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
                }
                model.board
            )
        , GamePanel.toHtml
            (selectionView model)
            (viewControls model)
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
            [ H.text "selection"
            ]
        , H.p
            [ A.attribute "role" "status"
            ]
            [ H.text (selectionText model)
            ]
        ]


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

        Board.UnitClicked id ->
            ( { model
                | selected =
                    model.board.units
                        |> List.filter (\unit -> unit.id == id)
                        |> List.head
                        |> Maybe.map .position
              }
            , E.none
            )

        Board.TileClicked position ->
            ( { model | selected = Just position }, E.none )
