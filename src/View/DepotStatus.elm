module View.DepotStatus exposing (toHtml)

import Css
import Depot exposing (Depot)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import View.Aria as Aria
import View.InfoMarker as InfoMarker
import View.StockGauge as StockGauge


toHtml : Depot -> Html msg
toHtml depot =
    Lazy.lazy depotView depot


depotView : Depot -> Html msg
depotView depot =
    let
        stock : Html msg
        stock =
            case depot.stock of
                Just level ->
                    StockGauge.toHtml
                        { label = Depot.resourceLabel depot
                        , accessibleLabel = "depot " ++ Depot.resourceLabel depot
                        , description = Depot.stockDescription depot
                        }
                        level

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
