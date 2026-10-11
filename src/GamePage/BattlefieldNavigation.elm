module GamePage.BattlefieldNavigation exposing
    ( Model
    , Msg(..)
    , active
    , camera
    , init
    , panDown
    , panLeft
    , panRight
    , panUp
    , press
    , resetViewport
    , scroll
    , subscriptions
    , suppressesClick
    , update
    , zoomIn
    , zoomOut
    )

import Browser.Events
import Camera exposing (Camera)
import Json.Decode as Decode
import Point exposing (Point)
import PointerGesture exposing (PointerGesture)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { offset : Point
    , zoom : Float
    , pointerGesture : PointerGesture
    }


type Msg
    = MouseMoved Point Int
    | MouseReleased Point
    | WindowVisibilityChanged Browser.Events.Visibility



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Model
init =
    { offset = { x = 0, y = 0 }
    , zoom = 1
    , pointerGesture = PointerGesture.idle
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


camera : Model -> Camera
camera model =
    { offset = model.offset, zoom = model.zoom }


active : Model -> Bool
active model =
    PointerGesture.active model.pointerGesture


suppressesClick : Model -> Bool
suppressesClick model =
    PointerGesture.suppressesClick model.pointerGesture


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


resetViewport : Model -> Model
resetViewport model =
    { model
        | offset = { x = 0, y = 0 }
        , zoom = 1
        , pointerGesture = PointerGesture.idle
    }


press : Point -> Model -> Model
press point model =
    { model | pointerGesture = PointerGesture.press { start = point, origin = model.offset } }


scroll : Point -> Float -> Model -> Model
scroll anchor delta model =
    zoomAt anchor (e ^ (negate (clamp -100 100 delta) * 0.002)) model



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


pan : Point -> Model -> Model
pan point model =
    let
        moved : { gesture : PointerGesture, offset : Maybe Point }
        moved =
            PointerGesture.move point model.pointerGesture
    in
    { model
        | pointerGesture = moved.gesture
        , offset = Maybe.withDefault model.offset moved.offset
    }


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
        , pointerGesture = PointerGesture.finish model.pointerGesture
    }


move : Point -> Int -> Model -> Model
move point buttons model =
    if buttons == 0 then
        finish model

    else
        pan point model


release : Point -> Model -> Model
release point model =
    model
        |> pan point
        |> finish


finish : Model -> Model
finish model =
    { model | pointerGesture = PointerGesture.finish model.pointerGesture }



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> Model
update msg model =
    case msg of
        MouseMoved point buttons ->
            move point buttons model

        MouseReleased point ->
            release point model

        WindowVisibilityChanged _ ->
            finish model



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        pointerGesture : PointerGesture
        pointerGesture =
            model.pointerGesture
    in
    if PointerGesture.active pointerGesture then
        Sub.batch
            [ Browser.Events.onMouseMove
                (Decode.map2
                    MouseMoved
                    Point.decoder
                    (Decode.field "buttons" Decode.int)
                )
            , Browser.Events.onMouseUp (Decode.map MouseReleased Point.decoder)
            , Browser.Events.onVisibilityChange WindowVisibilityChanged
            ]

    else
        Sub.none
