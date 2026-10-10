module View.RotationChoices exposing
    ( Msg(..)
    , toSvg
    )

import Api.Enum.Direction as Facing exposing (Direction)
import Coordinate exposing (Coordinate)
import Direction
import Html.Attributes as A
import Json.Decode as Decode
import Map exposing (Map)
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as Ev


type Msg
    = MouseMovedOverDirection Direction
    | ClickedDirection Direction


toSvg : Map -> Coordinate -> Direction -> Svg Msg
toSvg map position preview =
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
                        Facing.North ->
                            point (centerX - extent) (centerY - extent) ++ " " ++ point (centerX + extent) (centerY - extent)

                        Facing.East ->
                            point (centerX + extent) (centerY - extent) ++ " " ++ point (centerX + extent) (centerY + extent)

                        Facing.South ->
                            point (centerX + extent) (centerY + extent) ++ " " ++ point (centerX - extent) (centerY + extent)

                        Facing.West ->
                            point (centerX - extent) (centerY + extent) ++ " " ++ point (centerX - extent) (centerY - extent)
            in
            Svg.polygon
                [ SA.points (point centerX centerY ++ " " ++ corners)
                , SA.fill "transparent"
                , A.attribute "data-rotation-direction" (Direction.label direction)
                , Ev.on "mousemove" (Decode.succeed (MouseMovedOverDirection direction))
                , Ev.onClick (ClickedDirection direction)
                ]
                []

        label : Direction -> Svg Msg
        label direction =
            let
                offset : { x : Float, y : Float }
                offset =
                    case direction of
                        Facing.North ->
                            { x = 0
                            , y = -24
                            }

                        Facing.East ->
                            { x = 28
                            , y = 0
                            }

                        Facing.South ->
                            { x = 0
                            , y = 24
                            }

                        Facing.West ->
                            { x = -28
                            , y = 0
                            }

                color : String
                color =
                    if direction == preview then
                        S.yellow5Str

                    else
                        S.gray5Str
            in
            Svg.text_
                [ SA.x (String.fromFloat (clamp 16 (toFloat (map.width * 16 - 16)) (centerX + offset.x)))
                , SA.y (String.fromFloat (clamp 8 (toFloat (map.height * 16 - 8)) (centerY + offset.y)))
                , SA.textAnchor "middle"
                , SA.dominantBaseline "central"
                , SA.fontSize "6"
                , SA.fill color
                , SA.stroke S.gray0Str
                , SA.strokeWidth "1.5"
                , SA.strokeLinejoin "round"
                , SA.style "font-size: 8px; paint-order: stroke fill"
                , SA.pointerEvents "none"
                ]
                [ Svg.text (Direction.label direction)
                ]

        sectors : List (Svg Msg)
        sectors =
            List.map sector Direction.all

        labels : List (Svg Msg)
        labels =
            List.map label Direction.all

        content : List (Svg Msg)
        content =
            sectors ++ labels
    in
    Svg.g
        [ A.attribute "aria-label" "choose rotation on the map"
        , SA.cursor "crosshair"
        ]
        content
