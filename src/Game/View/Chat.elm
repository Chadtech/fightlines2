module Game.View.Chat exposing
    ( Msg(..)
    , dialog
    , dialogHtmlId
    , history
    , inputHtmlId
    , lobbyPanel
    , messagesHtmlId
    , notification
    , openKeyDecoder
    , overlay
    )

import Api.Enum.PlayerNumber as PlayerNumber
import Css
import Game.Chat as Chat exposing (Composer, Delivery(..), Message)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Dialog as Dialog exposing (Dialog)
import View.RequestError as RequestError
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Msg
    = OpenPressed
    | CloseClicked
    | TextChanged String
    | SendPressed
    | HistoryClicked
    | DialogOpened
    | HistoryScrolled Chat.ScrollPosition
    | RetrySendPressed
    | RetryUpdatesPressed
    | DismissErrorClicked


type ComposerPlacement
    = DialogComposer
    | LobbyComposer


type TranscriptPlacement
    = LobbyTranscript
    | HistoryTranscript


type alias KeyEvent =
    { key : String
    , tag : String
    , htmlId : String
    , modified : Bool
    , composing : Bool
    , repeated : Bool
    }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


dialogHtmlId : String
dialogHtmlId =
    "game-chat"


inputHtmlId : String
inputHtmlId =
    "game-chat-input"


historyHtmlId : String
historyHtmlId =
    "game-chat-history"


messagesHtmlId : String
messagesHtmlId =
    "chat-messages"


dialog : Chat.Model -> Composer -> Dialog Msg
dialog model composer =
    let
        historyBody : List (Html Msg)
        historyBody =
            if composer.history then
                [ history { onScroll = Just HistoryScrolled } model.messages ]

            else
                []

        errorOverlay : List (Html Msg)
        errorOverlay =
            notification model
                |> Maybe.map RequestError.toast
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    Dialog.make dialogHtmlId
        "chat"
        CloseClicked
        [ H.div
            [ A.hidden (not composer.history)
            , A.id historyHtmlId
            , A.css [ S.when (not composer.history) S.displayNone ]
            ]
            historyBody
        , editor DialogComposer composer
        ]
        |> Dialog.form
        |> Dialog.onOpened DialogOpened
        |> Dialog.withCloseButton
        |> Dialog.withOverlay errorOverlay


lobbyPanel : Chat.Model -> Html Msg
lobbyPanel model =
    let
        input : Html Msg
        input =
            case model.panel of
                Chat.Composing composer ->
                    editor LobbyComposer composer

                _ ->
                    H.text ""
    in
    [ transcript LobbyTranscript { onScroll = Just HistoryScrolled } model.messages
    , input
    ]
        |> Card.toHtml
            (Card.panel
                |> Card.withHeader (CardHeader.simple "chat")
            )


