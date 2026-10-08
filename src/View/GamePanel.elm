module View.GamePanel exposing (toHtml)

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S


toHtml : Html msg -> Html msg -> Html msg
toHtml selection controls =
    H.aside
        [ A.attribute "aria-label" "game panel"
        , A.css
            [ S.bgGray1
            , S.outdentLeft
            , S.col
            , S.justifySpaceBetween
            , S.g3
            , S.p3
            , S.shrink0
            , S.hFull
            , S.overflowAuto
            , S.wrapAnywhere
            , Css.property "width" "min(18rem, 45vw)"
            ]
        ]
        [ selection
        , controls
        ]
