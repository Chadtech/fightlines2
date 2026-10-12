module View.TurnControls exposing
    ( Activity(..)
    , Msg(..)
    , feedback
    , navigation
    , panel
    , playerRow
    , submit
    )

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
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


panel : List (Html msg) -> Html msg
panel children =
    H.section
        [ Aria.label "game controls"
        , A.class controlsClass
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
            , Css.width (Css.rem 64)
            , S.row
            , S.flexWrap
            , Css.alignItems Css.center
            , Css.minHeight (Css.rem 6)
            , Css.property "container-type" "inline-size"
            ]
        ]
        (styles :: children)


submit : Activity -> String -> Html Msg
submit activity label =
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

        className : String
        className =
            case activity of
                Ready ->
                    String.join " " [ submitClass, readyClass ]

                Waiting ->
                    String.join " " [ submitClass, sentClass ]

                _ ->
                    submitClass
    in
    H.div
        [ A.class className
        , A.css
            [ S.col
            , S.g2
            , S.shrink0
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
        [ A.class feedbackClass
        , A.css
            [ S.col
            , S.g1
            , S.minW0
            , S.flex1
            , S.wrapAnywhere
            , S.indentStrong
            , S.bgNightwood3
            , S.p3
            , S.overflowAuto
            , Css.alignSelf Css.stretch
            ]
        ]
        children


navigation : Html msg -> Html msg
navigation controls =
    H.div
        [ A.class navigationClass
        , A.css [ S.shrink0, S.minW0, S.maxWFull ]
        ]
        [ controls ]


playerRow : { name : String, side : PlayerNumber, status : String } -> Html msg
playerRow player =
    H.li
        [ A.class playerRowClass
        , A.css
            [ S.grid
            , Css.property "grid-template-columns" "repeat(2, minmax(0, 1fr))"
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
            [ playerColor player.side
            , H.span
                []
                [ H.text player.name ]
            ]
        , H.span
            []
            [ H.text player.status ]
        ]


playerColor : PlayerNumber -> Html msg
playerColor side =
    let
        color : Css.Style
        color =
            case side of
                PlayerNumber.Player1 ->
                    S.bgRed1

                PlayerNumber.Player2 ->
                    S.bgBlue0

        label : String
        label =
            case side of
                PlayerNumber.Player1 ->
                    "player 1: red"

                PlayerNumber.Player2 ->
                    "player 2: blue"
    in
    H.span
        [ Aria.role Aria.Image
        , Aria.label label
        , A.class playerColorClass
        , A.css
            [ color
            , S.w3
            , S.h3
            , S.shrink0
            ]
        ]
        []


controlsClass : String
controlsClass =
    "fightlines-turn-controls"


submitClass : String
submitClass =
    "fightlines-turn-submit"


readyClass : String
readyClass =
    "fightlines-turn-ready"


sentClass : String
sentClass =
    "fightlines-turn-sent"


feedbackClass : String
feedbackClass =
    "fightlines-turn-feedback"


navigationClass : String
navigationClass =
    "fightlines-turn-navigation"


playerRowClass : String
playerRowClass =
    "fightlines-player-row"


playerColorClass : String
playerColorClass =
    "fightlines-player-color"


shineAnimation : String
shineAnimation =
    "fightlines-turn-shine"


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text
            ("""
            ."""
                ++ feedbackClass
                ++ """ { min-width: min(14rem, 100%); }
            ."""
                ++ submitClass
                ++ """ button { min-width: 9rem; min-height: 3.5rem; }
            ."""
                ++ navigationClass
                ++ """ section { flex-wrap: nowrap; }
            ."""
                ++ navigationClass
                ++ """ [role="group"] {
                display: grid;
                grid-template-rows: repeat(3, 2.5rem);
                align-items: center;
                justify-items: center;
            }
            ."""
                ++ navigationClass
                ++ """ button { height: 2.5rem; align-self: center; }

            ."""
                ++ readyClass
                ++ """ button {
                position: relative;
                overflow: hidden;
                animation: """
                ++ readyClass
                ++ """ 1.8s ease-in-out infinite;
            }
            ."""
                ++ readyClass
                ++ """ button::after {
                content: '';
                position: absolute;
                inset: 0;
                background: linear-gradient(110deg, transparent 35%, currentColor 50%, transparent 65%);
                opacity: .16;
                transform: translateX(-150%);
                animation: """
                ++ shineAnimation
                ++ """ 3.6s ease-in-out infinite;
                pointer-events: none;
            }
            ."""
                ++ readyClass
                ++ """ button:focus-visible { outline: 2px solid currentColor; outline-offset: 3px; }
            ."""
                ++ sentClass
                ++ """ button { color: """
                ++ S.yellow5Str
                ++ """; }
            @keyframes """
                ++ readyClass
                ++ """ {
                0%, 100% { filter: brightness(1); }
                50% { filter: brightness(1.45); }
            }
            @keyframes """
                ++ shineAnimation
                ++ """ {
                0%, 35% { transform: translateX(-150%); }
                75%, 100% { transform: translateX(150%); }
            }
            @container (max-width: 57rem) {
                ."""
                ++ navigationClass
                ++ """ { flex-basis: 100%; }
                ."""
                ++ navigationClass
                ++ """ section { flex-wrap: wrap; }
            }
            @media (prefers-reduced-motion: reduce) {
                ."""
                ++ readyClass
                ++ """ button, ."""
                ++ readyClass
                ++ """ button::after { animation: none; }
                ."""
                ++ readyClass
                ++ """ button::after { display: none; }
            }
            """
            )
        ]
