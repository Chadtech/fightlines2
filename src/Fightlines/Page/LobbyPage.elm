module Fightlines.Page.LobbyPage exposing
    ( Flags
    , Location(..)
    , Model
    , Msg
    , currentLocation
    , init
    , listeners
    , load
    , setShared
    , subscriptions
    , update
    , view
    )

import Api.Enum.Controller
    exposing
        ( Controller(..)
        )
import Api.Enum.PlayerNumber
    exposing
        ( PlayerNumber(..)
        )
import Api.Mutation
import Api.Object
import Api.Object.PlayerView as PlayerView
import Api.Object.Snapshot as Snapshot
import Api.Query
import Api.Scalar
    exposing
        ( MapId
        )
import ApiRequest
    exposing
        ( Response
        )
import Audio
import Browser.Dom
import Browser.Events
import Deployment
import EditableMap exposing (NamedMap)
import Effect as E
    exposing
        ( Eff
        )
import Error exposing (Error(..))
import Fightlines.Route as Route
import Fightlines.View.MapChoice as MapChoice
import Game.Assets as Assets
import Game.Chat as Chat
import Game.MapId as MapId
import Game.PlayerNumber as PlayerNumber
import Game.View.Chat as ChatView
import Game.View.MapPreview as MapPreview
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Json.Decode as Decode
import LobbyId
    exposing
        ( LobbyId
        )
import NonEmptyList
import Ports.Js.From as FromJs
import Ports.Js.To as ToJs
import ScreenSize exposing (ScreenSize)
import Shared
import Style as S
import Time
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Dialog as Dialog
import View.RequestError as RequestError
import View.Select as Select
import View.Tabs as Tabs exposing (Tabs)
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { lobby : Snapshot
    , mapPreviews : List NamedMap
    , messages : List Chat.Message
    }


type alias Snapshot =
    { id : LobbyId
    , name : String
    , mapType : MapId
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    }


type alias Player =
    { name : String
    , isHost : Bool
    , controller : Controller
    , isYou : Bool
    , playerNumber : PlayerNumber
    }


type alias Model =
    { shared : Shared.Model
    , chat : Chat.Model
    , tab : LobbyTab
    , unreadChat : Bool
    , id : LobbyId
    , name : String
    , mapType : MapId
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    , mapPreviews : List NamedMap
    , screen : Screen
    , requestStatus : RequestStatus
    , refreshing : Bool
    , pollRevision : PollRevision
    , error : Maybe String
    , actionError : Maybe String
    , copyStatus : CopyStatus
    }


type Location
    = LobbySetup
    | MapLibrary


type Screen
    = Setup
    | Library LibraryState


type LobbyTab
    = PlayersTab
    | ChatTab


type alias LibraryState =
    { preview : MapId
    , search : String
    }


{-| Polls belong to the lobby settings revision at which they were requested.
A settings change invalidates older responses without blocking the controls.
-}
type PollRevision
    = PollRevision Int


{-| A pending side choice carries its displayed value, so failed requests
restore the authoritative selection.
-}
type RequestStatus
    = Idle
    | WaitingToStart
    | SavingSettings
    | SavingMap
    | ChoosingSide PlayerNumber
    | KickingPlayer String
    | ConfirmingClose
    | ClosingLobby


type CopyStatus
    = CopyIdle
    | Copying
    | Copied
    | CopyFailed


type alias CopyResult =
    { url : String
    , success : Bool
    }


type Msg
    = SideInputChanged PlayerNumber
    | LobbyTabClicked LobbyTab
    | LobbyTabNavigated LobbyTab
    | ChatMsg ChatView.Msg
    | ChatPollElapsed Time.Posix
    | ChatPollReceived (Response (List Chat.Message))
    | ChatSendReceived Chat.Submission (Response Chat.Message)
    | LobbyFocusReturned (Result Browser.Dom.Error ())
    | ChatScrollCompleted (Result Browser.Dom.Error ())
    | ControllerInputChanged Controller
    | KickPlayerButtonClicked Player
    | ChooseMapButtonClicked
    | BackToLobbyButtonClicked
    | MapPreviewClicked MapId
    | MapSearchInputChanged String
    | UseMapButtonClicked
    | MapResponseReceived (Response Snapshot)
    | CloseLobbyButtonClicked
    | CloseLobbyCanceled
    | CloseLobbyConfirmed
    | CloseLobbyResponseReceived (Response Bool)
    | CloseDialogOpened
    | CloseFocusReturned (Result Browser.Dom.Error ())
    | HomeButtonClicked
    | StartButtonClicked
    | RetryButtonClicked
    | CopyLinkButtonClicked
    | CopyLinkResultReceived CopyResult
    | CopyFeedbackElapsed
    | PollTimerElapsed Time.Posix
    | LobbyResponseReceived PollRevision (Response Snapshot)
    | ActionResponseReceived (Response Snapshot)



----------------------------------------------------------------
-- SHARED STATE --
----------------------------------------------------------------


currentLocation : Model -> Location
currentLocation model =
    case model.screen of
        Setup ->
            LobbySetup

        Library _ ->
            MapLibrary


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Location -> Shared.Model -> Flags -> ( Model, Eff Msg )
init location shared flags =
    let
        lobby : Snapshot
        lobby =
            flags.lobby

        canOpenLibrary : Bool
        canOpenLibrary =
            (location == MapLibrary) && lobby.isHost && (lobby.gameUrl == Nothing)

        mustReturnToLobby : Bool
        mustReturnToLobby =
            (location == MapLibrary) && not canOpenLibrary && (lobby.gameUrl == Nothing)

        screen : Screen
        screen =
            if canOpenLibrary then
                Library
                    { preview = lobby.mapType
                    , search = ""
                    }

            else
                Setup

        routeCorrection : Eff Msg
        routeCorrection =
            if mustReturnToLobby then
                Route.navigate shared.deployment (Route.Lobby lobby.id)

            else
                E.none

        model : Model
        model =
            { shared = shared
            , chat = Chat.init flags.messages |> Chat.open
            , tab = PlayersTab
            , unreadChat = False
            , id = lobby.id
            , name = lobby.name
            , mapType = lobby.mapType
            , screen = screen
            , mapPreviews = flags.mapPreviews
            , players = lobby.players
            , isHost = lobby.isHost
            , isMember = lobby.isMember
            , gameUrl = lobby.gameUrl
            , requestStatus = Idle
            , refreshing = False
            , pollRevision = PollRevision 0
            , error = Nothing
            , actionError = Nothing
            , copyStatus = CopyIdle
            }
    in
    ( model
    , E.batch
        [ gameNavigation shared.deployment
            { isMember = lobby.isMember
            , gameUrl = lobby.gameUrl
            }
            lobby.id
        , routeCorrection
        , scrollChatHistory model
        , preloadMapImages lobby.mapType flags.mapPreviews
        ]
    )


