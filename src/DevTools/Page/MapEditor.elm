module DevTools.Page.MapEditor exposing
    ( Flags
    , Model
    , Msg
    , init
    , listeners
    , load
    , setShared
    , subscriptions
    , update
    , view
    )

import Api.Enum.BuildingKind as BuildingKind exposing (BuildingKind)
import Api.Enum.Direction as Direction exposing (Direction)
import Api.Enum.MapTheme as MapTheme exposing (MapTheme)
import Api.Enum.MapType as MapType exposing (MapType)
import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Api.Object.MapCatalog as CatalogApi
import Api.Query as Query
import ApiRequest
import Browser.Dom
import Browser.Events
import DevTools.Shared as Shared
import Drag exposing (Drag)
import EditableMap exposing (Definition, NamedMap)
import Effect as E exposing (Eff)
import Error
import Game.Camera as Camera exposing (Camera)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot as Depot
import Game.Map as Map exposing (Map)
import Game.MapType as MapType
import Game.Road as Road
import Game.Terrain as Terrain exposing (Terrain)
import Game.UnitKind
import Game.View.MapPreview as MapPreview
import Game.View.TerrainTile as TerrainTile
import Graphql.Http
import Graphql.SelectionSet as SS
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Html.Styled.Lazy as Lazy
import Json.Decode as D exposing (Decoder)
import Point exposing (Point)
import Ports.Js.From as FromJs
import Ports.Js.To as ToJs
import Random
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Checkbox as Checkbox
import View.Select as Select
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { first : NamedMap
    , rest : List NamedMap
    }


type alias Document =
    { mapType : MapType
    , draft : Definition
    , saved : Definition
    , undo : List Definition
    , redo : List Definition
    }


type alias Model =
    { shared : Shared.Model
    , mapOptions : List MapType
    , current : Document
    , others : List Document
    , brush : Brush
    , playerNumber : PlayerNumber
    , facing : Direction
    , gesture : CanvasGesture
    , saveState : SaveState
    , mirror : Bool
    , brushSize : Int
    , canvasView : CanvasView
    , viewport : Maybe Browser.Dom.Element
    , tool : Tool
    , spaceHeld : Bool
    , widthInput : String
    , heightInput : String
    }


type Brush
    = PaintRoad
    | PaintTerrain Terrain
    | PlaceUnit UnitKind
    | PlaceDepot BuildingKind
    | EraseUnit
    | EraseDepot


type BrushGroup
    = TerrainBrushes
    | UnitBrushes
    | DepotBrushes


type CanvasView
    = FitWorkspace
    | FreeView Camera


type Tool
    = PaintTool
    | HandTool


type CanvasButton
    = PrimaryButton
    | MiddleButton


type ViewportPurpose
    = RefreshLayout
    | ZoomAtPointer Point Float


type alias BrushSettings =
    { brush : Brush
    , playerNumber : PlayerNumber
    , facing : Direction
    }


type CanvasGesture
    = Resting
    | Painting Definition
    | Panning Drag


type SaveState
    = Idle
    | Saving PendingSave
    | Saved
    | Failed String


type alias PendingSave =
    { mapType : MapType
    , definition : Definition
    , requestId : SaveRequestId
    , phase : SavePhase
    , feedback : Maybe String
    }


type SaveRequestId
    = SaveRequestId Int


type SavePhase
    = RenderingThumbnail
    | SendingMap


type alias ThumbnailResult =
    { requestId : SaveRequestId
    , result : Result String String
    }


type Msg
    = MapInputChanged String
    | BrushButtonClicked Brush
    | PlayerNumberInputChanged String
    | FacingInputChanged String
    | ThemeInputChanged String
    | MirrorInputChanged Bool
    | BrushSizeInputChanged String
    | HandToolClicked
    | ZoomInClicked
    | ZoomOutClicked
    | ActualSizeClicked
    | FitMapClicked
    | CanvasMousePressed CanvasButton Point
    | CanvasMouseMoved Point Int
    | WheelScrolled Point Float
    | CanvasKeyPressed String
    | SpaceReleased
    | CanvasFocusReceived (Result Browser.Dom.Error ())
    | CanvasFocusLost
    | WindowResized
    | ViewportMeasured ViewportPurpose (Result Browser.Dom.Error Browser.Dom.Element)
    | TileMousePressed Coordinate
    | TileMouseEntered Coordinate Int
    | TileActivated Coordinate
    | MouseReleased
    | UndoButtonClicked
    | RedoButtonClicked
    | SaveButtonClicked
    | ThumbnailGenerated ThumbnailResult
    | SaveResponseReceived SaveRequestId (ApiRequest.Response ())
    | WidthInputChanged String
    | HeightInputChanged String
    | ResizeButtonClicked



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> ( Model, Eff Msg )
init shared flags =
    ( { shared = shared
      , mapOptions = List.map .mapType (flags.first :: flags.rest)
      , current = document flags.first
      , others = List.map document flags.rest
      , brush = PaintTerrain Terrain.Forest
      , playerNumber = PlayerNumber.Player1
      , facing = Direction.East
      , gesture = Resting
      , saveState = Idle
      , mirror = False
      , brushSize = 1
      , canvasView = FitWorkspace
      , viewport = Nothing
      , tool = PaintTool
      , spaceHeld = False
      , widthInput = String.fromInt flags.first.definition.width
      , heightInput = String.fromInt flags.first.definition.height
      }
    , measureViewport
    )


load : Graphql.Http.Request Flags
load =
    Query.maps
        (SS.succeed Flags
            |> SS.with (CatalogApi.first EditableMap.namedSelection)
            |> SS.with (CatalogApi.rest EditableMap.namedSelection)
        )
        |> ApiRequest.queryRequest


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


saveEffect : PendingSave -> String -> Eff Msg
saveEffect pending thumbnail =
    EditableMap.saveMutation pending.mapType pending.definition thumbnail
        |> ApiRequest.mutationRequest
        |> E.request (SaveResponseReceived pending.requestId)



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setCanvasView : CanvasView -> Model -> Model
setCanvasView canvasView model =
    { model | canvasView = canvasView }


setCurrent : Document -> Model -> Model
setCurrent current model =
    { model | current = current }


setGesture : CanvasGesture -> Model -> Model
setGesture gesture model =
    { model | gesture = gesture }


