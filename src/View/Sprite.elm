module View.Sprite exposing (toSvg)

import Html.Styled.Lazy as Lazy
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria



-- A nested SVG clips a logical 16px cell from an atlas scaled to logical dimensions.


toSvg :
    { path : String
    , sheetWidth : Int
    , sheetHeight : Int
    , column : Int
    , row : Int
    }
    -> Svg msg
toSvg config =
    Lazy.lazy5
        spriteView
        config.path
        config.sheetWidth
        config.sheetHeight
        config.column
        config.row


spriteView : String -> Int -> Int -> Int -> Int -> Svg msg
spriteView path sheetWidth sheetHeight column row =
    Svg.svg
        [ SA.width "16"
        , SA.height "16"
        , SA.viewBox
            (String.join " "
                (List.map
                    String.fromInt
                    [ column * 16
                    , row * 16
                    , 16
                    , 16
                    ]
                )
            )
        , SA.overflow "hidden"
        , SA.pointerEvents "none"
        , Aria.hidden True
        ]
        [ Svg.image
            [ SA.xlinkHref path
            , SA.width (String.fromInt sheetWidth)
            , SA.height (String.fromInt sheetHeight)
            ]
            []
        ]
