module Drag exposing (Drag, origin, start, startAt)

import Point exposing (Point)


type Drag
    = Drag { start : Point, origin : Point }


startAt : { start : Point, origin : Point } -> Drag
startAt =
    Drag


start : Drag -> Point
start (Drag drag) =
    drag.start


origin : Drag -> Point
origin (Drag drag) =
    drag.origin