setSaveState : SaveState -> Model -> Model
setSaveState saveState model =
    { model | saveState = saveState }


setOthers : List Document -> Model -> Model
setOthers others model =
    { model | others = others }


setWidthInput : String -> Model -> Model
setWidthInput widthInput model =
    { model | widthInput = widthInput }


setHeightInput : String -> Model -> Model
setHeightInput heightInput model =
    { model | heightInput = heightInput }


setTool : Tool -> Model -> Model
setTool tool model =
    { model | tool = tool }


setSpaceHeld : Bool -> Model -> Model
setSpaceHeld spaceHeld model =
    { model | spaceHeld = spaceHeld }


setDocumentUndo : List Definition -> Document -> Document
setDocumentUndo undo model =
    { model | undo = undo }


setDocumentRedo : List Definition -> Document -> Document
setDocumentRedo redo model =
    { model | redo = redo }


setDocumentDraft : Definition -> Document -> Document
setDocumentDraft draft model =
    { model | draft = draft }


setPendingSaveFeedback : Maybe String -> PendingSave -> PendingSave
setPendingSaveFeedback feedback model =
    { model | feedback = feedback }


saveRequestIdValue : SaveRequestId -> Int
saveRequestIdValue (SaveRequestId value) =
    value


thumbnailHtmlId : String
thumbnailHtmlId =
    "map-thumbnail-source"


thumbnailSource : Model -> Html Msg
thumbnailSource model =
    case model.saveState of
        Saving pending ->
            H.div
                [ A.id thumbnailHtmlId
                , A.attribute "aria-hidden" "true"
                , A.css
                    [ S.displayNone
                    ]
                ]
                [ MapPreview.definitionToHtml
                    { mapType = pending.mapType
                    , definition = pending.definition
                    }
                ]

        _ ->
            H.text ""


canvasHtmlId : String
canvasHtmlId =
    "map-editor-canvas"


measureViewport : Eff Msg
measureViewport =
    E.measure canvasHtmlId (ViewportMeasured RefreshLayout)


{-| Camera offsets are screen pixels from the canvas center. At 100%, tiles are
32 pixels wide. Fit leaves room around every edge and follows workspace resizes.
-}
canvasCamera : Model -> Camera
canvasCamera model =
    case model.canvasView of
        FreeView camera ->
            camera

        FitWorkspace ->
            let
                fitZoom : Browser.Dom.Element -> Float
                fitZoom viewport =
                    min 4
                        (min
                            (max 1 (viewport.element.width - 32) / (toFloat model.current.draft.width * 32))
                            (max 1 (viewport.element.height - 32) / (toFloat model.current.draft.height * 32))
                        )
            in
            { offset = { x = 0, y = 0 }
            , zoom = model.viewport |> Maybe.map fitZoom |> Maybe.withDefault 1
            }


zoomCanvas : Point -> Float -> Model -> Model
zoomCanvas anchor factor model =
    let
        camera : Camera
        camera =
            canvasCamera model

        zoom : Float
        zoom =
            clamp 0.01 4 (camera.zoom * factor)

        ratio : Float
        ratio =
            zoom / camera.zoom
    in
    model
        |> setCanvasView
            (FreeView
                { zoom = zoom
                , offset =
                    { x = anchor.x - (anchor.x - camera.offset.x) * ratio
                    , y = anchor.y - (anchor.y - camera.offset.y) * ratio
                    }
                }
            )


panCanvas : Point -> Model -> Model
panCanvas delta model =
    let
        camera : Camera
        camera =
            canvasCamera model
    in
    model
        |> setCanvasView
            (FreeView
                (camera
                    |> Camera.setOffset
                        { x = camera.offset.x + delta.x
                        , y = camera.offset.y + delta.y
                        }
                )
            )


usesHand : Model -> Bool
usesHand model =
    (model.tool == HandTool) || model.spaceHeld


