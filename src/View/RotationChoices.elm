module View.RotationChoices exposing
    ( Msg(..)
    , ambushToSvg
    )

import Api.Enum.Direction as Direction exposing (Direction)
import Coordinate exposing (Coordinate)
import Direction
import Html.Attributes as A
import Json.Decode as Decode
import Map exposing (Map)
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as Ev
import View.Aria as Aria


type Msg
    = MouseMovedOverDirection Direction
    | ClickedDirection Direction


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
                            point (centerX - extent) (centerY - extent) ++ " " ++ point (centerX + extent) (centerY - extent)

                        Direction.East ->
                            point (centerX + extent) (centerY - extent) ++ " " ++ point (centerX + extent) (centerY + extent)

                        Direction.South ->
                            point (centerX + extent) (centerY + extent) ++ " " ++ point (centerX - extent) (centerY + extent)

                        Direction.West ->
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

        sectors : List (Svg Msg)
        sectors =
            List.map sector Direction.all
    in
    Svg.g
        [ Aria.svgLabel "choose direction on the map"
        , SA.cursor "crosshair"
        ]
        sectors
