module Game.CurrentTurn exposing
    ( Model
    , Msg(..)
    , Observation
    , acknowledgeIntroduction
    , canReplay
    , init
    , introductionPending
    , mapPlanning
    , pollFailed
    , pollSucceeded
    , replay
    , setError
    , setPhase
    , setRefreshing
    , setSelection
    , startSubmission
    , submissionFailed
    , submissionSucceeded
    , subscriptions
    )

import Game.OrderPlanning as OrderPlanning
import Game.Outcome as GameOutcome exposing (GameOutcome)
import Game.PlaybackPresentation as PlaybackPresentation
import Game.Selection exposing (Selection)
import Game.Turn as Turn
import Game.TurnLifecycle as TurnLifecycle exposing (Phase)
import Game.TurnPlayback as TurnPlayback
import InvariantCheck as IC exposing (InvariantCheck)
import Time



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { number : Int
    , outcome : Maybe GameOutcome
    , opponentSubmitted : Bool
    , resolution : Maybe Turn.Resolution
    , phase : Phase
    , refreshing : Bool
    , error : Maybe String
    , introduction : Introduction
    }


type Introduction
    = AwaitingIntroduction (List TurnPlayback.Frame)
    | IntroductionAcknowledged


type Msg
    = PollTimerElapsed
    | GotPlaybackPresentationMsg PlaybackPresentation.Msg


