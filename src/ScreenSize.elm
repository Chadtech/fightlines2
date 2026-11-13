module ScreenSize exposing
    ( ScreenSize
    , decoder
    , isMobileSize
    , onResize
    )

import Browser.Events
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


isMobileSize : ScreenSize -> Bool
isMobileSize screenSize =
    let
        shortEdge : Float
        shortEdge =
            min screenSize.width screenSize.height

        longEdge : Float
        longEdge =
            max screenSize.width screenSize.height
    in
    (shortEdge <= 600) && (longEdge <= 1023)


onResize : (ScreenSize -> msg) -> Sub msg
onResize toMsg =
    let
        size : Int -> Int -> ScreenSize
        size width height =
            { width = toFloat width
            , height = toFloat height
            }
    in
    Browser.Events.onResize (\width height -> toMsg (size width height))