{-| Leave native text editing and browser shortcuts alone. Space still activates
focused controls; pressing on the canvas moves focus there before a pan begins.
-}
canvasKeyDecoder : Decoder ( Msg, Bool )
canvasKeyDecoder =
    let
        interpret : String -> String -> Bool -> Bool -> Bool -> Decoder ( Msg, Bool )
        interpret key tag ctrl meta alt =
            if List.member tag [ "INPUT", "TEXTAREA", "SELECT" ] || ctrl || meta || alt then
                D.fail "text editing or browser shortcut"

            else if List.member key [ " ", "+", "=", "-", "Home", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown" ] then
                D.succeed ( CanvasKeyPressed key, (key /= " ") || not (List.member tag [ "BUTTON", "A" ]) )

            else
                D.fail "not a canvas shortcut"
    in
    D.map5 interpret
        (D.field "key" D.string)
        (D.at [ "target", "tagName" ] D.string)
        (D.field "ctrlKey" D.bool)
        (D.field "metaKey" D.bool)
        (D.field "altKey" D.bool)
        |> D.andThen identity


canvasPressDecoder : Decoder ( Msg, Bool )
canvasPressDecoder =
    let
        pressed : Int -> Decoder ( Msg, Bool )
        pressed button =
            case button of
                0 ->
                    D.map (\point -> ( CanvasMousePressed PrimaryButton point, True )) Point.decoder

                1 ->
                    D.map (\point -> ( CanvasMousePressed MiddleButton point, True )) Point.decoder

                _ ->
                    D.fail "only primary or middle mouse button"
    in
    D.field "button" D.int |> D.andThen pressed


canvasWheelDecoder : Decoder ( Msg, Bool )
canvasWheelDecoder =
    let
        scrolled : Point -> Int -> Float -> ( Msg, Bool )
        scrolled point mode delta =
            let
                pixels : Float
                pixels =
                    case mode of
                        1 ->
                            delta * 16

                        2 ->
                            delta * 800

                        _ ->
                            delta
            in
            ( WheelScrolled point pixels, True )
    in
    D.map3 scrolled
        (D.map2 Point (D.field "pageX" D.float) (D.field "pageY" D.float))
        (D.field "deltaMode" D.int)
        (D.field "deltaY" D.float)


editingSaveState : SaveState -> SaveState
editingSaveState state =
    case state of
        Saving pending ->
            Saving
                (pending
                    |> setPendingSaveFeedback Nothing
                )

        _ ->
            Idle


editFailed : String -> SaveState -> SaveState
editFailed message state =
    case state of
        Saving pending ->
            Saving
                (pending
                    |> setPendingSaveFeedback (Just message)
                )

        _ ->
            Failed message


document : NamedMap -> Document
document named =
    { mapType = named.mapType
    , draft = named.definition
    , saved = named.definition
    , undo = []
    , redo = []
    }


remember : Definition -> Document -> Document
remember before current =
    if before == current.draft then
        current

    else
        current
            |> setDocumentUndo (List.take 100 (before :: current.undo))
            |> setDocumentRedo []


finishGesture : Model -> Model
finishGesture model =
    case model.gesture of
        Resting ->
            model

        Painting before ->
            model
                |> setCurrent (remember before model.current)
                |> setGesture Resting

        Panning _ ->
            model
                |> setGesture Resting


applyEdit : Definition -> Model -> Model
applyEdit draft model =
    let
        current : Document
        current =
            model.current
    in
    model
        |> setCurrent
            (remember current.draft
                (current
                    |> setDocumentDraft draft
                )
            )
        |> setSaveState (editingSaveState model.saveState)


paint : Coordinate -> Model -> Model
paint position model =
    let
        current : Document
        current =
            model.current

        radius : Int
        radius =
            model.brushSize // 2

        positions : List Coordinate
        positions =
            List.range (position.y - radius) (position.y + radius)
                |> List.concatMap
                    (\y ->
                        List.range (position.x - radius) (position.x + radius)
                            |> List.map (\x -> { x = x, y = y })
                    )

        mirrored : List Coordinate
        mirrored =
            if model.mirror then
                List.map
                    (\positionToMirror ->
                        { positionToMirror | x = current.draft.width - 1 - positionToMirror.x }
                    )
                    positions

            else
                []

        inBounds : Coordinate -> Bool
        inBounds candidate =
            (candidate.x >= 0)
                && (candidate.y >= 0)
                && (candidate.x < current.draft.width)
                && (candidate.y < current.draft.height)

        settings : BrushSettings
        settings =
            { brush = model.brush
            , playerNumber = model.playerNumber
            , facing = model.facing
            }

        reflectedSettings : BrushSettings
        reflectedSettings =
            { settings
                | playerNumber = reflectedPlayerNumber settings.playerNumber
                , facing = reflectedFacing settings.facing
            }

        originalTiles : List Coordinate
        originalTiles =
            List.filter inBounds positions

        mirroredTiles : List Coordinate
        mirroredTiles =
            List.filter
                (\candidate -> inBounds candidate && not (List.member candidate originalTiles))
                mirrored

        paintedDraft : Definition
        paintedDraft =
            List.foldl (paintTile settings) current.draft originalTiles
                |> (\painted -> List.foldl (paintTile reflectedSettings) painted mirroredTiles)

        draft : Definition
        draft =
            if brushGroup model.brush == TerrainBrushes then
                EditableMap.reconnectRoads (originalTiles ++ mirroredTiles) paintedDraft

            else
                paintedDraft
    in
    model
        |> setCurrent
            (current
                |> setDocumentDraft draft
            )
        |> setSaveState (editingSaveState model.saveState)


reflectedPlayerNumber : PlayerNumber -> PlayerNumber
reflectedPlayerNumber playerNumber =
    case playerNumber of
        PlayerNumber.Player1 ->
            PlayerNumber.Player2

        PlayerNumber.Player2 ->
            PlayerNumber.Player1


reflectedFacing : Direction -> Direction
reflectedFacing facing =
    case facing of
        Direction.East ->
            Direction.West

        Direction.West ->
            Direction.East

        Direction.North ->
            Direction.North

        Direction.South ->
            Direction.South


paintTile : BrushSettings -> Coordinate -> Definition -> Definition
paintTile settings position draft =
    let
        elsewhere : { a | position : Coordinate } -> Bool
        elsewhere item =
            item.position /= position

        nextId : Int
        nextId =
            List.maximum (List.map .id draft.units)
                |> Maybe.withDefault 0
                |> (+) 1

        unitDirection : UnitKind -> Maybe Direction
        unitDirection kind =
            case kind of
                UnitKind.Truck ->
                    Nothing

                _ ->
                    Just settings.facing

        existingId : Int
        existingId =
            List.filter (\unit -> unit.position == position) draft.units
                |> List.head
                |> Maybe.map .id
                |> Maybe.withDefault nextId
    in
    case settings.brush of
        PaintRoad ->
            paintTile { settings | brush = PaintTerrain (Terrain.Road Road.NorthSouth) } position draft

        PaintTerrain terrain ->
            let
                currentTerrain : Terrain
                currentTerrain =
                    draft.features
                        |> List.filter (\feature -> feature.position == position)
                        |> List.head
                        |> Maybe.map .terrain
                        |> Maybe.withDefault Terrain.Plain
            in
            if currentTerrain == terrain then
                draft

            else
                let
                    features : List { position : Coordinate, terrain : Terrain }
                    features =
                        List.filter elsewhere draft.features

                    nextFeatures : List { position : Coordinate, terrain : Terrain }
                    nextFeatures =
                        if terrain == Terrain.Plain then
                            features

                        else
                            { position = position, terrain = terrain } :: features
                in
                draft
                    |> EditableMap.setFeatures nextFeatures

        PlaceUnit kind ->
            draft
                |> EditableMap.setUnits
                    ({ id = existingId
                     , position = position
                     , playerNumber = settings.playerNumber
                     , kind = kind
                     , direction = unitDirection kind
                     }
                        :: List.filter elsewhere draft.units
                    )

        PlaceDepot kind ->
            draft
                |> EditableMap.setDepots
                    ({ position = position, kind = kind }
                        :: List.filter elsewhere draft.depots
                    )

        EraseUnit ->
            draft
                |> EditableMap.setUnits (List.filter elsewhere draft.units)

        EraseDepot ->
            draft
                |> EditableMap.setDepots (List.filter elsewhere draft.depots)



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    let
        current : Document
        current =
            model.current

        draft : Definition
        draft =
            current.draft
    in
    case msg of
        ThumbnailGenerated result ->
            case model.saveState of
                Saving pending ->
                    let
                        matchesPending : Bool
                        matchesPending =
                            (result.requestId == pending.requestId) && (pending.phase == RenderingThumbnail)
                    in
                    if matchesPending then
                        case result.result of
                            Ok png ->
                                ( model
                                    |> setSaveState (Saving { pending | phase = SendingMap })
                                , saveEffect pending png
                                )

                            Err error ->
                                ( model
                                    |> setSaveState (Failed ("could not generate map thumbnail: " ++ error))
                                , E.none
                                )

                    else
                        ( model, E.none )

                _ ->
                    ( model, E.none )

        SaveResponseReceived requestId result ->
            case model.saveState of
                Saving pending ->
                    let
                        matchesPendingSave : Bool
                        matchesPendingSave =
                            (requestId == pending.requestId) && (pending.phase == SendingMap)
                    in
                    if not matchesPendingSave then
                        ( model, E.none )

                    else
                        case result of
                            Ok () ->
                                let
                                    markSaved : Document -> Document
                                    markSaved item =
                                        if item.mapType == pending.mapType then
                                            { item
                                                | saved = pending.definition
                                            }

                                        else
                                            item

                                    savedCurrent : Document
                                    savedCurrent =
                                        markSaved model.current

                                    nextSaveState : SaveState
                                    nextSaveState =
                                        if savedCurrent.mapType == pending.mapType && savedCurrent.draft == pending.definition then
                                            Saved

                                        else
                                            Idle
                                in
                                ( model
                                    |> setCurrent savedCurrent
                                    |> setOthers (List.map markSaved model.others)
                                    |> setSaveState nextSaveState
                                , E.none
                                )

                            Err error ->
                                ( model
                                    |> setSaveState
                                        (Failed
                                            ("could not save "
                                                ++ MapType.label pending.mapType
                                                ++ ": "
                                                ++ ApiRequest.errorMessage error
                                            )
                                        )
                                , E.none
                                )

                _ ->
                    ( model, E.none )

        SaveButtonClicked ->
            case model.saveState of
                Saving _ ->
                    ( model, E.none )

                _ ->
                    let
                        finished : Model
                        finished =
                            finishGesture model

                        request : ( Int, Random.Seed )
                        request =
                            Random.step (Random.int 0 2147483647) finished.shared.seed

                        pending : PendingSave
                        pending =
                            { mapType = finished.current.mapType
                            , definition = finished.current.draft
                            , feedback = Nothing
                            , requestId = SaveRequestId (Tuple.first request)
                            , phase = RenderingThumbnail
                            }
                    in
                    ( finished
                        |> setSaveState (Saving pending)
                        |> setShared (Shared.setSeed (Tuple.second request) finished.shared)
                    , E.toJs (ToJs.GenerateMapThumbnail { htmlId = thumbnailHtmlId, requestId = saveRequestIdValue pending.requestId })
                    )

        MapInputChanged value ->
            let
                finished : Model
                finished =
                    finishGesture model

                matches : Document -> Bool
                matches doc =
                    EditableMap.name doc.mapType == value
            in
            case List.filter matches model.others of
                selected :: _ ->
                    (finished
                        |> setCurrent selected
                        |> setCanvasView FitWorkspace
                        |> setOthers (finished.current :: List.filter (not << matches) model.others)
                        |> setWidthInput (String.fromInt selected.draft.width)
                        |> setHeightInput (String.fromInt selected.draft.height)
                        |> setSaveState (editingSaveState model.saveState)
                    )
                        |> E.withOut
                        |> E.and measureViewport

                [] ->
                    ( model, E.none )

        BrushButtonClicked brush ->
            ( { model | brush = brush }
                |> setTool PaintTool
            , E.none
            )

        PlayerNumberInputChanged value ->
            { model
                | playerNumber =
                    PlayerNumber.fromString value |> Maybe.withDefault model.playerNumber
            }
                |> E.withOut

        FacingInputChanged value ->
            { model
                | facing =
                    Direction.fromString value
                        |> Maybe.withDefault model.facing
            }
                |> E.withOut

        ThemeInputChanged value ->
            case MapTheme.fromString value of
                Just theme ->
                    ( applyEdit { draft | theme = theme } (finishGesture model), E.none )

                Nothing ->
                    ( model, E.none )

        MirrorInputChanged enabled ->
            ( { model | mirror = enabled }, E.none )

        BrushSizeInputChanged value ->
            ( { model | brushSize = String.toInt value |> Maybe.withDefault model.brushSize }, E.none )

        HandToolClicked ->
            ( model
                |> setTool HandTool
            , E.none
            )

        ZoomInClicked ->
            ( zoomCanvas { x = 0, y = 0 } 1.25 (finishGesture model), E.none )

        ZoomOutClicked ->
            ( zoomCanvas { x = 0, y = 0 } 0.8 (finishGesture model), E.none )

        ActualSizeClicked ->
            ( zoomCanvas { x = 0, y = 0 } (1 / (canvasCamera model).zoom) (finishGesture model), E.none )

        FitMapClicked ->
            ( (model
                |> setCanvasView FitWorkspace
              )
                |> finishGesture
            , measureViewport
            )

        CanvasMousePressed button point ->
            let
                next : Model
                next =
                    if usesHand model || (button == MiddleButton) then
                        let
                            finished : Model
                            finished =
                                finishGesture model

                            camera : Camera
                            camera =
                                canvasCamera finished
                        in
                        finished
                            |> setCanvasView (FreeView camera)
                            |> setGesture (Panning (Drag.startAt { start = point, origin = camera.offset }))

                    else
                        model
            in
            ( next, E.focus { htmlId = canvasHtmlId } CanvasFocusReceived )

        CanvasFocusReceived result ->
            case result of
                Ok () ->
                    E.withOut model

                Err error ->
                    (model
                        |> setShared (Shared.addError (Just (Error.ElementFocusFailed error)) model.shared)
                    )
                        |> E.withOut

        CanvasMouseMoved point buttons ->
            case model.gesture of
                Panning drag ->
                    if buttons == 0 then
                        ( finishGesture model, E.none )

                    else
                        let
                            camera : Camera
                            camera =
                                canvasCamera model
                        in
                        ( model
                            |> setCanvasView
                                (FreeView
                                    (camera
                                        |> Camera.setOffset
                                            { x = (Drag.origin drag).x + point.x - (Drag.start drag).x
                                            , y = (Drag.origin drag).y + point.y - (Drag.start drag).y
                                            }
                                    )
                                )
                        , E.none
                        )

                _ ->
                    if buttons == 0 then
                        ( finishGesture model, E.none )

                    else
                        ( model, E.none )

        WheelScrolled point delta ->
            ( finishGesture model, E.measure canvasHtmlId (ViewportMeasured (ZoomAtPointer point delta)) )

        CanvasKeyPressed key ->
            let
                finished : Model
                finished =
                    finishGesture model

                centeredZoom : Float -> ( Model, Eff Msg )
                centeredZoom factor =
                    ( zoomCanvas { x = 0, y = 0 } factor finished, E.none )

                pan : Point -> ( Model, Eff Msg )
                pan delta =
                    ( panCanvas delta finished, E.none )
            in
            case key of
                " " ->
                    if model.spaceHeld then
                        ( model, E.none )

                    else
                        ( finished
                            |> setSpaceHeld True
                        , E.none
                        )

                "+" ->
                    centeredZoom 1.25

                "=" ->
                    centeredZoom 1.25

                "-" ->
                    centeredZoom 0.8

                "Home" ->
                    ( finished
                        |> setCanvasView FitWorkspace
                    , measureViewport
                    )

                "ArrowLeft" ->
                    pan { x = 48, y = 0 }

                "ArrowRight" ->
                    pan { x = -48, y = 0 }

                "ArrowUp" ->
                    pan { x = 0, y = 48 }

                "ArrowDown" ->
                    pan { x = 0, y = -48 }

                _ ->
                    ( model, E.none )

        SpaceReleased ->
            ( model
                |> setSpaceHeld False
            , E.none
            )

        CanvasFocusLost ->
            ( (model
                |> setSpaceHeld False
              )
                |> finishGesture
            , E.none
            )

        WindowResized ->
            ( model, measureViewport )

        ViewportMeasured purpose result ->
            case result of
                Ok viewport ->
                    let
                        measured : Model
                        measured =
                            { model | viewport = Just viewport }
                    in
                    case purpose of
                        RefreshLayout ->
                            ( measured, E.none )

                        ZoomAtPointer point delta ->
                            let
                                anchor : Point
                                anchor =
                                    { x = point.x - viewport.element.x - viewport.element.width / 2
                                    , y = point.y - viewport.element.y - viewport.element.height / 2
                                    }
                            in
                            ( zoomCanvas anchor (e ^ (negate (clamp -100 100 delta) * 0.002)) measured, E.none )

                Err error ->
                    model
                        |> setShared
                            (Shared.addError
                                (Just (Error.BattlefieldMeasurementFailed error))
                                model.shared
                            )
                        |> E.withOut

        TileMousePressed position ->
            if usesHand model then
                ( model, E.none )

            else
                let
                    finished : Model
                    finished =
                        finishGesture model
                in
                ( paint
                    position
                    (finished
                        |> setGesture (Painting finished.current.draft)
                    )
                , E.none
                )

        TileMouseEntered position buttons ->
            case model.gesture of
                Painting _ ->
                    if buttons == 1 then
                        ( paint position model, E.none )

                    else
                        ( finishGesture model, E.none )

                _ ->
                    ( model, E.none )

        TileActivated position ->
            if usesHand model then
                ( model, E.none )

            else
                let
                    painted : Model
                    painted =
                        paint position (finishGesture model)
                in
                ( painted
                    |> setCurrent (remember draft painted.current)
                , E.none
                )

        MouseReleased ->
            ( finishGesture model, E.none )

        UndoButtonClicked ->
            case current.undo of
                previous :: rest ->
                    (model
                        |> setCurrent
                            (current
                                |> setDocumentDraft previous
                                |> setDocumentUndo rest
                                |> setDocumentRedo (draft :: current.redo)
                            )
                        |> setSaveState (editingSaveState model.saveState)
                        |> setWidthInput (String.fromInt previous.width)
                        |> setHeightInput (String.fromInt previous.height)
                    )
                        |> E.withOut

                [] ->
                    ( model, E.none )

        RedoButtonClicked ->
            case current.redo of
                next :: rest ->
                    (model
                        |> setCurrent
                            (current
                                |> setDocumentDraft next
                                |> setDocumentUndo (draft :: current.undo)
                                |> setDocumentRedo rest
                            )
                        |> setSaveState (editingSaveState model.saveState)
                        |> setWidthInput (String.fromInt next.width)
                        |> setHeightInput (String.fromInt next.height)
                    )
                        |> E.withOut

                [] ->
                    ( model, E.none )

        WidthInputChanged value ->
            ( model
                |> setWidthInput value
            , E.none
            )

        HeightInputChanged value ->
            ( model
                |> setHeightInput value
            , E.none
            )

        ResizeButtonClicked ->
            case ( String.toInt model.widthInput, String.toInt model.heightInput ) of
                ( Just width, Just height ) ->
                    if width >= 1 && height >= 1 && width <= 64 && height <= 64 then
                        let
                            inside : { a | position : Coordinate } -> Bool
                            inside item =
                                item.position.x < width && item.position.y < height

                            croppedPositions : List Coordinate
                            croppedPositions =
                                draft.features
                                    |> List.filter (not << inside)
                                    |> List.map .position
                        in
                        applyEdit
                            (({ draft | width = width, height = height }
                                |> EditableMap.setFeatures (List.filter inside draft.features)
                                |> EditableMap.setUnits (List.filter inside draft.units)
                                |> EditableMap.setDepots (List.filter inside draft.depots)
                             )
                                |> EditableMap.reconnectRoads croppedPositions
                            )
                            model
                            |> E.withOut
                            |> E.and measureViewport

                    else
                        (model
                            |> setSaveState (editFailed "dimensions must be between 1 and 64" model.saveState)
                        )
                            |> E.withOut

                _ ->
                    ( model
                        |> setSaveState (editFailed "enter whole-number dimensions" model.saveState)
                    , E.none
                    )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.col
            , S.g3
            , S.hViewportInsetRem 2
            , S.minH0
            , S.overflowHidden
            ]
        , Ev.preventDefaultOn "keydown" canvasKeyDecoder
        ]
        [ thumbnailSource model
        , H.div
            [ A.css
                [ S.col
                , S.shrink0
                , S.maxH40Viewport
                , S.minH0
                , S.overflowHidden
                ]
            ]
            [ toolbar model
            ]
        , H.div
            [ A.css
                [ S.row
                , S.g3
                , S.flex1
                , S.minH0
                , S.belowWidth 768
                    [ S.col
                    ]
                ]
            ]
            [ H.div
                [ A.css
                    [ S.w72
                    , S.shrink0
                    , S.col
                    , S.minH0
                    , S.belowWidth 768
                        [ S.wFull
                        , S.flexP4
                        ]
                    ]
                ]
                [ paintingTools model
                ]
            , H.div
                [ A.css
                    [ S.flex1
                    , S.minH0
                    , S.minW0
                    , S.col
                    ]
                ]
                [ workspace model
                ]
            ]
        ]
    ]


