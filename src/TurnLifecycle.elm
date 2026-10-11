module TurnLifecycle exposing
    ( Phase(..)
    , PlanningState
    , Submission
    , canPoll
    , editing
    , finishSubmission
    , initPlanningState
    , observeSubmission
    , orders
    , planningLocked
    , playback
    , setEditing
    , setOrders
    , startTurn
    , tick
    , toLabel
    )

import GamePage.EditingSelection exposing (EditingSelection)
import PlannedOrder exposing (PlannedOrder)
import TurnPlayback


type Phase
    = Planning PlanningState
    | Submitting Submission
    | WaitingForOpponent (List PlannedOrder)
    | Playing PlaybackState


type alias PlanningState =
    { orders : List PlannedOrder
    , editing : Maybe EditingSelection
    }


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


initPlanningState : PlanningState
initPlanningState =
    { orders = []
    , editing = Nothing
    }


toLabel : Phase -> String
toLabel phase =
    case phase of
        Playing _ ->
            "playing turn…"

        Submitting _ ->
            "submitting…"

        WaitingForOpponent _ ->
            "turn submitted"

        Planning _ ->
            "submit turn"


orders : Phase -> List PlannedOrder
orders phase =
    case phase of
        Planning planning ->
            planning.orders

        Submitting submission ->
            submission.orders

        WaitingForOpponent submitted ->
            submitted

        Playing _ ->
            []


planningLocked : Phase -> Bool
planningLocked phase =
    case phase of
        Planning _ ->
            False

        Submitting _ ->
            True

        WaitingForOpponent _ ->
            True

        Playing _ ->
            True


setOrders : List PlannedOrder -> Phase -> Phase
setOrders drafts phase =
    case phase of
        Planning planning ->
            Planning { planning | orders = drafts }

        _ ->
            phase


{-| Editable page interactions exist only while planning. Locking orders or
starting playback discards them without requiring the page to clear fields.
-}
editing : Phase -> Maybe EditingSelection
editing phase =
    case phase of
        Planning planning ->
            planning.editing

        _ ->
            Nothing


setEditing : Maybe EditingSelection -> Phase -> Phase
setEditing interaction phase =
    case phase of
        Planning planning ->
            Planning { planning | editing = interaction }

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
                Planning { orders = submission.orders, editing = Nothing }

            else
                phase

        _ ->
            phase


observeSubmission : Bool -> Phase -> Phase
observeSubmission submitted phase =
    if submitted then
        case phase of
            Planning planning ->
                WaitingForOpponent planning.orders

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
            observeSubmission submitted (Planning initPlanningState)

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
                            Planning initPlanningState

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
