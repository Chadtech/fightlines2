module Game.BattlefieldNavigation exposing
    ( DragMode(..)
    , Model
    , Msg(..)
    , TouchInput(..)
    , TouchRoute(..)
    , TouchUpdate
    , active
    , camera
    , finishReturn
    , init
    , panDown
    , panLeft
    , panRight
    , panUp
    , press
    , resetViewport
    , returning
    , scroll
    , setOffset
    , setZoom
    , startReturn
    , subscriptions
    , suppressesClick
    , touch
    , touchWithRoute
    , update
    , zoomIn
    , zoomOut
    )

import Browser.Events
import Game.Camera as Camera exposing (Camera)
import Json.Decode as Decode
import Point exposing (Point)
import PointerGesture exposing (PointerGesture)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { offset : Point
    , zoom : Float
    , gesture : Gesture
    , returnMotion : ReturnMotion
    }


type Gesture
    = MouseGesture PointerGesture
    | TouchGesture TouchGesture


type ReturnMotion
    = Settled
    | Returning


type DragMode
    = PanCamera
    | TraceRoute


type Msg
    = MouseMoved Point Int
    | MouseReleased Point
    | WindowVisibilityChanged Browser.Events.Visibility


{-| Touch positions are client coordinates minus half the surface size.
Subtract the surface origin as well when mapping a contact to a board tile.
-}
type TouchInput
    = TouchStarted (List Point)
    | TouchMoved (List Point)
    | TouchEnded TouchRelease
    | TouchCancelled


type alias TouchRelease =
    { remaining : List Point
    , released : List Point
    }


type TouchGesture
    = SingleTouch DragMode PointerGesture
    | Pinching Pinch
    | AwaitingTouchRelease


type TouchRoute
    = TraceAt Point
    | ReleaseAt Point


type alias TouchUpdate =
    { navigation : Model
    , route : List TouchRoute
    }


