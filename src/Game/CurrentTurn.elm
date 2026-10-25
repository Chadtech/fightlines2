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
    { model | introduction = IntroductionAcknowledged }


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
                    { currentTurn = { model | phase = TurnLifecycle.startTurn False frames }
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
            { model | phase = TurnLifecycle.Planning state }
    in
    case ( model.outcome, model.phase ) of
        ( Nothing, TurnLifecycle.Planning state ) ->
            transition state
                |> IC.map withPlanning

        _ ->
            IC.happy model


setSelection : Maybe Selection -> Model -> Model
setSelection selected model =
    { model | phase = TurnLifecycle.setSelection selected model.phase }


startSubmission : Model -> Maybe Model
startSubmission model =
    let
        phase : Phase
        phase =
            TurnLifecycle.startSubmission model.number model.phase
    in
    case ( model.outcome, model.phase, phase ) of
        ( Nothing, TurnLifecycle.Planning _, TurnLifecycle.Submitting _ ) ->
            Just { model | phase = phase, error = Nothing }

        _ ->
            Nothing


submissionSucceeded : Int -> Observation -> Model -> Model
submissionSucceeded originatingTurn observation model =
    if originatingTurn /= model.number then
        model

    else
        receive observation
            { model
                | phase =
                    TurnLifecycle.finishSubmission
                        originatingTurn
                        model.phase
                , error = Nothing
            }


submissionFailed : Int -> String -> Model -> Model
submissionFailed originatingTurn error model =
    case model.phase of
        TurnLifecycle.Submitting _ ->
            if originatingTurn == model.number then
                { model
                    | phase = TurnLifecycle.finishSubmission originatingTurn model.phase
                    , error = Just error
                }

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
        { model | refreshing = False }

    else
        receive observation { model | refreshing = False }


pollFailed : String -> Model -> Model
pollFailed error model =
    { model | refreshing = False, error = Just error }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


receive : Observation -> Model -> Model
receive observation model =
    if model.outcome /= Nothing then
        model

    else if GameOutcome.isResignation observation.turn.outcome then
        { model
            | number = observation.turn.number
            , outcome = observation.turn.outcome
            , opponentSubmitted = observation.turn.opponentSubmitted
            , resolution = Nothing
            , phase = TurnLifecycle.Planning OrderPlanning.init
            , error = Nothing
            , introduction = AwaitingIntroduction []
        }

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
        { model
            | outcome = observation.turn.outcome
            , opponentSubmitted = model.opponentSubmitted || observation.turn.opponentSubmitted
            , resolution = observation.turn.resolution
            , phase = reconciledPhase
        }

    else
        { model
            | number = observation.turn.number
            , outcome = observation.turn.outcome
            , opponentSubmitted = observation.turn.opponentSubmitted
            , resolution = observation.turn.resolution
            , phase = TurnLifecycle.startTurn observation.turn.submitted observation.playbackFrames
            , error = Nothing
            , introduction = AwaitingIntroduction observation.playbackFrames
        }



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
