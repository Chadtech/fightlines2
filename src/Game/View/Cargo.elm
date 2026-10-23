module Game.View.Cargo exposing
    ( pickupPreview
    , toHtml
    )

import Css
import Css.Global
import Game.PlannedOrder as PlannedOrder
import Game.Supply as Supply
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.View.CargoPassenger as CargoPassenger
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Util.List as ListUtil
import View.Aria as Aria
import View.InfoMarker as InfoMarker


{-| Show the available ground load using the same inset freight row as carried cargo.
-}
pickupPreview : Supply.CargoStock -> Html msg
pickupPreview stock =
    H.ul
        [ Aria.label "freight available for pickup"
        , A.css
            [ S.bgNightwood3
            , S.indentStrong
            , S.listStyleNone
            , Css.margin Css.zero
            , Css.padding Css.zero
            ]
        ]
        [ freightToHtml
            { number = 1
            , unload = Nothing
            }
            stock
        ]


toHtml :
    { capacity : Int
    , passengers : List Unit
    , freight : List Supply.CargoStock
    , unloads : List PlannedOrder.CrateUnload
    , onSelectPassenger : UnitId -> msg
    }
    -> Html msg
toHtml config =
    let
        passengerRow : Unit -> Html msg
        passengerRow passenger =
            H.li
                [ A.css
                    [ S.p2
                    ]
                ]
                [ CargoPassenger.toHtml
                    { onSelect = config.onSelectPassenger passenger.id }
                    passenger
                ]

        freightRow : Int -> Supply.CargoStock -> Html msg
        freightRow index stock =
            freightToHtml
                { number = index + 1
                , unload =
                    ListUtil.find (\unload -> unload.cargoIndex == index) config.unloads
                }
                stock

        rows : List (Html msg)
        rows =
            List.map passengerRow config.passengers
                ++ List.indexedMap freightRow config.freight

        contents : Html msg
        contents =
            if List.isEmpty rows then
                H.p
                    [ A.css
                        [ S.p3
                        ]
                    ]
                    [ H.text "empty" ]

            else
                H.ul
                    [ Aria.label "carried cargo"
                    , A.css
                        [ S.listStyleNone
                        , Css.margin Css.zero
                        , Css.padding Css.zero
                        , Css.Global.children
                            [ Css.Global.selector "li + li"
                                [ S.borderT
                                , Css.borderColor (Css.hex S.nightwood2Str)
                                ]
                            ]
                        ]
                    ]
                    rows

        occupiedSlots : Int
        occupiedSlots =
            List.length config.passengers + List.length config.freight
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        [ H.details
            []
            [ H.summary
                [ Aria.label "about cargo replenishment"
                , A.css
                    [ S.row
                    , S.itemsCenter
                    , S.justifySpaceBetween
                    , S.flexWrap
                    , S.g2
                    , S.pointerCursor
                    , S.listStyleNone
                    , S.hideDetailsMarker
                    ]
                ]
                [ H.span
                    [ A.css
                        [ S.row
                        , S.itemsCenter
                        , S.g2
                        , S.textGray5
                        ]
                    ]
                    [ H.text "cargo"
                    , InfoMarker.toHtml
                    ]
                , H.span
                    [ A.css
                        [ S.noWrap
                        , S.tabularNums
                        ]
                    ]
                    [ H.text (String.fromInt occupiedSlots ++ " / " ++ String.fromInt config.capacity ++ " slots") ]
                ]
            , H.p
                [ A.css
                    [ S.bgYellow2
                    , S.textGray5
                    , S.p2
                    , S.mt2
                    ]
                ]
                [ H.text "supplies refill provisions; fuel drums refill vehicles before upkeep, while stock lasts" ]
            ]
        , H.div
            [ A.css
                [ S.bgNightwood3
                , S.indentStrong
                ]
            ]
            [ contents ]
        ]


freightToHtml :
    { number : Int
    , unload : Maybe PlannedOrder.CrateUnload
    }
    -> Supply.CargoStock
    -> Html msg
freightToHtml config stock =
    let
        name : String
        name =
            Supply.cargoLabel stock.kind ++ " " ++ String.fromInt config.number

        fraction : Float
        fraction =
            if stock.maximum > 0 then
                clamp 0 1 (toFloat stock.current / toFloat stock.maximum)

            else
                0

        unloadDetails : List (Html msg)
        unloadDetails =
            case config.unload of
                Just unload ->
                    [ H.p
                        []
                        [ H.text
                            ("unload at ("
                                ++ String.fromInt unload.destination.x
                                ++ ", "
                                ++ String.fromInt unload.destination.y
                                ++ ")"
                            )
                        ]
                    ]

                Nothing ->
                    []

        details : List (Html msg)
        details =
            [ H.p
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text name ]
            , H.p
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.g2
                    ]
                ]
                [ H.span
                    [ A.css
                        [ S.textGray5
                        , S.tabularNums
                        , S.noWrap
                        ]
                    ]
                    [ H.text (String.fromInt stock.current ++ " / " ++ String.fromInt stock.maximum) ]
                , H.span
                    []
                    [ H.text (Supply.resourceLabel stock.kind) ]
                ]
            , H.div
                [ Aria.role Aria.Meter
                , Aria.label (name ++ " " ++ Supply.resourceLabel stock.kind)
                , Aria.valueMin 0
                , Aria.valueMax stock.maximum
                , Aria.valueNow stock.current
                , A.css
                    [ S.bgNightwood0
                    , S.h1
                    ]
                ]
                [ H.div
                    [ A.css
                        [ S.bgYellow4
                        , S.hFull
                        , S.widthPct (fraction * 100)
                        ]
                    ]
                    []
                ]
            ]
                ++ unloadDetails
    in
    H.li
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.flexWrap
            , S.g3
            , S.p3
            ]
        ]
        [ H.img
            [ A.src (Supply.cargoImage stock.kind)
            , A.alt ""
            , A.css
                [ S.block
                , S.w16
                , S.h16
                , S.shrink0
                , S.objectContain
                ]
            ]
            []
        , H.div
            [ A.css
                [ S.col
                , S.g1
                , S.flex1
                , S.minW0
                , Css.flexBasis (Css.rem 7)
                ]
            ]
            details
        ]
