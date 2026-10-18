module View.CardHeader exposing
    ( CardHeader
    , simple
    , toHtml
    , withCaption
    )

import Css
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Style as S


type CardHeader
    = CardHeader
        { title : String
        , caption : Maybe String
        }


simple : String -> CardHeader
simple title =
    CardHeader
        { title = title
        , caption = Nothing
        }


withCaption : String -> CardHeader -> CardHeader
withCaption caption (CardHeader header) =
    CardHeader { header | caption = Just caption }


headerPadding : Css.Style
headerPadding =
    Css.property "padding" "0.25rem calc(0.75rem - 2px)"


toHtml : CardHeader -> Html msg
toHtml (CardHeader header) =
    let
        content : List (Html msg)
        content =
            case header.caption of
                Nothing ->
                    [ H.text header.title
                    ]

                Just caption ->
                    [ H.span
                        [ A.css
                            [ S.minW0
                            , S.wrapAnywhere
                            ]
                        ]
                        [ H.text header.title
                        ]
                    , H.span
                        []
                        [ H.text caption
                        ]
                    ]
    in
    H.h1
        [ A.css
            [ S.bgGray3
            , S.textGray0
            , headerPadding
            , S.wFull
            , S.when (header.caption /= Nothing)
                (S.batch
                    [ S.row
                    , S.justifySpaceBetween
                    , S.flexWrap
                    , S.g2
                    ]
                )
            ]
        ]
        content
