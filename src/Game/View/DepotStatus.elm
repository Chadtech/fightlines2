module Game.View.DepotStatus exposing (toHtml)

import Api.Enum.BuildingKind as BuildingKind
import Css
import Game.Depot as Depot exposing (Depot)
import Game.Supply as Supply
import Game.View.InspectionHelp as InspectionHelp exposing (Help(..))
import Game.View.StockGauge as StockGauge
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import View.Aria as Aria
import View.InfoMarker as InfoMarker
import View.Layout as Layout exposing (Layout)


toHtml : (Help -> msg) -> Layout -> Depot -> Html msg
toHtml onHelp layout depot =
    Lazy.lazy3 depotView onHelp layout depot


depotView : (Help -> msg) -> Layout -> Depot -> Html msg
depotView onHelp layout depot =
    let
        events : InspectionHelp.Events msg
        events =
            { onHelp = onHelp }

        illustration : Html msg
        illustration =
            case layout of
                Layout.Desktop ->
                    depotIllustration depot

                Layout.Mobile ->
                    H.text ""

        status : Html msg
        status =
            if depot.kind == BuildingKind.Fortress then
                if Depot.isDestroyed depot then
                    H.p
                        []
                        [ H.text "destroyed · no defense bonus"
                        ]

                else
                    H.p
                        []
                        [ H.text "occupying units take 75% less damage · minimum 1 hp per hit"
                        ]

            else if Depot.isDestroyed depot then
                H.p
                    []
                    [ H.text "destroyed · no replenishment or freight loading"
                    ]

            else
                case ( Depot.resourceKind depot, depot.stock ) of
                    ( Just kind, Just level ) ->
                        let
                            label : String
                            label =
                                Supply.resourceLabel kind

                            accessibleLabel : String
                            accessibleLabel =
                                Depot.label depot ++ " " ++ label
                        in
                        StockGauge.toHtml
                            { label = label
                            , accessibleLabel = accessibleLabel
                            , help =
                                InspectionHelp.button events
                                    ("about " ++ accessibleLabel)
                                    (DepotStockHelp kind)
                                    |> StockGauge.DialogButton
                            }
                            level

                    _ ->
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
        , illustration
        , StockGauge.hp
            { accessibleLabel = Depot.label depot ++ " hp"
            , help =
                InspectionHelp.button events
                    ("about " ++ Depot.label depot ++ " hp")
                    BuildingHpHelp
                    |> StockGauge.DialogButton
            }
            depot.hp
        , status
        ]


depotIllustration : Depot -> Html msg
depotIllustration depot =
    H.div
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


summaryStyles : List Css.Style
summaryStyles =
    [ S.pointerCursor
    , S.listStyleNone
    , S.row
    , S.itemsCenter
    , S.g2
    , S.hideDetailsMarker
    ]
