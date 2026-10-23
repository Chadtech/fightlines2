module View.Card exposing
    ( Card
    , panel
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
    | Panel


{-| An ordinary card surface. Its caller owns width and placement.
-}
simple : Card
simple =
    { variant = Simple
    , header = Nothing
    }


{-| A card that fills a bounded layout slot. Headered panels have a fixed header
and a scrolling body.
-}
panel : Card
panel =
    { variant = Panel
    , header = Nothing
    }


withHeader : CardHeader -> Card -> Card
withHeader header card =
    { card | header = Just header }


toHtml : Card -> List (Html msg) -> Html msg
toHtml card content =
    let
        body : List (Html msg)
        body =
            case card.header of
                Nothing ->
                    content

                Just header ->
                    [ H.div
                        [ A.css
                            [ S.when (card.variant == Panel) S.shrink0
                            , S.p2px
                            ]
                        ]
                        [ CardHeader.toHtml header
                        ]
                    , H.div
                        [ A.css
                            [ S.col
                            , S.g3
                            , S.p3
                            , S.when (card.variant == Panel)
                                (S.batch
                                    [ S.flex1
                                    , S.minH0
                                    , S.overflowAuto
                                    ]
                                )
                            ]
                        ]
                        content
                    ]
    in
    H.article
        [ A.css
            [ S.bgGray1
            , S.col
            , S.outdent
            , S.when (card.variant == Panel)
                (S.batch
                    [ S.flex1
                    , S.minH0
                    , S.minW0
                    , S.overflowHidden
                    ]
                )
            , S.when (card.header == Nothing)
                (S.batch
                    [ S.g3
                    , S.p3
                    ]
                )
            ]
        ]
        body