type alias Pinch =
    { midpoint : Point
    , distance : Float
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Model
init =
    { offset = { x = 0, y = 0 }
    , zoom = 1
    , gesture = MouseGesture PointerGesture.idle
    , returnMotion = Settled
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


camera : Model -> Camera
camera model =
    { offset = model.offset, zoom = model.zoom }


startReturn : Model -> Model
startReturn model =
    model
        |> setReturnMotion Returning


finishReturn : Model -> Model
finishReturn model =
    model
        |> setReturnMotion Settled


returning : Model -> Bool
returning model =
    model.returnMotion == Returning


active : Model -> Bool
active model =
    case model.gesture of
        MouseGesture gesture ->
            PointerGesture.active gesture

        TouchGesture _ ->
            True


suppressesClick : Model -> Bool
suppressesClick model =
    case model.gesture of
        MouseGesture gesture ->
            PointerGesture.suppressesClick gesture

        TouchGesture (SingleTouch _ gesture) ->
            PointerGesture.suppressesClick gesture

        TouchGesture _ ->
            True


panLeft : Model -> Model
panLeft model =
    model
        |> setOffset
            { x = model.offset.x + 48, y = model.offset.y }


panRight : Model -> Model
panRight model =
    model
        |> setOffset
            { x = model.offset.x - 48, y = model.offset.y }


panUp : Model -> Model
panUp model =
    model
        |> setOffset
            { x = model.offset.x, y = model.offset.y + 48 }


panDown : Model -> Model
panDown model =
    model
        |> setOffset
            { x = model.offset.x, y = model.offset.y - 48 }


zoomIn : Model -> Model
zoomIn model =
    zoomAt { x = 0, y = 0 } 1.25 model


zoomOut : Model -> Model
zoomOut model =
    zoomAt { x = 0, y = 0 } 0.8 model


resetViewport : Model -> Model
resetViewport model =
    model
        |> setOffset
            { x = 0, y = 0 }
        |> setZoom 1
        |> setGesture (MouseGesture PointerGesture.idle)


press : Point -> Model -> Model
press point model =
    model
        |> setGesture (MouseGesture (PointerGesture.press { start = point, origin = model.offset }))


touch : TouchInput -> Model -> Model
touch input model =
    (touchWithRoute PanCamera input model).navigation


touchWithRoute :
    DragMode
    -> TouchInput
    -> Model
    -> TouchUpdate
touchWithRoute mode input model =
    let
        navigation : Model
        navigation =
            case input of
                TouchStarted points ->
                    case model.gesture of
                        TouchGesture AwaitingTouchRelease ->
                            model

                        _ ->
                            startTouch mode points model

                TouchMoved points ->
                    moveTouch points model

                TouchEnded touches ->
                    endTouch touches model

                TouchCancelled ->
                    model |> setGesture (MouseGesture PointerGesture.cancel)

        route : List TouchRoute
        route =
            case model.gesture of
                TouchGesture (SingleTouch TraceRoute gesture) ->
                    if suppressesClick navigation then
                        tracedContacts input gesture

                    else
                        []

                _ ->
                    []
    in
    { navigation = navigation, route = route }


tracedContacts : TouchInput -> PointerGesture -> List TouchRoute
tracedContacts input gesture =
    let
        fromStart : TouchRoute -> List TouchRoute
        fromStart contact =
            case PointerGesture.pressedAt gesture of
                Just start ->
                    [ TraceAt start, contact ]

                Nothing ->
                    [ contact ]
    in
    case input of
        TouchMoved [ point ] ->
            fromStart (TraceAt point)

        TouchEnded { remaining, released } ->
            case ( remaining, released ) of
                ( [], [ point ] ) ->
                    fromStart (ReleaseAt point)

                _ ->
                    []

        _ ->
            []


scroll : Point -> Float -> Model -> Model
scroll anchor delta model =
    zoomAt anchor (e ^ (negate (clamp -100 100 delta) * 0.002)) model



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setReturnMotion : ReturnMotion -> Model -> Model
setReturnMotion returnMotion model =
    { model | returnMotion = returnMotion }


setOffset : Point -> Model -> Model
setOffset offset model =
    { model | offset = offset }


setZoom : Float -> Model -> Model
setZoom zoom model =
    { model | zoom = zoom }


setGesture : Gesture -> Model -> Model
setGesture gesture model =
    { model | gesture = gesture }


drag : DragMode -> Point -> Model -> Model
drag dragMode point model =
    let
        move : (PointerGesture -> Gesture) -> PointerGesture -> Model
        move wrap gesture =
            let
                moved : { gesture : PointerGesture, offset : Maybe Point }
                moved =
                    PointerGesture.move point gesture

                offset : Point
                offset =
                    case dragMode of
                        PanCamera ->
                            Maybe.withDefault model.offset moved.offset

                        TraceRoute ->
                            model.offset
            in
            model
                |> setGesture (wrap moved.gesture)
                |> setOffset offset
    in
    case model.gesture of
        MouseGesture gesture ->
            move MouseGesture gesture

        TouchGesture (SingleTouch mode gesture) ->
            move (SingleTouch mode >> TouchGesture) gesture

        TouchGesture _ ->
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
    model
        |> setZoom zoom
        |> setOffset
            { x = anchor.x - (anchor.x - model.offset.x) * ratio
            , y = anchor.y - (anchor.y - model.offset.y) * ratio
            }
        |> finish


finish : Model -> Model
finish model =
    case model.gesture of
        MouseGesture gesture ->
            model |> setGesture (MouseGesture (PointerGesture.finish gesture))

        TouchGesture _ ->
            model


pinch : { first : Point, second : Point } -> Pinch
pinch points =
    { midpoint =
        { x = (points.first.x + points.second.x) / 2
        , y = (points.first.y + points.second.y) / 2
        }
    , distance = max 1 (sqrt ((points.second.x - points.first.x) ^ 2 + (points.second.y - points.first.y) ^ 2))
    }


startTouch : DragMode -> List Point -> Model -> Model
startTouch mode points model =
    case points of
        first :: second :: _ ->
            model |> setGesture (TouchGesture (Pinching (pinch { first = first, second = second })))

        [ point ] ->
            model
                |> setGesture
                    (TouchGesture (SingleTouch mode (PointerGesture.press { start = point, origin = model.offset })))

        [] ->
            model


moveTouch : List Point -> Model -> Model
moveTouch points model =
    case ( model.gesture, points ) of
        ( TouchGesture (SingleTouch mode _), [ point ] ) ->
            drag mode point model

        ( TouchGesture (Pinching previous), first :: second :: _ ) ->
            let
                current : Pinch
                current =
                    pinch { first = first, second = second }

                zoomed : Model
                zoomed =
                    zoomAt previous.midpoint (current.distance / previous.distance) model
            in
            zoomed
                |> setGesture (TouchGesture (Pinching current))
                |> setOffset
                    { x = zoomed.offset.x + current.midpoint.x - previous.midpoint.x
                    , y = zoomed.offset.y + current.midpoint.y - previous.midpoint.y
                    }

        _ ->
            model


endTouch : TouchRelease -> Model -> Model
endTouch touches model =
    case ( model.gesture, touches.remaining ) of
        ( TouchGesture (SingleTouch mode gesture), [] ) ->
            let
                moved : Model
                moved =
                    case touches.released of
                        [ point ] ->
                            model
                                |> setGesture (MouseGesture gesture)
                                |> drag mode point

                        _ ->
                            model |> setGesture (MouseGesture gesture)
            in
            finish moved

        ( TouchGesture _, [] ) ->
            model |> setGesture (MouseGesture PointerGesture.cancel)

        ( TouchGesture _, _ ) ->
            -- Wait for every finger to lift after pinching. Lifting one finger
            -- must not turn the remaining finger into a new tap or jump the map.
            model |> setGesture (TouchGesture AwaitingTouchRelease)

        ( MouseGesture _, _ ) ->
            model



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


{-| Route tracing keeps the camera fixed while retaining click suppression.
-}
update : DragMode -> Msg -> Model -> Model
update dragMode msg model =
    case msg of
        MouseMoved point buttons ->
            case model.gesture of
                MouseGesture _ ->
                    if buttons == 0 then
                        finish model

                    else
                        drag dragMode point model

                TouchGesture _ ->
                    model

        MouseReleased point ->
            case model.gesture of
                MouseGesture _ ->
                    model
                        |> drag dragMode point
                        |> finish

                TouchGesture _ ->
                    model

        WindowVisibilityChanged _ ->
            case model.gesture of
                TouchGesture _ ->
                    model |> setGesture (MouseGesture PointerGesture.cancel)

                MouseGesture _ ->
                    finish model



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.gesture of
        TouchGesture _ ->
            Browser.Events.onVisibilityChange WindowVisibilityChanged

        MouseGesture gesture ->
            if PointerGesture.active gesture then
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
