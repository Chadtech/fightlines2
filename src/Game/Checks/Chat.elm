port module Game.Checks.Chat exposing (main)

import Api.Enum.PlayerNumber as PlayerNumber
import Audio
import Game.Chat as Chat exposing (Delivery(..), Panel(..))
import Game.View.Chat as ChatView
import Json.Decode as Decode
import Json.Encode as Encode
import Platform
import Random


port results : List String -> Cmd msg


type alias KeyEvent =
    { key : String
    , tag : String
    , ctrl : Bool
    , meta : Bool
    , alt : Bool
    , composing : Bool
    , repeated : Bool
    }


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


message : Int -> Int -> Chat.Message
message sequence turn =
    { sequence = sequence
    , turnNumber = turn
    , sender = "player"
    , playerNumber = Just PlayerNumber.Player1
    , text = "message " ++ String.fromInt sequence
    }


checks : List String
checks =
    let
        initial : Chat.Model
        initial =
            Chat.init [ message 1 0 ] |> Chat.open |> Chat.edit "hello"

        gameEntry : Chat.Model
        gameEntry =
            Chat.initGame [ message 1 0, message 2 1, message 3 1, message 4 2, message 5 2 ]

        readingHistory : Chat.Model
        readingHistory =
            initial
                |> Chat.toggleHistory
                |> Chat.scrollHistory { scrollTop = 100, scrollHeight = 700, clientHeight = 200 }

        nearBottom : Chat.Model
        nearBottom =
            readingHistory
                |> Chat.scrollHistory { scrollTop = 496, scrollHeight = 700, clientHeight = 200 }

        remote : Chat.Message
        remote =
            let
                original : Chat.Message
                original =
                    message 2 1
            in
            { original | sender = "opponent", playerNumber = Just PlayerNumber.Player2 }

        ownAfterSideChange : Chat.Message
        ownAfterSideChange =
            { remote | sender = "player" }

        visitor : Chat.Message
        visitor =
            { remote | sender = "visitor", playerNumber = Nothing }

        incoming : { known : List Chat.Message, received : List Chat.Message } -> Bool
        incoming batch =
            Chat.hasNewIncoming
                { known = batch.known
                , received = batch.received
                , ownNames = [ "player" ]
                }

        chatKey : KeyEvent
        chatKey =
            { key = "c"
            , tag = "DIV"
            , ctrl = False
            , meta = False
            , alt = False
            , composing = False
            , repeated = False
            }

        shortcut : KeyEvent -> Result Decode.Error ChatView.Msg
        shortcut event =
            Encode.object
                [ ( "key", Encode.string event.key )
                , ( "target"
                  , Encode.object
                        [ ( "id", Encode.string "" )
                        , ( "tagName", Encode.string event.tag )
                        ]
                  )
                , ( "ctrlKey", Encode.bool event.ctrl )
                , ( "metaKey", Encode.bool event.meta )
                , ( "altKey", Encode.bool event.alt )
                , ( "isComposing", Encode.bool event.composing )
                , ( "repeat", Encode.bool event.repeated )
                ]
                |> Decode.decodeValue ChatView.openKeyDecoder

        cOpensChat : String -> Bool
        cOpensChat tag =
            shortcut { chatKey | tag = tag } == Ok ChatView.OpenPressed

        enterKeepsActivation : String -> Bool
        enterKeepsActivation tag =
            shortcut { chatKey | key = "Enter", tag = tag }
                |> Result.toMaybe
                |> (==) Nothing

        cKeepsTextEntry : String -> Bool
        cKeepsTextEntry tag =
            shortcut { chatKey | tag = tag }
                |> Result.toMaybe
                |> (==) Nothing

        ignoresEvent : KeyEvent -> Bool
        ignoresEvent event =
            shortcut event
                |> Result.toMaybe
                |> (==) Nothing

        assert : String -> Bool -> List String
        assert label passed =
            if passed then
                []

            else
                [ label ]
    in
    case Chat.prepareSend (Random.initialSeed 42) initial of
        Nothing ->
            [ "nonempty chat must prepare a submission" ]

        Just ( sending, seed, submission ) ->
            let
                hidden : Chat.Model
                hidden =
                    Chat.close sending

                failed : Chat.Model
                failed =
                    Chat.sent submission (Err "offline") hidden

                accepted : Chat.Model
                accepted =
                    Chat.sent submission (Ok (message 3 2)) hidden

                lobbyAccepted : Chat.Model
                lobbyAccepted =
                    Chat.sent submission (Ok (message 3 2)) sending

                polled : Chat.Model
                polled =
                    Chat.receive [ message 2 1, message 3 2 ] accepted

                reopened : Chat.Model
                reopened =
                    accepted |> Chat.open |> Chat.edit "another draft"

                late : Chat.Model
                late =
                    Chat.sent submission (Ok (message 3 2)) reopened

                retryUsesSameId : Bool
                retryUsesSameId =
                    case Chat.prepareSend seed (Chat.open failed) of
                        Just ( _, _, retry ) ->
                            retry == submission

                        Nothing ->
                            False

                editedUsesNewId : Bool
                editedUsesNewId =
                    case Chat.prepareSend seed (Chat.open failed |> Chat.edit "edited") of
                        Just ( _, _, retry ) ->
                            retry.id /= submission.id

                        Nothing ->
                            False

                draftPreserved : Bool
                draftPreserved =
                    case late.panel of
                        Composing composer ->
                            composer.text == "another draft"

                        _ ->
                            False

                failurePreserved : Bool
                failurePreserved =
                    case failed.panel of
                        Background composer ->
                            (composer.text == "hello") && (composer.delivery == SendFailed submission "offline")

                        _ ->
                            False

                lobbyCleared : Bool
                lobbyCleared =
                    case lobbyAccepted.panel of
                        Composing composer ->
                            String.isEmpty composer.text && (composer.delivery == Editing)

                        _ ->
                            False

                dismissedRetryUsesSameId : Bool
                dismissedRetryUsesSameId =
                    case Chat.prepareSend seed (failed |> Chat.dismissErrors |> Chat.open) of
                        Just ( _, _, retry ) ->
                            retry == submission

                        Nothing ->
                            False
            in
            List.concat
                [ assert "initial history must not replay notifications" (List.isEmpty initial.recent)
                , assert "chat audio uses the registered playback event"
                    (Decode.decodeValue (Decode.field "play" Decode.string) (Audio.encodeEvent Audio.chatReceived) == Ok "chatReceived")
                , assert "new messages from another player request a cue" (incoming { known = [], received = [ remote ] })
                , assert "your own poll echo stays silent before its send response" (not (incoming { known = [], received = [ message 2 1 ] }))
                , assert "your own message remains silent after switching lobby sides" (not (incoming { known = [], received = [ ownAfterSideChange ] }))
                , assert "initial history and repeated polls stay silent" (not (incoming { known = [ remote ], received = [ remote ] }))
                , assert "empty polls stay silent" (not (incoming { known = [ remote ], received = [] }))
                , assert "a mixed batch still detects a remote arrival" (incoming { known = [], received = [ message 1 0, remote ] })
                , assert "visitors are incoming even when your roster name is visitor"
                    (Chat.hasNewIncoming { known = [], received = [ visitor ], ownNames = [ "visitor" ] })
                , assert "scrolling up suspends automatic following" (Chat.historyVisible readingHistory && not (Chat.followsHistory readingHistory))
                , assert "incoming messages preserve reading mode" (not (Chat.followsHistory (Chat.receive [ message 2 1 ] readingHistory)))
                , assert "four pixels from the bottom resumes following" (Chat.followsHistory nearBottom)
                , assert "beyond four pixels preserves reading mode"
                    (not (Chat.followsHistory (Chat.scrollHistory { scrollTop = 495.5, scrollHeight = 700, clientHeight = 200 } nearBottom)))
                , assert "incoming messages retain automatic following" (Chat.followsHistory (Chat.receive [ message 2 1 ] nearBottom))
                , assert "reopening history follows the newest messages" (Chat.followsHistory (readingHistory |> Chat.toggleHistory |> Chat.toggleHistory))
                , assert "restoring a native dialog resumes following" (Chat.followsHistory (Chat.historyOpened readingHistory))
                , assert "entering a game shows messages sent before that player's initial load" (List.map .sequence gameEntry.recent == [ 3, 4, 5 ])
                , assert "game entry keeps complete history and advances the polling cursor" ((List.map .sequence gameEntry.messages == [ 1, 2, 3, 4, 5 ]) && (gameEntry.cursor == 5))
                , assert "an empty poll after entry must not erase the initial messages" ((Chat.receive [] gameEntry).recent == gameEntry.recent)
                , assert "lobby-only history does not become an in-game notification" (List.isEmpty (Chat.initGame [ message 1 0 ]).recent)
                , assert "game send hides the composer before its response" (not (Chat.isOpen hidden))
                , assert "hidden pending requests must still block duplicate sends" (Chat.prepareSend seed (Chat.open hidden) == Nothing)
                , assert "successful game sends stay closed" (not (Chat.isOpen accepted))
                , assert "successful lobby sends clear the field and keep the panel open" lobbyCleared
                , assert "pending send must block duplicate submission" (Chat.prepareSend seed sending == Nothing)
                , assert "failed sends preserve text and error" failurePreserved
                , assert "polls block duplicates until completion" (Maybe.andThen Chat.beginPoll (Chat.beginPoll initial) == Nothing)
                , assert "failed polls can be retried" (Chat.beginPoll (Chat.pollFailed "offline" initial) /= Nothing)
                , assert "dismissing a send failure must not hide a later update failure"
                    (Chat.pollError (failed |> Chat.dismissErrors |> Chat.pollFailed "updates offline") == Just "updates offline")
                , assert "dismissed update failures stay hidden until recovery"
                    (Chat.pollError (initial |> Chat.pollFailed "offline" |> Chat.dismissErrors |> Chat.pollFailed "still offline") == Nothing)
                , assert "a new update failure becomes visible after recovery"
                    (Chat.pollError (initial |> Chat.pollFailed "offline" |> Chat.dismissErrors |> Chat.receive [] |> Chat.pollFailed "offline again") == Just "offline again")
                , assert "failed game sends stay closed and expose an error notification" (not (Chat.isOpen failed) && (Chat.sendError failed == Just "offline"))
                , assert "dismissing the notification preserves retry identity" ((Chat.sendError (Chat.dismissErrors failed) == Nothing) && dismissedRetryUsesSameId)
                , assert "unchanged retry must reuse its id" retryUsesSameId
                , assert "editing a failed message must create a new id" editedUsesNewId
                , assert "send responses must not skip earlier remote messages" ((accepted.cursor == 1) && (List.map .sequence polled.messages == [ 1, 2, 3 ]) && (polled.cursor == 3))
                , assert "history retains lobby and all turns" (List.map .turnNumber polled.messages == [ 0, 1, 2 ])
                , assert "repeated polls must not duplicate messages" (Chat.receive [ message 2 1, message 3 2 ] polled == polled)
                , assert "late send response must preserve a new draft" draftPreserved
                , assert "old notification expiry must preserve newer messages" (Chat.expire (polled.overlayVersion - 1) polled == polled)
                , assert "current notification expiry hides only the overlay" (List.isEmpty (Chat.expire polled.overlayVersion polled).recent && ((Chat.expire polled.overlayVersion polled).messages == polled.messages))
                , assert "C opens chat on the battlefield and focused buttons" (List.all cOpensChat [ "DIV", "svg", "rect", "BUTTON", "A" ])
                , assert "uppercase C also opens chat" (shortcut { chatKey | key = "C" } == Ok ChatView.OpenPressed)
                , assert "Enter retains battlefield and native control activation" (List.all enterKeepsActivation [ "DIV", "rect", "INPUT", "TEXTAREA", "SELECT", "BUTTON", "A" ])
                , assert "C retains typing and native select behavior" (List.all cKeepsTextEntry [ "INPUT", "TEXTAREA", "SELECT" ])
                , assert "modified, repeated, and composing keys do not open chat"
                    (List.all ignoresEvent
                        [ { chatKey | ctrl = True }
                        , { chatKey | meta = True }
                        , { chatKey | alt = True }
                        , { chatKey | repeated = True }
                        , { chatKey | composing = True }
                        ]
                    )
                ]
