module Fightlines.Page.MatchMaking exposing
    ( Error
    , Flags
    , Model
    , Msg
    , fromLoadError
    , init
    , leave
    , load
    , loadFailedView
    , loadingView
    , prepareVisit
    , setShared
    , subscriptions
    , update
    , view
    , visitId
    )

import Api.Mutation
import Api.Object.MatchMakingIdle as IdleApi
import Api.Object.MatchMakingMatched as MatchedApi
import Api.Object.MatchMakingWaiting as WaitingApi
import Api.Query
import Api.Union
import Api.Union.MatchMakingSnapshot as SnapshotApi
import ApiRequest exposing (Response)
import Audio
import Browser.Events
import EditableMap exposing (NamedMap)
import Effect as E exposing (Eff)
import Fightlines.MatchMaking.VisitId as VisitId exposing (VisitId)
import Fightlines.Route as Route
import Fightlines.UserName as UserName
import Game.MapId as MapId
import Game.View.MapPreview as MapPreview
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import LobbyId exposing (LobbyId)
import Random
import Shared
import Style as S
import Time
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.LoadingBar as LoadingBar
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| The server-issued ID for one queue entry. Poll and cancel requests use it
with the browser session to keep delayed requests from affecting a later entry.
-}
type Ticket
    = Ticket String


type Error
    = InvalidName
    | QueueStopped
    | RequestFailed (Graphql.Http.Error Snapshot)


type alias Model =
    { shared : Shared.Model
    , visit : VisitId
    , name : String
    , stage : Stage
    , lastGameStartedAt : Maybe Time.Posix
    , error : Maybe Error
    }


type Stage
    = Entry
    | Joining
    | Waiting Ticket Activity
    | PreparingReady ReadyMatch
    | GettingReady ReadyMatch Time.Posix
    | EnteringGame


type alias ReadyMatch =
    { gameId : LobbyId
    , map : NamedMap
    , opponentName : String
    , remainingMilliseconds : Int
    }


type Activity
    = Available
    | Polling
    | Cancelling


type QueueState
    = Idle
    | Queued Ticket
    | Matched ReadyMatch


type alias Snapshot =
    { state : QueueState
    , lastGameSecondsAgo : Maybe Int
    }


type alias Flags =
    { matchMaking : Snapshot
    }


type Msg
    = NameInputChanged String
    | FindGameRequested
    | JoinResponseReceived String (Response Snapshot)
    | ReadyTimeReceived Time.Posix
    | ReadyTimerElapsed
    | WindowVisibilityChanged Browser.Events.Visibility
    | VisibleTimeReceived Time.Posix
    | PollTick
    | PollResponseReceived Ticket (Response Snapshot)
    | CancelButtonClicked
    | CancelResponseReceived Ticket (Response Snapshot)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


prepareVisit : Shared.Model -> ( VisitId, Shared.Model )
prepareVisit shared =
    let
        ( id, seed ) =
            Random.step VisitId.generator shared.seed
    in
    ( id, Shared.setSeed seed shared )


init : VisitId -> Shared.Model -> Flags -> ( Model, Eff Msg )
init id shared flags =
    let
        ( name, storageError ) =
            case UserName.fromLocalStorage shared.localStorage of
                Ok saved ->
                    ( Maybe.withDefault "" saved, Nothing )

                Err error ->
                    ( "", Just error )

        model : Model
        model =
            { shared = Shared.addError storageError shared
            , visit = id
            , name = name
            , stage = Entry
            , lastGameStartedAt = Nothing
            , error = Nothing
            }
    in
    receive flags.matchMaking model



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


fromLoadError : Graphql.Http.Error Flags -> Error
fromLoadError error =
    error
        |> Graphql.Http.mapError .matchMaking
        |> RequestFailed


visitId : Model -> VisitId
visitId model =
    model.visit


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


load : Graphql.Http.Request Flags
load =
    SS.succeed Flags
        |> SS.with (Api.Query.matchMaking selection)
        |> ApiRequest.queryRequest


{-| Best-effort departure during in-app navigation; closed documents expire
through the server's presence timeout.
-}
leave : Model -> Eff Msg
leave model =
    case model.stage of
        Waiting ((Ticket value) as ticket) _ ->
            Api.Mutation.leaveMatchMaking { ticket = value } selection
                |> ApiRequest.mutationRequest
                |> E.request (CancelResponseReceived ticket)

        _ ->
            E.none


