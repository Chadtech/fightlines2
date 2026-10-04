module View.CardHeader exposing
    ( CardHeader
    , simple
    , toHtml
    )

import Css
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Style as S


type CardHeader
    = CardHeader String


simple : String -> CardHeader
simple title =
    CardHeader title


headerPadding : Css.Style
headerPadding =
    Css.property "padding" "0.25rem calc(0.75rem - 2px)"


toHtml : CardHeader -> Html msg
toHtml (CardHeader title) =
    H.h1
        [ A.css
            [ S.bgGray3
            , S.textGray0
            , headerPadding
            , S.wFull
            ]
        ]
        [ H.text title
        ]
