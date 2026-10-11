module PlanningModel exposing
    ( Drafts
    , PlanningModel(..)
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
    , startStationaryUnload
    , startUnload
    , submissionDrafts
    , submissionWarningOpen
    , toggleUnloadPassenger
    , truckDestination
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
import PlannedOrder exposing (MovePlan, PlannedOrder, StationaryUnload)
import UnitId exposing (UnitId)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Planning has one active workflow. Unload stages own their truck plan and
only other units' orders; dialogs and board inspection are derived from the stage.
-}
type PlanningModel
    = OrdinaryPlanning Drafts
    | ConfirmingSubmission Drafts
    | ChoosingPassengers UnloadChoice
    | ChoosingExits UnloadPlanning


type alias Drafts =
    { orders : List PlannedOrder
    , selection : Maybe Selection
    }


type alias UnloadingTruck =
    { truckId : UnitId
    , plan : TruckPlan
    }


type TruckPlan
    = MovingTruck MovePlan
    | StationaryTruck StationaryUnload


type alias UnloadChoice =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , checked : List UnitId
    }


type alias UnloadPlanning =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , passengerId : UnitId
    , remaining : List UnitId
    , options : List Movement.Option
    , destinationFeedback : DestinationFeedback
    }


type alias UnloadQueue =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , passengers : List UnitId
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : PlanningModel
init =
    OrdinaryPlanning { orders = [], selection = Nothing }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


orders : PlanningModel -> List PlannedOrder
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


setOrders : List PlannedOrder -> PlanningModel -> PlanningModel
setOrders draftsOrders state =
    case state of
        OrdinaryPlanning drafts ->
            OrdinaryPlanning { drafts | orders = draftsOrders }

        _ ->
            state


selection : PlanningModel -> Maybe Selection
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


setSelection : Maybe Selection -> PlanningModel -> PlanningModel
setSelection selected state =
    OrdinaryPlanning { orders = orders state, selection = selected }


{-| Unfinished unloading cannot become a submission. The lifecycle consumes
these drafts only after planning is ready or its warning has been confirmed.
-}
submissionDrafts : PlanningModel -> Maybe Drafts
submissionDrafts state =
    case state of
        OrdinaryPlanning drafts ->
            Just drafts

        ConfirmingSubmission drafts ->
            Just drafts

        _ ->
            Nothing


truckOrder : UnloadingTruck -> PlannedOrder
truckOrder truck =
    let
        action : PlannedOrder.Action
        action =
            case truck.plan of
                MovingTruck plan ->
                    PlannedOrder.Move plan

                StationaryTruck plan ->
                    if List.isEmpty plan.unloads then
                        PlannedOrder.Hold plan.position

                    else
                        PlannedOrder.Unload plan
    in
    { unitId = truck.truckId, action = action }


truckDestination : UnloadingTruck -> Coordinate
truckDestination truck =
    truckOrder truck |> PlannedOrder.destination


startUnload : UnitId -> Movement.Option -> PlanningModel -> PlanningModel
startUnload truckId move state =
    startTruckUnload { truckId = truckId, plan = MovingTruck { move = move, unloads = [] } } state


startStationaryUnload : UnitId -> Coordinate -> PlanningModel -> PlanningModel
startStationaryUnload truckId position state =
    startTruckUnload { truckId = truckId, plan = StationaryTruck { position = position, unloads = [] } } state


startTruckUnload : UnloadingTruck -> PlanningModel -> PlanningModel
startTruckUnload truck state =
    case state of
        OrdinaryPlanning drafts ->
            ChoosingPassengers
                { truck = truck
                , otherOrders = List.filter (\order -> order.unitId /= truck.truckId) drafts.orders
                , checked = []
                }

        _ ->
            state


unloadChoice : PlanningModel -> Maybe UnloadChoice
unloadChoice state =
    case state of
        ChoosingPassengers choice ->
            Just choice

        _ ->
            Nothing


unloadPlanning : PlanningModel -> Maybe UnloadPlanning
unloadPlanning state =
    case state of
        ChoosingExits unloading ->
            Just unloading

        _ ->
            Nothing


toggleUnloadPassenger : UnitId -> Bool -> PlanningModel -> PlanningModel
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


confirmUnloadPassengers : (PlanningModel -> UnitId -> List Movement.Option) -> PlanningModel -> PlanningModel
confirmUnloadPassengers options state =
    case state of
        ChoosingPassengers choice ->
            nextUnloadPassenger options
                { truck = choice.truck, otherOrders = choice.otherOrders, passengers = List.reverse choice.checked }

        _ ->
            state


nextUnloadPassenger : (PlanningModel -> UnitId -> List Movement.Option) -> UnloadQueue -> PlanningModel
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

                state : PlanningModel
                state =
                    ChoosingExits unloading
            in
            ChoosingExits { unloading | options = options state passengerId }


saveUnloadDestination : (PlanningModel -> UnitId -> List Movement.Option) -> Coordinate -> PlanningModel -> PlanningModel
saveUnloadDestination options destination state =
    case state of
        ChoosingExits unloading ->
            if List.any (\option -> option.destination == destination) unloading.options then
                let
                    truck : UnloadingTruck
                    truck =
                        unloading.truck

                    appendUnload : List PlannedOrder.UnloadOrder -> List PlannedOrder.UnloadOrder
                    appendUnload unloads =
                        unloads ++ [ { unitId = unloading.passengerId, destination = destination } ]

                    plan : TruckPlan
                    plan =
                        case truck.plan of
                            MovingTruck moving ->
                                MovingTruck { moving | unloads = appendUnload moving.unloads }

                            StationaryTruck stationary ->
                                StationaryTruck { stationary | unloads = appendUnload stationary.unloads }

                    updated : UnloadingTruck
                    updated =
                        { truck | plan = plan }
                in
                nextUnloadPassenger options
                    { truck = updated, otherOrders = unloading.otherOrders, passengers = unloading.remaining }

            else
                ChoosingExits { unloading | destinationFeedback = DestinationUnavailable }

        _ ->
            state


showSubmissionWarning : PlanningModel -> PlanningModel
showSubmissionWarning state =
    case state of
        OrdinaryPlanning drafts ->
            ConfirmingSubmission drafts

        _ ->
            state


submissionWarningOpen : PlanningModel -> Bool
submissionWarningOpen state =
    case state of
        ConfirmingSubmission _ ->
            True

        _ ->
            False


dismissDialog : PlanningModel -> PlanningModel
dismissDialog state =
    case state of
        ConfirmingSubmission drafts ->
            OrdinaryPlanning drafts

        ChoosingPassengers _ ->
            setSelection (selection state) state

        _ ->
            state