toolbar : Model -> Html Msg
toolbar model =
    Card.toHtml (Card.panel |> Card.withHeader (CardHeader.simple "map editor"))
        [ H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g3
                , S.itemsEnd
                , S.justifySpaceBetween
                ]
            ]
            [ toolbarActions model
            , mapSettings model
            ]
        , H.p
            [ A.attribute "role" "status"
            , A.css
                [ S.m0
                ]
            ]
            [ H.text (status model)
            ]
        ]


toolbarActions : Model -> Html Msg
toolbarActions model =
    H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.g3
            , S.itemsEnd
            ]
        ]
        [ select "map-editor-map"
            "map"
            (EditableMap.name model.current.mapType)
            MapInputChanged
            (List.map (\kind -> ( EditableMap.name kind, MapType.label kind )) model.mapOptions)
        , H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g3
                , S.itemsCenter
                ]
            ]
            [ action "undo" (List.isEmpty model.current.undo) UndoButtonClicked
            , action "redo" (List.isEmpty model.current.redo) RedoButtonClicked
            , saveButton model
            , H.a
                [ A.href "/"
                , A.target "_blank"
                , A.rel "noopener"
                , A.css
                    [ S.textGray4
                    , S.selfCenter
                    , S.hover
                        [ S.textGray5
                        ]
                    ]
                ]
                [ H.text "play in new tab"
                ]
            ]
        ]