type alias Observation =
    { turn : Turn.Snapshot
    , playbackFrames : List TurnPlayback.Frame
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Observation -> Model
init observation =
    let
        turn : Turn.Snapshot
        turn =
            observation.turn
    in
    { number = turn.number
    , outcome = turn.outcome
    , opponentSubmitted = turn.opponentSubmitted
    , resolution = turn.resolution
    , phase = TurnLifecycle.observeSubmission turn.submitted (TurnLifecycle.Planning OrderPlanning.init)
    , refreshing = False
    , error = Nothing
    , introduction = AwaitingIntroduction observation.playbackFrames
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


introductionPending : Model -> Bool
introductionPending model =
    case model.introduction of
        AwaitingIntroduction _ ->
            not (TurnLifecycle.planningLocked model.phase)

        IntroductionAcknowledged ->
            False


acknowledgeIntroduction : Model -> Model
acknowledgeIntroduction model =
    model
        |> setIntroduction IntroductionAcknowledged


{-| Replay is available only before acknowledging the new turn's introduction.
Retain the viewer-projected frames until then, including during replay itself.
-}
canReplay : Model -> Bool
canReplay model =
    case model.introduction of
        AwaitingIntroduction (_ :: _ :: _) ->
            (model.outcome == Nothing) && introductionPending model

        _ ->
            False


replay : Model -> Maybe { currentTurn : Model, frame : TurnPlayback.Frame }
replay model =
    if canReplay model then
        case model.introduction of
            AwaitingIntroduction ((first :: _) as frames) ->
                Just
                    { currentTurn =
                        model
                            |> setPhase (TurnLifecycle.startTurn False frames)
                    , frame = first
                    }

            _ ->
                Nothing

    else
        Nothing


{-| Apply a checked transition only while the turn permits planning edits.
The caller supplies the planning rules and diagnostic type.
-}
mapPlanning :
    (OrderPlanning.Model -> InvariantCheck error OrderPlanning.Model)
    -> Model
    -> InvariantCheck error Model
mapPlanning transition model =
    let
        withPlanning : OrderPlanning.Model -> Model
        withPlanning state =
            model
                |> setPhase (TurnLifecycle.Planning state)
    in
    case ( model.outcome, model.phase ) of
        ( Nothing, TurnLifecycle.Planning state ) ->
            transition state
                |> IC.map withPlanning

        _ ->
            IC.happy model


setSelection : Maybe Selection -> Model -> Model
setSelection selected model =
    model
        |> setPhase (TurnLifecycle.setSelection selected model.phase)


startSubmission : Model -> Maybe Model
startSubmission model =
    let
        phase : Phase
        phase =
            TurnLifecycle.startSubmission model.number model.phase
    in
    case ( model.outcome, model.phase, phase ) of
        ( Nothing, TurnLifecycle.Planning _, TurnLifecycle.Submitting _ ) ->
            Just
                (model
                    |> setPhase phase
                    |> setError Nothing
                )

        _ ->
            Nothing


submissionSucceeded : Int -> Observation -> Model -> Model
submissionSucceeded originatingTurn observation model =
    if originatingTurn /= model.number then
        model

    else
        receive observation
            (model
                |> setPhase
                    (TurnLifecycle.finishSubmission
                        originatingTurn
                        model.phase
                    )
                |> setError Nothing
            )


submissionFailed : Int -> String -> Model -> Model
submissionFailed originatingTurn error model =
    case model.phase of
        TurnLifecycle.Submitting _ ->
            if originatingTurn == model.number then
                model
                    |> setPhase (TurnLifecycle.finishSubmission originatingTurn model.phase)
                    |> setError (Just error)

            else
                model

        _ ->
            model


pollSucceeded : Observation -> Model -> Model
pollSucceeded observation model =
    let
        preservePlayback : Bool
        preservePlayback =
            (TurnLifecycle.playback model.phase /= Nothing) && not (GameOutcome.isResignation observation.turn.outcome)
    in
    if preservePlayback then
        model
            |> setRefreshing False

    else
        receive observation
            (model
                |> setRefreshing False
            )


pollFailed : String -> Model -> Model
pollFailed error model =
    model
        |> setRefreshing False
        |> setError (Just error)



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setIntroduction : Introduction -> Model -> Model
setIntroduction introduction model =
    { model | introduction = introduction }


setPhase : Phase -> Model -> Model
setPhase phase model =
    { model | phase = phase }


setError : Maybe String -> Model -> Model
setError error model =
    { model | error = error }


setRefreshing : Bool -> Model -> Model
setRefreshing refreshing model =
    { model | refreshing = refreshing }


setNumber : Int -> Model -> Model
setNumber number model =
    { model | number = number }


setOutcome : Maybe GameOutcome -> Model -> Model
setOutcome outcome model =
    { model | outcome = outcome }


setOpponentSubmitted : Bool -> Model -> Model
setOpponentSubmitted opponentSubmitted model =
    { model | opponentSubmitted = opponentSubmitted }


setResolution : Maybe Turn.Resolution -> Model -> Model
setResolution resolution model =
    { model | resolution = resolution }


receive : Observation -> Model -> Model
receive observation model =
    if model.outcome /= Nothing then
        model

    else if GameOutcome.isResignation observation.turn.outcome then
        model
            |> setNumber observation.turn.number
            |> setOutcome observation.turn.outcome
            |> setOpponentSubmitted observation.turn.opponentSubmitted
            |> setResolution Nothing
            |> setPhase (TurnLifecycle.Planning OrderPlanning.init)
            |> setError Nothing
            |> setIntroduction (AwaitingIntroduction [])

    else if observation.turn.number < model.number then
        model

    else if observation.turn.number == model.number then
        let
            choosingExits : Bool
            choosingExits =
                TurnLifecycle.planning model.phase
                    |> Maybe.andThen OrderPlanning.unloadPlanning
                    |> (/=) Nothing

            phase : Phase
            phase =
                TurnLifecycle.observeSubmission observation.turn.submitted model.phase

            reconciledPhase : Phase
            reconciledPhase =
                if observation.turn.submitted && choosingExits then
                    TurnLifecycle.setSelection Nothing phase

                else
                    phase
        in
        model
            |> setOutcome observation.turn.outcome
            |> setOpponentSubmitted (model.opponentSubmitted || observation.turn.opponentSubmitted)
            |> setResolution observation.turn.resolution
            |> setPhase reconciledPhase

    else
        model
            |> setNumber observation.turn.number
            |> setOutcome observation.turn.outcome
            |> setOpponentSubmitted observation.turn.opponentSubmitted
            |> setResolution observation.turn.resolution
            |> setPhase (TurnLifecycle.startTurn observation.turn.submitted observation.playbackFrames)
            |> setError Nothing
            |> setIntroduction (AwaitingIntroduction observation.playbackFrames)



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 500 (\_ -> PollTimerElapsed)
        , PlaybackPresentation.subscriptions (TurnLifecycle.playback model.phase)
            |> Sub.map GotPlaybackPresentationMsg
        ]
