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
import Css
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
    | DevPanelClicked
    | FeedbackClicked
    | AboutClicked
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


chatButtonHtmlId : String
chatButtonHtmlId =
    "game-chat-button"


dialogHtmlId : String
dialogHtmlId =
    "game-menu"


closeButtonHtmlId : String
closeButtonHtmlId =
    dialogHtmlId ++ "-close"


resignationCancelButtonHtmlId : String
resignationCancelButtonHtmlId =
    resignationDialogHtmlId ++ "-cancel"


panel :
    { enabled : Bool, turnNumber : Int, mobile : Bool }
    -> Html Msg
panel config =
    let
        headerButton : String -> Msg -> Button.Button Msg
        headerButton label onClick =
            if config.enabled then
                Button.secondary label onClick

            else
                Button.disabled label

        turnLabel : String
        turnLabel =
            "turn " ++ String.fromInt config.turnNumber

        desktopPanel : Css.Style
        desktopPanel =
            S.batch
                [ S.bgGray1
                , S.outdent
                , S.borderT0
                , S.py1
                ]
    in
    H.section
        [ Aria.label "game header"
        , A.css
            [ S.when (not config.mobile) [ desktopPanel ]
            , S.grid
            , S.gridColumns "minmax(0, 4.5rem) minmax(0, 6rem) minmax(0, 4.5rem) minmax(0, 4.5rem)"
            , S.itemsCenter
            , S.g2
            , S.px1p5
            , S.maxWFull
            , S.childButtons
                [ S.disabled
                    [ S.outdentStrong
                    ]
                ]
            ]
        ]
        [ headerButton "menu" OpenClicked
            |> Button.small
            |> Button.fullWidth
            |> Button.withHtmlId buttonHtmlId
            |> Button.toHtml
        , H.img
            [ A.src "assets/fightlines-logo-v1.png"
            , A.alt "fightlines"
            , A.css
                [ S.block
                , S.w16
                , S.maxWFull
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
        , headerButton "chat" ChatClicked
            |> Button.small
            |> Button.fullWidth
            |> Button.withHtmlId chatButtonHtmlId
            |> Button.toHtml
        ]


dialog : { resigning : Bool, mobile : Bool } -> Dialog Msg
dialog config =
    let
        homeButton : Button.Button Msg
        homeButton =
            if config.resigning then
                Button.disabled "home"

            else
                Button.secondary "home" HomeClicked

        layoutStyles : List Css.Style
        layoutStyles =
            if config.mobile then
                [ S.grid
                , S.gridColumns "repeat(4, minmax(0, 1fr))"
                , S.maxW96
                , S.mAuto
                , S.shrink0
                , S.childButtons
                    [ Css.property "min-height" "clamp(2.75rem, 15dvh, 5rem)"
                    , S.fontSizeRem 1.25
                    , Css.property "grid-column" "span 2"
                    , Css.lastChild
                        [ Css.property "grid-column" "2 / 4"
                        ]
                    ]
                ]

            else
                []
    in
    Dialog.make dialogHtmlId
        "menu"
        CloseClicked
        [ H.div
            [ A.css
                [ S.col
                , S.g3
                , S.wFull
                , S.selfCenter
                , S.batch layoutStyles
                ]
            ]
            [ Button.secondary "settings" SettingsClicked
                |> Button.fullWidth
                |> Button.toHtml
            , Button.secondary "dev panel" DevPanelClicked
                |> Button.fullWidth
                |> Button.toHtml
            , Button.secondary "feedback" FeedbackClicked
                |> Button.fullWidth
                |> Button.toHtml
            , Button.secondary "about" AboutClicked
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
