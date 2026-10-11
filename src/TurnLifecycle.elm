module TurnLifecycle exposing
    ( Phase(..)
    , PlanningState
    , Submission
    , WaitingState
    , canPoll
    , finishSubmission
    , initPlanningState
    , observeSubmission
    , orders
    , planningLocked
    , playback
    , selection
    , setOrders
    , setSelection
    , startSubmission
    , startTurn
    , tick
    , toLabel
    )

import GamePage.Selection as Selection
    exposing
        ( Inspection
        , Selection(..)
        )
import PlannedOrder exposing (PlannedOrder)
import TurnPlayback


type Phase
    = Planning PlanningState
    | Submitting Submission
    | WaitingForOpponent WaitingState
    | Playing PlaybackState


type alias PlanningState =
    { orders : List PlannedOrder
    , selection : Maybe Selection
    }


type alias PlaybackState =
    { animation : TurnPlayback.Playback
    , inspection : Maybe Inspection
    , afterPlayback : AfterPlayback
    }


type AfterPlayback
    = StartPlanning
    | WaitForOpponent


type alias Submission =
    { turnNumber : Int
    , orders : List PlannedOrder
    , inspection : Maybe Inspection
    }


type alias WaitingState =
    { orders : List PlannedOrder
    , inspection : Maybe Inspection
    }


initPlanningState : PlanningState
initPlanningState =
    { orders = []
    , selection = Nothing
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
            submitted.orders

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


{-| Each phase owns exactly one selection. Locked phases store only inspection;
editable interactions can be stored only in PlanningState.
-}
selection : Phase -> Maybe Selection
selection phase =
    case phase of
        Planning planning ->
            planning.selection

        Submitting submission ->
            Maybe.map Inspecting submission.inspection

        WaitingForOpponent waiting ->
            Maybe.map Inspecting waiting.inspection

        Playing playing ->
            Maybe.map Inspecting playing.inspection


setSelection : Maybe Selection -> Phase -> Phase
setSelection selected phase =
    case phase of
        Planning planning ->
            Planning { planning | selection = selected }

        _ ->
            case selected of
                Nothing ->
                    setInspection Nothing phase

                Just (Inspecting inspection) ->
                    setInspection (Just inspection) phase

                _ ->
                    phase


setInspection : Maybe Inspection -> Phase -> Phase
setInspection inspection phase =
    case phase of
        Planning planning ->
            Planning { planning | selection = Maybe.map Inspecting inspection }

        Submitting submission ->
            Submitting { submission | inspection = inspection }

        WaitingForOpponent waiting ->
            WaitingForOpponent { waiting | inspection = inspection }

        Playing playing ->
            Playing { playing | inspection = inspection }


startSubmission : Int -> Phase -> Phase
startSubmission turnNumber phase =
    case phase of
        Planning planning ->
            Submitting
                { turnNumber = turnNumber
                , orders = planning.orders
                , inspection = Maybe.map Selection.toInspection planning.selection
                }

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
                Planning { orders = submission.orders, selection = Maybe.map Inspecting submission.inspection }

            else
                phase

        _ ->
            phase


observeSubmission : Bool -> Phase -> Phase
observeSubmission submitted phase =
    if submitted then
        case phase of
            Planning planning ->
                WaitingForOpponent { orders = planning.orders, inspection = Maybe.map Selection.toInspection planning.selection }

            Submitting submission ->
                WaitingForOpponent { orders = submission.orders, inspection = submission.inspection }

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
            Playing { animation = animation, inspection = Nothing, afterPlayback = afterPlayback }

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
                            Planning { initPlanningState | selection = Maybe.map Inspecting playing.inspection }

                        WaitForOpponent ->
                            WaitingForOpponent { orders = [], inspection = playing.inspection }

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