workspace : Model -> Html Msg
workspace model =
    let
        camera : Camera
        camera =
            canvasCamera model

        transform : String
        transform =
            "translate(" ++ String.fromFloat camera.offset.x ++ "px, " ++ String.fromFloat camera.offset.y ++ "px) scale(" ++ String.fromFloat camera.zoom ++ ")"

        panning : Bool
        panning =
            case model.gesture of
                Panning _ ->
                    True

                _ ->
                    False

        hint : String
        hint =
            if usesHand model then
                "drag to pan · choose a brush to paint"

            else
                "active brush · " ++ brushLabel model.brush ++ " · drag to paint"
    in
    Card.toHtml Card.panel
        [ H.div
            [ A.id canvasHtmlId
            , A.tabindex 0
            , A.attribute "aria-label" "map canvas · space and drag to pan · scroll to zoom · arrow keys to pan · home to fit"
            , A.css
                [ S.flex1
                , S.minH0
                , S.minW0
                , S.relative
                , S.row
                , S.itemsCenter
                , S.justifyCenter
                , S.overflowHidden
                , S.userSelectNone
                , S.bgNightwood3
                , S.indentStrong
                , S.focusVisible
                    [ S.outlineYellow5
                    , S.outlineOffsetNeg3
                    ]
                , S.when (usesHand model) S.grabCursor
                , S.when panning S.grabbingCursor
                ]
            , Ev.preventDefaultOn "mousedown" canvasPressDecoder
            , Ev.preventDefaultOn "wheel" canvasWheelDecoder
            , Ev.onBlur CanvasFocusLost
            ]
            [ H.div
                [ A.css
                    [ S.shrink0
                    , S.transform transform
                    ]
                ]
                [ Lazy.lazy board model.current.draft
                ]
            ]
        , H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g3
                , S.itemsCenter
                , S.shrink0
                ]
            ]
            [ Button.secondary "−" ZoomOutClicked
                |> Button.accessibleLabel "zoom out"
                |> Button.toHtml
            , Button.secondary (String.fromInt (round (camera.zoom * 100)) ++ "%") ActualSizeClicked
                |> Button.accessibleLabel "zoom to 100% · 32 pixels per tile"
                |> Button.toHtml
            , Button.secondary "+" ZoomInClicked
                |> Button.accessibleLabel "zoom in"
                |> Button.toHtml
            , Button.secondary "fit map" FitMapClicked
                |> Button.toHtml
            , H.p
                [ A.css
                    [ S.m0
                    ]
                ]
                [ H.text hint ]
            , H.p
                [ A.css
                    [ S.m0
                    ]
                ]
                [ H.text "space + drag to pan · scroll to zoom" ]
            ]
        ]


