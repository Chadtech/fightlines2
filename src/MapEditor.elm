module MapEditor exposing
    ( Flags
    , Model
    , Msg
    , init
    , load
    , setShared
    , subscriptions
    , update
    , view
    )

import Api.Enum.DepotKind as DepotKind exposing (DepotKind)
import Api.Enum.Direction as Direction exposing (Direction)
import Api.Enum.MapTheme as MapTheme exposing (MapTheme)
import Api.Enum.MapType as MapType exposing (MapType)
import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.Terrain as Terrain exposing (Terrain)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Api.Object.MapCatalog as CatalogApi
import Api.Query as Query
import ApiRequest
import Browser.Events
import Coordinate exposing (Coordinate)
import EditableMap exposing (Definition, NamedMap)
import Effect as E exposing (Eff)
import Graphql.Http
import Graphql.SelectionSet as SS
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as D
import Map
import MapType
import Shared
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Terrain
import Util.UnitKind
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Checkbox as Checkbox
import View.Select as Select
import View.Sprite as Sprite
import View.TerrainTile as TerrainTile
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
    , current : Document
    , others : List Document
    , brush : Brush
    , playerNumber : PlayerNumber
    , facing : Direction
    , stroke : Stroke
    , saveState : SaveState
    , mirror : Bool
    , brushSize : Int
    , tileSize : Int
    , widthInput : String
    , heightInput : String
    }


type Brush
    = PaintTerrain Terrain
    | PlaceUnit UnitKind
    | PlaceDepot DepotKind
    | EraseUnit
    | EraseDepot


type alias BrushSettings =
    { brush : Brush
    , playerNumber : PlayerNumber
    , facing : Direction
    }


type Stroke
    = Resting
    | Painting Definition


type SaveState
    = Idle
    | Saving PendingSave
    | Saved
    | Failed String


type alias PendingSave =
    { mapType : MapType
    , definition : Definition
    , feedback : Maybe String
    }


type Msg
    = MapInputChanged String
    | BrushButtonClicked Brush
    | PlayerNumberInputChanged String
    | FacingInputChanged String
    | ThemeInputChanged String
    | MirrorInputChanged Bool
    | BrushSizeInputChanged String
    | ZoomInputChanged String
    | TileMousePressed Coordinate
    | TileMouseEntered Coordinate Int
    | TileActivated Coordinate
    | MouseReleased
    | UndoButtonClicked
    | RedoButtonClicked
    | SaveButtonClicked
    | SaveResponseReceived (ApiRequest.Response ())
    | WidthInputChanged String
    | HeightInputChanged String
    | ResizeButtonClicked



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> Model
init shared flags =
    { shared = shared
    , current = document flags.first
    , others = List.map document flags.rest
    , brush = PaintTerrain Terrain.Forest
    , playerNumber = PlayerNumber.Player1
    , facing = Direction.East
    , stroke = Resting
    , saveState = Idle
    , mirror = False
    , brushSize = 1
    , tileSize = 32
    , widthInput = String.fromInt flags.first.definition.width
    , heightInput = String.fromInt flags.first.definition.height
    }


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


saveEffect : PendingSave -> Eff Msg
saveEffect pending =
    EditableMap.saveMutation pending.mapType pending.definition
        |> ApiRequest.mutationRequest
        |> E.request SaveResponseReceived



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


editingSaveState : SaveState -> SaveState
editingSaveState state =
    case state of
        Saving pending ->
            Saving
                { pending
                    | feedback = Nothing
                }

        _ ->
            Idle


editFailed : String -> SaveState -> SaveState
editFailed message state =
    case state of
        Saving pending ->
            Saving
                { pending
                    | feedback = Just message
                }

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
        { current | undo = List.take 100 (before :: current.undo), redo = [] }


finishStroke : Model -> Model
finishStroke model =
    case model.stroke of
        Resting ->
            model

        Painting before ->
            { model | current = remember before model.current, stroke = Resting }


