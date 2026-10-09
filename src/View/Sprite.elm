module View.Sprite exposing (toSvg)

import Html.Styled.Attributes as HA
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA



-- A nested SVG clips a logical 16px cell from an atlas scaled to logical dimensions.


toSvg : { path : String, sheetWidth : Int, sheetHeight : Int, column : Int, row : Int } -> Svg msg
toSvg config =
    Svg.svg
        [ SA.width "16"
        , SA.height "16"
        , SA.viewBox (String.join " " (List.map String.fromInt [ config.column * 16, config.row * 16, 16, 16 ]))
        , SA.overflow "hidden"
        , SA.pointerEvents "none"
        , HA.attribute "aria-hidden" "true"
        ]
        [ Svg.image
            [ SA.xlinkHref config.path
            , SA.width (String.fromInt config.sheetWidth)
            , SA.height (String.fromInt config.sheetHeight)
            ]
            []
        ]