saveButton : Model -> Html Msg
saveButton model =
    case model.saveState of
        Saving _ ->
            Button.disabled "saving…" |> Button.toHtml

        _ ->
            Button.primary "save map" SaveButtonClicked |> Button.toHtml


action : String -> Bool -> Msg -> Html Msg
action label disabled message =
    if disabled then
        Button.disabled label |> Button.toHtml

    else
        Button.secondary label message |> Button.toHtml


status : Model -> String
status model =
    case model.saveState of
        Saving pending ->
            pending.feedback |> Maybe.withDefault "saving…"

        Saved ->
            "saved to maps/"
                ++ EditableMap.name model.current.mapType
                ++ ".json. new development games use this map; rebuild for production."

        Failed error ->
            error

        Idle ->
            if model.current.draft /= model.current.saved then
                "unsaved changes · drafts stay here while switching maps"

            else
                "no unsaved changes · existing games keep their board"


select : String -> String -> String -> (String -> Msg) -> List ( String, String ) -> Html Msg
select htmlId label value changed options =
    let
        option : ( String, String ) -> { value : String, label : String }
        option ( key, caption ) =
            { value = key
            , label = caption
            }
    in
    H.div
        [ A.css
            [ S.col
            , S.g1
            ]
        ]
        [ H.label
            [ A.for htmlId
            ]
            [ H.text label
            ]
        , Select.toHtml
            { htmlId = htmlId
            , disabled = False
            , selected = value
            , options = List.map option options
            , toValue = identity
            , decoder = D.string
            , onChange = changed
            }
        ]