load : LobbyId -> Graphql.Http.Request Flags
load id =
    SS.succeed Flags
        |> SS.with (Api.Query.lobby { id = LobbyId.toString id } snapshotSelection)
        |> SS.with (Api.Query.mapPreviews EditableMap.namedSelection)
        |> SS.with (Chat.query id 0)
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setRequestStatus : RequestStatus -> Model -> Model
setRequestStatus requestStatus model =
    { model | requestStatus = requestStatus }


setActionError : Maybe String -> Model -> Model
setActionError actionError model =
    { model | actionError = actionError }


setRefreshing : Bool -> Model -> Model
setRefreshing refreshing model =
    { model | refreshing = refreshing }


setError : Maybe String -> Model -> Model
setError error model =
    { model | error = error }


setCopyStatus : CopyStatus -> Model -> Model
setCopyStatus copyStatus model =
    { model | copyStatus = copyStatus }


start : LobbyId -> Graphql.Http.Request Snapshot
start id =
    Api.Mutation.startGame { id = LobbyId.toString id } snapshotSelection
        |> ApiRequest.mutationRequest


saveMap : LobbyId -> MapId -> Graphql.Http.Request Snapshot
saveMap id mapType =
    Api.Mutation.setLobbyMap
        { id = LobbyId.toString id
        , mapType = mapType
        }
        snapshotSelection
        |> ApiRequest.mutationRequest


snapshotSelection : SelectionSet Snapshot Api.Object.Snapshot
snapshotSelection =
    SS.succeed Snapshot
        |> SS.with (Snapshot.id |> SS.mapOrFail LobbyId.parse)
        |> SS.with Snapshot.name
        |> SS.with Snapshot.mapType
        |> SS.with
            (Snapshot.players
                (SS.succeed Player
                    |> SS.with PlayerView.name
                    |> SS.with PlayerView.isHost
                    |> SS.with PlayerView.controller
                    |> SS.with PlayerView.isYou
                    |> SS.with PlayerView.playerNumber
                )
            )
        |> SS.with Snapshot.isHost
        |> SS.with Snapshot.isMember
        |> SS.with Snapshot.gameUrl


isMap : MapId -> NamedMap -> Bool
isMap mapType map =
    map.mapType == mapType


mapDimensions : NamedMap -> String
mapDimensions map =
    String.fromInt map.definition.width
        ++ " × "
        ++ String.fromInt map.definition.height


hasJoinedHuman : Model -> Bool
hasJoinedHuman model =
    let
        isJoinedHuman : Player -> Bool
        isJoinedHuman player =
            not player.isHost && (player.controller == Human)
    in
    List.any isJoinedHuman model.players


canManageLobby : Model -> Bool
canManageLobby model =
    not (isBusy model) && model.isHost && (model.gameUrl == Nothing)


startGameBlockedReason : Model -> Maybe String
startGameBlockedReason model =
    if model.gameUrl /= Nothing then
        Just "this game has started. joining is closed."

    else if not model.isHost then
        Just "waiting for the host to start the game…"

    else if List.length model.players < 2 then
        Just "waiting for another player"

    else if List.length model.players /= 2 then
        Just "this game requires exactly two players"

    else if isBusy model then
        Just "waiting for the current request to finish…"

    else
        Nothing


startGame : Model -> ( Model, Eff Msg )
startGame model =
    if startGameBlockedReason model /= Nothing then
        ( model, E.none )

    else if model.refreshing then
        ( model
            |> setRequestStatus WaitingToStart
            |> setActionError Nothing
        , E.none
        )

    else
        ( model
            |> setRequestStatus SavingSettings
            |> setActionError Nothing
        , E.request ActionResponseReceived (start model.id)
        )


finishRefresh : Model -> Model
finishRefresh model =
    let
        requestStatus : RequestStatus
        requestStatus =
            if model.requestStatus == WaitingToStart then
                Idle

            else
                model.requestStatus
    in
    model
        |> setRefreshing False
        |> setRequestStatus requestStatus


receiveRefresh : Snapshot -> Model -> ( Model, Eff Msg )
receiveRefresh snapshot model =
    let
        received : ( Model, Eff Msg )
        received =
            model
                |> finishRefresh
                |> receive snapshot
    in
    if model.requestStatus == WaitingToStart then
        received |> E.andThen startGame

    else
        received


isBusy : Model -> Bool
isBusy model =
    model.requestStatus /= Idle


beginSettingsChange : Model -> Model
beginSettingsChange model =
    let
        nextRevision : PollRevision -> PollRevision
        nextRevision (PollRevision revision) =
            PollRevision (revision + 1)
    in
    { model | pollRevision = nextRevision model.pollRevision }
        |> setRequestStatus SavingSettings
        |> setActionError Nothing
        |> setRefreshing False


refresh : Model -> ( Model, Eff Msg )
refresh model =
    if model.refreshing || isBusy model then
        ( model, E.none )

    else
        ( model
            |> setRefreshing True
        , E.request (LobbyResponseReceived model.pollRevision)
            (Api.Query.lobby
                { id = LobbyId.toString model.id
                }
                snapshotSelection
                |> ApiRequest.queryRequest
            )
        )


preloadMapImages : MapId -> List NamedMap -> Eff msg
preloadMapImages mapType previews =
    case List.filter (isMap mapType) previews |> List.head of
        Just preview ->
            E.toJs (ToJs.PreloadImages (Assets.imagePaths preview.definition.theme))

        Nothing ->
            E.none


receive : Snapshot -> Model -> ( Model, Eff Msg )
receive snapshot model =
    let
        rosterAudio : Audio.Event
        rosterAudio =
            if (model.gameUrl /= Nothing) || (snapshot.gameUrl /= Nothing) then
                Audio.none

            else if List.length snapshot.players > List.length model.players then
                Audio.lobbyPlayerJoined

            else if List.length snapshot.players < List.length model.players then
                Audio.lobbyPlayerLeft

            else
                Audio.none

        membershipNavigation : Eff Msg
        membershipNavigation =
            if model.isMember && not snapshot.isMember then
                Route.navigate model.shared.deployment
                    (Route.Lobby snapshot.id)

            else
                E.none

        preload : Eff Msg
        preload =
            if snapshot.mapType /= model.mapType then
                preloadMapImages snapshot.mapType model.mapPreviews

            else
                E.none
    in
    ( { model | id = snapshot.id, name = snapshot.name, mapType = snapshot.mapType, players = snapshot.players, isHost = snapshot.isHost, isMember = snapshot.isMember, gameUrl = snapshot.gameUrl }
        |> setError Nothing
    , E.batch
        [ gameNavigation model.shared.deployment
            { isMember = snapshot.isMember
            , gameUrl = snapshot.gameUrl
            }
            snapshot.id
        , membershipNavigation
        , preload
        , E.audio rosterAudio
        ]
    )


