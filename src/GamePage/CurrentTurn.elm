module GamePage.CurrentTurn exposing
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

import Browser.Events
import GameOutcome exposing (GameOutcome)
import GamePage.OrderPlanning as OrderPlanning
import GamePage.Selection exposing (Selection)
import InvariantCheck as IC exposing (InvariantCheck)
import Json.Decode as Decode
import Time
import Turn
import TurnLifecycle exposing (Phase)
import TurnPlayback
import Util.Html.Event as HtmlEvent



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
    | PlaybackFrameElapsed Float
    | CombatEnterReleased
    | CombatSeeMapReleased


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
    receive observation { model | refreshing = False }


pollFailed : String -> Model -> Model
pollFailed error model =
    { model | refreshing = False, error = Just error }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


receive : Observation -> Model -> Model
receive observation model =
    if observation.turn.number < model.number then
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
    let
        playback : Maybe TurnPlayback.Playback
        playback =
            TurnLifecycle.playback model.phase

        panel : Maybe TurnPlayback.Panel
        panel =
            playback |> Maybe.andThen TurnPlayback.panels

        animationFrames : Sub Msg
        animationFrames =
            if playback /= Nothing then
                Browser.Events.onAnimationFrameDelta PlaybackFrameElapsed

            else
                Sub.none

        combatKeys : Sub Msg
        combatKeys =
            if panel /= Nothing then
                Browser.Events.onKeyUp (HtmlEvent.enter CombatEnterReleased)

            else
                Sub.none

        mapRelease : Sub Msg
        mapRelease =
            if Maybe.map .mapView panel == Just TurnPlayback.SeeingMap then
                Browser.Events.onMouseUp (Decode.succeed CombatSeeMapReleased)

            else
                Sub.none
    in
    Sub.batch
        [ Time.every 2000 (\_ -> PollTimerElapsed)
        , animationFrames
        , combatKeys
        , mapRelease
        ]
