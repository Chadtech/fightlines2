module Fightlines.View.Feedback exposing
    ( Msg(..)
    , dialog
    , htmlId
    , inputHtmlId
    )

import Css
import Fightlines.Feedback as Feedback exposing (Draft, Status(..))
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)
import View.Textarea as Textarea



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Msg
    = TextChanged String
    | SubmitClicked
    | CloseClicked



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


htmlId : String
htmlId =
    "feedback-dialog"


inputHtmlId : String
inputHtmlId =
    "feedback-text"


dialog : { mobile : Bool } -> Draft -> Dialog Msg
dialog layout draft =
    let
        textarea : Textarea.Textarea Msg
        textarea =
            case draft.status of
                Sending _ ->
                    Textarea.readOnly draft.text

                _ ->
                    Textarea.simple draft.text TextChanged

        submit : Button.Button Msg
        submit =
            if Feedback.isSending draft then
                Button.disabled "submitting…"

            else if Feedback.canSubmit draft then
                Button.primary "submit feedback" SubmitClicked

            else
                Button.disabled "submit feedback"

        fieldHeight : Css.Style
        fieldHeight =
            if layout.mobile then
                S.flex1

            else
                S.h48
    in
    Dialog.make htmlId
        "feedback"
        CloseClicked
        [ H.label
            [ A.css
                [ S.col
                , S.g1
                , S.when layout.mobile
                    (S.batch [ S.flex1, S.minH20 ])
                ]
            ]
            [ H.text "your feedback"
            , H.div
                [ A.css
                    [ fieldHeight
                    , S.minH0
                    ]
                ]
                [ textarea
                    |> Textarea.withHtmlId inputHtmlId
                    |> Textarea.withAutofocus
                    |> Textarea.toHtml
                ]
            ]
        , status draft
        , H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g2
                , S.shrink0
                ]
            ]
            [ submit
                |> Button.toHtml
            , Button.secondary "close" CloseClicked
                |> Button.toHtml
            ]
        ]
        |> Dialog.compactForm


status : Draft -> Html Msg
status draft =
    let
        message : String
        message =
            case draft.status of
                Editing ->
                    if Feedback.tooLong draft then
                        "feedback must be 5000 characters or fewer."

                    else
                        ""

                Sending _ ->
                    "submitting feedback…"

                Failed error ->
                    error

                Submitted ->
                    "thank you. your feedback has been saved."

        role : Aria.Role
        role =
            case draft.status of
                Failed _ ->
                    Aria.Alert

                _ ->
                    Aria.Status
    in
    H.p
        [ Aria.role role
        , A.css
            [ S.wrapAnywhere
            , S.when (String.isEmpty message) S.absolute
            ]
        ]
        [ H.text message ]
