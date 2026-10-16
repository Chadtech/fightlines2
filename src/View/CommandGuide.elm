module View.CommandGuide exposing
    ( dialog
    , dialogHtmlId
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import UnitCommand as Command exposing (Command(..))
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)


dialogHtmlId : String
dialogHtmlId =
    "command-guide-dialog"


dialog : msg -> Dialog msg
dialog dismissed =
    let
        entries : List (Html msg)
        entries =
            List.map commandDescription Command.all

        close : Html msg
        close =
            Button.secondary "close" dismissed
                |> Button.toHtml

        content : List (Html msg)
        content =
            [ H.ul
                [ A.tabindex 0
                , A.attribute "aria-label" "command descriptions"
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
    Dialog.make dialogHtmlId "commands" dismissed content
        |> Dialog.reference


commandDescription : Command -> Html msg
commandDescription command =
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
            [ A.src ("/assets/commands-anime-v1/" ++ Command.assetName command ++ ".png")
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
                [ H.text (Command.label command) ]
            , H.p
                []
                [ H.text (description command) ]
            ]
        ]


description : Command -> String
description command =
    case command of
        Move ->
            "plan a route to another square within the unit's movement, supply, and fuel limits. trace the route with the pointer or arrow keys, then save its destination. ordinary movement stops when it encounters an enemy. trucks can pick up compatible allied units, supply crates, or fuel drums, load freight at supply or fuel depots, and unload cargo beside their destination."

        HoldPosition ->
            "stay on the current square and keep the current facing, paying normal supply upkeep without movement costs or combat readiness. a loaded truck can also choose cargo to unload beside its current square."

        Ambush ->
            "keep infantry, a tank, or a field gun in place and choose the direction it watches. the highlighted firing area shows where it can intercept enemies during movement. ambush costs readiness supplies in addition to normal upkeep, and each shot spends more supplies. facing, terrain, health, and the opposing unit affect combat."

        StandGround ->
            "keep infantry, a tank, or a field gun in place with combat readiness when attacked. choose its facing on the map or with an arrow key / wasd. it gains the same defensive readiness as an ambush, but does not fire or intercept enemies. this order costs normal supply upkeep plus readiness supplies."

        AttackMove ->
            "send infantry or a tank along a route prepared to fight enemies it encounters. choose the route first, then choose the final facing at its destination. on arrival, attack an enemy one square ahead in that direction. the red arrow shows the chosen facing, and enemy squares can be destinations. combat can interrupt the route. movement, readiness, firing, and normal upkeep spend supplies, and tanks also spend fuel. attack move does not load or unload cargo."

        IndirectFire ->
            "keep a field gun stationary and select any tile within its indirect range, including fog. one shell lands after movement and unloading, hitting whoever occupies that tile, including allies. terrain does not block the shot. empty tiles waste ammunition; unseen hits stay unconfirmed. readiness, firing, and normal upkeep spend supplies."

        DigIn ->
            "not implemented yet. this infantry and field-gun command is intended for preparing a defensive position. it is currently disabled; trench protection is not available."
