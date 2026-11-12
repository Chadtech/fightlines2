module View.CardHeader exposing
    ( CardHeader
    , focusOnOpen
    , simple
    , toHtml
    , withActions
    , withCaption
    , withHtmlId
    )

import Css
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Style as S


type CardHeader msg
    = CardHeader
        { title : String
        , caption : Maybe String
        , actions : List (Html msg)
        , htmlId : Maybe String
        , focusOnOpen : Bool
        }


simple : String -> CardHeader msg
simple title =
    CardHeader
        { title = title
        , caption = Nothing
        , actions = []
        , htmlId = Nothing
        , focusOnOpen = False
        }


withCaption : String -> CardHeader msg -> CardHeader msg
withCaption caption (CardHeader header) =
    CardHeader { header | caption = Just caption }


{-| Place controls beside the title, outside the heading's accessible name.
-}
withActions : List (Html msg) -> CardHeader msg -> CardHeader msg
withActions actions (CardHeader header) =
    CardHeader { header | actions = actions }


withHtmlId : String -> CardHeader msg -> CardHeader msg
withHtmlId htmlId (CardHeader header) =
    CardHeader { header | htmlId = Just htmlId }


{-| Focus the heading when its native dialog opens.
-}
focusOnOpen : CardHeader msg -> CardHeader msg
focusOnOpen (CardHeader header) =
    CardHeader { header | focusOnOpen = True }


headerPadding : Css.Style
headerPadding =
    Css.property "padding" "0.25rem calc(0.75rem - 2px)"


toHtml : CardHeader msg -> Html msg
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

        focusAttributes : List (H.Attribute msg)
        focusAttributes =
            if header.focusOnOpen then
                [ A.tabindex -1
                , A.autofocus True
                ]

            else
                []

        titleAttributes : List (H.Attribute msg)
        titleAttributes =
            [ A.css
                [ S.bgGray3
                , S.textGray0
                , headerPadding
                , S.wFull
                , S.flex1
                , S.minW0
                , S.when header.focusOnOpen [ S.outlineNone ]
                , S.when (header.caption /= Nothing)
                    [ S.row
                    , S.justifySpaceBetween
                    , S.flexWrap
                    , S.g2
                    ]
                ]
            ]
                ++ List.filterMap identity [ Maybe.map A.id header.htmlId ]
                ++ focusAttributes

        title : Html msg
        title =
            H.h1 titleAttributes content
    in
    if List.isEmpty header.actions then
        title

    else
        H.div
            [ A.css
                [ S.row
                , S.shrink0
                , S.bgGray3
                ]
            ]
            [ title
            , H.div
                [ A.css
                    [ S.row
                    , S.itemsStretch
                    , S.shrink0
                    , S.g1
                    , S.p2px
                    ]
                ]
                header.actions
            ]
