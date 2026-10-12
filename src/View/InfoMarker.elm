module View.InfoMarker exposing (toHtml)

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria


toHtml : Html msg
toHtml =
    H.span
        [ Aria.hidden True
        , A.css
            [ S.shrink0
            , Css.border3 (Css.px 1) Css.solid Css.currentcolor
            , Css.width (Css.rem 1)
            , Css.textAlign Css.center
            , Css.lineHeight (Css.num 1)
            ]
        ]
        [ H.text "i"
        ]