editor : ComposerPlacement -> Composer -> Html Msg
editor placement composer =
    let
        pending : Bool
        pending =
            case composer.delivery of
                Sending _ ->
                    True

                _ ->
                    False

        send : Button.Button Msg
        send =
            if pending then
                Button.disabled "sending…"

            else if String.isEmpty (String.trim composer.text) then
                Button.disabled "send"

            else
                Button.primary "send" SendPressed

        field : TextField.TextField Msg
        field =
            TextField.simple composer.text TextChanged
                |> TextField.withHtmlId inputHtmlId
                |> TextField.accessibleLabel "chat message"
                |> TextField.disabled pending
                |> TextField.withoutAutocomplete

        focusedField : TextField.TextField Msg
        focusedField =
            case placement of
                DialogComposer ->
                    TextField.withAutofocus field

                LobbyComposer ->
                    field

        historyLabel : String
        historyLabel =
            if composer.history then
                "hide history"

            else
                "message history"

        historyAction : Html Msg
        historyAction =
            Button.secondary historyLabel HistoryClicked
                |> Button.disclosure
                    { expanded = composer.history
                    , controlsHtmlId = historyHtmlId
                    }
                |> Button.toHtml

        content : List (Html Msg)
        content =
            case placement of
                DialogComposer ->
                    [ TextField.toHtml focusedField
                    , H.div
                        [ A.css
                            [ S.row
                            , S.justifySpaceBetween
                            , S.g3
                            , S.flexWrap
                            ]
                        ]
                        [ historyAction
                        , Button.toHtml send
                        ]
                    ]

                LobbyComposer ->
                    [ H.div
                        [ A.css
                            [ S.flex1
                            , S.minW0
                            ]
                        ]
                        [ TextField.toHtml focusedField
                        ]
                    , Button.toHtml send
                    ]

        layout : List Css.Style
        layout =
            case placement of
                DialogComposer ->
                    [ S.col
                    , S.g3
                    ]

                LobbyComposer ->
                    [ S.row
                    , S.itemsCenter
                    , S.g2
                    , S.shrink0
                    ]
    in
    H.div
        [ Ev.preventDefaultOn "keydown" sendKeyDecoder
        , A.css layout
        ]
        content


notification : Chat.Model -> Maybe (Html Msg)
notification model =
    case Chat.sendError model of
        Just message ->
            Just
                (RequestError.toHtml
                    { title = "couldn’t send message"
                    , message = message
                    , guidance = "your message is still here."
                    , retryEnabled = True
                    , onRetry = RetrySendPressed
                    , onDismiss = DismissErrorClicked
                    }
                )

        Nothing ->
            case Chat.pollError model of
                Just message ->
                    Just
                        (RequestError.toHtml
                            { title = "couldn’t update chat"
                            , message = message
                            , guidance = "retrying automatically…"
                            , retryEnabled = not model.polling
                            , onRetry = RetryUpdatesPressed
                            , onDismiss = DismissErrorClicked
                            }
                        )

                Nothing ->
                    Nothing


sendKeyDecoder : Decode.Decoder ( Msg, Bool )
sendKeyDecoder =
    let
        matching : KeyEvent -> Decode.Decoder ( Msg, Bool )
        matching event =
            if (event.key == "Enter") && (event.htmlId == inputHtmlId) && not (event.composing || event.repeated) then
                Decode.succeed ( SendPressed, True )

            else
                Decode.fail "chat input did not submit"
    in
    keyEventDecoder |> Decode.andThen matching


{-| C opens chat outside text-entry controls. The owning page suspends this
shortcut while another dialog is active.
-}
openKeyDecoder : Decode.Decoder Msg
openKeyDecoder =
    let
        decode : KeyEvent -> Decode.Decoder Msg
        decode event =
            let
                textControl : Bool
                textControl =
                    List.member event.tag [ "INPUT", "TEXTAREA", "SELECT" ]

                chatShortcut : Bool
                chatShortcut =
                    (String.toLower event.key == "c")
                        && not
                            (textControl
                                || event.modified
                                || event.composing
                                || event.repeated
                            )
            in
            if chatShortcut then
                Decode.succeed OpenPressed

            else
                Decode.fail "not a chat shortcut"
    in
    keyEventDecoder |> Decode.andThen decode


keyEventDecoder : Decode.Decoder KeyEvent
keyEventDecoder =
    let
        shortcutModifier : Bool -> Bool -> Bool -> Bool
        shortcutModifier control meta alt =
            control || meta || alt
    in
    Decode.map6 KeyEvent
        (Decode.field "key" Decode.string)
        (Decode.at [ "target", "tagName" ] Decode.string)
        (Decode.at [ "target", "id" ] Decode.string)
        (Decode.map3 shortcutModifier
            (Decode.field "ctrlKey" Decode.bool)
            (Decode.field "metaKey" Decode.bool)
            (Decode.field "altKey" Decode.bool)
        )
        (Decode.field "isComposing" Decode.bool)
        (Decode.field "repeat" Decode.bool)


