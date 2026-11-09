module ScreenSize exposing
    ( ScreenSize
    , decoder
    )

import Json.Decode as Decode exposing (Decoder)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Browser viewport dimensions in CSS pixels.
-}
type alias ScreenSize =
    { width : Float
    , height : Float
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


decoder : Decoder ScreenSize
decoder =
    Decode.map2
        ScreenSize
        (Decode.field "width" Decode.float)
        (Decode.field "height" Decode.float)
