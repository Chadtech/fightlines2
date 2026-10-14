module View.SupplyCrate exposing (toSvg)

import Api.Enum.DepotKind exposing (DepotKind)
import Html.Attributes as A
import Supply
import Svg exposing (Svg)
import Svg.Attributes as SA
import View.Aria as Aria


{-| Illustrated neutral freight. Interaction belongs to its tile.
-}
toSvg : DepotKind -> Svg msg
toSvg kind =
    Svg.image
        [ SA.x "2"
        , SA.y "2"
        , SA.width "12"
        , SA.height "12"
        , SA.xlinkHref (Supply.cargoImage kind)
        , A.style "image-rendering" "auto"
        , SA.pointerEvents "none"
        , Aria.svgHidden True
        ]
        []