brushGroup : Brush -> BrushGroup
brushGroup brush =
    case brush of
        PaintRoad ->
            TerrainBrushes

        PaintTerrain _ ->
            TerrainBrushes

        PlaceUnit _ ->
            UnitBrushes

        EraseUnit ->
            UnitBrushes

        PlaceDepot _ ->
            DepotBrushes

        EraseDepot ->
            DepotBrushes


brushLabel : Brush -> String
brushLabel brush =
    case brush of
        PaintRoad ->
            "road"

        PaintTerrain terrain ->
            Terrain.label terrain

        PlaceUnit kind ->
            Game.UnitKind.label kind

        PlaceDepot kind ->
            Depot.kindLabel kind

        EraseUnit ->
            "erase unit"

        EraseDepot ->
            "erase building"


paintingTools : Model -> Html Msg
paintingTools model =
    let
        group : BrushGroup
        group =
            brushGroup model.brush

        groupButton : String -> BrushGroup -> Brush -> Html Msg
        groupButton label target initial =
            let
                brush : Brush
                brush =
                    if group == target then
                        model.brush

                    else
                        initial
            in
            Button.choice label ((group == target) && (model.tool == PaintTool)) (BrushButtonClicked brush)
                |> Button.toHtml

        brushes : List Brush
        brushes =
            case group of
                TerrainBrushes ->
                    List.map PaintTerrain Terrain.all ++ [ PaintRoad ]

                UnitBrushes ->
                    List.map PlaceUnit UnitKind.list
                        ++ [ EraseUnit
                           ]

                DepotBrushes ->
                    [ PlaceDepot BuildingKind.Supply
                    , PlaceDepot BuildingKind.Fuel
                    , PlaceDepot BuildingKind.Fortress
                    , EraseDepot
                    ]

        unitSettings : List (Html Msg)
        unitSettings =
            case group of
                UnitBrushes ->
                    [ select "map-editor-player"
                        "player"
                        (PlayerNumber.toString model.playerNumber)
                        PlayerNumberInputChanged
                        [ ( "PLAYER1", "player 1 · red" )
                        , ( "PLAYER2", "player 2 · blue" )
                        ]
                    , select "map-editor-facing"
                        "facing"
                        (Direction.toString model.facing)
                        FacingInputChanged
                        (List.map (\direction -> ( Direction.toString direction, String.toLower (Direction.toString direction) )) Direction.list)
                    ]

                _ ->
                    []

        content : List (Html Msg)
        content =
            [ H.div
                [ A.css
                    [ S.col
                    , S.g1
                    ]
                ]
                [ Button.choice "hand · pan" (model.tool == HandTool) HandToolClicked
                    |> Button.toHtml
                , groupButton "terrain" TerrainBrushes (PaintTerrain Terrain.Forest)
                , groupButton "starting units" UnitBrushes (PlaceUnit UnitKind.Infantry)
                , groupButton "buildings" DepotBrushes (PlaceDepot BuildingKind.Supply)
                ]
            , H.div
                [ A.css
                    [ S.grid
                    , S.gridCols2
                    , S.g1
                    ]
                ]
                (List.map (brushButton model) brushes)
            ]
                ++ unitSettings
                ++ [ select "map-editor-brush-size"
                        "brush size"
                        (String.fromInt model.brushSize)
                        BrushSizeInputChanged
                        [ ( "1", "1 × 1" )
                        , ( "3", "3 × 3" )
                        , ( "5", "5 × 5" )
                        ]
                   , Checkbox.new
                        { label = "mirror paint horizontally"
                        , checked = model.mirror
                        , onCheck = MirrorInputChanged
                        }
                        |> Checkbox.toHtml
                            [ H.text "mirror paint horizontally"
                            ]
                   , H.p
                        [ A.css
                            [ S.m0
                            ]
                        ]
                        [ H.text "mirrored units swap players and reflect facing."
                        ]
                   ]
    in
    Card.toHtml (Card.panel |> Card.withHeader (CardHeader.simple "painting tools")) content


mapSettings : Model -> Html Msg
mapSettings model =
    H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.itemsEnd
            , S.g3
            ]
        ]
        [ select "map-editor-theme"
            "theme"
            (MapTheme.toString model.current.draft.theme)
            ThemeInputChanged
            [ ( "GREEN_FOREST", "green forest" )
            , ( "DESERT", "desert" )
            , ( "SNOW", "snow" )
            ]
        , H.div
            [ A.css
                [ S.row
                , S.g2
                ]
            ]
            [ dimensionField "width" model.widthInput WidthInputChanged
            , dimensionField "height" model.heightInput HeightInputChanged
            ]
        , H.div
            []
            [ Button.secondary "resize" ResizeButtonClicked
                |> Button.accessibleLabel "resize · shrinking crops outside tiles and objects; undo restores them"
                |> Button.toHtml
            ]
        ]


dimensionField : String -> String -> (String -> Msg) -> Html Msg
dimensionField label value changed =
    H.label
        [ A.css
            [ S.col
            , S.g1
            , S.w16
            ]
        ]
        [ H.text label
        , TextField.simple value changed |> TextField.toHtml
        ]


brushButton : Model -> Brush -> Html Msg
brushButton model brush =
    let
        button : Button.Button Msg
        button =
            Button.choice (brushLabel brush) ((model.brush == brush) && (model.tool == PaintTool)) (BrushButtonClicked brush)

        illustrated : Button.Button Msg
        illustrated =
            case brush of
                EraseUnit ->
                    button

                EraseDepot ->
                    button

                _ ->
                    button |> Button.withIcon (brushPreview model brush)
    in
    illustrated |> Button.toHtml


