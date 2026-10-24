module Game.View.StockGauge exposing (hp, toHtml)

import Css
import Game.Depot as Depot
import Game.Supply as Supply
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.InfoMarker as InfoMarker


type GaugeKind
    = ResourceStock
    | DepotHp


type alias Description =
    { label : String
    , accessibleLabel : String
    , description : String
    }


summaryStyles : List Css.Style
summaryStyles =
    [ S.pointerCursor
    , S.listStyleNone
    , S.row
    , S.itemsCenter
    , S.g2
    , S.hideDetailsMarker
    ]


toHtml : Description -> Supply.Stock -> Html msg
toHtml =
    gauge ResourceStock


hp : { accessibleLabel : String, description : String } -> Depot.Hp -> Html msg
hp config =
    gauge DepotHp
        { label = "hp"
        , accessibleLabel = config.accessibleLabel
        , description = config.description
        }


gauge : GaugeKind -> Description -> { current : Int, maximum : Int } -> Html msg
gauge kind config stock =
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
            if (kind == ResourceStock) && (fraction <= 0.25) then
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
                    [ Aria.label ("about " ++ config.accessibleLabel)
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
                        [ H.text config.label
                        , InfoMarker.toHtml
                        ]
                    , H.span
                        [ A.css
                            [ S.noWrap
                            , S.tabularNums
                            ]
                        ]
                        [ H.text
                            (String.fromInt stock.current
                                ++ " / "
                                ++ String.fromInt stock.maximum
                            )
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
                    [ H.text config.description
                    ]
                ]
            , H.div
                [ Aria.role Aria.Meter
                , Aria.label config.accessibleLabel
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
