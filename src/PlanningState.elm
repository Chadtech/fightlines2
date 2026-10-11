module PlanningState exposing
    ( Drafts
    , PlanningState(..)
    , UnloadChoice
    , UnloadPlanning
    , confirmUnloadPassengers
    , dismissDialog
    , init
    , orders
    , saveUnloadDestination
    , selection
    , setOrders
    , setSelection
    , showSubmissionWarning
    , startUnload
    , submissionDrafts
    , submissionWarningOpen
    , toggleUnloadPassenger
    , unloadChoice
    , unloadPlanning
    )

import Coordinate exposing (Coordinate)
import GamePage.Selection as Selection
    exposing
        ( DestinationFeedback(..)
        , Selection(..)
        )
import Movement
import PlannedOrder exposing (MovePlan, PlannedOrder)
import UnitId exposing (UnitId)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Planning has one active workflow. Unload stages own their truck move and
only other units' orders; dialogs and board inspection are derived from the stage.
-}
type PlanningState
    = OrdinaryPlanning Drafts
    | ConfirmingSubmission Drafts
    | ChoosingPassengers UnloadChoice
    | ChoosingExits UnloadPlanning


type alias Drafts =
    { orders : List PlannedOrder
    , selection : Maybe Selection
    }


type alias TruckMove =
    { truckId : UnitId
    , plan : MovePlan
    }


type alias UnloadChoice =
    { truck : TruckMove
    , otherOrders : List PlannedOrder
    , checked : List UnitId
    }


type alias UnloadPlanning =
    { truck : TruckMove
    , otherOrders : List PlannedOrder
    , passengerId : UnitId
    , remaining : List UnitId
    , options : List Movement.Option
    , destinationFeedback : DestinationFeedback
    }


type alias UnloadQueue =
    { truck : TruckMove
    , otherOrders : List PlannedOrder
    , passengers : List UnitId
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : PlanningState
init =
    OrdinaryPlanning { orders = [], selection = Nothing }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


orders : PlanningState -> List PlannedOrder
orders state =
    case state of
        OrdinaryPlanning drafts ->
            drafts.orders

        ConfirmingSubmission drafts ->
            drafts.orders

        ChoosingPassengers choice ->
            truckOrder choice.truck :: choice.otherOrders

        ChoosingExits unloading ->
            truckOrder unloading.truck :: unloading.otherOrders


setOrders : List PlannedOrder -> PlanningState -> PlanningState
setOrders draftsOrders state =
    case state of
        OrdinaryPlanning drafts ->
            OrdinaryPlanning { drafts | orders = draftsOrders }

        _ ->
            state


selection : PlanningState -> Maybe Selection
selection state =
    case state of
        OrdinaryPlanning drafts ->
            drafts.selection

        ConfirmingSubmission drafts ->
            drafts.selection

        ChoosingPassengers choice ->
            Just (Inspecting (Selection.UnitInspection choice.truck.truckId))

        ChoosingExits unloading ->
            Just (Inspecting (Selection.UnitInspection unloading.passengerId))


setSelection : Maybe Selection -> PlanningState -> PlanningState
setSelection selected state =
    OrdinaryPlanning { orders = orders state, selection = selected }


{-| Unfinished unloading cannot become a submission. The lifecycle consumes
these drafts only after planning is ready or its warning has been confirmed.
-}
submissionDrafts : PlanningState -> Maybe Drafts
submissionDrafts state =
    case state of
        OrdinaryPlanning drafts ->
            Just drafts

        ConfirmingSubmission drafts ->
            Just drafts

        _ ->
            Nothing


truckOrder : TruckMove -> PlannedOrder
truckOrder truck =
    { unitId = truck.truckId, action = PlannedOrder.Move truck.plan }


startUnload : UnitId -> Movement.Option -> PlanningState -> PlanningState
startUnload truckId move state =
    case state of
        OrdinaryPlanning drafts ->
            ChoosingPassengers
                { truck = { truckId = truckId, plan = { move = move, unloads = [] } }
                , otherOrders = List.filter (\order -> order.unitId /= truckId) drafts.orders
                , checked = []
                }

        _ ->
            state


unloadChoice : PlanningState -> Maybe UnloadChoice
unloadChoice state =
    case state of
        ChoosingPassengers choice ->
            Just choice

        _ ->
            Nothing


unloadPlanning : PlanningState -> Maybe UnloadPlanning
unloadPlanning state =
    case state of
        ChoosingExits unloading ->
            Just unloading

        _ ->
            Nothing


toggleUnloadPassenger : UnitId -> Bool -> PlanningState -> PlanningState
toggleUnloadPassenger id checked state =
    case state of
        ChoosingPassengers choice ->
            let
                retained : List UnitId
                retained =
                    List.filter ((/=) id) choice.checked

                selected : List UnitId
                selected =
                    if checked then
                        id :: retained

                    else
                        retained
            in
            ChoosingPassengers { choice | checked = selected }

        _ ->
            state


confirmUnloadPassengers : (PlanningState -> UnitId -> List Movement.Option) -> PlanningState -> PlanningState
confirmUnloadPassengers options state =
    case state of
        ChoosingPassengers choice ->
            nextUnloadPassenger options
                { truck = choice.truck, otherOrders = choice.otherOrders, passengers = List.reverse choice.checked }

        _ ->
            state


nextUnloadPassenger : (PlanningState -> UnitId -> List Movement.Option) -> UnloadQueue -> PlanningState
nextUnloadPassenger options queue =
    case queue.passengers of
        [] ->
            OrdinaryPlanning
                { orders = truckOrder queue.truck :: queue.otherOrders
                , selection = Just (Inspecting (Selection.UnitInspection queue.truck.truckId))
                }

        passengerId :: remaining ->
            let
                unloading : UnloadPlanning
                unloading =
                    { truck = queue.truck
                    , otherOrders = queue.otherOrders
                    , passengerId = passengerId
                    , remaining = remaining
                    , options = []
                    , destinationFeedback = NoDestinationFeedback
                    }

                state : PlanningState
                state =
                    ChoosingExits unloading
            in
            ChoosingExits { unloading | options = options state passengerId }


saveUnloadDestination : (PlanningState -> UnitId -> List Movement.Option) -> Coordinate -> PlanningState -> PlanningState
saveUnloadDestination options destination state =
    case state of
        ChoosingExits unloading ->
            if List.any (\option -> option.destination == destination) unloading.options then
                let
                    truck : TruckMove
                    truck =
                        unloading.truck

                    plan : MovePlan
                    plan =
                        truck.plan

                    updated : TruckMove
                    updated =
                        { truck | plan = { plan | unloads = plan.unloads ++ [ { unitId = unloading.passengerId, destination = destination } ] } }
                in
                nextUnloadPassenger options
                    { truck = updated, otherOrders = unloading.otherOrders, passengers = unloading.remaining }

            else
                ChoosingExits { unloading | destinationFeedback = DestinationUnavailable }

        _ ->
            state


showSubmissionWarning : PlanningState -> PlanningState
showSubmissionWarning state =
    case state of
        OrdinaryPlanning drafts ->
            ConfirmingSubmission drafts

        _ ->
            state


submissionWarningOpen : PlanningState -> Bool
submissionWarningOpen state =
    case state of
        ConfirmingSubmission _ ->
            True

        _ ->
            False


dismissDialog : PlanningState -> PlanningState
dismissDialog state =
    case state of
        ConfirmingSubmission drafts ->
            OrdinaryPlanning drafts

        ChoosingPassengers _ ->
            setSelection (selection state) state

        _ ->
            state
