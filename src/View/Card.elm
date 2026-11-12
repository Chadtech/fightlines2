module View.Card exposing
    ( Card
    , danger
    , panel
    , simple
    , toHtml
    , withHeader
    )

import Css
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


type alias Card msg =
    { variant : Variant
    , header : Maybe (CardHeader msg)
    , tone : Tone
    }


type Tone
    = Neutral
    | Danger


type Variant
    = Simple
    | Panel


{-| An ordinary card surface. Its caller owns width and placement.
-}
simple : Card msg
simple =
    { variant = Simple
    , header = Nothing
    , tone = Neutral
    }


{-| A card that fills a bounded layout slot. Headered panels have a fixed header
and a scrolling body.
-}
panel : Card msg
panel =
    { variant = Panel
    , header = Nothing
    , tone = Neutral
    }


{-| A muted red surface with the ordinary card bevel and title bar.
-}
danger : Card msg -> Card msg
danger card =
    { card | tone = Danger }


withHeader : CardHeader msg -> Card msg -> Card msg
withHeader header card =
    { card | header = Just header }


toHtml : Card msg -> List (Html msg) -> Html msg
toHtml card content =
    let
        toneStyles : List Css.Style
        toneStyles =
            case card.tone of
                Neutral ->
                    [ S.bgGray1
                    ]

                Danger ->
                    [ S.bgRed0
                    , S.textGray5
                    ]

        body : List (Html msg)
        body =
            case card.header of
                Nothing ->
                    content

                Just header ->
                    [ H.div
                        [ A.css
                            [ S.when (card.variant == Panel) [ S.shrink0 ]
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
                                [ S.flex1
                                , S.minH0
                                , S.overflowAuto
                                ]
                            ]
                        ]
                        content
                    ]
    in
    H.article
        [ A.css
            [ S.batch toneStyles
            , S.col
            , S.outdent
            , S.when (card.variant == Panel)
                [ S.flex1
                , S.minH0
                , S.minW0
                , S.overflowHidden
                ]
            , S.when (card.header == Nothing)
                [ S.g3
                , S.p3
                ]
            ]
        ]
        body
