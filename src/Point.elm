module Point exposing (Point, decoder)

import Json.Decode as Decode


type alias Point =
    { x : Float
    , y : Float
    }


decoder : Decode.Decoder Point
decoder =
    Decode.map2 Point
        (Decode.field "clientX" Decode.float)
        (Decode.field "clientY" Decode.float)
