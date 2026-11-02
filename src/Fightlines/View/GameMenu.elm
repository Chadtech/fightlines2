module Fightlines.View.GameMenu exposing
    ( Msg(..)
    , Status(..)
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
import Css
import Css.Global
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
    | AboutClicked
    | PrivacyPolicyClicked
    | CloseClicked
    | FocusReturned (Result Browser.Dom.Error ())
    | ResignClicked
    | ResignationConfirmed
    | ResignationCanceled
    | HomeClicked


type Status
    = ActiveGame
    | Resigning
    | FinishedGame



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
            , Css.borderTop Css.zero
            , S.grid
            , Css.property "grid-template-columns" "4.5rem 6rem 4.5rem"
            , S.itemsCenter
            , S.g2
            , Css.padding2 (Css.rem 0.25) (Css.rem 0.375)
            , S.maxWFull
            , Css.Global.children
                [ Css.Global.button
                    [ Css.padding2 (Css.rem 0.125) (Css.rem 0.625)
                    , Css.minHeight (Css.rem 1.875)
                    ]
                ]
            ]
        ]
        [ button
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
                , Css.property "justify-self" "center"
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
                , Css.padding2 (Css.rem 0.125) (Css.rem 0.25)
                , Css.minHeight (Css.rem 1.875)
                ]
            ]
            [ H.text turnLabel
            ]
        ]


dialog : Status -> Dialog Msg
dialog status =
    let
        homeButton : Button.Button Msg
        homeButton =
            case status of
                Resigning ->
                    Button.disabled "home"

                _ ->
                    Button.secondary "home" HomeClicked

        resignButton : Button.Button Msg
        resignButton =
            case status of
                ActiveGame ->
                    Button.danger "resign game" ResignClicked

                Resigning ->
                    Button.disabled "resigning…"

                FinishedGame ->
                    Button.disabled "resign game"
    in
    Dialog.make dialogHtmlId
        "menu"
        CloseClicked
        [ Button.primary "close" CloseClicked
            |> Button.withHtmlId closeButtonHtmlId
            |> Button.fullWidth
            |> Button.toHtml
        , Button.secondary "settings" SettingsClicked
            |> Button.fullWidth
            |> Button.toHtml
        , Button.secondary "chat" ChatClicked
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
        , H.div
            [ A.css
                [ S.mt4
                ]
            ]
            [ resignButton
                |> Button.fullWidth
                |> Button.toHtml
            ]
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
                "going home will resign this game. your opponent will win, and this cannot be undone."

            else
                "resigning ends this game. your opponent will win, and this cannot be undone."

        confirmLabel : String
        confirmLabel =
            if config.goingHome then
                "resign and go home"

            else
                "resign game"
    in
    Dialog.make resignationDialogHtmlId
        "resign game?"
        ResignationCanceled
        [ H.p
            []
            [ H.text explanation ]
        , Button.primary "cancel" ResignationCanceled
            |> Button.fullWidth
            |> Button.withHtmlId resignationCancelButtonHtmlId
            |> Button.toHtml
        , Button.danger confirmLabel ResignationConfirmed
            |> Button.fullWidth
            |> Button.toHtml
        ]