applyEdit : Definition -> Model -> Model
applyEdit draft model =
    let
        current : Document
        current =
            model.current
    in
    { model
        | current = remember current.draft { current | draft = draft }
        , saveState = editingSaveState model.saveState
    }


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

        draft : Definition
        draft =
            List.foldl (paintTile settings) current.draft originalTiles
                |> (\painted -> List.foldl (paintTile reflectedSettings) painted mirroredTiles)
    in
    { model
        | current = { current | draft = draft }
        , saveState = editingSaveState model.saveState
    }


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
        PaintTerrain terrain ->
            if Map.terrainAt (EditableMap.map draft) position == terrain then
                draft

            else
                let
                    features : List { position : Coordinate, terrain : Terrain }
                    features =
                        List.filter elsewhere draft.features

                    nextFeatures : List { position : Coordinate, terrain : Terrain }
                    nextFeatures =
                        if terrain == Terrain.GrassPlain then
                            features

                        else
                            { position = position, terrain = terrain } :: features
                in
                { draft | features = nextFeatures }

        PlaceUnit kind ->
            { draft
                | units =
                    { id = existingId
                    , position = position
                    , playerNumber = settings.playerNumber
                    , kind = kind
                    , direction = unitDirection kind
                    }
                        :: List.filter elsewhere draft.units
            }

        PlaceDepot kind ->
            { draft
                | depots =
                    { position = position, kind = kind }
                        :: List.filter elsewhere draft.depots
            }

        EraseUnit ->
            { draft
                | units =
                    List.filter elsewhere draft.units
            }

        EraseDepot ->
            { draft
                | depots =
                    List.filter elsewhere draft.depots
            }



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
        SaveResponseReceived result ->
            case model.saveState of
                Saving pending ->
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
                            ( { model
                                | current = savedCurrent
                                , others = List.map markSaved model.others
                                , saveState = nextSaveState
                              }
                            , E.none
                            )

                        Err error ->
                            ( { model
                                | saveState =
                                    Failed
                                        ("could not save "
                                            ++ MapType.label pending.mapType
                                            ++ ": "
                                            ++ ApiRequest.errorMessage error
                                        )
                              }
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
                            finishStroke model

                        pending : PendingSave
                        pending =
                            { mapType = finished.current.mapType
                            , definition = finished.current.draft
                            , feedback = Nothing
                            }
                    in
                    ( { finished
                        | saveState = Saving pending
                      }
                    , saveEffect pending
                    )

        MapInputChanged value ->
            let
                finished : Model
                finished =
                    finishStroke model

                matches : Document -> Bool
                matches doc =
                    EditableMap.name doc.mapType == value
            in
            case List.filter matches model.others of
                selected :: _ ->
                    { finished
                        | current = selected
                        , others = finished.current :: List.filter (not << matches) model.others
                        , widthInput = String.fromInt selected.draft.width
                        , heightInput = String.fromInt selected.draft.height
                        , saveState = editingSaveState model.saveState
                    }
                        |> E.withOut

                [] ->
                    ( model, E.none )

        BrushButtonClicked brush ->
            ( { model | brush = brush }, E.none )

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
                    ( applyEdit { draft | theme = theme } (finishStroke model), E.none )

                Nothing ->
                    ( model, E.none )

        MirrorInputChanged enabled ->
            ( { model | mirror = enabled }, E.none )

        BrushSizeInputChanged value ->
            ( { model | brushSize = String.toInt value |> Maybe.withDefault model.brushSize }, E.none )

        ZoomInputChanged value ->
            ( { model | tileSize = String.toInt value |> Maybe.withDefault model.tileSize }, E.none )

        TileMousePressed position ->
            let
                finished : Model
                finished =
                    finishStroke model
            in
            ( paint position { finished | stroke = Painting finished.current.draft }, E.none )

        TileMouseEntered position buttons ->
            case model.stroke of
                Painting _ ->
                    if buttons == 1 then
                        ( paint position model, E.none )

                    else
                        ( finishStroke model, E.none )

                Resting ->
                    ( model, E.none )

        TileActivated position ->
            let
                painted : Model
                painted =
                    paint position (finishStroke model)
            in
            ( { painted | current = remember draft painted.current }, E.none )

        MouseReleased ->
            ( finishStroke model, E.none )

        UndoButtonClicked ->
            case current.undo of
                previous :: rest ->
                    { model
                        | current =
                            { current
                                | draft = previous
                                , undo = rest
                                , redo = draft :: current.redo
                            }
                        , saveState = editingSaveState model.saveState
                        , widthInput = String.fromInt previous.width
                        , heightInput = String.fromInt previous.height
                    }
                        |> E.withOut

                [] ->
                    ( model, E.none )

        RedoButtonClicked ->
            case current.redo of
                next :: rest ->
                    { model
                        | current =
                            { current
                                | draft = next
                                , undo = draft :: current.undo
                                , redo = rest
                            }
                        , saveState = editingSaveState model.saveState
                        , widthInput = String.fromInt next.width
                        , heightInput = String.fromInt next.height
                    }
                        |> E.withOut

                [] ->
                    ( model, E.none )

        WidthInputChanged value ->
            ( { model | widthInput = value }, E.none )

        HeightInputChanged value ->
            ( { model | heightInput = value }, E.none )

        ResizeButtonClicked ->
            case ( String.toInt model.widthInput, String.toInt model.heightInput ) of
                ( Just width, Just height ) ->
                    if width >= 1 && height >= 1 && width <= 64 && height <= 64 then
                        let
                            inside : { a | position : Coordinate } -> Bool
                            inside item =
                                item.position.x < width && item.position.y < height
                        in
                        applyEdit
                            { draft
                                | width = width
                                , height = height
                                , features = List.filter inside draft.features
                                , units = List.filter inside draft.units
                                , depots = List.filter inside draft.depots
                            }
                            model
                            |> E.withOut

                    else
                        { model | saveState = editFailed "dimensions must be between 1 and 64" model.saveState }
                            |> E.withOut

                _ ->
                    ( { model | saveState = editFailed "enter whole-number dimensions" model.saveState }, E.none )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g3
                , S.itemsCenter
                ]
            ]
            [ H.text "map editor"
            , select "map-editor-map"
                "map"
                (EditableMap.name model.current.mapType)
                MapInputChanged
                (List.map
                    (\kind -> ( EditableMap.name kind, MapType.label kind ))
                    MapType.list
                )
            , action "undo" (List.isEmpty model.current.undo) UndoButtonClicked
            , action "redo" (List.isEmpty model.current.redo) RedoButtonClicked
            , saveButton model
            , H.a
                [ A.href "/"
                , A.target "_blank"
                , A.rel "noopener"
                , A.css
                    [ S.textGray4
                    , S.hover
                        [ S.textGray5
                        ]
                    ]
                ]
                [ H.text "play in new tab"
                ]
            ]
        , H.p
            [ A.attribute "role" "status"
            ]
            [ H.text (status model)
            ]
        , H.fieldset
            [ A.css
                [ S.border0
                , S.minW0
                , S.wFull
                , S.row
                , S.flexWrap
                , S.g3
                ]
            ]
            [ H.div
                [ A.css
                    [ S.w72
                    , S.maxHViewportInset8
                    , S.overflowAuto
                    , S.belowWidth 768
                        [ S.wFull
                        , S.maxH64
                        ]
                    ]
                ]
                [ controls model
                ]
            , H.div
                [ A.css
                    [ S.flex1
                    , S.minW0
                    , S.overflowAuto
                    , S.belowWidth 768
                        [ S.basisFull
                        ]
                    ]
                ]
                [ board model
                ]
            ]
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
                "click or drag to paint · save writes the map file · existing games keep their board"


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
            [ A.for htmlId ]
            [ H.text label ]
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


