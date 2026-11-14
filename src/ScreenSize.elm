module ScreenSize exposing
    ( ScreenSize
    , decoder
    , mobileStyles
    , subscription
    , usesMobileLayout
    )

import Browser.Events
import Css
import Css.Media
import Json.Decode as Decode exposing (Decoder)
import OperatingSystem exposing (OperatingSystem)



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


usesMobileLayout : OperatingSystem -> ScreenSize -> Bool
usesMobileLayout operatingSystem screenSize =
    OperatingSystem.isMobile operatingSystem || isMobileSize screenSize


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
    (shortEdge <= mobileShortEdge) && (longEdge <= mobileLongEdge)


{-| Apply the same mobile sizing rule to styles without listening for resize.
-}
mobileStyles : OperatingSystem -> List Css.Style -> Css.Style
mobileStyles operatingSystem styles =
    if OperatingSystem.isMobile operatingSystem then
        Css.batch styles

    else
        Css.Media.withMedia
            [ Css.Media.all
                [ Css.Media.maxWidth (Css.px mobileShortEdge)
                , Css.Media.maxHeight (Css.px mobileLongEdge)
                ]
            , Css.Media.all
                [ Css.Media.maxWidth (Css.px mobileLongEdge)
                , Css.Media.maxHeight (Css.px mobileShortEdge)
                ]
            ]
            styles


mobileShortEdge : Float
mobileShortEdge =
    600


mobileLongEdge : Float
mobileLongEdge =
    1023


subscription : (ScreenSize -> msg) -> Sub msg
subscription toMsg =
    let
        size : Int -> Int -> ScreenSize
        size width height =
            { width = toFloat width
            , height = toFloat height
            }
    in
    Browser.Events.onResize (\width height -> toMsg (size width height))
