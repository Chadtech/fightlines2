module View.Card exposing
    ( Card
    , compactForm
    , simple
    , toHtml
    )

import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Style as S


type Card
    = Simple
    | CompactForm


simple : Card
simple =
    Simple


compactForm : Card
compactForm =
    CompactForm


toHtml : Card -> List (Html msg) -> Html msg
toHtml card content =
    H.article
        [ A.css
            [ S.bgGray1
            , S.col
            , S.g3
            , S.outdent
            , S.p3
            , S.when (card == CompactForm)
                (S.batch
                    [ S.wFull
                    , S.maxW96
                    ]
                )
            ]
        ]
        content