controls : Model -> Html Msg
controls model =
    let
        terrainButton : Terrain -> Html Msg
        terrainButton terrain =
            brushButton model (Terrain.label terrain) (PaintTerrain terrain)

        unitButton : UnitKind -> Html Msg
        unitButton kind =
            brushButton model (Util.UnitKind.label kind) (PlaceUnit kind)
    in
    [ H.text "terrain"
    , H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.g1
            ]
        ]
        (List.map terrainButton Terrain.list)
    , H.text "starting units"
    , select "map-editor-player"
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
        (List.map
            (\direction ->
                ( Direction.toString
                    direction
                , String.toLower (Direction.toString direction)
                )
            )
            Direction.list
        )
    , H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.g1
            ]
        ]
        (List.map unitButton UnitKind.list)
    , brushButton model "erase unit" EraseUnit
    , H.text "depots"
    , H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.g1
            ]
        ]
        [ brushButton model "supply" (PlaceDepot DepotKind.Supply)
        , brushButton model "fuel" (PlaceDepot DepotKind.Fuel)
        , brushButton model "erase depot" EraseDepot
        ]
    , select "map-editor-theme"
        "theme"
        (MapTheme.toString model.current.draft.theme)
        ThemeInputChanged
        [ ( "GREEN_FOREST", "green forest" )
        , ( "DESERT", "desert" )
        , ( "SNOW", "snow" )
        ]
    , select "map-editor-brush-size"
        "brush size"
        (String.fromInt model.brushSize)
        BrushSizeInputChanged
        [ ( "1", "1 × 1" )
        , ( "3", "3 × 3" )
        , ( "5", "5 × 5" )
        ]
    , Checkbox.toHtml
        { label = "mirror paint horizontally"
        , checked = model.mirror
        , onCheck = MirrorInputChanged
        }
        [ H.text "mirror paint horizontally"
        ]
    , H.p []
        [ H.text "mirrored units use the opposing player and reflected facing."
        ]
    , select "map-editor-tile-size"
        "tile size"
        (String.fromInt model.tileSize)
        ZoomInputChanged
        [ ( "16", "small" )
        , ( "32", "medium" )
        , ( "48", "large" )
        ]
    , H.div
        [ A.css
            [ S.row
            , S.g2
            ]
        ]
        [ H.label
            [ A.css
                [ S.col
                , S.g1
                ]
            ]
            [ H.text "width"
            , TextField.simple model.widthInput WidthInputChanged |> TextField.toHtml
            ]
        , H.label
            [ A.css
                [ S.col
                , S.g1
                ]
            ]
            [ H.text "height"
            , TextField.simple model.heightInput HeightInputChanged |> TextField.toHtml
            ]
        ]
    , Button.secondary "resize" ResizeButtonClicked |> Button.toHtml
    , H.p []
        [ H.text "shrinking crops outside tiles and objects. undo restores them."
        ]
    ]
        |> Card.toHtml (Card.simple |> Card.withHeader (CardHeader.simple "tools"))