gameNavigation :
    Deployment.Model
    -> { isMember : Bool, gameUrl : Maybe String }
    -> LobbyId
    -> Eff msg
gameNavigation deployment args lobbyId =
    if args.isMember && args.gameUrl /= Nothing then
        Route.navigate deployment (Route.Game lobbyId)

    else
        E.none


inviteUrl : Model -> String
inviteUrl model =
    model.shared.origin ++ Route.toString (Route.Lobby model.id)


applyChatUpdate : Chat.Model -> Model -> ( Model, Eff Msg )
applyChatUpdate chat model =
    let
        next : Model
        next =
            { model | chat = chat }

        scroll : Eff Msg
        scroll =
            if chat.overlayVersion /= model.chat.overlayVersion then
                scrollChatHistory next

            else
                E.none
    in
    ( next, scroll )


lobbyUsesTabs : Model -> Bool
lobbyUsesTabs model =
    let
        size : ScreenSize
        size =
            model.shared.screenSize
    in
    (size.width > size.height) && (size.height <= 500) && (size.width <= 1023)


chatVisible : Model -> Bool
chatVisible model =
    (model.screen == Setup) && (not (lobbyUsesTabs model) || (model.tab == ChatTab))


lobbyTabHtmlId : LobbyTab -> String
lobbyTabHtmlId tab =
    case tab of
        PlayersTab ->
            "lobby-players-tab"

        ChatTab ->
            "lobby-chat-tab"


selectLobbyTab : LobbyTab -> Model -> ( Model, Eff Msg )
selectLobbyTab tab model =
    case tab of
        PlayersTab ->
            { model | tab = PlayersTab }
                |> E.withOut

        ChatTab ->
            let
                next : Model
                next =
                    { model
                        | tab = ChatTab
                        , unreadChat = False
                    }
            in
            ( next, scrollChatHistory next )


scrollChatHistory : Model -> Eff Msg
scrollChatHistory model =
    if chatVisible model && Chat.followsHistory model.chat then
        E.scrollToBottom { htmlId = ChatView.messagesHtmlId } ChatScrollCompleted

    else
        E.none


openChat : Model -> ( Model, Eff Msg )
openChat model =
    if (model.screen == Setup) && not model.shared.devPanelOpen then
        let
            selected : ( Model, Eff Msg )
            selected =
                if lobbyUsesTabs model then
                    selectLobbyTab ChatTab model

                else
                    ( model, E.none )
        in
        selected
            |> E.and
                (E.focus
                    { htmlId = ChatView.inputHtmlId }
                    LobbyFocusReturned
                )

    else
        model
            |> E.withOut


handleChatMsg : ChatView.Msg -> Model -> ( Model, Eff Msg )
handleChatMsg msg model =
    case msg of
        ChatView.OpenPressed ->
            openChat model

        ChatView.CloseClicked ->
            model
                |> E.withOut

        ChatView.TextChanged text ->
            { model | chat = Chat.edit text model.chat }
                |> E.withOut

        ChatView.HistoryClicked ->
            model
                |> E.withOut

        ChatView.DialogOpened ->
            model
                |> E.withOut

        ChatView.HistoryScrolled position ->
            { model | chat = Chat.scrollHistory position model.chat }
                |> E.withOut

        ChatView.SendPressed ->
            sendChat model

        ChatView.RetrySendPressed ->
            sendChat model

        ChatView.RetryUpdatesPressed ->
            pollChat model

        ChatView.DismissErrorClicked ->
            openChat { model | chat = Chat.dismissErrors model.chat }


sendChat : Model -> ( Model, Eff Msg )
sendChat model =
    case Chat.prepareSend model.shared.seed model.chat of
        Just ( chat, seed, submission ) ->
            ( { model | chat = chat }
                |> setShared (Shared.setSeed seed model.shared)
            , E.batch
                [ E.request (ChatSendReceived submission) (Chat.sendRequest model.id submission)
                , E.audio Audio.chatSent
                ]
            )

        Nothing ->
            model
                |> E.withOut


