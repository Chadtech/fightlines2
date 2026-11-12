module Fightlines.View.TurnIntroduction exposing
    ( Msg(..)
    , conclusion
    , dialog
    , dialogHtmlId
    , feedbackButtonHtmlId
    , styles
    )

import Css
import Css.Media
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
    | FeedbackClicked
    | SkipDialogsChanged Bool


dialogHtmlId : String
dialogHtmlId =
    "turn-introduction"


feedbackButtonHtmlId : String
feedbackButtonHtmlId =
    "game-over-feedback-button"


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
            , reportView TurnStartReport config.previousTurn
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
                reportView FinalReport config.previousTurn

            else
                H.text ""

        result : Html Msg
        result =
            H.div
                [ A.css (emblemStyles config.previousTurn) ]
                [ H.div
                    [ A.css
                        [ S.letterSpacingEm 0.16
                        , S.textAlignCenter
                        , compactConclusion [ S.displayNone ]
                        ]
                    ]
                    [ H.text "the battle is over" ]
                , H.h2
                    [ A.autofocus True
                    , A.tabindex -1
                    , A.css
                        [ S.fontSizeValue "clamp(2rem, 7vw, 4rem)"
                        , S.lineHeight1
                        , S.textAlignCenter
                        , S.wrapAnywhere
                        , S.textYellow5
                        , S.outlineNone
                        , compactConclusion [ S.fontSizeRem 2 ]
                        ]
                    ]
                    [ H.text config.headline ]
                , H.p
                    [ A.css
                        [ S.textGray4
                        , S.textAlignCenter
                        ]
                    ]
                    [ H.text config.caption ]
                , finalReport
                ]

        followUp : Html Msg
        followUp =
            H.div
                [ A.css
                    [ S.col
                    , S.justifyCenter
                    , S.g3
                    ]
                ]
                [ H.p
                    [ A.css [ compactConclusion [ S.displayNone ] ] ]
                    [ H.text "thanks for playing! fightlines is a new game in development. your feedback helps shape what comes next." ]
                , H.p
                    [ A.css
                        [ S.displayNone
                        , compactConclusion [ S.block ]
                        ]
                    ]
                    [ H.text "thanks for playing! your feedback helps us improve fightlines." ]
                , H.div
                    [ A.css
                        [ S.grid
                        , S.gridCols2
                        , S.g3
                        , compactConclusion [ S.gridCols1 ]
                        , S.belowWidth 480
                            [ S.gridCols1 ]
                        ]
                    ]
                    [ Button.primary
                        "return to battlefield"
                        BattlefieldViewClicked
                        |> Button.large
                        |> Button.fullWidth
                        |> Button.toHtml
                    , Button.secondary "give feedback" FeedbackClicked
                        |> Button.large
                        |> Button.fullWidth
                        |> Button.withHtmlId feedbackButtonHtmlId
                        |> Button.toHtml
                    ]
                ]
    in
    Dialog.make dialogHtmlId
        "game over"
        BattlefieldViewClicked
        [ H.div
            [ A.css
                [ S.grid
                , S.gridCols1
                , S.shrink0
                , S.g3
                , sideBySideConclusion
                    [ S.gridColumns "minmax(0, 3fr) minmax(0, 2fr)"
                    , Css.lineHeight (Css.num 1.2)
                    ]
                ]
            ]
            [ result
            , followUp
            ]
        ]
        |> Dialog.announcement


compactConclusion : List Css.Style -> Css.Style
compactConclusion =
    Css.Media.withMediaQuery
        [ "(max-width: 1023px) and (max-height: 600px)" ]


sideBySideConclusion : List Css.Style -> Css.Style
sideBySideConclusion =
    Css.Media.withMediaQuery
        [ "(min-width: 560px) and (max-width: 1023px) and (max-height: 600px)" ]


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
    , S.grow
    , S.col
    , S.itemsCenter
    , S.justifyCenter
    , S.g4
    , S.minH76
    , S.batch [ S.py8, S.px4 ]
    , S.textYellow5
    , S.animation "fightlines-turn-pop 320ms cubic-bezier(.2,.8,.2,1) both"
    , S.reducedMotion
        [ S.animationNone ]
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
        [ S.minH0
        , S.g1
        , S.p2
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

        compactFontSize : Float
        compactFontSize =
            if hasReport previousTurn then
                2

            else
                5
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
        [ S.fontSizeRem compactFontSize
        ]
    ]


type ReportLayout
    = TurnStartReport
    | FinalReport


reportView : ReportLayout -> Maybe Turn.Resolution -> Html msg
reportView layout previousTurn =
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
                        , S.belowHeight 600
                            [ S.m0 ]
                        ]
                    ]
                    [ H.text ("turn " ++ String.fromInt resolution.number ++ " report") ]
                , H.dl
                    [ A.css
                        [ S.grid
                        , S.gridCols2
                        , S.g3
                        , S.m0
                        , S.belowHeight 600
                            [ S.g1 ]
                        ]
                    ]
                    [ reportMetric layout
                        "your units lost"
                        (String.fromInt report.unitsLost)
                    , reportMetric layout
                        "confirmed enemy losses"
                        (String.fromInt report.enemyUnitsDestroyed)
                    , reportMetric layout
                        "known damage inflicted"
                        (String.fromInt report.damageInflicted ++ " hp")
                    , reportMetric layout
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


reportMetric : ReportLayout -> String -> String -> Html msg
reportMetric layout label value =
    let
        finalReport : Bool
        finalReport =
            layout == FinalReport
    in
    H.div
        [ A.css
            [ S.p2
            , S.bgGray0_60
            , S.borderYellow5_20
            , S.belowHeight 600
                [ S.row
                , S.justifySpaceBetween
                , S.g2
                ]
            , S.when finalReport
                [ sideBySideConclusion
                    [ S.px1
                    , Css.property "padding-block" "0.1875rem"
                    ]
                ]
            ]
        ]
        [ H.dt
            [ A.css
                [ S.textGray4
                , S.mb1p4
                , S.belowHeight 600
                    [ S.m0 ]
                ]
            ]
            [ H.text label ]
        , H.dd
            [ A.css
                [ S.m0
                , S.textYellow5
                , S.when finalReport
                    [ sideBySideConclusion [ S.noWrap, S.shrink0 ] ]
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
            @keyframes fightlines-turn-appear {
                from { opacity: 0; }
                to { opacity: 1; }
            }
            @keyframes fightlines-turn-introduction-shine {
                0%, 12% { transform: translateX(-240%) skewX(-22deg); opacity: 0; }
                20% { opacity: .7; }
                65% { opacity: .7; }
                80%, 100% { transform: translateX(600%) skewX(-22deg); opacity: 0; }
            }
            #turn-introduction[open] {
                /* Transforms here would anchor fixed viewport controls to the dialog. */
                animation: fightlines-turn-appear 320ms ease-out both;
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