brushButton : Model -> String -> Brush -> Html Msg
brushButton model label brush =
    if model.brush == brush then
        Button.primary label (BrushButtonClicked brush) |> Button.toHtml

    else
        Button.secondary label (BrushButtonClicked brush) |> Button.toHtml


board : Model -> Html Msg
board model =
    let
        draft : Definition
        draft =
            model.current.draft

        tiles : List (Svg Msg)
        tiles =
            Map.positions (EditableMap.map draft) |> List.map (tile model)
    in
    Svg.svg
        [ SA.width (String.fromInt (draft.width * model.tileSize))
        , SA.height (String.fromInt (draft.height * model.tileSize))
        , SA.viewBox ("0 0 " ++ String.fromInt (draft.width * 16) ++ " " ++ String.fromInt (draft.height * 16))
        , A.attribute "aria-label" "editable battlefield"
        , A.css
            [ S.userSelectNone
            ]
        ]
        tiles


tile : Model -> Coordinate -> Svg Msg
tile model position =
    let
        draft : Definition
        draft =
            model.current.draft

        terrain : Terrain
        terrain =
            Map.terrainAt (EditableMap.map draft) position

        objects : List (Svg Msg)
        objects =
            List.filter (\depot -> depot.position == position) draft.depots |> List.map depotArt

        units : List (Svg Msg)
        units =
            List.filter (\unit -> unit.position == position) draft.units |> List.map unitArt

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
                        if key == "Enter" || key == " " then
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

        objectLabels : List String
        objectLabels =
            List.filter (\unit -> unit.position == position) draft.units
                |> List.map
                    (\unit ->
                        String.toLower (PlayerNumber.toString unit.playerNumber)
                            ++ " "
                            ++ Util.UnitKind.label unit.kind
                    )

        accessibleLabel : String
        accessibleLabel =
            String.join " · " (tileLabel :: objectLabels)

        ground : Svg Msg
        ground =
            TerrainTile.toSvg { theme = draft.theme, terrain = terrain }

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


depotArt : EditableMap.DepotPlacement -> Svg Msg
depotArt depot =
    let
        path : String
        path =
            case depot.kind of
                DepotKind.Supply ->
                    "/assets/supply-depot-illustrated-v1.png"

                DepotKind.Fuel ->
                    "/assets/fuel-depot-illustrated-v4.png"
    in
    Svg.image
        [ SA.xlinkHref path
        , SA.width "16"
        , SA.height "16"
        , SA.pointerEvents "none"
        ]
        []


unitArt : EditableMap.UnitPlacement -> Svg Msg
unitArt unit =
    let
        baseRow : Int
        baseRow =
            case unit.kind of
                UnitKind.Infantry ->
                    0

                UnitKind.Tank ->
                    3

                UnitKind.Truck ->
                    6

                UnitKind.FieldGun ->
                    9

        playerRow : Int
        playerRow =
            case unit.playerNumber of
                PlayerNumber.Player1 ->
                    0

                PlayerNumber.Player2 ->
                    1

        transform : String
        transform =
            case unit.direction of
                Just Direction.East ->
                    ""

                Just Direction.West ->
                    "translate(16 0) scale(-1 1)"

                _ ->
                    case unit.playerNumber of
                        PlayerNumber.Player1 ->
                            ""

                        PlayerNumber.Player2 ->
                            "translate(16 0) scale(-1 1)"
    in
    Svg.g
        [ SA.transform transform
        , SA.pointerEvents "none"
        ]
        [ Sprite.toSvg
            { path = "/assets/units_illustrated-v4.png"
            , sheetWidth = 64
            , sheetHeight = 192
            , column = 0
            , row = baseRow + playerRow
            }
        ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.stroke of
        Resting ->
            Sub.none

        Painting _ ->
            Sub.batch
                [ Browser.Events.onMouseUp (D.succeed MouseReleased)
                , Browser.Events.onVisibilityChange (always MouseReleased)
                ]
