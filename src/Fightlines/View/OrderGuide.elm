module Fightlines.View.OrderGuide exposing
    ( dialog
    , dialogHtmlId
    )

import Game.UnitOrder as Order exposing (Order(..))
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)


dialogHtmlId : String
dialogHtmlId =
    "order-guide-dialog"


dialog : msg -> Dialog msg
dialog dismissed =
    let
        entries : List (Html msg)
        entries =
            List.map orderDescription Order.all

        close : Html msg
        close =
            Button.secondary "close" dismissed
                |> Button.toHtml

        content : List (Html msg)
        content =
            [ H.ul
                [ A.tabindex 0
                , A.attribute "aria-label" "order descriptions"
                , A.css
                    [ S.col
                    , S.p0
                    , S.indentStrong
                    , S.bgNightwood3
                    , S.textGray5
                    , S.overflowAuto
                    , S.h128
                    , S.maxHViewportInsetRem 10
                    ]
                ]
                entries
            , close
            ]
    in
    Dialog.make dialogHtmlId "orders" dismissed content
        |> Dialog.reference


orderDescription : Order -> Html msg
orderDescription order =
    H.li
        [ A.css
            [ S.row
            , S.g3
            , S.shrink0
            , S.p3
            , S.evenChildren
                [ S.bgNightwood2 ]
            ]
        ]
        [ H.img
            [ A.src ("/assets/orders-anime-v1/" ++ Order.assetName order ++ ".png")
            , A.alt ""
            , A.css
                [ S.w16
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
                , S.minW0
                ]
            ]
            [ H.h3
                [ A.css
                    [ S.textGray5 ]
                ]
                [ H.text (Order.label order) ]
            , H.p
                []
                [ H.text (description order) ]
            ]
        ]


description : Order -> String
description order =
    case order of
        Move ->
            "plan a route to another square within the unit's movement, supply, and fuel limits. trace the route with the pointer or arrow keys, then save its destination. ordinary movement stops when it encounters an enemy. trucks can move onto things to pick up cargo, such as allied units, supply crates, fuel drums, or load freight at supply or fuel depots. they can unload cargo beside their destination."

        HoldPosition ->
            "stay on the current square, paying normal supply upkeep without movement costs or combat readiness. a loaded truck ordered to hold position can also choose cargo to unload beside its current square."

        Ambush ->
            "keep a unit in place and choose the direction it watches in ambush. the highlighted firing area shows where it can intercept enemies during movement. ambush costs readiness supplies in addition to normal upkeep, and each shot spends more supplies. facing, terrain, health, and the opposing unit affect combat."

        StandGround ->
            "keep infantry, a tank, or a field gun in place with combat readiness when attacked. it gains the same defensive readiness as an ambush, but does not fire or intercept enemies. this order costs normal supply upkeep plus readiness supplies."

        AttackMove ->
            "send a unit along a route prepared to fight any enemy it encounters. choose the route first, then choose the final facing at its destination. on arrival, attack an enemy one square ahead in that direction. the red arrow shows the chosen facing. combat will interrupt the route."

        IndirectFire ->
            "a devastating attack from a remote location. keep a field gun stationary and select any tile within its indirect range, including fog. this attack hits whoever occupies that tile, including allies."

        Sabotage ->
            "infantry already standing on an intact depot or fortress spend the whole turn sabotaging it. if they survive combat, the building is destroyed. sabotage costs normal upkeep and does not damage units or freight. moving, firing, and sabotage cannot be combined."

        DigIn ->
            "infantry spend their whole turn and supplies digging into trenches. protection begins at turn end and greatly reduces damage from infantry and field guns. tanks ignore trench protection. roads, buildings, and building wreckage prevent digging."
