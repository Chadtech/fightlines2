module GamePage.CurrentTurn exposing
    ( Model
    , Msg(..)
    , Observation
    , acknowledgeIntroduction
    , init
    , introductionPending
    , mapPlanning
    , pollFailed
    , pollSucceeded
    , setSelection
    , startSubmission
    , submissionFailed
    , submissionSucceeded
    , subscriptions
    )

import Browser.Events
import GamePage.OrderPlanning as OrderPlanning
import GamePage.Selection exposing (Selection)
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
    , opponentSubmitted : Bool
    , resolution : Maybe Turn.Resolution
    , phase : Phase
    , refreshing : Bool
    , error : Maybe String
    , introduction : Introduction
    }


type Introduction
    = AwaitingIntroduction
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


init : Turn.Snapshot -> Model
init turn =
    { number = turn.number
    , opponentSubmitted = turn.opponentSubmitted
    , resolution = turn.resolution
    , phase = TurnLifecycle.observeSubmission turn.submitted (TurnLifecycle.Planning OrderPlanning.init)
    , refreshing = False
    , error = Nothing
    , introduction = AwaitingIntroduction
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


introductionPending : Model -> Bool
introductionPending model =
    model.introduction == AwaitingIntroduction && not (TurnLifecycle.planningLocked model.phase)


acknowledgeIntroduction : Model -> Model
acknowledgeIntroduction model =
    { model | introduction = IntroductionAcknowledged }


mapPlanning : (OrderPlanning.Model -> OrderPlanning.Model) -> Model -> Model
mapPlanning transition model =
    { model | phase = TurnLifecycle.mapPlanning transition model.phase }


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
    case ( model.phase, phase ) of
        ( TurnLifecycle.Planning _, TurnLifecycle.Submitting _ ) ->
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
            | opponentSubmitted = model.opponentSubmitted || observation.turn.opponentSubmitted
            , resolution = observation.turn.resolution
            , phase = reconciledPhase
        }

    else
        { model
            | number = observation.turn.number
            , opponentSubmitted = observation.turn.opponentSubmitted
            , resolution = observation.turn.resolution
            , phase = TurnLifecycle.startTurn observation.turn.submitted observation.playbackFrames
            , error = Nothing
            , introduction = AwaitingIntroduction
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
