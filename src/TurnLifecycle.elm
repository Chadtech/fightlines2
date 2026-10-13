module TurnLifecycle exposing
    ( Phase(..)
    , Submission
    , WaitingState
    , acknowledgeLoss
    , canPoll
    , continueCombat
    , finishSubmission
    , mapPlanning
    , observeSubmission
    , orders
    , planning
    , planningLocked
    , playback
    , selection
    , setCombatMapView
    , setOrders
    , setSelection
    , startSubmission
    , startTurn
    , tick
    , tickUntilLoss
    , toLabel
    )

import GamePage.OrderPlanning as OrderPlanning
import GamePage.Selection as Selection exposing (Inspection, Selection(..))
import PlannedOrder exposing (PlannedOrder)
import TurnPlayback
import UnitId exposing (UnitId)


type Phase
    = Planning OrderPlanning.Model
    | Submitting Submission
    | WaitingForOpponent WaitingState
    | Playing PlaybackState


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
        Planning state ->
            OrderPlanning.orders state

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


{-| Apply a planning transition only while planning remains editable.
-}
mapPlanning : (OrderPlanning.Model -> OrderPlanning.Model) -> Phase -> Phase
mapPlanning transition phase =
    case phase of
        Planning state ->
            Planning (transition state)

        _ ->
            phase


planning : Phase -> Maybe OrderPlanning.Model
planning phase =
    case phase of
        Planning state ->
            Just state

        _ ->
            Nothing


setOrders : List PlannedOrder -> Phase -> Phase
setOrders drafts =
    mapPlanning (OrderPlanning.setOrders drafts)


{-| Each phase owns exactly one selection. Locked phases store only inspection;
editable interactions can be stored only in OrderPlanning.
-}
selection : Phase -> Maybe Selection
selection phase =
    case phase of
        Planning state ->
            OrderPlanning.selection state

        Submitting submission ->
            Maybe.map Inspecting submission.inspection

        WaitingForOpponent waiting ->
            Maybe.map Inspecting waiting.inspection

        Playing playing ->
            Maybe.map Inspecting playing.inspection


setSelection : Maybe Selection -> Phase -> Phase
setSelection selected phase =
    case phase of
        Planning state ->
            Planning (OrderPlanning.setSelection selected state)

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
        Planning state ->
            Planning (OrderPlanning.setSelection (Maybe.map Inspecting inspection) state)

        Submitting submission ->
            Submitting { submission | inspection = inspection }

        WaitingForOpponent waiting ->
            WaitingForOpponent { waiting | inspection = inspection }

        Playing playing ->
            Playing { playing | inspection = inspection }


startSubmission : Int -> Phase -> Phase
startSubmission turnNumber phase =
    case phase of
        Planning state ->
            case OrderPlanning.submissionDrafts state of
                Just drafts ->
                    submissionFromDrafts turnNumber drafts

                Nothing ->
                    phase

        _ ->
            phase


submissionFromDrafts : Int -> OrderPlanning.Drafts -> Phase
submissionFromDrafts turnNumber drafts =
    Submitting
        { turnNumber = turnNumber
        , orders = drafts.orders
        , inspection = Maybe.map Selection.toInspection drafts.selection
        }


{-| Return drafts after the matching request finishes. A poll may already have
confirmed submission or advanced the turn; neither state may be unlocked here.
-}
finishSubmission : Int -> Phase -> Phase
finishSubmission turnNumber phase =
    case phase of
        Submitting submission ->
            if submission.turnNumber == turnNumber then
                resumePlanning submission.orders submission.inspection

            else
                phase

        _ ->
            phase


observeSubmission : Bool -> Phase -> Phase
observeSubmission submitted phase =
    if submitted then
        case phase of
            Planning _ ->
                WaitingForOpponent { orders = orders phase, inspection = Maybe.map Selection.toInspection (selection phase) }

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


continueCombat : Phase -> Maybe { phase : Phase, frame : TurnPlayback.Frame }
continueCombat phase =
    case phase of
        Playing playing ->
            let
                continued :
                    { animation : TurnPlayback.Playback
                    , frame : TurnPlayback.Frame
                    }
                    -> { phase : Phase, frame : TurnPlayback.Frame }
                continued next =
                    { phase = Playing { playing | animation = next.animation }
                    , frame = next.frame
                    }
            in
            TurnPlayback.continueCombat playing.animation |> Maybe.map continued

        _ ->
            Nothing


acknowledgeLoss : UnitId -> Phase -> Phase
acknowledgeLoss unitId phase =
    case phase of
        Playing playing ->
            Playing { playing | animation = TurnPlayback.acknowledgeLoss unitId playing.animation }

        _ ->
            phase


setCombatMapView : TurnPlayback.MapView -> Phase -> Phase
setCombatMapView mapView phase =
    case phase of
        Playing playing ->
            Playing { playing | animation = TurnPlayback.setMapView mapView playing.animation }

        _ ->
            phase


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
            observeSubmission submitted (Planning OrderPlanning.init)

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
tick =
    tickWith TurnPlayback.tick


tickUntilLoss : Float -> Phase -> Maybe { phase : Phase, frame : TurnPlayback.Frame }
tickUntilLoss =
    tickWith TurnPlayback.tickUntilLoss


tickWith : (Float -> TurnPlayback.Playback -> ( Maybe TurnPlayback.Playback, TurnPlayback.Frame )) -> Float -> Phase -> Maybe { phase : Phase, frame : TurnPlayback.Frame }
tickWith advance delta phase =
    case phase of
        Playing playing ->
            let
                ( remaining, frame ) =
                    advance delta playing.animation

                ready : Phase
                ready =
                    case playing.afterPlayback of
                        StartPlanning ->
                            resumePlanning [] playing.inspection

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


resumePlanning : List PlannedOrder -> Maybe Inspection -> Phase
resumePlanning drafts inspection =
    OrderPlanning.init
        |> OrderPlanning.setOrders drafts
        |> OrderPlanning.setSelection (Maybe.map Inspecting inspection)
        |> Planning
