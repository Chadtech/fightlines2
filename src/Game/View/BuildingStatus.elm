module Game.View.BuildingStatus exposing (toHtml)

import Api.Enum.BuildingKind as BuildingKind
import Css
import Game.Building as Building exposing (Building)
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


toHtml : (Help -> msg) -> Layout -> Building -> Html msg
toHtml onHelp layout building =
    Lazy.lazy3 buildingView onHelp layout building


buildingView : (Help -> msg) -> Layout -> Building -> Html msg
buildingView onHelp layout building =
    let
        events : InspectionHelp.Events msg
        events =
            { onHelp = onHelp }

        heading : Html msg
        heading =
            case building.kind of
                BuildingKind.Fortress ->
                    H.div
                        [ A.css
                            [ S.row
                            , S.itemsCenter
                            , S.g2
                            ]
                        ]
                        [ H.h2
                            []
                            [ H.text (Building.label building) ]
                        , InspectionHelp.button events
                            ("about " ++ Building.label building)
                            (BuildingHelp building)
                        ]

                _ ->
                    H.details
                        []
                        [ H.summary
                            [ Aria.label ("about " ++ Building.label building)
                            , A.css summaryStyles
                            ]
                            [ H.h2
                                []
                                [ H.text (Building.label building)
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
                            [ H.text (Building.description building)
                            ]
                        ]

        illustration : Html msg
        illustration =
            case layout of
                Layout.Desktop ->
                    buildingIllustration building

                Layout.Mobile ->
                    H.text ""

        status : Html msg
        status =
            if building.kind == BuildingKind.Fortress then
                if Building.isDestroyed building then
                    H.p
                        []
                        [ H.text "destroyed · no defense bonus"
                        ]

                else
                    H.p
                        []
                        [ H.text "occupying units take 75% less damage · minimum 1 hp per hit"
                        ]

            else if Building.isDestroyed building then
                H.p
                    []
                    [ H.text "destroyed · no replenishment or freight loading"
                    ]

            else
                case ( Building.resourceKind building, building.stock ) of
                    ( Just kind, Just level ) ->
                        let
                            label : String
                            label =
                                Supply.resourceLabel kind

                            accessibleLabel : String
                            accessibleLabel =
                                Building.label building ++ " " ++ label
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
        [ heading
        , illustration
        , StockGauge.hp
            { accessibleLabel = Building.label building ++ " hp"
            , help =
                InspectionHelp.button events
                    ("about " ++ Building.label building ++ " hp")
                    BuildingHpHelp
                    |> StockGauge.DialogButton
            }
            building.hp
        , status
        ]


buildingIllustration : Building -> Html msg
buildingIllustration building =
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
            [ A.src (Building.image building)
            , A.alt (Building.label building)
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
