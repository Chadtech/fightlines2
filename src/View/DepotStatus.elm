module View.DepotStatus exposing
    ( linkToHtml
    , toHtml
    )

import Css
import Depot exposing (Depot)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import Supply
import View.Aria as Aria
import View.DepotStock as DepotStock
import View.InfoMarker as InfoMarker


linkToHtml : { clicked : msg } -> Depot -> Html msg
linkToHtml events depot =
    let
        label : String
        label =
            case depot.stock of
                Just stock ->
                    DepotStock.label depot stock

                Nothing ->
                    Depot.label depot ++ " · stock outside sight"
    in
    H.button
        [ A.type_ "button"
        , Ev.onClick events.clicked
        , A.css
            [ S.textGray5
            , S.bgNightwood3
            , S.p2
            , S.pointerCursor
            , S.textLeft
            , S.border0
            , S.hover [ S.bgYellow2 ]
            , S.focusVisible
                [ S.outlineYellow5Thick ]
            ]
        ]
        [ H.text label ]


toHtml : Depot -> Html msg
toHtml depot =
    let
        stock : Html msg
        stock =
            case depot.stock of
                Just level ->
                    stockGauge depot level

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
                [ Aria.label ("about " ++ Depot.label depot)
                , A.css summaryStyles
                ]
                [ H.h2
                    []
                    [ H.text (Depot.label depot)
                    ]
                , InfoMarker.toHtml
                ]
            , H.p
                [ A.css
                    [ S.bgYellow2
                    , S.textGray5
                    , S.p3
                    , S.mt3
                    , S.mlNeg3
                    , S.mrNeg3
                    ]
                ]
                [ H.text (Depot.description depot)
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
                [ A.src (Depot.image depot)
                , A.alt (Depot.label depot)
                , A.css
                    [ S.block
                    , S.w128px
                    , S.h128px
                    , S.maxWFull
                    , S.objectContain
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
    , S.hideDetailsMarker
    ]


stockGauge : Depot -> Supply.Stock -> Html msg
stockGauge depot stock =
    let
        fraction : Float
        fraction =
            toFloat stock.current / toFloat stock.maximum

        fill : Css.Style
        fill =
            if fraction <= 0.25 then
                S.bgRed1

            else if fraction > 0.75 then
                S.bgGreen1

            else
                S.bgYellow4

        notice : List (Html msg)
        notice =
            if fraction <= 0.25 then
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
                    [ Aria.label ("about depot " ++ Depot.resourceLabel depot)
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
                        [ H.text (Depot.resourceLabel depot)
                        , InfoMarker.toHtml
                        ]
                    , H.span
                        [ A.css
                            [ S.noWrap
                            , S.tabularNums
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
                        , S.mt2
                        ]
                    ]
                    [ H.text (Depot.stockDescription depot)
                    ]
                ]
            , H.div
                [ Aria.role Aria.Meter
                , Aria.label ("depot " ++ Depot.resourceLabel depot)
                , Aria.valueMin 0
                , Aria.valueMax stock.maximum
                , Aria.valueNow stock.current
                , A.css
                    [ S.bgGray0
                    , S.h3
                    ]
                ]
                [ H.div
                    [ A.css
                        [ fill
                        , S.hFull
                        , S.widthPct (fraction * 100)
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