selection : SelectionSet Snapshot Api.Union.MatchMakingSnapshot
selection =
    SnapshotApi.fragments
        { onMatchMakingIdle =
            SS.succeed (Snapshot Idle)
                |> SS.with IdleApi.lastGameStartedSecondsAgo
        , onMatchMakingWaiting =
            SS.succeed Snapshot
                |> SS.with (WaitingApi.ticket |> SS.map (Ticket >> Queued))
                |> SS.with WaitingApi.lastGameStartedSecondsAgo
        , onMatchMakingMatched =
            SS.succeed Snapshot
                |> SS.with
                    (SS.succeed ReadyMatch
                        |> SS.with (MatchedApi.gameId |> SS.mapOrFail LobbyId.parse)
                        |> SS.with (MatchedApi.map EditableMap.namedSelection)
                        |> SS.with MatchedApi.opponentName
                        |> SS.with MatchedApi.readyRemainingMilliseconds
                        |> SS.map Matched
                    )
                |> SS.with MatchedApi.lastGameStartedSecondsAgo
        }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setStage : Stage -> Model -> Model
setStage stage model =
    { model | stage = stage }


setError : Maybe Error -> Model -> Model
setError error model =
    { model | error = error }


receive : Snapshot -> Model -> ( Model, Eff Msg )
receive snapshot model =
    let
        f : Model -> ( Model, Eff Msg )
        f =
            case snapshot.state of
                Idle ->
                    setStage Entry >> E.withOut

                Queued ticket ->
                    setStage (Waiting ticket Available) >> E.withOut

                Matched found ->
                    if found.remainingMilliseconds <= 0 then
                        enterGame found

                    else
                        setStage (PreparingReady found)
                            >> E.with (E.now ReadyTimeReceived)
    in
    { model
        | lastGameStartedAt =
            snapshot.lastGameSecondsAgo
                |> Maybe.map
                    (\secondsAgo ->
                        Time.millisToPosix (Time.posixToMillis model.shared.now - secondsAgo * 1000)
                    )
        , error = Nothing
    }
        |> f


