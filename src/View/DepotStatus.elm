module View.DepotStatus exposing (toHtml)

import Css
import Depot exposing (Depot)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Supply
import View.Aria as Aria
import View.InfoMarker as InfoMarker


toHtml : Depot -> Html msg
toHtml depot =
    let
        stock : Html msg
        stock =
            case depot.stock of
                Just level ->
                    stockGauge level

                Nothing ->
                    H.p
                        [ A.css
                            [ S.textGray4
                            ]
                        ]
                        [ H.text "stock outside sight"
                        ]
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            , S.textGray5
            ]
        ]
        [ H.details
            []
            [ H.summary
                [ Aria.label "about supply depot"
                , A.css summaryStyles
                ]
                [ H.h2
                    []
                    [ H.text "supply depot"
                    ]
                , InfoMarker.toHtml
                ]
            , H.p
                [ A.css
                    [ S.bgYellow2
                    , S.textGray5
                    , S.p3
                    , Css.marginTop (Css.rem 0.75)
                    , Css.marginLeft (Css.rem -0.75)
                    , Css.marginRight (Css.rem -0.75)
                    ]
                ]
                [ H.text "a neutral supply source for either side. replenishes units on its square or one cardinally adjacent square at the end of the turn, before upkeep."
                ]
            ]
        , H.div
            [ A.css
                [ S.bgNightwood3
                , S.indentStrong
                , S.p3
                , S.row
                , S.justifyCenter
                ]
            ]
            [ H.img
                [ A.src "/assets/supply-depot-illustrated-v1.png"
                , A.alt "illustrated concrete supply depot"
                , A.css
                    [ S.block
                    , Css.width (Css.px 128)
                    , Css.height (Css.px 128)
                    , Css.maxWidth (Css.pct 100)
                    , Css.objectFit Css.contain_
                    ]
                ]
                []
            ]
        , stock
        ]


summaryStyles : List Css.Style
summaryStyles =
    [ S.pointerCursor
    , S.listStyleNone
    , S.row
    , S.itemsCenter
    , S.g2
    , Css.pseudoElement "-webkit-details-marker"
        [ S.displayNone
        ]
    ]


stockGauge : Supply.Stock -> Html msg
stockGauge stock =
    let
        fraction : Float
        fraction =
            toFloat stock.current / toFloat stock.maximum

        fill : Css.Style
        fill =
            if fraction < 0.25 then
                S.bgRed1

            else if fraction > 0.75 then
                S.bgGreen1

            else
                S.bgYellow4

        notice : List (Html msg)
        notice =
            if fraction < 0.25 then
                let
                    label : String
                    label =
                        if stock.current == 0 then
                            "empty"

                        else
                            "low"
                in
                [ H.p
                    [ A.css
                        [ S.textGray4
                        ]
                    ]
                    [ H.text label
                    ]
                ]

            else
                []

        contents : List (Html msg)
        contents =
            [ H.details
                []
                [ H.summary
                    [ Aria.label "about depot supplies"
                    , A.css
                        [ S.batch summaryStyles
                        , S.justifySpaceBetween
                        , S.flexWrap
                        , S.g1
                        ]
                    ]
                    [ H.span
                        [ A.css
                            [ S.row
                            , S.itemsCenter
                            , S.g2
                            ]
                        ]
                        [ H.text "supplies"
                        , InfoMarker.toHtml
                        ]
                    , H.span
                        [ A.css
                            [ Css.whiteSpace Css.nowrap
                            , Css.property "font-variant-numeric" "tabular-nums"
                            ]
                        ]
                        [ H.text (String.fromInt stock.current ++ " / " ++ String.fromInt stock.maximum)
                        ]
                    ]
                , H.p
                    [ A.css
                        [ S.bgYellow2
                        , S.textGray5
                        , S.p2
                        , Css.marginTop (Css.rem 0.5)
                        ]
                    ]
                    [ H.text "finite stock, shared by both sides. delivery and loading crates draw from these supplies."
                    ]
                ]
            , H.div
                [ Aria.role Aria.Meter
                , Aria.label "depot supplies"
                , Aria.valueMin 0
                , Aria.valueMax stock.maximum
                , Aria.valueNow stock.current
                , A.css
                    [ S.bgGray0
                    , Css.height (Css.rem 0.75)
                    ]
                ]
                [ H.div
                    [ A.css
                        [ fill
                        , S.hFull
                        , Css.width (Css.pct (fraction * 100))
                        ]
                    ]
                    []
                ]
            ]
    in
    H.div
        [ A.css
            [ S.col
            , S.g1
            ]
        ]
        (contents ++ notice)
