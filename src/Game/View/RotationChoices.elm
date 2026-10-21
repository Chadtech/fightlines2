module Game.View.RotationChoices exposing
    ( Msg(..)
    , ambushToSvg
    , attackFacing
    , attackToSvg
    )

import Api.Enum.Direction as Direction exposing (Direction)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Direction as Direction
import Game.Map as Map exposing (Map)
import Html.Attributes as A
import Json.Decode as Decode
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as Ev
import View.Aria as Aria


type Msg
    = MouseMovedOverDirection Direction
    | FocusedDirection Direction
    | ClickedDirection Direction
    | DirectionActivationKeyPressed Direction


attackToSvg : List Coordinate -> Map -> Coordinate -> Direction -> Svg Msg
attackToSvg path map origin selected =
    let
        allowed : List Direction
        allowed =
            List.filter (\direction -> not (Direction.reversesPath path direction)) Direction.all

        choice : Direction -> Svg Msg
        choice direction =
            let
                color : String
                color =
                    if direction == selected then
                        S.red1Str

                    else
                        S.yellow5Str

                activate : String -> Decode.Decoder Msg
                activate key =
                    if key == "Enter" || key == " " then
                        Decode.succeed (DirectionActivationKeyPressed direction)

                    else
                        Decode.fail "not a direction activation key"

                activateWithoutShortcut : Bool -> Decode.Decoder ( Msg, Bool )
                activateWithoutShortcut shortcutPressed =
                    if shortcutPressed then
                        Decode.fail "shortcut chords do not activate directions"

                    else
                        Decode.field "key" Decode.string
                            |> Decode.andThen activate
                            |> Decode.map (\msg -> ( msg, True ))
            in
            directionSquare origin
                direction
                [ SA.fill color
                , SA.fillOpacity "0.24"
                , SA.stroke color
                , A.attribute "data-attack-direction" (Direction.label direction)
                , A.attribute "tabindex" "0"
                , Aria.svgRole Aria.Button
                , Aria.svgLabel ("face " ++ Direction.label direction)
                , Ev.on "mousemove" (Decode.succeed (MouseMovedOverDirection direction))
                , Ev.on "focus" (Decode.succeed (FocusedDirection direction))
                , Ev.onClick (ClickedDirection direction)
                , Ev.preventDefaultOn "keydown"
                    (Decode.map2 (||)
                        (Decode.field "metaKey" Decode.bool)
                        (Decode.field "ctrlKey" Decode.bool)
                        |> Decode.andThen activateWithoutShortcut
                    )
                ]
    in
    Svg.g
        [ Aria.svgLabel "choose attack move final direction"
        , SA.cursor "crosshair"
        ]
        (ambushToSvg map origin selected :: List.map choice allowed)


attackFacing : Coordinate -> Direction -> Svg msg
attackFacing origin direction =
    directionSquare origin
        direction
        [ SA.fill S.red1Str
        , SA.fillOpacity "0.24"
        , SA.stroke S.red1Str
        , SA.pointerEvents "none"
        , Aria.svgHidden True
        ]


directionSquare : Coordinate -> Direction -> List (Svg.Attribute msg) -> Svg msg
directionSquare origin direction attributes =
    let
        position : Coordinate
        position =
            Direction.step origin direction

        geometry : List (Svg.Attribute msg)
        geometry =
            [ SA.x (String.fromInt (position.x * 16 + 1))
            , SA.y (String.fromInt (position.y * 16 + 1))
            , SA.width "14"
            , SA.height "14"
            , SA.strokeWidth "0.85"
            , SA.strokeDasharray "1 1"
            ]
    in
    Svg.rect
        (geometry ++ attributes)
        []


ambushToSvg : Map -> Coordinate -> Direction -> Svg Msg
ambushToSvg map position _ =
    let
        centerX : Float
        centerX =
            toFloat (position.x * 16 + 8)

        centerY : Float
        centerY =
            toFloat (position.y * 16 + 8)

        extent : Float
        extent =
            toFloat (max map.width map.height * 32)

        point : Float -> Float -> String
        point x y =
            String.fromFloat x ++ "," ++ String.fromFloat y

        sector : Direction -> Svg Msg
        sector direction =
            let
                corners : String
                corners =
                    case direction of
                        Direction.North ->
                            point
                                (centerX - extent)
                                (centerY - extent)
                                ++ " "
                                ++ point (centerX + extent) (centerY - extent)

                        Direction.East ->
                            point
                                (centerX + extent)
                                (centerY - extent)
                                ++ " "
                                ++ point (centerX + extent) (centerY + extent)

                        Direction.South ->
                            point
                                (centerX + extent)
                                (centerY + extent)
                                ++ " "
                                ++ point (centerX - extent) (centerY + extent)

                        Direction.West ->
                            point
                                (centerX - extent)
                                (centerY + extent)
                                ++ " "
                                ++ point (centerX - extent) (centerY - extent)
            in
            Svg.polygon
                [ SA.points (point centerX centerY ++ " " ++ corners)
                , SA.fill "transparent"
                , A.attribute "data-rotation-direction" (Direction.label direction)
                , Ev.on "mousemove" (Decode.succeed (MouseMovedOverDirection direction))
                , Ev.onClick (ClickedDirection direction)
                ]
                []

        sectors : List (Svg Msg)
        sectors =
            List.map sector Direction.all
    in
    Svg.g
        [ Aria.svgLabel "choose direction on the map"
        , SA.cursor "crosshair"
        ]
        sectors
