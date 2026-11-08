module Admin.Page.Dashboard exposing
    ( Flags
    , Model
    , Msg(..)
    , init
    , load
    , needsLogin
    , requiresCurrentDeployment
    , setShared
    , subscriptions
    , update
    , view
    )

import Admin.Route as Route
import Api.Enum.Controller as Controller exposing (Controller)
import Api.Enum.EntryStatus as Status exposing (EntryStatus)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Object
import Api.Object.AdminEntry as EntryApi
import Api.Object.AdminPlayer as PlayerApi
import Api.Object.Dashboard as DashboardApi
import Api.Object.DeploymentObservation as DeploymentApi
import Api.Object.DeploymentStatus as DeploymentStatusApi
import Api.Object.FeedbackPage as FeedbackPageApi
import Api.Object.FeedbackReadError as FeedbackErrorApi
import Api.Object.FeedbackRecord as FeedbackApi
import Api.Object.RecordingsPage as RecordingsApi
import Api.Query
import Api.Scalar exposing (MapId)
import ApiRequest exposing (Response)
import Effect as E exposing (Eff)
import Game.Archive as Archive exposing (Entry(..))
import Game.MapId as MapId
import Game.PlayerNumber as PlayerNumber
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import LobbyId exposing (LobbyId)
import Shared
import Style as S
import Time
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Snapshot =
    { deployments : List Deployment
    , serverVersion : String
    , concurrentGames : Int
    , waitingLobbies : Int
    , retainedFinishedGames : Int
    , entries : List LiveEntry
    }


type alias Deployment =
    { id : String
    , available : Bool
    , status : Maybe DeploymentStatus
    }


type alias DeploymentStatus =
    { version : String
    , startedAt : String
    , observedAt : String
    , draining : Bool
    , shutdownAt : Maybe String
    , concurrentGames : Int
    , waitingLobbies : Int
    , retainedFinishedGames : Int
    , entries : List LiveEntry
    }


type alias LiveEntry =
    { id : LobbyId
    , name : String
    , mapType : MapId
    , status : EntryStatus
    , turnNumber : Maybe Int
    , players : List Player
    , startedSecondsAgo : Maybe Int
    , lastActivitySecondsAgo : Int
    , warningSecondsRemaining : Maybe Int
    , busy : Bool
    }


type alias Player =
    { name : String
    , controller : Controller
    , playerNumber : PlayerNumber
    , ordersSubmitted : Bool
    }


type FeedbackId
    = FeedbackId String


type alias Feedback =
    { id : FeedbackId
    , submittedAt : String
    , serverVersion : String
    , text : String
    }


type alias ReadError =
    { id : FeedbackId
    , message : String
    }


type alias FeedbackPage =
    { records : List Feedback
    , errors : List ReadError
    , total : Int
    , nextOffset : Maybe Int
    }


type alias RecordingsPage =
    { entries : List Archive.Entry
    , total : Int
    , nextOffset : Maybe Int
    }


type alias Model =
    { shared : Shared.Model
    , snapshot : Snapshot
    , feedback : FeedbackPage
    , recordings : RecordingsPage
    , selectedGame : Maybe LobbyId
    , selectedFeedback : Maybe FeedbackId
    , feedbackExpanded : Bool
    , recordingsExpanded : Bool
    , feedbackOffset : Int
    , recordingOffset : Int
    , request : Request
    , listError : Maybe String
    , error : Maybe String
    , updatedAt : Time.Posix
    }


type Request
    = Idle
    | Polling
    | Refreshing
    | LoadingFeedback Int
    | LoadingRecordings Int


type Msg
    = PollTimerElapsed Time.Posix
    | SnapshotResponseReceived (Response Snapshot)
    | RefreshButtonClicked
    | LogoutButtonClicked
    | RefreshResponseReceived (Response Flags)
    | FeedbackListToggled
    | RecordingListToggled
    | GameButtonClicked LobbyId
    | FeedbackButtonClicked FeedbackId
    | FeedbackPageClicked Int
    | FeedbackResponseReceived Int (Response FeedbackPage)
    | RecordingPageClicked Int
    | RecordingsResponseReceived Int (Response RecordingsPage)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { snapshot : Snapshot
    , feedback : FeedbackPage
    , recordings : RecordingsPage
    }


