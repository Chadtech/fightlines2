module Fightlines.View.TurnIntroduction exposing
    ( Msg(..)
    , conclusion
    , dialog
    , dialogHtmlId
    , styles
    )

import Css
import Game.Turn as Turn
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)


type Msg
    = BeginClicked
    | ReplayClicked
    | BattlefieldViewClicked
    | SkipDialogsChanged Bool


dialogHtmlId : String
dialogHtmlId =
    "turn-introduction"


type alias DialogConfig =
    { turnNumber : Int
    , skipDialogs : Bool
    , previousTurn : Maybe Turn.Resolution
    , canReplay : Bool
    }


dialog : DialogConfig -> Dialog Msg
dialog config =
    let
        replayButton : Html Msg
        replayButton =
            if config.canReplay then
                Button.secondary "replay turn" ReplayClicked
                    |> Button.large
                    |> Button.toHtml

            else
                H.text ""
    in
    Dialog.make dialogHtmlId
        ("turn " ++ String.fromInt config.turnNumber)
        BeginClicked
        [ H.div
            [ A.css (emblemStyles config.previousTurn)
            ]
            [ H.div
                [ A.css
                    [ S.letterSpacingEm 0.16
                    , S.textAlignCenter
                    ]
                ]
                [ H.text "a new turn begins" ]
            , H.div
                [ A.css (numberStyles config.previousTurn)
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
            , replayButton
            , Checkbox.new
                { label = "skip this dialog"
                , checked = config.skipDialogs
                , onCheck = SkipDialogsChanged
                }
                |> Checkbox.toHtml
                    [ H.text "skip this dialog" ]
            ]
        ]
        |> Dialog.announcement


conclusion :
    { headline : String
    , caption : String
    , previousTurn : Maybe Turn.Resolution
    }
    -> Dialog Msg
conclusion config =
    let
        finalReport : Html Msg
        finalReport =
            if hasReport config.previousTurn then
                reportView config.previousTurn

            else
                H.text ""
    in
    Dialog.make dialogHtmlId
        "game over"
        BattlefieldViewClicked
        [ H.div
            [ A.css (emblemStyles config.previousTurn) ]
            [ H.div
                [ A.css
                    [ S.letterSpacingEm 0.16
                    , S.textAlignCenter
                    ]
                ]
                [ H.text "the battle is over" ]
            , H.div
                [ A.css
                    [ S.fontSizeValue "clamp(2rem, 7vw, 4rem)"
                    , S.lineHeight1
                    , S.textAlignCenter
                    ]
                ]
                [ H.text config.headline ]
            , H.div
                [ A.css
                    [ S.textGray4
                    , S.textAlignCenter
                    ]
                ]
                [ H.text config.caption ]
            , finalReport
            ]
        , H.form
            [ A.attribute "method" "dialog" ]
            [ Button.primary "view battlefield" BattlefieldViewClicked
                |> Button.large
                |> Button.toHtml
            ]
        ]
        |> Dialog.announcement


{-| Layout stays local to the styled elements; only keyframe definitions and
native-dialog animation rules need the shared style node.
-}
emblemStyles : Maybe Turn.Resolution -> List Css.Style
emblemStyles previousTurn =
    let
        reportLayout : Css.Style
        reportLayout =
            if hasReport previousTurn then
                S.batch
                    [ S.g3
                    , S.batch [ S.py6, S.px4 ]
                    ]

            else
                S.batch []
    in
    [ S.bgNightwood3
    , S.indentStrong
    , S.relative
    , S.isolate
    , S.overflowHidden
    , S.col
    , S.itemsCenter
    , S.justifyCenter
    , S.g4
    , S.minH76
    , S.batch [ S.py8, S.px4 ]
    , S.textYellow5
    , reportLayout
    , S.after
        [ S.contentEmpty
        , S.absolute
        , S.topNeg30Pct
        , S.left0
        , S.w30Pct
        , S.h160Pct
        , S.pointerEventsNone
        , Css.property "background" ("linear-gradient(90deg, transparent, " ++ S.gray5Str ++ "88, transparent)")
        , S.mixBlendScreen
        , S.animation "fightlines-turn-introduction-shine 4.8s ease-in-out .2s infinite"
        , S.reducedMotion
            [ S.animationNone
            , S.transparent
            ]
        ]
    , S.belowHeight 600
        [ S.minH36
        , S.g2
        , S.p4
        ]
    ]


hasReport : Maybe Turn.Resolution -> Bool
hasReport previousTurn =
    Maybe.andThen .report previousTurn /= Nothing


numberStyles : Maybe Turn.Resolution -> List Css.Style
numberStyles previousTurn =
    let
        fontSize : String
        fontSize =
            if hasReport previousTurn then
                "clamp(4rem, 14vw, 6rem)"

            else
                "clamp(5rem, 18vw, 9rem)"
    in
    [ S.fontSizeValue fontSize
    , S.lineHeight1
    , S.letterSpacingEm -0.06
    , S.paddingRightEm 0.06
    , Css.property
        "text-shadow"
        ("0 2px 0 "
            ++ S.yellow5Str
            ++ "33, 0 0 32px "
            ++ S.yellow5Str
            ++ "33"
        )
    , S.belowHeight 600
        [ S.fontSizeRem 5
        ]
    ]


reportView : Maybe Turn.Resolution -> Html msg
reportView previousTurn =
    case
        Maybe.andThen
            (\resolution ->
                Maybe.map (Tuple.pair resolution) resolution.report
            )
            previousTurn
    of
        Just ( resolution, report ) ->
            H.section
                [ A.css
                    [ S.wFull
                    , S.maxW120
                    ]
                , Aria.label "previous turn report"
                ]
                [ H.div
                    [ A.css
                        [ S.textGray4
                        , S.textAlignCenter
                        , S.mt3
                        ]
                    ]
                    [ H.text ("turn " ++ String.fromInt resolution.number ++ " report") ]
                , H.dl
                    [ A.css
                        [ S.grid
                        , S.gridCols2
                        , S.g3
                        , S.m0
                        , S.belowWidth 440
                            [ S.gridCols1
                            , S.g1p4
                            ]
                        ]
                    ]
                    [ reportMetric
                        "your units lost"
                        (String.fromInt report.unitsLost)
                    , reportMetric
                        "confirmed enemy losses"
                        (String.fromInt report.enemyUnitsDestroyed)
                    , reportMetric
                        "known damage inflicted"
                        (String.fromInt report.damageInflicted ++ " hp")
                    , reportMetric
                        "your supplies consumed"
                        (String.fromInt report.suppliesConsumed)
                    ]
                ]

        Nothing ->
            battlefieldCaption


battlefieldCaption : Html msg
battlefieldCaption =
    H.div
        [ A.css
            [ S.textGray4
            , S.textAlignCenter
            ]
        ]
        [ H.text "the battlefield awaits" ]


reportMetric : String -> String -> Html msg
reportMetric label value =
    H.div
        [ A.css
            [ S.p2
            , S.bgGray0_60
            , S.borderYellow5_20
            , S.belowWidth 440
                [ S.row
                , S.justifySpaceBetween
                , S.g2
                ]
            ]
        ]
        [ H.dt
            [ A.css
                [ S.textGray4
                , S.mb1p4
                , S.belowWidth 440
                    [ S.m0
                    ]
                ]
            ]
            [ H.text label ]
        , H.dd
            [ A.css
                [ S.m0
                , S.textYellow5
                ]
            ]
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
            @media (prefers-reduced-motion: reduce) {
                #turn-introduction[open] { animation: none; }
            }
            """
                |> String.replace "SHADOW" (S.gray0Str ++ "99")
                |> String.replace "GOLDGLOW" (S.yellow5Str ++ "33")
    in
    H.node "style"
        []
        [ H.text css ]
