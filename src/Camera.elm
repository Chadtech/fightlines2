module Camera exposing (Camera)

import Point exposing (Point)


type alias Camera =
    { offset : Point
    , zoom : Float
    }
