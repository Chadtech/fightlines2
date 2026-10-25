module Game.View.GameMenu exposing
    ( Msg(..)
    , Status(..)
    , buttonHtmlId
    , dialog
    , dialogHtmlId
    , panel
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
    | CloseClicked
    | FocusReturned (Result Browser.Dom.Error ())
    | ResignClicked
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
                    Button.secondary "resign game" ResignClicked

                Resigning ->
                    Button.disabled "resigning…"

                FinishedGame ->
                    Button.disabled "resign game"
    in
    Dialog.make dialogHtmlId
        "menu"
        CloseClicked
        [ Button.disabled "settings"
            |> Button.fullWidth
            |> Button.toHtml
        , homeButton
            |> Button.fullWidth
            |> Button.toHtml
        , resignButton
            |> Button.fullWidth
            |> Button.toHtml
        , Button.secondary "close" CloseClicked
            |> Button.fullWidth
            |> Button.toHtml
        ]
