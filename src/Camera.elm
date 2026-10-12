module Camera exposing
    ( Camera
    , anchor
    , boardWidth
    , transform
    )

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