recentMatchSecondsAgo : Model -> Maybe Int
recentMatchSecondsAgo model =
    let
        elapsedSeconds : Time.Posix -> Int
        elapsedSeconds startedAt =
            max 0 ((Time.posixToMillis model.shared.now - Time.posixToMillis startedAt) // 1000)
    in
    Maybe.map elapsedSeconds model.lastGameStartedAt


enterGame : ReadyMatch -> Model -> ( Model, Eff Msg )
enterGame found model =
    model
        |> setStage EnteringGame
        |> E.with
            (Route.navigateReplacing model.shared.deployment
                (Route.Game found.gameId)
            )


join : Model -> ( Model, Eff Msg )
join model =
    let
        name : String
        name =
            String.trim model.name
    in
    if String.isEmpty name || (String.length name > 40) then
        model
            |> setError (Just InvalidName)
            |> E.withOut

    else
        let
            request : Graphql.Http.Request Snapshot
            request =
                Api.Mutation.joinMatchMaking { name = name } selection
                    |> ApiRequest.mutationRequest
        in
        ( model
            |> setStage Joining
            |> setError Nothing
        , E.request (JoinResponseReceived name) request
        )


activityText : Maybe Int -> String
activityText seconds =
    let
        ago : Int -> String -> String
        ago count unit =
            "last game started " ++ String.fromInt count ++ " " ++ unit ++ " ago"
    in
    case seconds of
        Nothing ->
            "no games started yet"

        Just elapsed ->
            if elapsed < 60 then
                "last game started just now"

            else if elapsed < 120 then
                ago 1 "minute"

            else if elapsed < 3600 then
                ago (elapsed // 60) "minutes"

            else if elapsed < 7200 then
                ago 1 "hour"

            else if elapsed < 86400 then
                ago (elapsed // 3600) "hours"

            else if elapsed < 172800 then
                ago 1 "day"

            else
                ago (elapsed // 86400) "days"


handoff : Graphql.Http.Error Snapshot -> Eff Msg
handoff error =
    if ApiRequest.requiresCurrentDeployment error then
        Route.load Route.MatchMaking

    else
        E.none



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        NameInputChanged name ->
            ( { model | name = name }, E.none )

        FindGameRequested ->
            case model.stage of
                Entry ->
                    join model

                _ ->
                    ( model, E.none )

        JoinResponseReceived submittedName result ->
            case ( model.stage, result ) of
                ( Joining, Ok snapshot ) ->
                    receive snapshot model
                        |> E.and (UserName.remember submittedName)

                ( Joining, Err error ) ->
                    model
                        |> setStage Entry
                        |> setError (Just (RequestFailed error))
                        |> E.with (handoff error)

                _ ->
                    ( model, E.none )

        ReadyTimeReceived now ->
            case model.stage of
                PreparingReady found ->
                    let
                        endsAt : Time.Posix
                        endsAt =
                            Time.millisToPosix
                                (Time.posixToMillis now + found.remainingMilliseconds)
                    in
                    ( setStage (GettingReady found endsAt) model
                    , E.batch
                        [ E.audio Audio.matchMakingReady
                        , E.after
                            (toFloat found.remainingMilliseconds)
                            ReadyTimerElapsed
                        ]
                    )

                _ ->
                    E.withOut model

        ReadyTimerElapsed ->
            case model.stage of
                GettingReady found _ ->
                    enterGame found model

                _ ->
                    E.withOut model

        WindowVisibilityChanged visibility ->
            case visibility of
                Browser.Events.Visible ->
                    ( model, E.now VisibleTimeReceived )

                Browser.Events.Hidden ->
                    E.withOut model

        VisibleTimeReceived now ->
            case model.stage of
                GettingReady found endsAt ->
                    if Time.posixToMillis now >= Time.posixToMillis endsAt then
                        enterGame found model

                    else
                        E.withOut model

                _ ->
                    E.withOut model

        PollTick ->
            case model.stage of
                Waiting ((Ticket value) as ticket) Available ->
                    ( model
                        |> setStage (Waiting ticket Polling)
                    , Api.Mutation.pollMatchMaking { ticket = value } selection
                        |> ApiRequest.mutationRequest
                        |> E.request (PollResponseReceived ticket)
                    )

                _ ->
                    ( model, E.none )

        PollResponseReceived ticket result ->
            case model.stage of
                Waiting current Polling ->
                    if ticket == current then
                        case result of
                            Ok snapshot ->
                                case snapshot.state of
                                    Idle ->
                                        model
                                            |> setStage Entry
                                            |> setError (Just QueueStopped)
                                            |> E.withOut

                                    _ ->
                                        receive snapshot model

                            Err error ->
                                model
                                    |> setStage (Waiting ticket Available)
                                    |> setError (Just (RequestFailed error))
                                    |> E.with (handoff error)

                    else
                        ( model, E.none )

                _ ->
                    ( model, E.none )

        CancelButtonClicked ->
            case model.stage of
                Waiting ((Ticket value) as ticket) activity ->
                    if activity == Cancelling then
                        ( model, E.none )

                    else
                        ( model
                            |> setStage (Waiting ticket Cancelling)
                            |> setError Nothing
                        , Api.Mutation.leaveMatchMaking { ticket = value } selection
                            |> ApiRequest.mutationRequest
                            |> E.request (CancelResponseReceived ticket)
                        )

                _ ->
                    ( model, E.none )

        CancelResponseReceived ticket result ->
            case model.stage of
                Waiting current Cancelling ->
                    if ticket == current then
                        case result of
                            Ok snapshot ->
                                receive snapshot model

                            Err error ->
                                model
                                    |> setStage (Waiting ticket Available)
                                    |> setError (Just (RequestFailed error))
                                    |> E.with (handoff error)

                    else
                        ( model, E.none )

                _ ->
                    ( model, E.none )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    let
        content : List (Html Msg)
        content =
            case model.stage of
                Entry ->
                    [ H.form
                        [ Ev.onSubmit FindGameRequested
                        , A.css
                            [ S.col
                            , S.g4
                            ]
                        ]
                        [ H.label
                            [ A.css
                                [ S.col
                                , S.g2
                                ]
                            ]
                            [ H.text "user name"
                            , TextField.simple model.name NameInputChanged
                                |> TextField.withHtmlId "match-making-user-name"
                                |> TextField.toHtml
                            ]
                        , Button.primary "find a game" FindGameRequested
                            |> Button.fullWidth
                            |> Button.toHtml
                        ]
                    ]

                Joining ->
                    waitingContent (recentMatchSecondsAgo model) (Button.disabled "cancel")

                Waiting _ Cancelling ->
                    waitingContent (recentMatchSecondsAgo model) (Button.disabled "cancel")

                Waiting _ _ ->
                    waitingContent (recentMatchSecondsAgo model) (Button.secondary "cancel" CancelButtonClicked)

                PreparingReady found ->
                    readyContent found found.remainingMilliseconds

                GettingReady found endsAt ->
                    readyContent found
                        (Time.posixToMillis endsAt - Time.posixToMillis model.shared.now)

                EnteringGame ->
                    [ waitingStatus "starting game…" ]

        errors : List (Html Msg)
        errors =
            case model.error of
                Nothing ->
                    []

                Just error ->
                    [ errorView error ]
    in
    panel (content ++ errors)


loadFailedView : { error : Error, onRetry : msg } -> List (Html msg)
loadFailedView args =
    panel
        [ Button.secondary "try again" args.onRetry
            |> Button.toHtml
        , errorView args.error
        ]


errorToString : Error -> String
errorToString error =
    case error of
        InvalidName ->
            "enter a name between 1 and 40 characters."

        QueueStopped ->
            "match making stopped. find a game to try again."

        RequestFailed requestError ->
            ApiRequest.errorMessage requestError


errorView : Error -> Html msg
errorView error =
    H.p
        [ Aria.role Aria.Status
        , A.css
            [ S.m0
            , S.bgRed0
            , S.textGray5
            , S.p2
            ]
        ]
        [ H.text (errorToString error)
        ]


panel : List (Html msg) -> List (Html msg)
panel content =
    [ H.div
        [ A.css
            [ S.flex1
            , S.col
            , S.itemsCenter
            , S.justifyCenter
            , S.py8
            ]
        ]
        [ H.div
            [ A.css
                [ S.wFull
                , S.maxW96
                ]
            ]
            [ Card.toHtml Card.simple content
            ]
        ]
    ]


loadingView : List (Html msg)
loadingView =
    panel
        [ waitingStatus "loading match making…"
        ]


waitingStatus : String -> Html msg
waitingStatus text =
    H.div
        [ A.css
            [ S.col
            , S.itemsCenter
            , S.g4
            , S.py3
            ]
        ]
        [ H.p
            [ Aria.role Aria.Status
            , A.css
                [ S.m0
                , S.textGray5
                ]
            ]
            [ H.text text
            ]
        , LoadingBar.toHtml True
        ]


waitingContent : Maybe Int -> Button.Button Msg -> List (Html Msg)
waitingContent lastGameSecondsAgo cancel =
    [ waitingStatus "finding a game…"
    , H.p
        [ A.css
            [ S.m0
            , S.textAlignCenter
            , S.py3
            ]
        ]
        [ H.text (activityText lastGameSecondsAgo)
        ]
    , cancel
        |> Button.fullWidth
        |> Button.toHtml
    ]


readyContent : ReadyMatch -> Int -> List (Html Msg)
readyContent found millisecondsUntilReady =
    let
        remainingMilliseconds : Int
        remainingMilliseconds =
            clamp 0 found.remainingMilliseconds millisecondsUntilReady

        seconds : Int
        seconds =
            ceiling (toFloat remainingMilliseconds / 1000)
    in
    [ H.p
        [ A.css
            [ S.m0
            , S.textAlignCenter
            , S.textYellow5
            ]
        ]
        [ H.text "get ready"
        ]
    , H.p
        [ A.css
            [ S.m0
            , S.textAlignCenter
            , S.wrapAnywhere
            ]
        ]
        [ H.text ("opponent: " ++ found.opponentName)
        ]
    , H.div
        [ A.css
            [ S.wFull
            , S.h64
            , S.bgNightwood2
            , S.indentStrong
            ]
        ]
        [ MapPreview.toHtml found.map
        ]
    , H.p
        [ A.css
            [ S.m0
            , S.textAlignCenter
            ]
        ]
        [ H.text (MapId.label found.map.mapType)
        ]
    , H.p
        [ Aria.role Aria.Status
        , A.css
            [ S.m0
            , S.textAlignCenter
            , S.textYellow5
            ]
        ]
        [ H.text ("starting in " ++ String.fromInt seconds ++ "…")
        ]
    ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.stage of
        Waiting _ _ ->
            Time.every 2000 (\_ -> PollTick)

        GettingReady _ _ ->
            Browser.Events.onVisibilityChange WindowVisibilityChanged

        _ ->
            Sub.none
