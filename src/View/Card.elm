module View.Card exposing
    ( Card
    , compactForm
    , simple
    , toHtml
    , withHeader
    )

import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Style as S
import View.CardHeader as CardHeader
    exposing
        ( CardHeader
        )


type alias Card =
    { variant : Variant
    , header : Maybe CardHeader
    }


type Variant
    = Simple
    | CompactForm


simple : Card
simple =
    { variant = Simple
    , header = Nothing
    }


compactForm : Card
compactForm =
    { variant = CompactForm
    , header = Nothing
    }


withHeader : CardHeader -> Card -> Card
withHeader header card =
    { card | header = Just header }


toHtml : Card -> List (Html msg) -> Html msg
toHtml card content =
    H.article
        [ A.css
            [ S.bgGray1
            , S.col
            , S.outdent
            , S.when (card.header == Nothing)
                (S.batch
                    [ S.g3
                    , S.p3
                    ]
                )
            , S.when (card.variant == CompactForm)
                (S.batch
                    [ S.wFull
                    , S.maxW96
                    ]
                )
            ]
        ]
        (case card.header of
            Nothing ->
                content

            Just header ->
                [ H.div
                    [ A.css
                        [ S.p2px
                        ]
                    ]
                    [ CardHeader.toHtml header
                    ]
                , H.div
                    [ A.css
                        [ S.col
                        , S.g3
                        , S.p3
                        ]
                    ]
                    content
                ]
        )