pollChat : Model -> ( Model, Eff Msg )
pollChat model =
    case Chat.beginPoll model.chat of
        Nothing ->
            model
                |> E.withOut

        Just chat ->
            ( { model | chat = chat }
            , Chat.query model.id chat.cursor
                |> ApiRequest.queryRequest
                |> E.request ChatPollReceived
            )



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        LobbyTabClicked tab ->
            selectLobbyTab tab model

        LobbyTabNavigated tab ->
            selectLobbyTab tab model
                |> E.and
                    (E.focus
                        { htmlId = lobbyTabHtmlId tab }
                        LobbyFocusReturned
                    )

        ChatMsg chatMsg ->
            handleChatMsg chatMsg model

        ChatPollElapsed _ ->
            pollChat model

        ChatPollReceived result ->
            case result of
                Ok messages ->
                    let
                        incoming : Bool
                        incoming =
                            Chat.hasNewIncoming
                                { known = model.chat.messages
                                , received = messages
                                , ownNames =
                                    model.players
                                        |> List.filter .isYou
                                        |> List.map .name
                                }

                        notification : Eff Msg
                        notification =
                            if incoming then
                                E.audio Audio.chatReceived

                            else
                                E.none
                    in
                    { model
                        | unreadChat =
                            not (chatVisible model)
                                && (incoming || model.unreadChat)
                    }
                        |> applyChatUpdate (Chat.receive messages model.chat)
                        |> E.and notification

                Err error ->
                    { model | chat = Chat.pollFailed (ApiRequest.errorMessage error) model.chat }
                        |> E.withOut

        ChatSendReceived submission result ->
            let
                chat : Chat.Model
                chat =
                    Chat.sent
                        submission
                        (Result.mapError ApiRequest.errorMessage result)
                        model.chat

                focus : Eff Msg
                focus =
                    if chatVisible model && Chat.isOpen chat && not (isBusy model) then
                        E.focus { htmlId = ChatView.inputHtmlId } LobbyFocusReturned

                    else
                        E.none
            in
            model
                |> applyChatUpdate chat
                |> E.and focus

        ChatScrollCompleted result ->
            case result of
                Err error ->
                    if model.screen == Setup then
                        model
                            |> setShared (Shared.addError (Just (ElementScrollFailed error)) model.shared)
                            |> E.withOut

                    else
                        model
                            |> E.withOut

                Ok () ->
                    model
                        |> E.withOut

        LobbyFocusReturned result ->
            case result of
                Ok _ ->
                    model
                        |> E.withOut

                Err error ->
                    model
                        |> setShared (Shared.addError (Just (ElementFocusFailed error)) model.shared)
                        |> E.withOut

        SideInputChanged playerNumber ->
            let
                canChooseSide : Bool
                canChooseSide =
                    not (isBusy model)
                        && model.isMember
                        && (model.gameUrl == Nothing)
                        && List.any .isYou model.players

                isSelectedSide : Player -> Bool
                isSelectedSide player =
                    player.isYou && (player.playerNumber == playerNumber)

                alreadySelected : Bool
                alreadySelected =
                    List.any isSelectedSide model.players
            in
            if not canChooseSide || alreadySelected then
                ( model, E.none )

            else
                let
                    updatedModel : Model
                    updatedModel =
                        beginSettingsChange model
                in
                ( updatedModel
                    |> setRequestStatus (ChoosingSide playerNumber)
                , Api.Mutation.setLobbySide
                    { id = LobbyId.toString model.id
                    , playerNumber = playerNumber
                    }
                    snapshotSelection
                    |> ApiRequest.mutationRequest
                    |> E.request ActionResponseReceived
                )

        ControllerInputChanged controller ->
            let
                canChangeController : Bool
                canChangeController =
                    not (isBusy model)
                        && model.isHost
                        && (model.gameUrl == Nothing)
                        && not (hasJoinedHuman model)
            in
            if not canChangeController then
                ( model, E.none )

            else
                ( beginSettingsChange model
                , Api.Mutation.setLobbyController
                    { id = LobbyId.toString model.id
                    , controller = controller
                    }
                    snapshotSelection
                    |> ApiRequest.mutationRequest
                    |> E.request ActionResponseReceived
                )

        KickPlayerButtonClicked player ->
            if not (canManageLobby model) || player.isHost || (player.controller /= Human) then
                ( model, E.none )

            else
                ( beginSettingsChange model
                    |> setRequestStatus (KickingPlayer player.name)
                , Api.Mutation.kickLobbyPlayer
                    { id = LobbyId.toString model.id
                    , name = player.name
                    }
                    snapshotSelection
                    |> ApiRequest.mutationRequest
                    |> E.request ActionResponseReceived
                )

        ChooseMapButtonClicked ->
            if not (canManageLobby model) then
                ( model, E.none )

            else
                ( model
                , Route.navigate model.shared.deployment
                    (Route.LobbyMaps model.id)
                )

        BackToLobbyButtonClicked ->
            ( model
            , Route.navigate model.shared.deployment (Route.Lobby model.id)
            )

        MapSearchInputChanged search ->
            case model.screen of
                Library library ->
                    ( { model | screen = Library { library | search = search } }
                    , E.none
                    )

                Setup ->
                    ( model, E.none )

        MapPreviewClicked mapType ->
            case model.screen of
                Library library ->
                    if List.any (isMap mapType) model.mapPreviews then
                        ( { model
                            | screen =
                                Library
                                    { library
                                        | preview = mapType
                                    }
                          }
                        , E.none
                        )

                    else
                        ( model, E.none )

                Setup ->
                    ( model, E.none )

        UseMapButtonClicked ->
            case model.screen of
                Library library ->
                    if not (canManageLobby model) then
                        ( model, E.none )

                    else
                        let
                            updatedModel : Model
                            updatedModel =
                                beginSettingsChange model
                        in
                        ( updatedModel
                            |> setRequestStatus SavingMap
                        , E.request MapResponseReceived (saveMap model.id library.preview)
                        )

                Setup ->
                    ( model, E.none )

        MapResponseReceived result ->
            if model.requestStatus /= SavingMap then
                ( model, E.none )

            else
                case result of
                    Ok snapshot ->
                        let
                            returnToLobby : Eff Msg
                            returnToLobby =
                                if snapshot.gameUrl == Nothing then
                                    Route.navigate model.shared.deployment
                                        (Route.Lobby model.id)

                                else
                                    E.none
                        in
                        (model
                            |> setRequestStatus Idle
                            |> setActionError Nothing
                        )
                            |> receive snapshot
                            |> E.and returnToLobby

                    Err error ->
                        ( model
                            |> setRequestStatus Idle
                            |> setActionError (Just (ApiRequest.errorMessage error))
                        , E.none
                        )

        HomeButtonClicked ->
            ( model, Route.navigate model.shared.deployment Route.Home )

        CloseLobbyButtonClicked ->
            if not (canManageLobby model) then
                ( model, E.none )

            else
                ( beginSettingsChange model
                    |> setRequestStatus ConfirmingClose
                , E.toJs (ToJs.OpenDialog { htmlId = closeDialogHtmlId })
                )

        CloseDialogOpened ->
            ( model, E.focus { htmlId = closeCancelButtonHtmlId } CloseFocusReturned )

        CloseLobbyCanceled ->
            if model.requestStatus /= ConfirmingClose then
                ( model, E.none )

            else
                ( model
                    |> setRequestStatus Idle
                    |> setActionError Nothing
                , E.focus { htmlId = closeButtonHtmlId } CloseFocusReturned
                )

        CloseFocusReturned result ->
            case result of
                Ok () ->
                    ( model, E.none )

                Err error ->
                    ( model
                        |> setShared (Shared.addError (Just (ElementFocusFailed error)) model.shared)
                    , E.none
                    )

        CloseLobbyConfirmed ->
            if model.requestStatus /= ConfirmingClose then
                ( model, E.none )

            else
                ( model
                    |> setRequestStatus ClosingLobby
                    |> setActionError Nothing
                , Api.Mutation.closeLobby { id = LobbyId.toString model.id }
                    |> ApiRequest.mutationRequest
                    |> E.request CloseLobbyResponseReceived
                )

        CloseLobbyResponseReceived result ->
            if model.requestStatus /= ClosingLobby then
                ( model, E.none )

            else
                case result of
                    Ok _ ->
                        ( model
                        , Route.navigate model.shared.deployment Route.Home
                        )

                    Err error ->
                        ( model
                            |> setRequestStatus ConfirmingClose
                            |> setActionError (Just (ApiRequest.errorMessage error))
                        , E.none
                        )

        StartButtonClicked ->
            startGame model

        RetryButtonClicked ->
            refresh model

        CopyLinkButtonClicked ->
            if model.copyStatus == Copying || model.copyStatus == Copied then
                ( model, E.none )

            else
                ( model
                    |> setCopyStatus Copying
                , E.toJs (ToJs.CopyLink { url = inviteUrl model })
                )

        CopyLinkResultReceived result ->
            if result.url /= inviteUrl model || model.copyStatus /= Copying then
                ( model, E.none )

            else if result.success then
                ( model
                    |> setCopyStatus Copied
                , E.after 2000 CopyFeedbackElapsed
                )

            else
                ( model
                    |> setCopyStatus CopyFailed
                , E.none
                )

        CopyFeedbackElapsed ->
            ( model
                |> setCopyStatus CopyIdle
            , E.none
            )

        PollTimerElapsed _ ->
            refresh model

        LobbyResponseReceived pollRevision result ->
            if pollRevision /= model.pollRevision then
                ( model, E.none )

            else
                case result of
                    Ok snapshot ->
                        receiveRefresh snapshot model

                    Err error ->
                        (model
                            |> finishRefresh
                            |> setError (Just (ApiRequest.errorMessage error))
                        )
                            |> E.withOut

        ActionResponseReceived result ->
            case result of
                Ok snapshot ->
                    (model
                        |> setRequestStatus Idle
                        |> setActionError Nothing
                    )
                        |> receive snapshot

                Err error ->
                    ( model
                        |> setRequestStatus Idle
                        |> setActionError (Just (ApiRequest.errorMessage error))
                    , E.none
                    )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    let
        notification : List (Html Msg)
        notification =
            ChatView.notification model.chat
                |> Maybe.map (H.map ChatMsg >> RequestError.toast)
                |> Maybe.map List.singleton
                |> Maybe.withDefault []

        dialog : List (Html Msg)
        dialog =
            [ closeDialogView model ]
    in
    pageView model ++ notification ++ dialog


