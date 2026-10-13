module View.SupplyCrate exposing (toSvg)

import Html.Attributes as A
import Svg exposing (Svg)
import Svg.Attributes as SA
import View.Aria as Aria


{-| An illustrated supply cache. Interaction belongs to its tile.
-}
toSvg : Svg msg
toSvg =
    Svg.image
        [ SA.x "2"
        , SA.y "2"
        , SA.width "12"
        , SA.height "12"
        , SA.xlinkHref "/assets/supply-crate-illustrated-v1.png"
        , A.style "image-rendering" "auto"
        , SA.pointerEvents "none"
        , Aria.svgHidden True
        ]
        []