brushPreview : Model -> Brush -> Html Msg
brushPreview model brush =
    let
        artwork : List (Svg Msg)
        artwork =
            case brush of
                PaintRoad ->
                    [ TerrainTile.toSvg { theme = model.current.draft.theme, terrain = Terrain.Road Road.EastSouthWest } ]

                PaintTerrain terrain ->
                    [ TerrainTile.toSvg { theme = model.current.draft.theme, terrain = terrain }
                    ]

                PlaceUnit kind ->
                    [ MapPreview.unitToSvg
                        { id = 0
                        , position =
                            { x = 0
                            , y = 0
                            }
                        , playerNumber = model.playerNumber
                        , kind = kind
                        , direction = Just model.facing
                        }
                    ]

                PlaceDepot kind ->
                    [ MapPreview.depotToSvg
                        { position =
                            { x = 0
                            , y = 0
                            }
                        , kind = kind
                        }
                    ]

                EraseUnit ->
                    []

                EraseDepot ->
                    []
    in
    Svg.svg
        [ SA.width "32"
        , SA.height "32"
        , SA.viewBox "0 0 16 16"
        , A.attribute "aria-hidden" "true"
        , A.css
            [ S.shrink0
            , S.pointerEventsNone
            ]
        ]
        artwork


board : Definition -> Html Msg
board draft =
    let
        tiles : Html Msg
        tiles =
            Lazy.lazy boardTiles draft
    in
    Svg.svg
        [ SA.width (String.fromInt (draft.width * 32))
        , SA.height (String.fromInt (draft.height * 32))
        , SA.viewBox ("0 0 " ++ String.fromInt (draft.width * 16) ++ " " ++ String.fromInt (draft.height * 16))
        , A.attribute "aria-label" "editable battlefield"
        , A.css
            [ S.userSelectNone
            , S.block
            , S.shrink0
            ]
        ]
        [ tiles ]


boardTiles : Definition -> Svg Msg
boardTiles draft =
    let
        map : Map
        map =
            EditableMap.map draft
    in
    Svg.g
        []
        (Map.positions map |> List.map (tile draft map))


tile : Definition -> Map -> Coordinate -> Svg Msg
tile draft map position =
    let
        terrain : Terrain
        terrain =
            Map.terrainAt map position

        objects : List (Svg Msg)
        objects =
            List.filter (\depot -> depot.position == position) draft.depots |> List.map MapPreview.depotToSvg

        units : List (Svg Msg)
        units =
            List.filter (\unit -> unit.position == position) draft.units |> List.map MapPreview.unitToSvg

        pressed : D.Decoder ( Msg, Bool )
        pressed =
            D.field "button" D.int
                |> D.andThen
                    (\button ->
                        if button == 0 then
                            D.succeed ( TileMousePressed position, True )

                        else
                            D.fail "primary button only"
                    )

        activated : D.Decoder ( Msg, Bool )
        activated =
            D.field "key" D.string
                |> D.andThen
                    (\key ->
                        if key == "Enter" then
                            D.succeed ( TileActivated position, True )

                        else
                            D.fail "tile activation only"
                    )

        tileLabel : String
        tileLabel =
            "tile "
                ++ String.fromInt position.x
                ++ ", "
                ++ String.fromInt position.y
                ++ " · "
                ++ Terrain.label terrain

        unitLabels : List String
        unitLabels =
            List.filter (\unit -> unit.position == position) draft.units
                |> List.map
                    (\unit ->
                        String.toLower (PlayerNumber.toString unit.playerNumber)
                            ++ " "
                            ++ Game.UnitKind.label unit.kind
                    )

        buildingLabels : List String
        buildingLabels =
            draft.depots
                |> List.filter (\depot -> depot.position == position)
                |> List.map (.kind >> Depot.kindLabel)

        objectLabels : List String
        objectLabels =
            buildingLabels ++ unitLabels

        accessibleLabel : String
        accessibleLabel =
            String.join " · " (tileLabel :: objectLabels)

        ground : Svg Msg
        ground =
            TerrainTile.onMap map position

        interaction : Svg Msg
        interaction =
            Svg.rect
                [ SA.width "16"
                , SA.height "16"
                , SA.fill "transparent"
                , SA.stroke S.gray3Str
                , SA.strokeWidth "0.2"
                , A.attribute "role" "button"
                , A.attribute "tabindex" "0"
                , A.attribute "aria-label" accessibleLabel
                , Ev.preventDefaultOn "mousedown" pressed
                , Ev.on "mouseenter" (D.map (TileMouseEntered position) (D.field "buttons" D.int))
                , Ev.preventDefaultOn "keydown" activated
                ]
                []

        content : List (Svg Msg)
        content =
            ground
                :: (objects
                        ++ units
                        ++ [ interaction
                           ]
                   )
    in
    Svg.g
        [ SA.transform
            ("translate("
                ++ String.fromInt (position.x * 16)
                ++ " "
                ++ String.fromInt (position.y * 16)
                ++ ")"
            )
        ]
        content



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


listeners : FromJs.Listener Msg
listeners =
    let
        thumbnailResultDecoder : Decoder (Result String String)
        thumbnailResultDecoder =
            let
                fromError : Maybe String -> Decoder (Result String String)
                fromError error =
                    case error of
                        Just message ->
                            D.succeed (Err message)

                        Nothing ->
                            D.field "png" D.string |> D.map Ok
            in
            D.field "error" (D.nullable D.string) |> D.andThen fromError
    in
    FromJs.data "mapThumbnailGenerated"
        (D.map2 ThumbnailResult
            (D.field "requestId" D.int |> D.map SaveRequestId)
            thumbnailResultDecoder
        )
        ThumbnailGenerated


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        gestures : Sub Msg
        gestures =
            case model.gesture of
                Resting ->
                    Sub.none

                _ ->
                    Sub.batch
                        [ Browser.Events.onMouseMove (D.map2 CanvasMouseMoved Point.decoder (D.field "buttons" D.int))
                        , Browser.Events.onMouseUp (D.succeed MouseReleased)
                        ]

        releasedSpace : D.Decoder Msg
        releasedSpace =
            D.field "key" D.string
                |> D.andThen
                    (\key ->
                        if key == " " then
                            D.succeed SpaceReleased

                        else
                            D.fail "not space"
                    )
    in
    Sub.batch
        [ gestures
        , Browser.Events.onKeyUp releasedSpace
        , Browser.Events.onVisibilityChange (always CanvasFocusLost)
        , Browser.Events.onResize (\_ _ -> WindowResized)
        ]