pageView : Model -> List (Html Msg)
pageView model =
    let
        content : List (Html Msg)
        content =
            case model.screen of
                Setup ->
                    lobbyView model

                Library library ->
                    [ H.div
                        [ A.css
                            [ S.pt12
                            , S.flex1
                            , S.minH0
                            , S.col
                            , S.shortLandscape
                                [ S.pt4
                                ]
                            , S.belowWidth 400
                                [ S.pt16
                                ]
                            ]
                        ]
                        [ libraryView model library
                        ]
                    ]
    in
    [ H.div
        [ A.css
            [ S.fixed
            , S.inset0
            , S.p4
            , S.col
            , S.g4
            , S.wFull
            , S.minH0
            , S.overflowHidden
            , S.shortLandscape
                [ S.g1
                , S.pb2
                ]
            ]
        ]
        content
    ]


libraryView : Model -> LibraryState -> Html Msg
libraryView model library =
    let
        search : String
        search =
            String.trim library.search |> String.toLower

        matchesSearch : NamedMap -> Bool
        matchesSearch map =
            String.contains search
                (String.toLower (MapId.label map.mapType ++ " " ++ map.definition.description))

        matchingMaps : List NamedMap
        matchingMaps =
            List.filter matchesSearch model.mapPreviews

        choices : List (Html Msg)
        choices =
            if List.isEmpty matchingMaps then
                [ H.p
                    [ Aria.role Aria.Status
                    , A.css
                        [ S.p2
                        ]
                    ]
                    [ H.text "no maps match your search."
                    ]
                ]

            else
                List.map choice matchingMaps

        choice : NamedMap -> Html Msg
        choice map =
            MapChoice.toHtml
                { map = map
                , selected = map.mapType == library.preview
                , onSelect = MapPreviewClicked map.mapType
                }

        preview : Html Msg
        preview =
            case List.filter (isMap library.preview) model.mapPreviews |> List.head of
                Just map ->
                    mapDetailsView map

                Nothing ->
                    H.p
                        [ Aria.role Aria.Alert
                        ]
                        [ H.text "this map preview is unavailable. choose another map."
                        ]

        saveFeedback : Maybe String
        saveFeedback =
            if model.requestStatus == SavingMap then
                Just "saving…"

            else
                Nothing

        actionError : Html Msg
        actionError =
            case model.actionError of
                Just error ->
                    H.p
                        [ Aria.role Aria.Alert
                        ]
                        [ H.text error
                        ]

                Nothing ->
                    H.text ""

        pollError : Html Msg
        pollError =
            case model.error of
                Just error ->
                    H.div
                        [ A.css
                            [ S.col
                            , S.g2
                            ]
                        ]
                        [ H.p
                            [ Aria.role Aria.Status
                            ]
                            [ H.text error
                            ]
                        , Button.secondary "retry" RetryButtonClicked
                            |> Button.toHtml
                        ]

                Nothing ->
                    H.text ""
    in
    Card.toHtml
        (Card.panel
            |> Card.withHeader
                (CardHeader.simple "choose map"
                    |> CardHeader.withCaption model.name
                )
        )
        [ H.div
            [ A.css
                [ S.row
                , S.g4
                , S.flex1
                , S.minH0
                , S.belowWidthExceptShortLandscape 720
                    [ S.col
                    , S.overflowAuto
                    ]
                , S.shortLandscape
                    [ S.row
                    , S.g2
                    ]
                ]
            ]
            [ H.div
                [ A.css
                    [ S.w72
                    , S.maxWFull
                    , S.shrink0
                    , S.col
                    , S.g3
                    , S.minH0
                    , S.belowWidthExceptShortLandscape 720
                        [ S.wFull
                        , S.h48
                        ]
                    , S.shortLandscape
                        [ S.w40Pct
                        , S.hAuto
                        , S.g2
                        ]
                    ]
                ]
                [ H.label
                    [ A.css
                        [ S.col
                        , S.shrink0
                        , S.g1
                        ]
                    ]
                    [ H.text "search maps"
                    , TextField.simple library.search MapSearchInputChanged
                        |> TextField.toHtml
                    ]
                , H.div
                    [ A.css
                        [ S.col
                        , S.bgNightwood3
                        , S.indentStrong
                        , S.p2px
                        , S.flex1
                        , S.minH0
                        , S.overflowAuto
                        ]
                    ]
                    choices
                ]
            , H.div
                [ A.css
                    [ S.flex1
                    , S.minW0
                    , S.wFull
                    , S.minH0
                    , S.col
                    , S.belowWidthExceptShortLandscape 720
                        [ S.minH76
                        , S.shrink0
                        ]
                    , S.shortLandscape
                        [ S.minH0
                        , S.wAuto
                        ]
                    ]
                ]
                [ preview
                ]
            ]
        , pollError
        , actionError
        , H.div
            [ A.css
                [ S.row
                , S.itemsCenter
                , S.flexWrap
                , S.g3
                , S.pt3
                , S.shrink0
                ]
            ]
            [ H.fieldset
                [ A.disabled (isBusy model || not model.isHost || (model.gameUrl /= Nothing))
                , A.css
                    [ S.border0
                    ]
                ]
                [ Button.primary "use this map" UseMapButtonClicked
                    |> Button.withFeedback saveFeedback
                    |> Button.toHtml
                ]
            , Button.secondary "back to lobby" BackToLobbyButtonClicked
                |> Button.toHtml
            ]
        ]


