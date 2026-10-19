module View.TurnControls exposing
    ( Activity(..)
    , Msg(..)
    , feedback
    , htmlId
    , navigation
    , panel
    , playerRow
    , styles
    , submit
    )

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Css
import Css.Global
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.LoadingBar as LoadingBar


type Activity
    = Planning
    | Ready
    | Locked
    | Submitting
    | Waiting
    | Playing


type Msg
    = SubmitClicked


htmlId : String
htmlId =
    "game-controls"


panel : List (Html msg) -> Html msg
panel children =
    H.section
        [ A.id htmlId
        , Aria.label "game controls"
        , A.css
            [ S.bgGray1
            , S.outdentTopRight
            , S.absolute
            , S.bottom0
            , S.left0
            , S.z1
            , S.p3
            , S.g3
            , S.shrink0
            , S.maxWFull
            , S.w256
            , S.row
            , S.flexWrap
            , S.itemsCenter
            , S.minH24
            , S.containerInlineSize
            ]
        ]
        children


submit : Activity -> String -> Html Msg
submit activity label =
    Lazy.lazy2 submitView activity label


submitView : Activity -> String -> Html Msg
submitView activity label =
    let
        button : Button.Button Msg
        button =
            case activity of
                Planning ->
                    Button.secondary label SubmitClicked

                Ready ->
                    Button.primary label SubmitClicked

                _ ->
                    Button.disabled label

        activityStyles : Css.Style
        activityStyles =
            case activity of
                Ready ->
                    readyButtonStyles

                Waiting ->
                    Css.Global.descendants
                        [ Css.Global.button
                            [ S.textYellow5
                            ]
                        ]

                _ ->
                    S.batch []
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            , S.shrink0
            , Css.Global.descendants
                [ Css.Global.button
                    [ S.minW36
                    , S.minH14
                    ]
                ]
            , activityStyles
            ]
        ]
        [ button
            |> Button.large
            |> Button.toHtml
        , LoadingBar.toHtml (activity == Waiting)
        ]


feedback : List (Html msg) -> Html msg
feedback children =
    H.div
        [ A.css
            [ S.col
            , S.g1
            , S.minW56Clamped
            , S.flex1
            , S.wrapAnywhere
            , S.indentStrong
            , S.bgNightwood3
            , S.p3
            , S.overflowAuto
            , S.selfStretch
            ]
        ]
        children


navigation : Html msg -> Html msg
navigation controls =
    H.div
        [ A.class navigationClass
        , A.css
            [ S.shrink0
            , S.minW0
            , S.maxWFull
            , Css.Global.descendants
                [ Css.Global.selector "[role=group]"
                    [ S.grid
                    , S.gridRowsRem 3 2.75
                    , S.itemsCenter
                    , S.justifyItemsCenter
                    , Css.Global.children
                        [ Css.Global.div
                            [ S.grid
                            , S.gridColumnsRem 3 2.75
                            , S.g1
                            , S.itemsCenter
                            , S.justifyItemsCenter
                            ]
                        ]
                    ]
                , Css.Global.button
                    [ S.h11
                    , S.minW11
                    , S.selfCenter
                    ]
                , Css.Global.selector "[aria-label=\"zoom map\"]"
                    [ Css.Global.children
                        [ Css.Global.button
                            [ S.wFull
                            ]
                        ]
                    ]
                ]
            ]
        ]
        [ controls ]


playerRow : { name : String, playerNumber : PlayerNumber, status : String } -> Html msg
playerRow player =
    Lazy.lazy3 playerRowView player.name player.playerNumber player.status


playerRowView : String -> PlayerNumber -> String -> Html msg
playerRowView name playerNumber status =
    H.li
        [ A.css
            [ S.grid
            , S.gridCols2
            , S.g2
            , S.itemsStart
            ]
        ]
        [ H.div
            [ A.css
                [ S.row
                , S.itemsCenter
                , S.g2
                , S.minW0
                ]
            ]
            [ playerColor playerNumber
            , H.span
                []
                [ H.text name ]
            ]
        , H.span
            []
            [ H.text status ]
        ]


playerColor : PlayerNumber -> Html msg
playerColor playerNumber =
    let
        color : Css.Style
        color =
            case playerNumber of
                PlayerNumber.Player1 ->
                    S.bgRed1

                PlayerNumber.Player2 ->
                    S.bgBlue0

        label : String
        label =
            case playerNumber of
                PlayerNumber.Player1 ->
                    "player 1: red"

                PlayerNumber.Player2 ->
                    "player 2: blue"
    in
    H.span
        [ Aria.role Aria.Image
        , Aria.label label
        , A.css
            [ color
            , S.w3
            , S.h3
            , S.shrink0
            ]
        ]
        []


navigationClass : String
navigationClass =
    "fightlines-turn-navigation"


{-| Button effects are scoped through Elm CSS; the style node only defines
keyframes and the container query unsupported by this version of elm-css.
-}
readyButtonStyles : Css.Style
readyButtonStyles =
    Css.Global.descendants
        [ Css.Global.button
            [ S.relative
            , S.overflowHidden
            , S.animation "fightlines-turn-ready 1.8s ease-in-out infinite"
            , S.focusVisible
                [ S.outlineCurrentThick
                , S.outlineOffset3
                ]
            , S.after
                [ S.contentEmpty
                , S.absolute
                , S.inset0
                , Css.property "background" "linear-gradient(110deg, transparent 35%, currentColor 50%, transparent 65%)"
                , S.opacity 0.16
                , S.transform "translateX(-150%)"
                , S.animation "fightlines-turn-shine 3.6s ease-in-out infinite"
                , S.pointerEventsNone
                ]
            , S.reducedMotion
                [ S.animationNone
                , S.after
                    [ S.animationNone
                    , S.displayNone
                    ]
                ]
            ]
        ]


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text
            ("""
            @keyframes fightlines-turn-ready {
                0%, 100% { filter: brightness(1); }
                50% { filter: brightness(1.45); }
            }
            @keyframes fightlines-turn-shine {
                0%, 35% { transform: translateX(-150%); }
                75%, 100% { transform: translateX(150%); }
            }
            ."""
                ++ navigationClass
                ++ """ section { flex-wrap: nowrap; }
            @container (max-width: 57rem) {
                ."""
                ++ navigationClass
                ++ """ { flex-basis: 100%; }
                ."""
                ++ navigationClass
                ++ """ section { flex-wrap: wrap; }
            }
            """
            )
        ]