init : Shared.Model -> Flags -> Model
init shared flags =
    { shared = shared
    , snapshot = flags.snapshot
    , feedback = flags.feedback
    , recordings = flags.recordings
    , selectedGame = Nothing
    , selectedFeedback = Nothing
    , feedbackExpanded = False
    , recordingsExpanded = False
    , feedbackOffset = 0
    , recordingOffset = 0
    , request = Idle
    , listError = Nothing
    , error = Nothing
    , updatedAt = shared.now
    }


load : Graphql.Http.Request Flags
load =
    SS.succeed Flags
        |> SS.with (Api.Query.adminDashboard snapshotSelection)
        |> SS.with
            (Api.Query.adminFeedback
                { offset = 0
                }
                feedbackPageSelection
            )
        |> SS.with
            (Api.Query.adminRecordings
                { offset = 0
                }
                recordingsSelection
            )
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }


snapshotSelection : SelectionSet Snapshot Api.Object.Dashboard
snapshotSelection =
    SS.succeed Snapshot
        |> SS.with (DashboardApi.deployments deploymentSelection)
        |> SS.with DashboardApi.serverVersion
        |> SS.with DashboardApi.concurrentGames
        |> SS.with DashboardApi.waitingLobbies
        |> SS.with DashboardApi.retainedFinishedGames
        |> SS.with (DashboardApi.entries entrySelection)


entrySelection : SelectionSet LiveEntry Api.Object.AdminEntry
entrySelection =
    SS.succeed LiveEntry
        |> SS.with (EntryApi.id |> SS.mapOrFail LobbyId.fromString)
        |> SS.with EntryApi.name
        |> SS.with EntryApi.mapType
        |> SS.with EntryApi.status
        |> SS.with EntryApi.turnNumber
        |> SS.with (EntryApi.players playerSelection)
        |> SS.with EntryApi.startedSecondsAgo
        |> SS.with EntryApi.lastActivitySecondsAgo
        |> SS.with EntryApi.warningSecondsRemaining
        |> SS.with EntryApi.busy


playerSelection : SelectionSet Player Api.Object.AdminPlayer
playerSelection =
    SS.succeed Player
        |> SS.with PlayerApi.name
        |> SS.with PlayerApi.controller
        |> SS.with PlayerApi.playerNumber
        |> SS.with PlayerApi.ordersSubmitted


feedbackIdToString : FeedbackId -> String
feedbackIdToString (FeedbackId value) =
    value


feedbackPageSelection : SelectionSet FeedbackPage Api.Object.FeedbackPage
feedbackPageSelection =
    let
        record : SelectionSet Feedback Api.Object.FeedbackRecord
        record =
            SS.succeed Feedback
                |> SS.with (FeedbackApi.id |> SS.map FeedbackId)
                |> SS.with FeedbackApi.submittedAt
                |> SS.with FeedbackApi.serverVersion
                |> SS.with FeedbackApi.text

        readError : SelectionSet ReadError Api.Object.FeedbackReadError
        readError =
            SS.succeed ReadError
                |> SS.with (FeedbackErrorApi.id |> SS.map FeedbackId)
                |> SS.with FeedbackErrorApi.message
    in
    SS.succeed FeedbackPage
        |> SS.with (FeedbackPageApi.records record)
        |> SS.with (FeedbackPageApi.errors readError)
        |> SS.with FeedbackPageApi.total
        |> SS.with FeedbackPageApi.nextOffset


recordingsSelection : SelectionSet RecordingsPage Api.Object.RecordingsPage
recordingsSelection =
    SS.succeed RecordingsPage
        |> SS.with (RecordingsApi.entries Archive.entrySelection)
        |> SS.with RecordingsApi.total
        |> SS.with RecordingsApi.nextOffset