mapDetailsView : NamedMap -> Html Msg
mapDetailsView map =
    H.section
        [ Aria.label "map details"
        , A.css
            [ S.grid
            , S.gridColumns "minmax(0, 1.2fr) minmax(0, 1fr)"
            , S.g4
            , S.flex1
            , S.minH0
            , S.belowWidthExceptShortLandscape 1100
                [ S.gridCols1
                , S.gridRows "minmax(0, 1.2fr) minmax(0, 1fr)"
                ]
            , S.shortLandscape
                [ S.gridCols2
                , S.gridRows "minmax(0, 1fr)"
                , S.g2
                ]
            ]
        ]
        [ fittedMapView map
        , H.div
            [ A.css
                [ S.col
                , S.g3
                , S.minW0
                , S.minH0
                , S.overflowAuto
                ]
            ]
            [ H.h2
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text (MapId.label map.mapType)
                ]
            , H.p
                [ A.css
                    [ S.textGray4
                    ]
                ]
                [ H.text (mapDimensions map)
                ]
            , H.p
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.flexWrap
                    , S.g2
                    , S.textGray4
                    ]
                ]
                [ H.text "starting forces:"
                , H.span
                    [ A.css
                        [ S.textRed1
                        ]
                    ]
                    [ H.text "player 1 (red)"
                    ]
                , H.span
                    [ A.css
                        [ S.textBlue1
                        ]
                    ]
                    [ H.text "player 2 (blue)"
                    ]
                ]
            , H.p
                [ A.css
                    [ S.borderT
                    , S.borderGray2
                    , S.pt3
                    , S.textGray5
                    ]
                ]
                [ H.text map.definition.description
                ]
            ]
        ]


lobbyView : Model -> List (Html Msg)
lobbyView model =
    [ lobbyHeaderView model.name
    , H.div
        [ A.css
            [ S.grid
            , S.gridCols2
            , S.g4
            , S.wFull
            , S.flex1
            , S.minH0
            , S.belowWidthExceptShortLandscape 720
                [ S.col
                , S.overflowAuto
                ]
            , S.shortLandscape
                [ S.grid
                , S.gridRows "minmax(0, 1fr)"
                , S.g2
                ]
            ]
        ]
        [ H.div
            [ A.css
                [ S.col
                , S.minW0
                , S.minH0
                , S.belowWidthExceptShortLandscape 720
                    [ S.h80
                    , S.shrink0
                    ]
                , S.shortLandscape
                    [ S.hAuto
                    , S.overflowAuto
                    ]
                ]
            ]
            [ H.div
                [ A.css
                    [ S.flex1
                    , S.minH0
                    , S.col
                    , S.shortLandscape
                        [ S.minH48
                        ]
                    ]
                ]
                [ mapView model ]
            ]
        , lobbySideView model
        ]
    , H.div
        [ A.css
            [ S.shrink0
            ]
        ]
        [ lobbyActionsView model
        ]
    ]


lobbySideView : Model -> Html Msg
lobbySideView model =
    if lobbyUsesTabs model then
        lobbyTabsView model

    else
        H.div
            [ A.css
                [ S.minW0
                , S.minH0
                , S.grid
                , S.gridRows "minmax(0, auto) minmax(9rem, 1fr)"
                , S.g4
                , S.belowWidthExceptShortLandscape 720
                    [ S.gridRows "auto 16rem"
                    , S.shrink0
                    ]
                ]
            ]
            [ H.div
                [ A.css
                    [ S.minH0
                    , S.overflowAuto
                    ]
                ]
                [ playersView model
                ]
            , ChatView.lobbyPanel model.chat |> H.map ChatMsg
            ]


lobbyTabsView : Model -> Html Msg
lobbyTabsView model =
    let
        chatLabel : String
        chatLabel =
            if model.unreadChat then
                "chat •"

            else
                "chat"

        lobbyTabs : Tabs LobbyTab Msg
        lobbyTabs =
            Tabs.new
                { label = "lobby"
                , selected = model.tab
                , options =
                    NonEmptyList.fromCons
                        { value = PlayersTab, label = "players" }
                        [ { value = ChatTab, label = chatLabel }
                        ]
                , htmlId = lobbyTabHtmlId
                , onClick = LobbyTabClicked
                , onNavigate = LobbyTabNavigated
                }
                |> Tabs.horizontal

        tabs : Tabs LobbyTab Msg
        tabs =
            if model.unreadChat then
                lobbyTabs
                    |> Tabs.withAccessibleLabel ChatTab "chat, unread messages"

            else
                lobbyTabs
    in
    H.article
        [ A.css
            [ S.minW0
            , S.minH0
            , S.grid
            , S.gridRows "auto minmax(0, 1fr)"
            , S.bgGray1
            , S.outdent
            , S.overflowHidden
            ]
        ]
        [ Tabs.toHeader tabs
        , Tabs.panel tabs
            PlayersTab
            [ H.div
                [ A.css
                    [ S.hFull
                    , S.col
                    , S.g2
                    , S.p2
                    , S.overflowAuto
                    ]
                ]
                (playersContent model)
            ]
        , Tabs.panel tabs
            ChatTab
            [ ChatView.lobbyTab model.chat |> H.map ChatMsg
            ]
        ]


lobbyHeaderView : String -> Html Msg
lobbyHeaderView name =
    H.div
        [ A.css
            [ S.row
            , S.justifyCenter
            , S.itemsStart
            , S.mtNeg4
            , S.minH14
            , S.shrink0
            , S.belowWidth 400
                [ S.minH16
                ]
            , S.shortLandscape
                [ S.minH0
                ]
            ]
        ]
        [ H.header
            [ A.css
                [ S.bgGray1
                , S.outdent
                , S.row
                , S.itemsCenter
                , S.g3
                , S.px3
                , S.py2
                , S.maxWViewportInsetRem 7
                ]
            ]
            [ H.img
                [ A.src "assets/fightlines-logo-v1.png"
                , A.alt "fightlines"
                , A.css
                    [ S.w16
                    , S.hAuto
                    , S.shrink0
                    ]
                ]
                []
            , H.h1
                [ A.css
                    [ S.textGray5
                    , S.wrapAnywhere
                    , S.minW0
                    ]
                ]
                [ H.text name
                ]
            ]
        ]


lobbyActionsView : Model -> Html Msg
lobbyActionsView model =
    let
        notice : String
        notice =
            [ model.error
            , model.actionError
            ]
                |> List.filterMap identity
                |> String.join " "
                |> String.trim

        errorNotice : Html Msg
        errorNotice =
            if String.isEmpty notice then
                H.text ""

            else
                H.p
                    [ Aria.role Aria.Status
                    ]
                    [ H.text notice
                    ]

        retryControl : Html Msg
        retryControl =
            case model.error of
                Just _ ->
                    H.fieldset
                        [ A.disabled (isBusy model || model.refreshing)
                        , A.css
                            [ S.border0
                            ]
                        ]
                        [ Button.secondary "retry" RetryButtonClicked
                            |> Button.toHtml
                        ]

                Nothing ->
                    H.text ""
    in
    [ H.div
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.justifySpaceBetween
            , S.flexWrap
            , S.g3
            ]
        ]
        [ startControlsView model
        , closeLobbyControlView model
        ]
    , errorNotice
    , retryControl
    ]
        |> Card.toHtml Card.simple


