module Camera exposing
    ( Camera
    , anchor
    , boardWidth
    , focusTransform
    , transform
    )

import Coordinate exposing (Coordinate)
import Map exposing (Map)
import Point exposing (Point)


type alias Camera =
    { offset : Point
    , zoom : Float
    }


{-| The initial whole-map overview, shared by the board and command anchors.
-}
boardWidth : String
boardWidth =
    "min(80cqw, 76cqh)"


anchor : Camera -> Point -> { x : String, y : String }
anchor camera fraction =
    let
        projected : { x : String, y : String }
        projected =
            displacement camera fraction
    in
    { x = "calc(50cqw + " ++ projected.x ++ ")"
    , y = "calc(50cqh + " ++ projected.y ++ ")"
    }


displacement : Camera -> Point -> { x : String, y : String }
displacement camera fraction =
    let
        axis : Float -> Float -> String
        axis boardFraction offset =
            "calc(" ++ boardWidth ++ " * " ++ String.fromFloat (boardFraction * camera.zoom) ++ " + " ++ String.fromFloat offset ++ "px)"
    in
    { x = axis fraction.x camera.offset.x
    , y = axis fraction.y camera.offset.y
    }


transform : Camera -> String
transform camera =
    let
        translation : { x : String, y : String }
        translation =
            displacement camera { x = 0, y = 0 }
    in
    "translate(" ++ translation.x ++ ", " ++ translation.y ++ ") scale(" ++ String.fromFloat camera.zoom ++ ")"


{-| Frame visible tiles without changing the saved camera. Container units keep
the framing correct through viewport resizing, without measuring unit elements.
-}
focusTransform : Map -> List Coordinate -> Camera -> String
focusTransform map positions camera =
    case positions of
        [] ->
            transform camera

        first :: rest ->
            let
                bounds :
                    { left : Int
                    , right : Int
                    , top : Int
                    , bottom : Int
                    }
                bounds =
                    List.foldl extend
                        { left = first.x, right = first.x, top = first.y, bottom = first.y }
                        rest

                extend :
                    Coordinate
                    -> { left : Int, right : Int, top : Int, bottom : Int }
                    -> { left : Int, right : Int, top : Int, bottom : Int }
                extend position current =
                    { left = min current.left position.x
                    , right = max current.right position.x
                    , top = min current.top position.y
                    , bottom = max current.bottom position.y
                    }

                mapWidth : Float
                mapWidth =
                    toFloat map.width

                -- Include the tiles themselves and one tile of breathing room
                -- on each side. Both SVG axes use the board's rendered width.
                span : Float
                span =
                    toFloat
                        (max
                            (bounds.right - bounds.left + 3)
                            (bounds.bottom - bounds.top + 3)
                        )

                zoom : Float
                zoom =
                    min camera.zoom (mapWidth / span)

                center : Point
                center =
                    { x =
                        (toFloat (bounds.left + bounds.right + 1) - mapWidth) / (2 * mapWidth)
                    , y =
                        (toFloat (bounds.top + bounds.bottom + 1) - toFloat map.height) / (2 * mapWidth)
                    }

                axis : Float -> String
                axis fraction =
                    "calc("
                        ++ boardWidth
                        ++ " * "
                        ++ String.fromFloat (negate fraction * zoom)
                        ++ ")"
            in
            "translate("
                ++ axis center.x
                ++ ", "
                ++ axis center.y
                ++ ") scale("
                ++ String.fromFloat zoom
                ++ ")"