needsLogin : Msg -> Bool
needsLogin msg =
    case msg of
        SnapshotResponseReceived (Err error) ->
            ApiRequest.requiresAdminLogin error

        RefreshResponseReceived (Err error) ->
            ApiRequest.requiresAdminLogin error

        FeedbackResponseReceived _ (Err error) ->
            ApiRequest.requiresAdminLogin error

        RecordingsResponseReceived _ (Err error) ->
            ApiRequest.requiresAdminLogin error

        _ ->
            False


toggle : a -> Maybe a -> Maybe a
toggle value selected =
    if selected == Just value then
        Nothing

    else
        Just value


duration : Int -> String
duration seconds =
    if seconds < 60 then
        String.fromInt seconds ++ "s"

    else if seconds < 3600 then
        String.fromInt (seconds // 60) ++ "m"

    else
        String.fromInt (seconds // 3600) ++ "h " ++ String.fromInt (modBy 60 (seconds // 60)) ++ "m"


isLive : LiveEntry -> Bool
isLive entry =
    (entry.status /= Status.WaitingLobby) && (entry.status /= Status.Finished)


isWaitingLobby : LiveEntry -> Bool
isWaitingLobby entry =
    entry.status == Status.WaitingLobby


statusLabel : LiveEntry -> String
statusLabel entry =
    if entry.busy then
        "busy · updating game"

    else
        case entry.status of
            Status.WaitingLobby ->
                "waiting to start"

            Status.Planning ->
                "waiting for orders"

            Status.WaitingForPlayer ->
                "waiting for one player"

            Status.InactivityWarning ->
                "inactivity warning"

            Status.Finished ->
                "finished"


requiresCurrentDeployment : Msg -> Bool
requiresCurrentDeployment msg =
    case msg of
        SnapshotResponseReceived (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        RefreshResponseReceived (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        FeedbackResponseReceived _ (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        RecordingsResponseReceived _ (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        _ ->
            False



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        LogoutButtonClicked ->
            ( model, Route.pushUrl Route.SignOut )

        PollTimerElapsed _ ->
            if model.request /= Idle then
                model |> E.withOut

            else
                ( { model
                    | request = Polling
                  }
                , Api.Query.adminDashboard snapshotSelection |> ApiRequest.queryRequest |> E.request SnapshotResponseReceived
                )

        SnapshotResponseReceived result ->
            case result of
                Ok snapshot ->
                    { model
                        | snapshot = snapshot
                        , request = Idle
                        , error = Nothing
                        , updatedAt = model.shared.now
                    }
                        |> E.withOut

                Err error ->
                    { model
                        | request = Idle
                        , error = Just (ApiRequest.errorMessage error)
                    }
                        |> E.withOut

        RefreshButtonClicked ->
            if model.request /= Idle then
                model |> E.withOut

            else
                ( { model
                    | request = Refreshing
                  }
                , load |> E.request RefreshResponseReceived
                )

        RefreshResponseReceived result ->
            case result of
                Ok flags ->
                    { model
                        | snapshot = flags.snapshot
                        , feedback = flags.feedback
                        , recordings = flags.recordings
                        , feedbackOffset = 0
                        , recordingOffset = 0
                        , request = Idle
                        , listError = Nothing
                        , error = Nothing
                        , updatedAt = model.shared.now
                    }
                        |> E.withOut

                Err error ->
                    { model
                        | request = Idle
                        , listError = Just (ApiRequest.errorMessage error)
                    }
                        |> E.withOut

        FeedbackListToggled ->
            { model
                | feedbackExpanded = not model.feedbackExpanded
            }
                |> E.withOut

        RecordingListToggled ->
            { model
                | recordingsExpanded = not model.recordingsExpanded
            }
                |> E.withOut

        GameButtonClicked id ->
            { model
                | selectedGame = toggle id model.selectedGame
            }
                |> E.withOut

        FeedbackButtonClicked id ->
            { model
                | selectedFeedback = toggle id model.selectedFeedback
            }
                |> E.withOut

        FeedbackPageClicked offset ->
            if model.request /= Idle then
                model |> E.withOut

            else
                ( { model
                    | request = LoadingFeedback offset
                  }
                , Api.Query.adminFeedback
                    { offset = offset
                    }
                    feedbackPageSelection
                    |> ApiRequest.queryRequest
                    |> E.request (FeedbackResponseReceived offset)
                )

        FeedbackResponseReceived offset result ->
            case result of
                Ok feedback ->
                    { model
                        | feedback = feedback
                        , feedbackOffset = offset
                        , selectedFeedback = Nothing
                        , request = Idle
                        , listError = Nothing
                    }
                        |> E.withOut

                Err error ->
                    { model
                        | request = Idle
                        , listError = Just (ApiRequest.errorMessage error)
                    }
                        |> E.withOut

        RecordingPageClicked offset ->
            if model.request /= Idle then
                model |> E.withOut

            else
                ( { model
                    | request = LoadingRecordings offset
                  }
                , Api.Query.adminRecordings
                    { offset = offset
                    }
                    recordingsSelection
                    |> ApiRequest.queryRequest
                    |> E.request (RecordingsResponseReceived offset)
                )

        RecordingsResponseReceived offset result ->
            case result of
                Ok recordings ->
                    { model
                        | recordings = recordings
                        , recordingOffset = offset
                        , request = Idle
                        , listError = Nothing
                    }
                        |> E.withOut

                Err error ->
                    { model
                        | request = Idle
                        , listError = Just (ApiRequest.errorMessage error)
                    }
                        |> E.withOut



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    let
        live : List LiveEntry
        live =
            List.filter isLive model.snapshot.entries

        lobbies : List LiveEntry
        lobbies =
            List.filter isWaitingLobby model.snapshot.entries

        failure : String -> Html Msg
        failure message =
            H.p
                [ Aria.role Aria.Alert
                , A.css
                    [ S.textYellow5
                    ]
                ]
                [ H.text message
                ]

        pollFailure : String -> Html Msg
        pollFailure error =
            failure (error ++ " showing the last successful game snapshot.")

        listFailure : String -> Html Msg
        listFailure error =
            failure (error ++ " the previous lists are still shown.")

        pollErrors : List (Html Msg)
        pollErrors =
            model.error
                |> Maybe.map (pollFailure >> List.singleton)
                |> Maybe.withDefault []

        listErrors : List (Html Msg)
        listErrors =
            model.listError
                |> Maybe.map (listFailure >> List.singleton)
                |> Maybe.withDefault []

        errors : List (Html Msg)
        errors =
            pollErrors ++ listErrors

        content : List (Html Msg)
        content =
            errors
                ++ [ Card.toHtml Card.simple
                        [ H.div
                            [ A.css
                                [ S.grid
                                , S.gridColumns "repeat(3, minmax(0, 1fr))"
                                , S.g3
                                , S.belowWidth 650
                                    [ S.gridCols1
                                    ]
                                ]
                            ]
                            [ stat { title = "games in progress", value = model.snapshot.concurrentGames, caption = "started and unfinished" }
                            , stat { title = "waiting lobbies", value = model.snapshot.waitingLobbies, caption = "not started yet" }
                            , stat { title = "feedback submissions", value = model.feedback.total, caption = "all time · refresh to update" }
                            ]
                        ]
                   , deploymentsView model
                   , entriesPanel model "games in progress" live
                   , entriesPanel model "waiting lobbies" lobbies
                   , H.div
                        [ A.css
                            [ S.grid
                            , S.gridCols2
                            , S.g4
                            , S.itemsStart
                            , S.belowWidth 850
                                [ S.gridCols1
                                ]
                            ]
                        ]
                        [ feedbackView model
                        , recordingsView model
                        ]
                   , H.p
                        []
                        [ H.text
                            ("game snapshot "
                                ++ duration ((Time.posixToMillis model.shared.now - Time.posixToMillis model.updatedAt) // 1000)
                                ++ " ago · "
                                ++ String.fromInt model.snapshot.retainedFinishedGames
                                ++ " finished games retained in memory · completed games are excluded from the concurrent count"
                            )
                        ]
                   ]
    in
    [ H.div
        [ A.css
            [ S.col
            , S.g4
            , S.wFull
            , S.maxW320
            , S.selfCenter
            ]
        ]
        (toolbar model :: content)
    ]


toolbar : Model -> Html Msg
toolbar model =
    let
        refresh : Button.Button Msg
        refresh =
            if model.request == Idle then
                Button.secondary "refresh all" RefreshButtonClicked

            else
                Button.disabled "refreshing…"
    in
    Card.toHtml Card.simple
        [ H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g3
                , S.itemsCenter
                , S.justifySpaceBetween
                ]
            ]
            [ H.p
                []
                [ H.text
                    ("server v" ++ model.snapshot.serverVersion ++ " · games refresh every 5 seconds")
                ]
            , H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.g3
                    ]
                ]
                [ refresh
                    |> Button.toHtml
                , Button.secondary "log out" LogoutButtonClicked
                    |> Button.toHtml
                ]
            ]
        ]


stat : { title : String, value : Int, caption : String } -> Html msg
stat statValue =
    H.div
        [ A.css
            [ S.col
            , S.g3
            , S.p3
            , S.indentStrong
            , S.bgNightwood3
            , S.wrapAnywhere
            ]
        ]
        [ H.p
            []
            [ H.text (statValue.title ++ ": " ++ String.fromInt statValue.value)
            ]
        , H.p
            []
            [ H.text statValue.caption
            ]
        ]


entriesPanel : Model -> String -> List LiveEntry -> Html Msg
entriesPanel model title entries =
    let
        rows : List (Html Msg)
        rows =
            if List.isEmpty entries then
                [ H.p
                    []
                    [ H.text "none right now."
                    ]
                ]

            else
                List.map (entryView model.selectedGame) entries
                    |> List.intersperse divider
    in
    Card.toHtml (Card.simple |> Card.withHeader (CardHeader.simple title)) rows


divider : Html msg
divider =
    H.hr
        [ A.css
            [ S.border0
            , S.borderT
            , S.borderGray2
            , S.wFull
            ]
        ]
        []


entryView : Maybe LobbyId -> LiveEntry -> Html Msg
entryView selected entry =
    let
        expanded : Bool
        expanded =
            selected == Just entry.id

        turn : String
        turn =
            entry.turnNumber
                |> Maybe.map (\number -> "turn " ++ String.fromInt number)
                |> Maybe.withDefault "not started"

        detailHtmlId : String
        detailHtmlId =
            "admin-game-" ++ LobbyId.toString entry.id

        details : List (Html Msg)
        details =
            if expanded then
                [ entryDetails detailHtmlId entry
                ]

            else
                []

        row : Html Msg
        row =
            H.div
                [ A.css
                    [ S.grid
                    , S.gridColumns "minmax(0,2fr) minmax(0,1fr) minmax(0,2fr) minmax(0,1fr)"
                    , S.g3
                    , S.itemsCenter
                    , S.belowWidth 650
                        [ S.gridCols2
                        ]
                    ]
                ]
                [ H.div
                    [ A.css
                        [ S.col
                        , S.g1
                        , S.itemsStart
                        ]
                    ]
                    [ Button.secondary entry.name (GameButtonClicked entry.id)
                        |> Button.disclosure
                            { expanded = expanded
                            , controlsHtmlId = detailHtmlId
                            }
                        |> Button.toHtml
                    , H.p
                        []
                        [ H.text (MapId.label entry.mapType)
                        ]
                    ]
                , H.p
                    []
                    [ H.text turn
                    ]
                , H.p
                    []
                    [ H.text (statusLabel entry)
                    ]
                , H.p
                    []
                    [ H.text ("active " ++ duration entry.lastActivitySecondsAgo ++ " ago")
                    ]
                ]

        content : List (Html Msg)
        content =
            row :: details
    in
    H.article
        [ A.css
            [ S.col
            , S.g3
            , S.wrapAnywhere
            ]
        ]
        content


entryDetails : String -> LiveEntry -> Html Msg
entryDetails htmlId entry =
    let
        player : Player -> Html Msg
        player value =
            let
                controller : String
                controller =
                    if value.controller == Controller.Ai then
                        "ai"

                    else
                        "human"

                readiness : String
                readiness =
                    if entry.status == Status.WaitingLobby then
                        "in lobby"

                    else if entry.status == Status.Finished then
                        "finished"

                    else if value.ordersSubmitted then
                        "orders submitted"

                    else
                        "waiting for orders"
            in
            H.p
                []
                [ H.text
                    (PlayerNumber.label
                        value.playerNumber
                        ++ " · "
                        ++ value.name
                        ++ " · "
                        ++ controller
                        ++ " · "
                        ++ readiness
                    )
                ]

        started : List (Html Msg)
        started =
            entry.startedSecondsAgo
                |> Maybe.map
                    (\seconds ->
                        [ H.p
                            []
                            [ H.text ("started " ++ duration seconds ++ " ago")
                            ]
                        ]
                    )
                |> Maybe.withDefault []

        warning : List (Html Msg)
        warning =
            entry.warningSecondsRemaining
                |> Maybe.map
                    (\seconds ->
                        [ H.p
                            [ A.css
                                [ S.textYellow5
                                ]
                            ]
                            [ H.text ("inactivity timeout in " ++ String.fromInt seconds ++ "s")
                            ]
                        ]
                    )
                |> Maybe.withDefault []

        busy : List (Html Msg)
        busy =
            if entry.busy then
                [ H.p
                    []
                    [ H.text "game is busy. details show its last completed update."
                    ]
                ]

            else
                []

        content : List (Html Msg)
        content =
            started ++ List.map player entry.players ++ warning ++ busy
    in
    H.div
        [ A.id htmlId
        , A.css
            [ S.col
            , S.g2
            , S.p3
            , S.bgNightwood3
            , S.indentStrong
            ]
        ]
        content


feedbackView : Model -> Html Msg
feedbackView model =
    let
        recordView : Feedback -> Html Msg
        recordView record =
            let
                expanded : Bool
                expanded =
                    model.selectedFeedback == Just record.id

                showFullText : Bool
                showFullText =
                    expanded || (String.length record.text <= 100)

                text : String
                text =
                    if showFullText then
                        record.text

                    else
                        String.left 100 record.text ++ "…"

                htmlId : String
                htmlId =
                    "admin-feedback-" ++ feedbackIdToString record.id
            in
            H.article
                [ A.css
                    [ S.col
                    , S.g2
                    , S.wrapAnywhere
                    ]
                ]
                [ Button.secondary
                    (Archive.startedAtLabel record.submittedAt
                        ++ " · v"
                        ++ record.serverVersion
                    )
                    (FeedbackButtonClicked record.id)
                    |> Button.disclosure
                        { expanded = expanded
                        , controlsHtmlId = htmlId
                        }
                    |> Button.toHtml
                , H.p
                    [ A.id htmlId
                    , A.css
                        [ S.whitespacePreWrap
                        ]
                    ]
                    [ H.text text
                    ]
                ]

        unreadable : ReadError -> Html Msg
        unreadable error =
            H.p
                [ Aria.role Aria.Status
                ]
                [ H.text (feedbackIdToString error.id ++ ": " ++ error.message)
                ]

        empty : List (Html Msg)
        empty =
            if model.feedback.total == 0 then
                [ H.p
                    []
                    [ H.text "no feedback yet."
                    ]
                ]

            else
                []

        visible : List Feedback
        visible =
            if model.feedbackExpanded then
                model.feedback.records

            else
                List.take 3 model.feedback.records

        controls : List (Html Msg)
        controls =
            if model.feedbackExpanded then
                [ Button.secondary "show fewer" FeedbackListToggled
                    |> Button.toHtml
                , pageButtons
                    { onPage = FeedbackPageClicked
                    , request = model.request
                    , offset = model.feedbackOffset
                    , nextOffset = model.feedback.nextOffset
                    , pageSize = 50
                    }
                ]

            else if model.feedback.total > 3 then
                [ Button.secondary "browse all feedback" FeedbackListToggled
                    |> Button.toHtml
                ]

            else
                []

        rows : List (Html Msg)
        rows =
            List.map recordView visible ++ List.map unreadable model.feedback.errors

        content : List (Html Msg)
        content =
            empty ++ List.intersperse divider rows ++ controls
    in
    Card.toHtml
        (Card.simple
            |> Card.withHeader
                (CardHeader.simple ("feedback · " ++ String.fromInt model.feedback.total))
        )
        content


recordingsView : Model -> Html Msg
recordingsView model =
    let
        recording : Archive.Entry -> Html Msg
        recording entry =
            case entry of
                Readable game ->
                    H.article
                        [ A.css
                            [ S.col
                            , S.g2
                            ]
                        ]
                        [ H.a
                            [ A.href (Route.toString (Route.Replay game.id))
                            , A.css
                                [ S.link
                                , S.wrapAnywhere
                                ]
                            ]
                            [ H.text game.name
                            ]
                        , H.p
                            []
                            [ H.text
                                (Archive.statusLabel game.status
                                    ++ " · "
                                    ++ String.fromInt game.turnCount
                                    ++ " completed turns · "
                                    ++ MapId.label game.mapType
                                )
                            ]
                        , H.p
                            []
                            [ H.text (Archive.startedAtLabel game.startedAt)
                            ]
                        ]

                Unreadable error ->
                    H.p
                        [ Aria.role Aria.Status
                        ]
                        [ H.text error.message
                        ]

        empty : List (Html Msg)
        empty =
            if model.recordings.total == 0 then
                [ H.p
                    []
                    [ H.text "no recorded games yet."
                    ]
                ]

            else
                []

        visible : List Archive.Entry
        visible =
            if model.recordingsExpanded then
                model.recordings.entries

            else
                List.take 3 model.recordings.entries

        controls : List (Html Msg)
        controls =
            if model.recordingsExpanded then
                [ Button.secondary "show fewer" RecordingListToggled
                    |> Button.toHtml
                , pageButtons
                    { onPage = RecordingPageClicked
                    , request = model.request
                    , offset = model.recordingOffset
                    , nextOffset = model.recordings.nextOffset
                    , pageSize = 20
                    }
                ]

            else if model.recordings.total > 3 then
                [ Button.secondary "browse recordings" RecordingListToggled
                    |> Button.toHtml
                ]

            else
                []

        rows : List (Html Msg)
        rows =
            List.map recording visible
                |> List.intersperse divider

        content : List (Html Msg)
        content =
            empty ++ rows ++ controls
    in
    Card.toHtml
        (Card.simple
            |> Card.withHeader (CardHeader.simple ("recorded games · " ++ String.fromInt model.recordings.total))
        )
        content


pageButtons : { onPage : Int -> Msg, request : Request, offset : Int, nextOffset : Maybe Int, pageSize : Int } -> Html Msg
pageButtons pagination =
    let
        button : String -> Int -> Html Msg
        button label destination =
            if pagination.request == Idle then
                Button.secondary label (pagination.onPage destination)
                    |> Button.toHtml

            else
                Button.disabled label
                    |> Button.toHtml

        previous : List (Html Msg)
        previous =
            if pagination.offset > 0 then
                [ button "newer" (max 0 (pagination.offset - pagination.pageSize))
                ]

            else
                []

        older : List (Html Msg)
        older =
            pagination.nextOffset
                |> Maybe.map
                    (\destination ->
                        [ button "older" destination
                        ]
                    )
                |> Maybe.withDefault []

        content : List (Html Msg)
        content =
            previous ++ older
    in
    H.div
        [ A.css
            [ S.row
            , S.g2
            ]
        ]
        content


deploymentSelection : SelectionSet Deployment Api.Object.DeploymentObservation
deploymentSelection =
    SS.succeed Deployment
        |> SS.with DeploymentApi.id
        |> SS.with DeploymentApi.available
        |> SS.with (DeploymentApi.status deploymentStatusSelection)


deploymentStatusSelection : SelectionSet DeploymentStatus Api.Object.DeploymentStatus
deploymentStatusSelection =
    SS.succeed DeploymentStatus
        |> SS.with DeploymentStatusApi.version
        |> SS.with DeploymentStatusApi.startedAt
        |> SS.with DeploymentStatusApi.observedAt
        |> SS.with DeploymentStatusApi.draining
        |> SS.with DeploymentStatusApi.shutdownAt
        |> SS.with DeploymentStatusApi.concurrentGames
        |> SS.with DeploymentStatusApi.waitingLobbies
        |> SS.with DeploymentStatusApi.retainedFinishedGames
        |> SS.with (DeploymentStatusApi.entries entrySelection)


deploymentsView : Model -> Html Msg
deploymentsView model =
    let
        deploymentRow : Deployment -> Html Msg
        deploymentRow deployment =
            let
                description : String
                description =
                    case deployment.status of
                        Just status ->
                            "v"
                                ++ status.version
                                ++ " · "
                                ++ lifecycle status
                                ++ " · "
                                ++ String.fromInt status.concurrentGames
                                ++ " games"
                                ++ " · "
                                ++ String.fromInt status.waitingLobbies
                                ++ " lobbies"
                                ++ " · "
                                ++ String.fromInt status.retainedFinishedGames
                                ++ " postgame"
                                ++ " · uptime "
                                ++ elapsed status.startedAt
                                ++ " · last seen "
                                ++ elapsed status.observedAt
                                ++ " ago"

                        Nothing ->
                            "no status received"

                health : String
                health =
                    if deployment.available then
                        "healthy"

                    else
                        "status unavailable · last reported values follow"

                gameRows : List (Html Msg)
                gameRows =
                    deployment.status
                        |> Maybe.map (.entries >> List.map gameRow)
                        |> Maybe.withDefault []

                gameRow : LiveEntry -> Html Msg
                gameRow entry =
                    H.p
                        []
                        [ H.text (entry.name ++ " · " ++ statusLabel entry)
                        ]
            in
            H.details
                []
                [ H.summary
                    []
                    [ H.text (deployment.id ++ " · " ++ health ++ " · " ++ description)
                    ]
                , H.div
                    [ A.css
                        [ S.col
                        , S.g2
                        ]
                    ]
                    gameRows
                ]

        lifecycle : DeploymentStatus -> String
        lifecycle status =
            if status.draining then
                "draining" ++ Maybe.withDefault "" (Maybe.map remaining status.shutdownAt)

            else
                "accepting new games"

        remaining : String -> String
        remaining value =
            case String.toInt value of
                Just deadline ->
                    " · shutdown in " ++ duration (max 0 ((deadline - Time.posixToMillis model.shared.now) // 1000))

                Nothing ->
                    " · invalid shutdown deadline"

        elapsed : String -> String
        elapsed value =
            value
                |> String.toInt
                |> Maybe.map elapsedTimestamp
                |> Maybe.withDefault "unknown"

        elapsedTimestamp : Int -> String
        elapsedTimestamp timestamp =
            duration (max 0 ((Time.posixToMillis model.shared.now - timestamp) // 1000))

        rows : List (Html Msg)
        rows =
            List.map deploymentRow model.snapshot.deployments

        isDraining : Deployment -> Bool
        isDraining deployment =
            Maybe.map .draining deployment.status == Just True

        draining : Int
        draining =
            model.snapshot.deployments
                |> List.filter isDraining
                |> List.length
    in
    Card.toHtml Card.simple
        [ H.h2
            []
            [ H.text (String.fromInt (List.length rows) ++ " deployments supervised · " ++ String.fromInt draining ++ " draining")
            ]
        , H.div
            [ A.css
                [ S.col
                , S.g3
                ]
            ]
            rows
        , H.p
            []
            [ H.text "stale deployments remain visible; counts above describe this admin server. expand a deployment to inspect its sessions."
            ]
        ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Sub Msg
subscriptions =
    Time.every 5000 PollTimerElapsed
