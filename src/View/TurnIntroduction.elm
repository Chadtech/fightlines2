module View.TurnIntroduction exposing
    ( Msg(..)
    , dialog
    , dialogHtmlId
    , styles
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Turn
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)


type Msg
    = BeginClicked
    | SkipDialogsChanged Bool


dialogHtmlId : String
dialogHtmlId =
    "turn-introduction"


type alias DialogConfig =
    { turnNumber : Int
    , skipDialogs : Bool
    , previousTurn : Maybe Turn.Resolution
    }


dialog : DialogConfig -> Dialog Msg
dialog config =
    Dialog.make dialogHtmlId
        ("turn " ++ String.fromInt config.turnNumber)
        BeginClicked
        [ H.div
            [ A.class (emblemClass config.previousTurn)
            , A.css [ S.bgNightwood3, S.indentStrong ]
            ]
            [ H.div
                [ A.class "fightlines-turn-kicker" ]
                [ H.text "a new turn begins" ]
            , H.div
                [ A.class "fightlines-turn-number"
                , Aria.hidden True
                ]
                [ H.text (String.padLeft 2 '0' (String.fromInt config.turnNumber)) ]
            , reportView config.previousTurn
            ]
        , H.form
            [ A.attribute "method" "dialog"
            , A.css [ S.row, S.flexWrap, S.itemsCenter, S.g3 ]
            ]
            [ Button.primary "begin turn" BeginClicked
                |> Button.large
                |> Button.toHtml
            , Checkbox.toHtml
                { label = "skip this dialog"
                , checked = config.skipDialogs
                , onCheck = SkipDialogsChanged
                }
                [ H.text "skip this dialog" ]
            ]
        ]
        |> Dialog.announcement


emblemClass : Maybe Turn.Resolution -> String
emblemClass previousTurn =
    case Maybe.andThen .report previousTurn of
        Just _ ->
            "fightlines-turn-emblem fightlines-turn-with-report"

        Nothing ->
            "fightlines-turn-emblem"


reportView : Maybe Turn.Resolution -> Html msg
reportView previousTurn =
    case previousTurn of
        Just resolution ->
            case resolution.report of
                Just report ->
                    H.section
                        [ A.class "fightlines-turn-report"
                        , Aria.label "previous turn report"
                        ]
                        [ H.div
                            [ A.class "fightlines-turn-report-title" ]
                            [ H.text ("turn " ++ String.fromInt resolution.number ++ " report") ]
                        , H.dl
                            [ A.class "fightlines-turn-report-grid" ]
                            [ reportMetric "your units lost" (String.fromInt report.unitsLost)
                            , reportMetric "confirmed enemy losses" (String.fromInt report.enemyUnitsDestroyed)
                            , reportMetric "known damage inflicted" (String.fromInt report.damageInflicted ++ " hp")
                            , reportMetric "your supplies consumed" (String.fromInt report.suppliesConsumed)
                            ]
                        ]

                Nothing ->
                    battlefieldCaption

        Nothing ->
            battlefieldCaption


battlefieldCaption : Html msg
battlefieldCaption =
    H.div
        [ A.class "fightlines-turn-caption" ]
        [ H.text "the battlefield awaits" ]


reportMetric : String -> String -> Html msg
reportMetric label value =
    H.div
        [ A.class "fightlines-turn-report-metric" ]
        [ H.dt
            []
            [ H.text label ]
        , H.dd
            []
            [ H.text value ]
        ]


styles : Html msg
styles =
    let
        css : String
        css =
            """
            @keyframes fightlines-turn-pop {
                0% { transform: translateY(24px) scale(.72); opacity: 0; }
                72% { transform: translateY(-3px) scale(1.025); opacity: 1; }
                100% { transform: translateY(0) scale(1); opacity: 1; }
            }
            @keyframes fightlines-turn-introduction-shine {
                0%, 12% { transform: translateX(-240%) skewX(-22deg); opacity: 0; }
                20% { opacity: .7; }
                65% { opacity: .7; }
                80%, 100% { transform: translateX(600%) skewX(-22deg); opacity: 0; }
            }
            #turn-introduction[open] {
                animation: fightlines-turn-pop 320ms cubic-bezier(.2,.8,.2,1) both;
                box-shadow: 0 24px 90px SHADOW, 0 0 48px GOLDGLOW;
            }
            .fightlines-turn-emblem {
                position: relative; isolation: isolate; overflow: hidden;
                display: flex; flex-direction: column; align-items: center;
                justify-content: center; gap: 1rem; min-height: 19rem; padding: 2rem 1rem;
                color: GOLD;
            }
            .fightlines-turn-emblem::after {
                content: ''; position: absolute; top: -30%; left: 0;
                width: 30%; height: 160%; pointer-events: none;
                background: linear-gradient(90deg, transparent, SHINE, transparent);
                mix-blend-mode: screen;
                animation: fightlines-turn-introduction-shine 4.8s ease-in-out .2s infinite;
            }
            .fightlines-turn-kicker { letter-spacing: .16em; text-align: center; }
            .fightlines-turn-number {
                font-size: clamp(5rem, 18vw, 9rem); line-height: 1;
                letter-spacing: -.06em; padding-right: .06em;
                text-shadow: 0 2px 0 GOLDGLOW, 0 0 32px GOLDGLOW;
            }
            .fightlines-turn-caption { color: MUTED; text-align: center; }
            .fightlines-turn-with-report { gap: .75rem; padding: 1.5rem 1rem; }
            .fightlines-turn-with-report .fightlines-turn-number { font-size: clamp(4rem, 14vw, 6rem); }
            .fightlines-turn-report { width: 100%; max-width: 30rem; }
            .fightlines-turn-report-title { color: MUTED; text-align: center; margin-bottom: .75rem; }
            .fightlines-turn-report-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .75rem; margin: 0; }
            .fightlines-turn-report-metric { padding: .5rem; background: SHADOW; border: 1px solid GOLDGLOW; }
            .fightlines-turn-report-metric dt { color: MUTED; margin-bottom: .35rem; }
            .fightlines-turn-report-metric dd { margin: 0; color: GOLD; }
            @media (max-width: 440px) {
                .fightlines-turn-report-grid { grid-template-columns: 1fr; gap: .35rem; }
                .fightlines-turn-report-metric { display: flex; justify-content: space-between; gap: .5rem; }
                .fightlines-turn-report-metric dt { margin: 0; }
            }
            @media (max-height: 600px) {
                .fightlines-turn-emblem { min-height: 9rem; gap: .5rem; padding: 1rem; }
                .fightlines-turn-number { font-size: 5rem; }
            }
            @media (prefers-reduced-motion: reduce) {
                #turn-introduction[open] { animation: none; }
                .fightlines-turn-emblem::after { animation: none; opacity: 0; }
            }
            """
                |> String.replace "SHADOW" (S.gray0Str ++ "99")
                |> String.replace "SHINE" (S.gray5Str ++ "88")
                |> String.replace "GOLDGLOW" (S.yellow5Str ++ "33")
                |> String.replace "GOLD" S.yellow5Str
                |> String.replace "MUTED" S.gray4Str
    in
    H.node "style"
        []
        [ H.text css ]
