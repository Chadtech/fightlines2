module Game.Inactivity exposing
    ( Inactivity(..)
    , Model
    , Report
    , beginReport
    , countdownSeconds
    , error
    , failed
    , init
    , nextTurn
    , observe
    , pending
    , recordInteraction
    , reportDelay
    , reportingContext
    , selection
    , sequence
    , succeeded
    )

import Api.Enum.InactivityRenewalReason exposing (InactivityRenewalReason(..))
import Api.Object
import Api.Object.EnabledInactivity as EnabledInactivityApi
import Api.Object.GameSnapshot as SnapshotApi
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Time



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Inactivity
    = Disabled
    | Enabled (Maybe Int)


type ReportingContext
    = ReportingDisabled
    | ReportingEnabled
    | WarningOpen


{-| Disabled activity cannot carry a countdown or any reporting state.
Local sequencing keeps delayed polls from restoring an acknowledged warning.
-}
type Model
    = DisabledActivity
    | EnabledActivity EnabledState


type alias EnabledState =
    { countdown : Maybe Countdown
    , dirty : Bool
    , sequence : Int
    , request : Request
    , lastSent : Maybe Time.Posix
    , error : Maybe String
    }


type alias Countdown =
    { seconds : Int
    , observedAt : Time.Posix
    }


type Request
    = Ready
    | Sending Report


type alias Report =
    { sequence : Int
    , turnNumber : Int
    , reason : InactivityRenewalReason
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Time.Posix -> Inactivity -> Model
init now inactivity =
    case inactivity of
        Disabled ->
            DisabledActivity

        Enabled remaining ->
            EnabledActivity
                { countdown = Maybe.map (\seconds -> Countdown seconds now) remaining
                , dirty = False
                , sequence = 0
                , request = Ready
                , lastSent = Nothing
                , error = Nothing
                }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


receive : Time.Posix -> Inactivity -> Model -> Model
receive now inactivity model =
    case ( inactivity, model ) of
        ( Disabled, _ ) ->
            DisabledActivity

        ( Enabled _, DisabledActivity ) ->
            init now inactivity

        ( Enabled remaining, EnabledActivity state ) ->
            EnabledActivity
                { state
                    | countdown = Maybe.map (\seconds -> Countdown seconds now) remaining
                }


reportIntervalMilliseconds : Int
reportIntervalMilliseconds =
    10000


reportWaitMilliseconds : Time.Posix -> EnabledState -> Int
reportWaitMilliseconds now state =
    case state.lastSent of
        Nothing ->
            0

        Just sent ->
            if state.dirty && (state.countdown /= Nothing) then
                0

            else
                let
                    elapsedMilliseconds : Int
                    elapsedMilliseconds =
                        Time.posixToMillis now - Time.posixToMillis sent
                in
                max 0 (reportIntervalMilliseconds - elapsedMilliseconds)


reportReason :
    Maybe InactivityRenewalReason
    -> EnabledState
    -> Maybe InactivityRenewalReason
reportReason presentation state =
    if state.dirty then
        Just UserInteraction

    else
        presentation



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| GraphQL null represents Disabled; the enabled object owns optional warning
seconds. Decode directly into the domain type without a Boolean/Maybe pair.
-}
selection : SelectionSet Inactivity Api.Object.GameSnapshot
selection =
    SnapshotApi.inactivity (SS.map Enabled EnabledInactivityApi.warningSecondsRemaining)
        |> SS.map (Maybe.withDefault Disabled)


recordInteraction : Model -> Model
recordInteraction model =
    case model of
        DisabledActivity ->
            model

        EnabledActivity state ->
            EnabledActivity { state | dirty = True }


sequence : Model -> Int
sequence model =
    case model of
        DisabledActivity ->
            0

        EnabledActivity state ->
            state.sequence


pending : Model -> Bool
pending model =
    case model of
        DisabledActivity ->
            False

        EnabledActivity state ->
            case state.request of
                Ready ->
                    False

                Sending _ ->
                    True


error : Model -> Maybe String
error model =
    case model of
        DisabledActivity ->
            Nothing

        EnabledActivity state ->
            state.error


countdownSeconds : Time.Posix -> Model -> Maybe Int
countdownSeconds now model =
    case model of
        DisabledActivity ->
            Nothing

        EnabledActivity state ->
            let
                remaining : Countdown -> Int
                remaining countdown =
                    max 0 (countdown.seconds - (Time.posixToMillis now - Time.posixToMillis countdown.observedAt) // 1000)
            in
            Maybe.map remaining state.countdown


observe : Time.Posix -> Int -> Inactivity -> Model -> Model
observe now responseSequence inactivity model =
    if (responseSequence == sequence model) && not (pending model) then
        receive now inactivity model

    else
        model


{-| Server observations affect report timing when they enable reporting or
open or close a warning. Updating the displayed seconds has no such effect.
-}
reportingContext : Model -> ReportingContext
reportingContext model =
    case model of
        DisabledActivity ->
            ReportingDisabled

        EnabledActivity { countdown } ->
            case countdown of
                Nothing ->
                    ReportingEnabled

                Just _ ->
                    WarningOpen


{-| Milliseconds until a pending interaction or presentation can be reported.
-}
reportDelay :
    Time.Posix
    -> Maybe InactivityRenewalReason
    -> Model
    -> Maybe Int
reportDelay now presentation model =
    case model of
        EnabledActivity state ->
            case ( state.request, reportReason presentation state ) of
                ( Ready, Just _ ) ->
                    Just (reportWaitMilliseconds now state)

                _ ->
                    Nothing

        DisabledActivity ->
            Nothing


beginReport :
    Time.Posix
    ->
        { turnNumber : Int
        , presentation : Maybe InactivityRenewalReason
        }
    -> Model
    -> ( Model, Maybe Report )
beginReport now context model =
    case model of
        DisabledActivity ->
            ( model, Nothing )

        EnabledActivity state ->
            case ( reportReason context.presentation state, state.request ) of
                ( Just kind, Ready ) ->
                    if reportWaitMilliseconds now state == 0 then
                        let
                            report : Report
                            report =
                                { sequence = state.sequence + 1
                                , turnNumber = context.turnNumber
                                , reason = kind
                                }
                        in
                        ( EnabledActivity
                            { state
                                | sequence = report.sequence
                                , dirty = False
                                , request = Sending report
                                , lastSent = Just now
                            }
                        , Just report
                        )

                    else
                        ( model, Nothing )

                _ ->
                    ( model, Nothing )


nextTurn : Model -> Model
nextTurn model =
    case model of
        DisabledActivity ->
            model

        EnabledActivity state ->
            EnabledActivity
                { state
                    | sequence = state.sequence + 1
                    , countdown = Nothing
                    , request = Ready
                    , lastSent = Nothing
                    , dirty = False
                    , error = Nothing
                }


succeeded : Time.Posix -> Report -> Inactivity -> Model -> Model
succeeded now report inactivity model =
    case model of
        DisabledActivity ->
            model

        EnabledActivity state ->
            if state.request == Sending report then
                EnabledActivity
                    { state
                        | request = Ready
                        , sequence = state.sequence + 1
                        , error = Nothing
                    }
                    |> receive now inactivity

            else
                model


failed : Report -> String -> Model -> Model
failed report message model =
    case model of
        DisabledActivity ->
            model

        EnabledActivity state ->
            if state.request == Sending report then
                EnabledActivity
                    { state
                        | request = Ready
                        , dirty = state.dirty || (report.reason == UserInteraction)
                        , error = Just message
                    }

            else
                model
