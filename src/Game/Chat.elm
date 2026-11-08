module Game.Chat exposing
    ( Composer
    , Delivery(..)
    , Message
    , Model
    , Panel(..)
    , ScrollPosition
    , Submission
    , beginPoll
    , close
    , dismissErrors
    , edit
    , expire
    , followsHistory
    , hasNewIncoming
    , hide
    , historyOpened
    , historyVisible
    , init
    , initGame
    , isOpen
    , open
    , pollError
    , pollFailed
    , prepareSend
    , query
    , receive
    , scrollHistory
    , selection
    , sendError
    , sendRequest
    , sent
    , toggleHistory
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.ChatMessage as MessageApi
import Api.Query
import ApiRequest
import Graphql.Http
import Graphql.Operation exposing (RootQuery)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import LobbyId exposing (LobbyId)
import Random



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Message =
    { sequence : Int
    , turnNumber : Int
    , sender : String
    , playerNumber : Maybe PlayerNumber
    , text : String
    }


type MessageId
    = MessageId String


type alias Submission =
    { id : MessageId
    , text : String
    }


type alias Model =
    { messages : List Message
    , recent : List Message
    , overlayVersion : Int
    , cursor : Int
    , panel : Panel
    , polling : Bool
    , updateFailure : UpdateFailure
    , historyScroll : HistoryScroll
    }


type HistoryScroll
    = FollowingLatest
    | ReadingEarlier


{-| DOM scroll measurements in pixels.
-}
type alias ScrollPosition =
    { scrollTop : Float
    , scrollHeight : Float
    , clientHeight : Float
    }


type UpdateFailure
    = NoUpdateFailure
    | UpdateFailed String
    | UpdateFailureDismissed String


type Panel
    = Closed
    | Composing Composer
    | Background Composer


type alias Composer =
    { text : String
    , history : Bool
    , delivery : Delivery
    }


type Delivery
    = Editing
    | Sending Submission
    | SendFailed Submission String
    | Unsent Submission



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


init : List Message -> Model
init messages =
    { messages = messages
    , recent = []
    , overlayVersion = 0
    , cursor = List.maximum (List.map .sequence messages) |> Maybe.withDefault 0
    , panel = Closed
    , polling = False
    , updateFailure = NoUpdateFailure
    , historyScroll = FollowingLatest
    }


{-| A player entering the game still needs to see messages already accepted
during the lobby-to-game transition. Lobby-only history stays in the panel.
-}
initGame : List Message -> Model
initGame messages =
    let
        model : Model
        model =
            init messages

        inGame : Message -> Bool
        inGame message =
            message.turnNumber > 0

        recent : List Message
        recent =
            List.filter inGame messages |> latestMessages
    in
    { model
        | recent = recent
        , overlayVersion =
            if List.isEmpty recent then
                0

            else
                1
    }


latestMessages : List Message -> List Message
latestMessages messages =
    List.sortBy .sequence messages
        |> List.reverse
        |> List.take 3
        |> List.reverse


isOpen : Model -> Bool
isOpen model =
    case model.panel of
        Composing _ ->
            True

        _ ->
            False


open : Model -> Model
open model =
    case model.panel of
        Background composer ->
            { model
                | panel = Composing composer
                , historyScroll = FollowingLatest
            }

        Composing _ ->
            model

        Closed ->
            { model
                | panel =
                    Composing
                        { text = ""
                        , history = False
                        , delivery = Editing
                        }
                , historyScroll = FollowingLatest
            }


{-| Hide the composer while retaining its draft and delivery state for reopening.
-}
hide : Model -> Model
hide model =
    case model.panel of
        Composing composer ->
            { model | panel = Background composer }

        _ ->
            model


close : Model -> Model
close model =
    case model.panel of
        Composing composer ->
            case composer.delivery of
                Sending _ ->
                    { model | panel = Background composer }

                _ ->
                    { model | panel = Closed }

        _ ->
            model


edit : String -> Model -> Model
edit text model =
    case model.panel of
        Composing composer ->
            let
                editSubmission : Submission -> Model
                editSubmission submission =
                    let
                        delivery : Delivery
                        delivery =
                            if String.trim text == submission.text then
                                composer.delivery

                            else
                                Editing
                    in
                    { model | panel = Composing { composer | text = text, delivery = delivery } }
            in
            case composer.delivery of
                Sending _ ->
                    model

                SendFailed submission _ ->
                    editSubmission submission

                Unsent submission ->
                    editSubmission submission

                Editing ->
                    { model | panel = Composing { composer | text = text } }

        _ ->
            model


toggleHistory : Model -> Model
toggleHistory model =
    case model.panel of
        Composing composer ->
            { model
                | panel = Composing { composer | history = not composer.history }
                , historyScroll = FollowingLatest
            }

        _ ->
            model


historyOpened : Model -> Model
historyOpened model =
    { model | historyScroll = FollowingLatest }


historyVisible : Model -> Bool
historyVisible model =
    case model.panel of
        Composing composer ->
            composer.history

        _ ->
            False


followsHistory : Model -> Bool
followsHistory model =
    model.historyScroll == FollowingLatest


scrollHistory : ScrollPosition -> Model -> Model
scrollHistory position model =
    let
        scroll : HistoryScroll
        scroll =
            if position.scrollHeight - position.clientHeight - position.scrollTop <= 4 then
                FollowingLatest

            else
                ReadingEarlier
    in
    { model | historyScroll = scroll }


prepareSend : Random.Seed -> Model -> Maybe ( Model, Random.Seed, Submission )
prepareSend seed model =
    case model.panel of
        Composing composer ->
            let
                text : String
                text =
                    String.trim composer.text

                ( numbers, nextSeed ) =
                    Random.step (Random.list 4 (Random.int 0 Random.maxInt)) seed

                fresh : Submission
                fresh =
                    { id = MessageId (String.join "-" (List.map String.fromInt numbers))
                    , text = text
                    }

                begin : Submission -> Random.Seed -> Maybe ( Model, Random.Seed, Submission )
                begin submission resultingSeed =
                    Just
                        ( { model | panel = Composing { composer | delivery = Sending submission } }
                        , resultingSeed
                        , submission
                        )
            in
            if String.isEmpty text then
                Nothing

            else
                case composer.delivery of
                    Sending _ ->
                        Nothing

                    SendFailed submission _ ->
                        begin submission seed

                    Unsent submission ->
                        begin submission seed

                    Editing ->
                        begin fresh nextSeed

        _ ->
            Nothing


merge : List Message -> Model -> Model
merge incoming model =
    let
        fresh : List Message
        fresh =
            List.filter isFresh incoming

        isFresh : Message -> Bool
        isFresh message =
            not (List.any (hasSequence message.sequence) model.messages)

        hasSequence : Int -> Message -> Bool
        hasSequence sequence message =
            message.sequence == sequence

        recent : List Message
        recent =
            latestMessages (model.recent ++ fresh)
    in
    if List.isEmpty fresh then
        model

    else
        { model
            | messages = List.sortBy .sequence (model.messages ++ fresh)
            , recent = recent
            , overlayVersion = model.overlayVersion + 1
        }


{-| Only polls advance the cursor. A send response may overtake a poll and
must not skip earlier messages from the other player.
-}
receive : List Message -> Model -> Model
receive messages model =
    let
        next : Model
        next =
            merge messages model
    in
    { next
        | cursor =
            List.maximum
                (model.cursor :: List.map .sequence messages)
                |> Maybe.withDefault model.cursor
        , polling = False
        , updateFailure = NoUpdateFailure
    }


{-| Roster names are unique and stay stable when lobby sides change. A visitor
has no player number and remains a different sender even if your name is "visitor".
-}
hasNewIncoming :
    { known : List Message
    , received : List Message
    , ownNames : List String
    }
    -> Bool
hasNewIncoming batch =
    let
        incoming : Message -> Bool
        incoming message =
            let
                alreadyKnown : Bool
                alreadyKnown =
                    List.any (hasSequence message.sequence) batch.known

                fromYou : Bool
                fromYou =
                    case message.playerNumber of
                        Just _ ->
                            List.member message.sender batch.ownNames

                        Nothing ->
                            False
            in
            not (alreadyKnown || fromYou)

        hasSequence : Int -> Message -> Bool
        hasSequence sequence message =
            message.sequence == sequence
    in
    List.any incoming batch.received


beginPoll : Model -> Maybe Model
beginPoll model =
    if model.polling then
        Nothing

    else
        Just { model | polling = True }


pollFailed : String -> Model -> Model
pollFailed error model =
    let
        failure : UpdateFailure
        failure =
            case model.updateFailure of
                UpdateFailureDismissed _ ->
                    UpdateFailureDismissed error

                _ ->
                    UpdateFailed error
    in
    { model | polling = False, updateFailure = failure }


pollError : Model -> Maybe String
pollError model =
    case model.updateFailure of
        UpdateFailed error ->
            Just error

        _ ->
            Nothing


sent : Submission -> Result String Message -> Model -> Model
sent submission result model =
    let
        next : Model
        next =
            case result of
                Ok message ->
                    merge [ message ] model

                Err _ ->
                    model

        finish : (Composer -> Panel) -> Composer -> Model
        finish panel composer =
            if composer.delivery == Sending submission then
                { next
                    | panel =
                        case result of
                            Ok _ ->
                                case model.panel of
                                    Background _ ->
                                        Closed

                                    _ ->
                                        panel
                                            { composer | text = "", delivery = Editing }

                            Err error ->
                                panel
                                    { composer
                                        | delivery = SendFailed submission error
                                    }
                }

            else
                next
    in
    case model.panel of
        Composing composer ->
            finish Composing composer

        Background composer ->
            finish Background composer

        Closed ->
            next


sendError : Model -> Maybe String
sendError model =
    let
        error : Composer -> Maybe String
        error composer =
            case composer.delivery of
                SendFailed _ message ->
                    Just message

                _ ->
                    Nothing
    in
    case model.panel of
        Composing composer ->
            error composer

        Background composer ->
            error composer

        Closed ->
            Nothing


{-| Dismissing a failure hides the notification while retaining the receipt and
draft. An unchanged retry still uses the original message ID.
-}
dismissErrors : Model -> Model
dismissErrors model =
    let
        dismiss : Composer -> Composer
        dismiss composer =
            case composer.delivery of
                SendFailed submission _ ->
                    { composer | delivery = Unsent submission }

                _ ->
                    composer

        panel : Panel
        panel =
            case model.panel of
                Composing composer ->
                    Composing (dismiss composer)

                Background composer ->
                    Background (dismiss composer)

                Closed ->
                    Closed

        failure : UpdateFailure
        failure =
            case model.updateFailure of
                UpdateFailed error ->
                    UpdateFailureDismissed error

                _ ->
                    model.updateFailure
    in
    { model | panel = panel, updateFailure = failure }


expire : Int -> Model -> Model
expire version model =
    if version == model.overlayVersion then
        { model | recent = [] }

    else
        model


selection : SelectionSet Message Api.Object.ChatMessage
selection =
    SS.succeed Message
        |> SS.with MessageApi.sequence
        |> SS.with MessageApi.turnNumber
        |> SS.with MessageApi.sender
        |> SS.with MessageApi.playerNumber
        |> SS.with MessageApi.text


query : LobbyId -> Int -> SelectionSet (List Message) RootQuery
query id after =
    Api.Query.chat { id = LobbyId.toString id, after = after } selection


sendRequest : LobbyId -> Submission -> Graphql.Http.Request Message
sendRequest id submission =
    let
        (MessageId messageId) =
            submission.id
    in
    Api.Mutation.sendChat
        { input =
            Api.InputObject.buildSendChatInput
                { id = LobbyId.toString id
                , messageId = messageId
                , text = submission.text
                }
        }
        selection
        |> ApiRequest.mutationRequest
