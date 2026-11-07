module Fightlines.View.GameMenu exposing
    ( Msg(..)
    , buttonHtmlId
    , closeButtonHtmlId
    , dialog
    , dialogHtmlId
    , panel
    , resignationCancelButtonHtmlId
    , resignationDialog
    , resignationDialogHtmlId
    )

import Browser.Dom
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Msg
    = OpenClicked
    | ChatClicked
    | SettingsClicked
    | FeedbackClicked
    | AboutClicked
    | PrivacyPolicyClicked
    | CloseClicked
    | FocusReturned (Result Browser.Dom.Error ())
    | ResignationConfirmed
    | ResignationCanceled
    | HomeClicked



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


buttonHtmlId : String
buttonHtmlId =
    "game-menu-button"


dialogHtmlId : String
dialogHtmlId =
    "game-menu"


closeButtonHtmlId : String
closeButtonHtmlId =
    dialogHtmlId ++ "-close"


resignationCancelButtonHtmlId : String
resignationCancelButtonHtmlId =
    resignationDialogHtmlId ++ "-cancel"


panel : { enabled : Bool, turnNumber : Int } -> Html Msg
panel config =
    let
        button : Button.Button Msg
        button =
            if config.enabled then
                Button.secondary "menu" OpenClicked

            else
                Button.disabled "menu"

        turnLabel : String
        turnLabel =
            "turn " ++ String.fromInt config.turnNumber
    in
    H.section
        [ Aria.label "game header"
        , A.css
            [ S.bgGray1
            , S.outdent
            , S.borderT0
            , S.grid
            , S.gridColumns "4.5rem 6rem 4.5rem"
            , S.itemsCenter
            , S.g2
            , S.py1
            , S.px1p5
            , S.maxWFull
            , S.childButtons
                [ S.disabled
                    [ S.outdentStrong
                    ]
                ]
            ]
        ]
        [ button
            |> Button.small
            |> Button.fullWidth
            |> Button.withHtmlId buttonHtmlId
            |> Button.toHtml
        , H.img
            [ A.src "/assets/fightlines-logo-v1.png"
            , A.alt "fightlines"
            , A.css
                [ S.block
                , S.w16
                , S.hAuto
                , S.justifySelfCenter
                ]
            ]
            []
        , H.span
            [ Aria.role Aria.Status
            , A.title turnLabel
            , A.css
                [ S.bgNightwood3
                , S.textGray5
                , S.indentStrong
                , S.tabularNums
                , S.textAlignCenter
                , S.textEllipsis
                , S.py0p5
                , S.px1
                , S.minH7p5
                ]
            ]
            [ H.text turnLabel
            ]
        ]


dialog : { resigning : Bool } -> Dialog Msg
dialog config =
    let
        homeButton : Button.Button Msg
        homeButton =
            if config.resigning then
                Button.disabled "home"

            else
                Button.secondary "home" HomeClicked
    in
    Dialog.make dialogHtmlId
        "menu"
        CloseClicked
        [ Button.secondary "settings" SettingsClicked
            |> Button.fullWidth
            |> Button.toHtml
        , Button.secondary "chat (c)" ChatClicked
            |> Button.fullWidth
            |> Button.toHtml
        , Button.secondary "feedback" FeedbackClicked
            |> Button.fullWidth
            |> Button.toHtml
        , Button.secondary "about" AboutClicked
            |> Button.fullWidth
            |> Button.toHtml
        , Button.secondary "privacy policy" PrivacyPolicyClicked
            |> Button.fullWidth
            |> Button.toHtml
        , homeButton
            |> Button.fullWidth
            |> Button.toHtml
        , Button.primary "close" CloseClicked
            |> Button.withHtmlId closeButtonHtmlId
            |> Button.fullWidth
            |> Button.toHtml
        ]


resignationDialogHtmlId : String
resignationDialogHtmlId =
    "confirm-resignation"


resignationDialog : { goingHome : Bool } -> Dialog Msg
resignationDialog config =
    let
        explanation : String
        explanation =
            if config.goingHome then
                "going home will surrender this game. your opponent will win, and this cannot be undone."

            else
                "your opponent will win, and this cannot be undone."

        confirmLabel : String
        confirmLabel =
            if config.goingHome then
                "surrender and go home"

            else
                "surrender"
    in
    Dialog.make resignationDialogHtmlId
        "surrender?"
        ResignationCanceled
        [ H.p
            []
            [ H.text explanation ]
        , Button.primary "keep fighting" ResignationCanceled
            |> Button.fullWidth
            |> Button.withHtmlId resignationCancelButtonHtmlId
            |> Button.toHtml
        , Button.danger confirmLabel ResignationConfirmed
            |> Button.fullWidth
            |> Button.toHtml
        ]
