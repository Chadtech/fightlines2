module TurnLifecycle exposing
    ( Phase(..)
    , Submission
    , canPoll
    , finishSubmission
    , observeSubmission
    , orders
    , playback
    , setOrders
    , startTurn
    , tick
    )

import PlannedOrder exposing (PlannedOrder)
import TurnPlayback


type Phase
    = Planning (List PlannedOrder)
    | Submitting Submission
    | WaitingForOpponent (List PlannedOrder)
    | Playing PlaybackState


type alias PlaybackState =
    { animation : TurnPlayback.Playback
    , afterPlayback : AfterPlayback
    }


type AfterPlayback
    = StartPlanning
    | WaitForOpponent


type alias Submission =
    { turnNumber : Int
    , orders : List PlannedOrder
    }


orders : Phase -> List PlannedOrder
orders phase =
    case phase of
        Planning drafts ->
            drafts

        Submitting submission ->
            submission.orders

        WaitingForOpponent submitted ->
            submitted

        Playing _ ->
            []


setOrders : List PlannedOrder -> Phase -> Phase
setOrders drafts phase =
    case phase of
        Planning _ ->
            Planning drafts

        _ ->
            phase


{-| Return drafts after the matching request finishes. A poll may already have
confirmed submission or advanced the turn; neither state may be unlocked here.
-}
finishSubmission : Int -> Phase -> Phase
finishSubmission turnNumber phase =
    case phase of
        Submitting submission ->
            if submission.turnNumber == turnNumber then
                Planning submission.orders

            else
                phase

        _ ->
            phase


observeSubmission : Bool -> Phase -> Phase
observeSubmission submitted phase =
    if submitted then
        case phase of
            Planning drafts ->
                WaitingForOpponent drafts

            Submitting submission ->
                WaitingForOpponent submission.orders

            WaitingForOpponent _ ->
                phase

            Playing playing ->
                Playing { playing | afterPlayback = WaitForOpponent }

    else
        phase


playback : Phase -> Maybe TurnPlayback.Playback
playback phase =
    case phase of
        Playing playing ->
            Just playing.animation

        _ ->
            Nothing


canPoll : Phase -> Bool
canPoll phase =
    case phase of
        Planning _ ->
            True

        WaitingForOpponent _ ->
            True

        Submitting _ ->
            False

        Playing _ ->
            False


startTurn : Bool -> List TurnPlayback.Frame -> Phase
startTurn submitted frames =
    let
        ready : Phase
        ready =
            observeSubmission submitted (Planning [])

        afterPlayback : AfterPlayback
        afterPlayback =
            if submitted then
                WaitForOpponent

            else
                StartPlanning
    in
    case TurnPlayback.start frames of
        Just animation ->
            Playing { animation = animation, afterPlayback = afterPlayback }

        Nothing ->
            ready


tick : Float -> Phase -> Maybe { phase : Phase, frame : TurnPlayback.Frame }
tick delta phase =
    case phase of
        Playing playing ->
            let
                ( remaining, frame ) =
                    TurnPlayback.tick delta playing.animation

                ready : Phase
                ready =
                    case playing.afterPlayback of
                        StartPlanning ->
                            Planning []

                        WaitForOpponent ->
                            WaitingForOpponent []

                next : Phase
                next =
                    case remaining of
                        Just animation ->
                            Playing { playing | animation = animation }

                        Nothing ->
                            ready
            in
            Just { phase = next, frame = frame }

        _ ->
            Nothing