overlay : List Message -> Html msg
overlay messages =
    H.div
        [ A.attribute "aria-live" "polite"
        , A.attribute "aria-relevant" "additions"
        , Aria.label "recent chat messages"
        , A.css
            [ S.fixed
            , S.top16
            , S.left4
            , S.right4
            , S.z4
            , S.pointerEventsNone
            , S.col
            , S.g1
            , S.textGray5
            , S.maxWFull
            , S.wrapAnywhere
            , S.maxW168
            , S.textShadowBlack
            ]
        ]
        (List.map messageLine messages)


history : { onScroll : Maybe (Chat.ScrollPosition -> msg) } -> List Message -> Html msg
history events messages =
    transcript HistoryTranscript events messages


transcript : TranscriptPlacement -> { onScroll : Maybe (Chat.ScrollPosition -> msg) } -> List Message -> Html msg
transcript placement events messages =
    let
        scrollAttributes : List (H.Attribute msg)
        scrollAttributes =
            case events.onScroll of
                Just onScroll ->
                    [ Ev.on "scroll" (Decode.map onScroll scrollPositionDecoder) ]

                Nothing ->
                    []

        turns : List Int
        turns =
            List.foldl addTurn [] messages |> List.sort

        addTurn : Message -> List Int -> List Int
        addTurn message known =
            if List.member message.turnNumber known then
                known

            else
                message.turnNumber :: known

        group : Int -> Html msg
        group turn =
            let
                label : String
                label =
                    if turn == 0 then
                        "lobby"

                    else
                        "turn " ++ String.fromInt turn

                rows : List (Html msg)
                rows =
                    messages
                        |> List.filter onTurn
                        |> List.sortBy .sequence
                        |> List.map messageLine

                onTurn : Message -> Bool
                onTurn message =
                    message.turnNumber == turn
            in
            H.section
                [ A.css
                    [ S.col
                    , S.g2
                    ]
                ]
                (H.h3
                    [ A.css [ S.textGray4 ] ]
                    [ H.text label ]
                    :: rows
                )

        content : List (Html msg)
        content =
            if List.isEmpty messages then
                [ H.p [] [ H.text "no messages yet." ] ]

            else
                List.map group turns

        placementStyles : List Css.Style
        placementStyles =
            case placement of
                LobbyTranscript ->
                    [ S.flex1
                    , S.minH0
                    ]

                HistoryTranscript ->
                    [ S.maxH35Viewport ]

        attributes : List (H.Attribute msg)
        attributes =
            [ A.id messagesHtmlId
            , Aria.label "message history"
            , A.tabindex 0
            , A.css
                [ S.col
                , S.g3
                , S.bgNightwood3
                , S.textGray5
                , S.indentStrong
                , S.p3
                , S.overflowAuto
                , S.batch placementStyles
                ]
            ]
                ++ scrollAttributes
    in
    H.div
        attributes
        content


scrollPositionDecoder : Decode.Decoder Chat.ScrollPosition
scrollPositionDecoder =
    Decode.map3 Chat.ScrollPosition
        (Decode.at [ "target", "scrollTop" ] Decode.float)
        (Decode.at [ "target", "scrollHeight" ] Decode.float)
        (Decode.at [ "target", "clientHeight" ] Decode.float)


messageLine : Message -> Html msg
messageLine message =
    let
        senderStyle : Css.Style
        senderStyle =
            case message.playerNumber of
                Just PlayerNumber.Player1 ->
                    S.textRed1Light

                Just PlayerNumber.Player2 ->
                    S.textBlue0Light

                Nothing ->
                    S.textGray5
    in
    H.p
        [ A.css [ S.wrapAnywhere ] ]
        [ H.span
            [ A.css [ senderStyle ] ]
            [ H.text (message.sender ++ ": ") ]
        , H.text message.text
        ]
