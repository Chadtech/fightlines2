module View.BoardViewport exposing (Msg(..), toHtml)

import Browser.Events
import Css
import Drag exposing (Drag)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Point exposing (Point)
import Style as S


type Msg
    = MousePressed Point
    | MouseMoved Point Int
    | MouseReleased Point
    | WindowVisibilityChanged Browser.Events.Visibility
    | WheelScrolled Point Float
    | KeyPressed String
    | ZoomInClicked
    | ZoomOutClicked
    | ResetClicked


toHtml : (Msg -> msg) -> { a | offset : Point, zoom : Float, drag : Maybe Drag } -> Html msg -> Html msg
toHtml toMsg model board =
    H.div
        [ A.attribute "tabindex" "0"
        , A.attribute "aria-label" "battlefield navigation"
        , A.css
            [ S.fixed
            , S.top0
            , S.bottom0
            , S.left0
            , S.right0
            , S.row
            , S.itemsCenter
            , S.justifyCenter
            , S.overflowHidden
            , S.userSelectNone
            , Css.cursor
                (if model.drag == Nothing then
                    Css.grab

                 else
                    Css.grabbing
                )
            ]
        , Ev.on "mousedown" (Decode.map toMsg mousePressedDecoder)
        , Ev.preventDefaultOn "wheel"
            (Decode.map (preventDefault toMsg) wheelScrolledDecoder)
        , Ev.preventDefaultOn "keydown"
            (Decode.map (preventDefault toMsg) navigationKeyDecoder)
        ]
        [ H.div
            [ A.css
                [ Css.property "width" "min(80vw, 76vh)"
                , S.shrink0
                , Css.property "transform"
                    ("translate(" ++ String.fromFloat model.offset.x ++ "px, " ++ String.fromFloat model.offset.y ++ "px) scale(" ++ String.fromFloat model.zoom ++ ")")
                ]
            ]
            [ board ]
        ]


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
    Decode.map3 WheelEvent
        Point.decoder
        viewportSizeDecoder
        wheelDeltaDecoder
        |> Decode.map wheelScrolled


viewportSizeDecoder : Decode.Decoder Point
viewportSizeDecoder =
    Decode.map2 Point
        (Decode.at [ "view", "innerWidth" ] Decode.float)
        (Decode.at [ "view", "innerHeight" ] Decode.float)


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


wheelScrolled : WheelEvent -> Msg
wheelScrolled event =
    WheelScrolled
        { x = event.pointer.x - event.viewportSize.x / 2
        , y = event.pointer.y - event.viewportSize.y / 2
        }
        event.delta


navigationKeyDecoder : Decode.Decoder Msg
navigationKeyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen navigationKeyPressed


navigationKeyPressed : String -> Decode.Decoder Msg
navigationKeyPressed key =
    if List.member key [ "+", "=", "-", "Home", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown" ] then
        Decode.succeed (KeyPressed key)

    else
        Decode.fail "not a navigation key"


preventDefault : (Msg -> msg) -> Msg -> ( msg, Bool )
preventDefault toMsg msg =
    ( toMsg msg, True )