closeButtonHtmlId : String
closeButtonHtmlId =
    "close-lobby"


closeCancelButtonHtmlId : String
closeCancelButtonHtmlId =
    "cancel-close-lobby"


closeDialogHtmlId : String
closeDialogHtmlId =
    "close-lobby-dialog"


closeLobbyControlView : Model -> Html Msg
closeLobbyControlView model =
    let
        closeControl : Html Msg
        closeControl =
            if model.isHost && (model.gameUrl == Nothing) then
                H.fieldset
                    [ A.disabled (isBusy model)
                    , A.css
                        [ S.border0
                        ]
                    ]
                    [ Button.danger "close lobby" CloseLobbyButtonClicked
                        |> Button.withHtmlId closeButtonHtmlId
                        |> Button.toHtml
                    ]

            else
                H.text ""
    in
    H.div
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.flexWrap
            , S.g3
            ]
        ]
        [ Button.secondary "home" HomeButtonClicked
            |> Button.toHtml
        , closeControl
        ]


closeDialogView : Model -> Html Msg
closeDialogView model =
    let
        isOpen : Bool
        isOpen =
            (model.requestStatus == ConfirmingClose) || (model.requestStatus == ClosingLobby)

        errorNotice : Html Msg
        errorNotice =
            case model.actionError of
                Just error ->
                    H.p
                        [ Aria.role Aria.Alert
                        ]
                        [ H.text error
                        ]

                Nothing ->
                    H.text ""
    in
    if isOpen then
        Dialog.make closeDialogHtmlId
            "close lobby?"
            CloseLobbyCanceled
            [ H.p
                []
                [ H.text "this closes the lobby for everyone. the invite link will stop working."
                ]
            , errorNotice
            , H.fieldset
                [ A.disabled (model.requestStatus == ClosingLobby)
                , A.css
                    [ S.border0
                    , S.row
                    , S.flexWrap
                    , S.g3
                    ]
                ]
                [ Button.secondary "cancel" CloseLobbyCanceled
                    |> Button.withHtmlId closeCancelButtonHtmlId
                    |> Button.toHtml
                , Button.danger "close lobby" CloseLobbyConfirmed
                    |> Button.toHtml
                ]
            ]
            |> Dialog.withCloseButton
            |> Dialog.onOpened CloseDialogOpened
            |> Dialog.toHtml

    else
        H.text ""


inviteView : Model -> Html Msg
inviteView model =
    let
        copyFeedback : Maybe String
        copyFeedback =
            case model.copyStatus of
                Copied ->
                    Just "copied"

                _ ->
                    Nothing

        copyFallback : Html Msg
        copyFallback =
            case model.copyStatus of
                CopyFailed ->
                    H.div
                        [ A.css
                            [ S.col
                            , S.g2
                            ]
                        ]
                        [ H.p
                            [ Aria.role Aria.Alert
                            ]
                            [ H.text "could not copy. select the link and copy it manually."
                            ]
                        , H.input
                            [ A.type_ "text"
                            , A.value (inviteUrl model)
                            , A.readonly True
                            , Aria.label "invite link"
                            , A.css
                                [ S.wFull
                                , S.minW0
                                , S.p2
                                , S.indentStrong
                                , S.bgNightwood3
                                , S.textGray5
                                ]
                            ]
                            []
                        ]

                _ ->
                    H.text ""
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            , S.borderT
            , S.borderGray2
            , S.pt3
            ]
        ]
        [ H.fieldset
            [ A.disabled (model.copyStatus == Copying || model.copyStatus == Copied)
            , A.css
                [ S.border0
                ]
            ]
            [ Button.secondary "copy invite link" CopyLinkButtonClicked
                |> Button.withFeedback copyFeedback
                |> Button.toHtml
            ]
        , copyFallback
        ]


mapView : Model -> Html Msg
mapView model =
    let
        chooseButton : Html Msg
        chooseButton =
            if model.isHost && (model.gameUrl == Nothing) then
                H.fieldset
                    [ A.disabled (isBusy model)
                    , A.css
                        [ S.border0
                        ]
                    ]
                    [ Button.secondary "choose map" ChooseMapButtonClicked
                        |> Button.toHtml
                    ]

            else
                H.text ""
    in
    case List.filter (isMap model.mapType) model.mapPreviews |> List.head of
        Just map ->
            [ fittedMapView map
            , H.div
                [ A.css
                    [ S.row
                    , S.justifySpaceBetween
                    , S.itemsCenter
                    , S.flexWrap
                    , S.g3
                    , S.shrink0
                    ]
                ]
                [ H.div
                    [ A.css
                        [ S.col
                        , S.g1
                        , S.minW0
                        , S.wrapAnywhere
                        ]
                    ]
                    [ H.h2
                        [ A.css
                            [ S.textGray5
                            ]
                        ]
                        [ H.text (MapId.label model.mapType)
                        ]
                    , H.p
                        []
                        [ H.text (mapDimensions map)
                        ]
                    ]
                , chooseButton
                ]
            ]
                |> Card.toHtml
                    (Card.panel
                        |> Card.withHeader (CardHeader.simple "battlefield")
                    )

        Nothing ->
            H.p
                []
                [ H.text "map preview unavailable."
                ]


fittedMapView : NamedMap -> Html Msg
fittedMapView map =
    H.div
        [ A.css
            [ S.flex1
            , S.minW0
            , S.minH0
            , S.containerSize
            , S.row
            , S.itemsCenter
            , S.justifyCenter
            ]
        ]
        [ H.div
            [ A.css
                [ S.fitWithinContainer
                    { width = map.definition.width
                    , height = map.definition.height
                    }
                , S.aspectRatio
                    { width = map.definition.width
                    , height = map.definition.height
                    }
                , S.bgNightwood2
                , S.indentStrong
                ]
            ]
            [ MapPreview.toHtml map
            ]
        ]


controllerLabel : Controller -> String
controllerLabel controller =
    case controller of
        Human ->
            "human"

        Ai ->
            "ai"


startControlsView : Model -> Html Msg
startControlsView model =
    let
        blockedReason : Maybe String
        blockedReason =
            startGameBlockedReason model

        startControl : Button.Button Msg
        startControl =
            case blockedReason of
                Nothing ->
                    Button.primary "start game" StartButtonClicked

                Just reason ->
                    Button.disabled "start game"
                        |> Button.accessibleLabel ("start game: " ++ reason)

        startButton : Html Msg
        startButton =
            if model.isHost && (model.gameUrl == Nothing) then
                startControl
                    |> Button.toHtml

            else
                H.text ""

        status : Html Msg
        status =
            case blockedReason of
                Just reason ->
                    H.p
                        []
                        [ H.text reason
                        ]

                Nothing ->
                    H.text ""
    in
    H.div
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.flexWrap
            , S.g3
            ]
        ]
        [ startButton
        , status
        ]


