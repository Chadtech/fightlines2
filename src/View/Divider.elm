module View.Divider exposing (toHtml)

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S


toHtml : Html msg
toHtml =
    H.hr
        [ A.css
            [ S.border0
            , S.borderT
            , S.borderGray2
            , S.wFull
            ]
        ]
        []