playersView : Model -> Html Msg
playersView model =
    playersContent model
        |> Card.toHtml
            (Card.simple
                |> Card.withHeader
                    (CardHeader.simple "players"
                        |> CardHeader.withCaption (String.fromInt (List.length model.players) ++ " / 2")
                    )
            )


playersContent : Model -> List (Html Msg)
playersContent model =
    [ H.ul
        [ A.css
            [ S.col
            , S.g2
            , S.listNone
            ]
        ]
        (List.map (playerSlotView model) Api.Enum.PlayerNumber.list)
    , sideView model
    , inviteView model
    ]


sideLabel : PlayerNumber -> String
sideLabel playerNumber =
    let
        color : String
        color =
            case playerNumber of
                Player1 ->
                    "red"

                Player2 ->
                    "blue"
    in
    PlayerNumber.label playerNumber ++ " (" ++ color ++ ")"


sideView : Model -> Html Msg
sideView model =
    let
        sideHtmlId : String
        sideHtmlId =
            "your-side"

        ownPlayer : Maybe Player
        ownPlayer =
            List.filter .isYou model.players |> List.head

        selectedSide : Player -> PlayerNumber
        selectedSide player =
            case model.requestStatus of
                ChoosingSide playerNumber ->
                    playerNumber

                _ ->
                    player.playerNumber

        option : PlayerNumber -> { value : PlayerNumber, label : String }
        option playerNumber =
            { value = playerNumber
            , label = sideLabel playerNumber
            }
    in
    case ownPlayer of
        Just player ->
            H.div
                [ A.css
                    [ S.col
                    , S.g1
                    ]
                ]
                [ H.div
                    [ A.css
                        [ S.row
                        , S.itemsCenter
                        , S.justifySpaceBetween
                        , S.flexWrap
                        , S.g2
                        ]
                    ]
                    [ H.label
                        [ A.for sideHtmlId
                        ]
                        [ H.text "your side"
                        ]
                    , H.div
                        [ A.css
                            [ S.w48
                            , S.maxWFull
                            ]
                        ]
                        [ Select.new
                            { selected = selectedSide player
                            , options = List.map option Api.Enum.PlayerNumber.list
                            , onChange = SideInputChanged
                            }
                            |> Select.withHtmlId sideHtmlId
                            |> Select.disabled (isBusy model || (model.gameUrl /= Nothing))
                            |> Select.toHtml
                        ]
                    ]
                , H.p
                    []
                    [ H.text "switching sides also moves the other player."
                    ]
                ]

        Nothing ->
            H.text ""


playerSlotView : Model -> PlayerNumber -> Html Msg
playerSlotView model playerNumber =
    let
        belongsToSlot : Player -> Bool
        belongsToSlot player =
            player.playerNumber == playerNumber

        occupant : Maybe Player
        occupant =
            model.players
                |> List.filter belongsToSlot
                |> List.head

        controller : Controller
        controller =
            occupant
                |> Maybe.map .controller
                |> Maybe.withDefault Human

        canConfigure : Bool
        canConfigure =
            model.isHost && (model.gameUrl == Nothing) && (Maybe.map .isHost occupant /= Just True)

        controllerHtmlId : String
        controllerHtmlId =
            "slot-controller-" ++ Api.Enum.PlayerNumber.toString playerNumber

        slotLabel : String
        slotLabel =
            sideLabel playerNumber

        label : Html Msg
        label =
            if canConfigure then
                H.label
                    [ A.for controllerHtmlId
                    ]
                    [ H.text slotLabel
                    ]

            else
                H.span
                    []
                    [ H.text slotLabel
                    ]

        occupantName : String
        occupantName =
            case occupant of
                Just player ->
                    let
                        role : String
                        role =
                            if player.isHost && player.isYou then
                                " (you, host)"

                            else if player.isHost then
                                " (host)"

                            else if player.isYou then
                                " (you)"

                            else
                                ""
                    in
                    player.name ++ role

                Nothing ->
                    "waiting for player"

        option : Controller -> { value : Controller, label : String }
        option choice =
            { value = choice
            , label = controllerLabel choice
            }

        control : Html Msg
        control =
            if canConfigure then
                Select.new
                    { selected = controller
                    , options = List.map option Api.Enum.Controller.list
                    , onChange = ControllerInputChanged
                    }
                    |> Select.withHtmlId controllerHtmlId
                    |> Select.disabled (isBusy model || hasJoinedHuman model)
                    |> Select.toHtml

            else
                H.span
                    []
                    [ H.text (controllerLabel controller)
                    ]

        kickControl : Html Msg
        kickControl =
            case occupant of
                Just player ->
                    if canConfigure && (player.controller == Human) then
                        let
                            button : Button.Button Msg
                            button =
                                if isBusy model then
                                    Button.disabled "kick"

                                else
                                    Button.danger "kick" (KickPlayerButtonClicked player)

                            feedback : Maybe String
                            feedback =
                                if model.requestStatus == KickingPlayer player.name then
                                    Just "kicking…"

                                else
                                    Nothing
                        in
                        button
                            |> Button.accessibleLabel ("kick " ++ player.name)
                            |> Button.withFeedback feedback
                            |> Button.toHtml

                    else
                        H.text ""

                Nothing ->
                    H.text ""

        controlTitle : String
        controlTitle =
            if canConfigure && hasJoinedHuman model then
                "kick the joined player before changing the controller"

            else
                ""
    in
    H.li
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.g3
            , S.py1
            , S.when (playerNumber /= Player1)
                [ S.borderT
                , S.borderGray2
                , S.pt3
                ]
            ]
        ]
        [ H.div
            [ A.css
                [ S.col
                , S.g1
                , S.flex1
                , S.minW0
                , S.wrapAnywhere
                , S.when (playerNumber == Player1) [ S.textRed1Light ]
                , S.when (playerNumber == Player2) [ S.textBlue0Light ]
                ]
            ]
            [ label
            , H.span
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text occupantName
                ]
            ]
        , H.div
            [ A.title controlTitle
            , A.css
                [ S.col
                , S.g2
                , S.w32
                , S.shrink0
                ]
            ]
            [ control
            , kickControl
            ]
        ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        shortcut : Sub Msg
        shortcut =
            if (model.screen == Setup) && not model.shared.devPanelOpen then
                Browser.Events.onKeyDown (Decode.map ChatMsg ChatView.openKeyDecoder)

            else
                Sub.none
    in
    Sub.batch [ Time.every 2000 PollTimerElapsed, Time.every 1000 ChatPollElapsed, shortcut ]


listeners : FromJs.Listener Msg
listeners =
    FromJs.data "copyLinkResult"
        (Decode.map2 CopyResult
            (Decode.field "url" Decode.string)
            (Decode.field "success" Decode.bool)
        )
        CopyLinkResultReceived
