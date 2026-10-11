port module TurnLifecycleChecks exposing (main)

import Coordinate
import GamePage.Selection
    exposing
        ( DestinationFeedback(..)
        , Inspection(..)
        , Selection(..)
        , UnitInteraction(..)
        )
import Movement
import PlannedOrder
import PlanningModel exposing (PlanningModel(..))
import Platform
import TurnLifecycle exposing (Phase(..))
import TurnPlayback
import UnitId


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results (checks ++ unloadChecks) )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    case UnitId.parse "1" of
        Err _ ->
            [ "could not construct lifecycle fixture ID" ]

        Ok unitId ->
            let
                drafts : List PlannedOrder.PlannedOrder
                drafts =
                    [ { unitId = unitId, action = PlannedOrder.Hold { x = 1, y = 1 } } ]

                selection : Selection
                selection =
                    UnitSelection
                        { id = unitId
                        , interaction = ChoosingMove { preview = Movement.start { x = 1, y = 1 }, options = [], destinationFeedback = DestinationUnavailable }
                        }

                inspectedTile : Selection
                inspectedTile =
                    Inspecting (TileInspection { x = 2, y = 3 })

                choosingMove : Phase
                choosingMove =
                    Planning (OrdinaryPlanning { orders = drafts, selection = Just selection })

                pending : Phase
                pending =
                    Submitting { turnNumber = 1, orders = drafts, inspection = Just (UnitInspection unitId) }

                confirmed : Phase
                confirmed =
                    TurnLifecycle.observeSubmission True pending

                frames : List TurnPlayback.Frame
                frames =
                    [ { units = [], visibleTiles = [] }
                    , { units = [], visibleTiles = [ { x = 1, y = 1 } ] }
                    ]

                playing : Phase
                playing =
                    TurnLifecycle.startTurn False frames

                alreadySubmittedPlayback : Phase
                alreadySubmittedPlayback =
                    TurnLifecycle.startTurn True frames
            in
            List.concat
                [ expect "starting submission must lock editing and retain the inspected unit"
                    (TurnLifecycle.startSubmission 1 choosingMove == pending)
                , expect "starting submission again must not alter any locked phase"
                    (TurnLifecycle.startSubmission 2 pending
                        == pending
                        && TurnLifecycle.startSubmission 2 confirmed
                        == confirmed
                        && TurnLifecycle.startSubmission 2 playing
                        == playing
                    )
                , expect "inspection can change or clear during every locked phase"
                    (TurnLifecycle.selection (TurnLifecycle.setSelection (Just inspectedTile) pending)
                        == Just inspectedTile
                        && TurnLifecycle.selection (TurnLifecycle.setSelection (Just inspectedTile) confirmed)
                        == Just inspectedTile
                        && TurnLifecycle.selection (TurnLifecycle.setSelection (Just inspectedTile) playing)
                        == Just inspectedTile
                        && TurnLifecycle.selection (TurnLifecycle.setSelection Nothing pending)
                        == Nothing
                        && TurnLifecycle.selection (TurnLifecycle.setSelection Nothing confirmed)
                        == Nothing
                        && TurnLifecycle.selection (TurnLifecycle.setSelection Nothing playing)
                        == Nothing
                    )
                , expect "a failed submission must preserve inspection changed while the request was pending"
                    (TurnLifecycle.selection (TurnLifecycle.finishSubmission 1 (TurnLifecycle.setSelection (Just inspectedTile) pending)) == Just inspectedTile)
                , expect "poll confirmation must preserve inspection changed while submitting"
                    (TurnLifecycle.selection (TurnLifecycle.observeSubmission True (TurnLifecycle.setSelection (Just inspectedTile) pending)) == Just inspectedTile)
                , expect "playback completion must preserve inspection chosen during animation"
                    (Maybe.map (.phase >> TurnLifecycle.selection) (TurnLifecycle.tick 1000 (TurnLifecycle.setSelection (Just inspectedTile) playing))
                        == Just (Just inspectedTile)
                        && Maybe.map (.phase >> TurnLifecycle.selection) (TurnLifecycle.tick 1000 (TurnLifecycle.setSelection (Just inspectedTile) alreadySubmittedPlayback))
                        == Just (Just inspectedTile)
                    )
                , expect "a new turn must start without carrying selection from the previous turn"
                    (TurnLifecycle.selection (TurnLifecycle.startTurn False frames)
                        == Nothing
                        && TurnLifecycle.selection (TurnLifecycle.startTurn True [])
                        == Nothing
                    )
                , expect "editing an order must preserve the active planning interaction"
                    (TurnLifecycle.setOrders [] choosingMove == Planning (OrdinaryPlanning { orders = [], selection = Just selection }))
                , expect "submission confirmed by polling must discard editable interactions"
                    (TurnLifecycle.observeSubmission True choosingMove == WaitingForOpponent { orders = drafts, inspection = Just (UnitInspection unitId) })
                , expect "unsubmitted polling must preserve the active planning interaction"
                    (TurnLifecycle.observeSubmission False choosingMove == choosingMove)
                , expect "locked phases must reject attempts to open an editable interaction"
                    (TurnLifecycle.setSelection (Just selection) pending
                        == pending
                        && TurnLifecycle.setSelection (Just selection) confirmed
                        == confirmed
                        && TurnLifecycle.setSelection (Just selection) playing
                        == playing
                    )
                , expect "submission failure must recover drafts as inspection without reopening a command or preview"
                    (TurnLifecycle.selection (TurnLifecycle.finishSubmission 1 pending) == Just (Inspecting (UnitInspection unitId)))
                , expect "playback without a selected object must finish with no selection"
                    (Maybe.map (.phase >> TurnLifecycle.selection) (TurnLifecycle.tick 1000 playing) == Just Nothing)
                , expect "submission failure must restore the exact drafts"
                    (TurnLifecycle.finishSubmission 1 pending == Planning (OrdinaryPlanning { orders = drafts, selection = Just (Inspecting (UnitInspection unitId)) }))
                , expect "an older request must not finish a newer submission"
                    (TurnLifecycle.finishSubmission 0 pending == pending)
                , expect "poll confirmation must lock drafts before the submit request finishes"
                    (confirmed == WaitingForOpponent { orders = drafts, inspection = Just (UnitInspection unitId) })
                , expect "late failure must not unlock a turn already confirmed by polling"
                    (TurnLifecycle.finishSubmission 1 confirmed == confirmed)
                , expect "an unsubmitted poll must not regress waiting or pending submission"
                    (TurnLifecycle.observeSubmission False confirmed == confirmed && TurnLifecycle.observeSubmission False pending == pending)
                , expect "order edits are allowed only during planning"
                    (TurnLifecycle.setOrders [] (Planning (OrdinaryPlanning { orders = drafts, selection = Nothing })) == Planning (OrdinaryPlanning { orders = [], selection = Nothing }) && TurnLifecycle.setOrders [] pending == pending && TurnLifecycle.setOrders [] confirmed == confirmed)
                , expect "polling remains available in planning and waiting, but not submitting or playback"
                    (TurnLifecycle.canPoll (Planning (OrdinaryPlanning { orders = drafts, selection = Nothing })) && TurnLifecycle.canPoll confirmed && not (TurnLifecycle.canPoll pending) && not (TurnLifecycle.canPoll playing))
                , expect "late submission completion must not interrupt playback or restore old drafts"
                    (TurnLifecycle.finishSubmission 1 playing == playing && TurnLifecycle.orders playing == [])
                , expect "same-turn submission flags must not interrupt playback"
                    (TurnLifecycle.playback (TurnLifecycle.observeSubmission True playing) == TurnLifecycle.playback playing)
                , expect "playback completion must open a fresh planning turn and use the final frame"
                    (TurnLifecycle.tick 1000 playing == Just { phase = Planning (OrdinaryPlanning { orders = [], selection = Nothing }), frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "playback completion must retain submission of a turn submitted elsewhere"
                    (TurnLifecycle.tick 1000 alreadySubmittedPlayback == Just { phase = WaitingForOpponent { orders = [], inspection = Nothing }, frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "submission observed during playback must lock the completed turn"
                    (TurnLifecycle.tick 1000 (TurnLifecycle.observeSubmission True playing) == Just { phase = WaitingForOpponent { orders = [], inspection = Nothing }, frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "turns without playback must enter planning or waiting immediately"
                    (TurnLifecycle.startTurn False [] == Planning (OrdinaryPlanning { orders = [], selection = Nothing }) && TurnLifecycle.startTurn True [] == WaitingForOpponent { orders = [], inspection = Nothing })
                , expect "stray animation messages must not advance a planning or waiting turn"
                    (TurnLifecycle.tick 1000 (Planning (OrdinaryPlanning { orders = drafts, selection = Nothing })) == Nothing && TurnLifecycle.tick 1000 confirmed == Nothing)
                ]


unloadChecks : List String
unloadChecks =
    case ( UnitId.parse "1", UnitId.parse "2", UnitId.parse "3" ) of
        ( Ok truck, Ok first, Ok second ) ->
            let
                move : Movement.Option
                move =
                    { destination = { x = 2, y = 1 }, path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ], cost = 2 }

                order : PlannedOrder.PlannedOrder
                order =
                    { unitId = truck, action = PlannedOrder.Move { move = move, unloads = [] } }

                ordinary : Phase
                ordinary =
                    Planning (OrdinaryPlanning { orders = [ order ], selection = Just (Inspecting (UnitInspection truck)) })

                checklist : Phase
                checklist =
                    TurnLifecycle.mapPlanning (PlanningModel.startUnload truck move) ordinary

                checked : Phase
                checked =
                    checklist
                        |> TurnLifecycle.mapPlanning (PlanningModel.toggleUnloadPassenger first True)
                        |> TurnLifecycle.mapPlanning (PlanningModel.toggleUnloadPassenger second True)

                exitOptions : PlanningModel -> UnitId.UnitId -> List Movement.Option
                exitOptions state _ =
                    let
                        reserved : List Coordinate.Coordinate
                        reserved =
                            PlanningModel.orders state |> List.concatMap (PlannedOrder.unloads >> List.map .destination)

                        option : Coordinate.Coordinate -> Movement.Option
                        option position =
                            { destination = position, path = [ move.destination, position ], cost = 2 }
                    in
                    [ { x = 2, y = 2 }, { x = 3, y = 1 } ]
                        |> List.filter (\position -> not (List.member position reserved))
                        |> List.map option

                firstPassenger : Phase
                firstPassenger =
                    TurnLifecycle.mapPlanning (PlanningModel.confirmUnloadPassengers exitOptions) checked

                rejectedFirstExit : Phase
                rejectedFirstExit =
                    TurnLifecycle.mapPlanning (PlanningModel.saveUnloadDestination exitOptions { x = 9, y = 9 }) firstPassenger

                secondPassenger : Phase
                secondPassenger =
                    TurnLifecycle.mapPlanning (PlanningModel.saveUnloadDestination exitOptions { x = 2, y = 2 }) rejectedFirstExit

                rejectedExit : Phase
                rejectedExit =
                    TurnLifecycle.mapPlanning (PlanningModel.saveUnloadDestination exitOptions { x = 2, y = 2 }) secondPassenger

                complete : Phase
                complete =
                    TurnLifecycle.mapPlanning (PlanningModel.saveUnloadDestination exitOptions { x = 3, y = 1 }) rejectedExit

                completedOrder : PlannedOrder.PlannedOrder
                completedOrder =
                    { unitId = truck
                    , action = PlannedOrder.Move { move = move, unloads = [ { unitId = first, destination = { x = 2, y = 2 } }, { unitId = second, destination = { x = 3, y = 1 } } ] }
                    }

                stationaryPosition : Coordinate.Coordinate
                stationaryPosition =
                    { x = 1, y = 1 }

                stationaryChecklist : Phase
                stationaryChecklist =
                    TurnLifecycle.mapPlanning (PlanningModel.startStationaryUnload truck stationaryPosition) ordinary

                stationaryHold : PlannedOrder.PlannedOrder
                stationaryHold =
                    { unitId = truck, action = PlannedOrder.Hold stationaryPosition }

                stationaryOptions : PlanningModel -> UnitId.UnitId -> List Movement.Option
                stationaryOptions state _ =
                    let
                        reserved : List Coordinate.Coordinate
                        reserved =
                            PlanningModel.orders state |> List.concatMap (PlannedOrder.unloads >> List.map .destination)

                        option : Coordinate.Coordinate -> Movement.Option
                        option position =
                            { destination = position, path = [ stationaryPosition, position ], cost = 2 }
                    in
                    [ { x = 0, y = 1 }, { x = 1, y = 2 } ]
                        |> List.filter (\position -> not (List.member position reserved))
                        |> List.map option

                stationaryFirst : Phase
                stationaryFirst =
                    stationaryChecklist
                        |> TurnLifecycle.mapPlanning (PlanningModel.toggleUnloadPassenger first True)
                        |> TurnLifecycle.mapPlanning (PlanningModel.toggleUnloadPassenger second True)
                        |> TurnLifecycle.mapPlanning (PlanningModel.confirmUnloadPassengers stationaryOptions)

                stationarySecond : Phase
                stationarySecond =
                    TurnLifecycle.mapPlanning (PlanningModel.saveUnloadDestination stationaryOptions { x = 0, y = 1 }) stationaryFirst

                stationaryComplete : Phase
                stationaryComplete =
                    TurnLifecycle.mapPlanning (PlanningModel.saveUnloadDestination stationaryOptions { x = 1, y = 2 }) stationarySecond

                stationaryOrder : PlannedOrder.PlannedOrder
                stationaryOrder =
                    { unitId = truck
                    , action =
                        PlannedOrder.Unload
                            { position = stationaryPosition
                            , unloads =
                                [ { unitId = first, destination = { x = 0, y = 1 } }
                                , { unitId = second, destination = { x = 1, y = 2 } }
                                ]
                            }
                    }

                hasOneOwner : Bool
                hasOneOwner =
                    case checklist of
                        Planning (ChoosingPassengers choice) ->
                            List.isEmpty choice.otherOrders && PlanningModel.truckDestination choice.truck == move.destination

                        _ ->
                            False

                reservesFirstExit : Bool
                reservesFirstExit =
                    case planningExits secondPassenger of
                        Just unloading ->
                            unloading.passengerId == second && List.map .destination unloading.options == [ { x = 3, y = 1 } ]

                        Nothing ->
                            False
            in
            List.concat
                [ expect "stationary unloading replaces the truck move with one hold at its origin"
                    (TurnLifecycle.orders stationaryChecklist == [ stationaryHold ])
                , expect "canceling or declining stationary unloading leaves a plain hold"
                    (TurnLifecycle.orders (TurnLifecycle.mapPlanning PlanningModel.dismissDialog stationaryChecklist)
                        == [ stationaryHold ]
                        && TurnLifecycle.orders (TurnLifecycle.mapPlanning (PlanningModel.confirmUnloadPassengers stationaryOptions) stationaryChecklist)
                        == [ stationaryHold ]
                    )
                , expect "stationary unloading reserves each exit before choosing the next passenger"
                    (Maybe.map (\planning -> List.map .destination planning.options) (planningExits stationarySecond) == Just [ { x = 1, y = 2 } ])
                , expect "stationary unloading completes with one stationary truck order and both exits"
                    (TurnLifecycle.orders stationaryComplete
                        == [ stationaryOrder ]
                        && planningExits stationaryComplete
                        == Nothing
                        && PlannedOrder.path stationaryOrder
                        == [ stationaryPosition ]
                        && not (PlannedOrder.isMoving stationaryOrder)
                    )
                , expect "completed stationary unloads can submit and revoke normally"
                    (TurnLifecycle.planningLocked (TurnLifecycle.startSubmission 1 stationaryComplete)
                        && TurnLifecycle.orders (TurnLifecycle.setOrders [] stationaryComplete)
                        == []
                    )
                , expect "the passenger checklist owns one truck move and derives its inspection"
                    (hasOneOwner && TurnLifecycle.orders checklist == [ order ] && TurnLifecycle.selection checklist == Just (Inspecting (UnitInspection truck)))
                , expect "canceling the checklist retains the move and returns to ordinary planning"
                    (TurnLifecycle.mapPlanning PlanningModel.dismissDialog checked == ordinary)
                , expect "proceeding without passengers retains the move"
                    (TurnLifecycle.mapPlanning (PlanningModel.confirmUnloadPassengers exitOptions) checklist == ordinary)
                , expect "the next passenger cannot reuse an exit already saved"
                    reservesFirstExit
                , expect "an unavailable exit cannot advance the workflow"
                    (Maybe.map .passengerId (planningExits rejectedExit)
                        == Just second
                        && TurnLifecycle.orders rejectedExit
                        == TurnLifecycle.orders secondPassenger
                        && Maybe.map .destinationFeedback (planningExits rejectedExit)
                        == Just DestinationUnavailable
                    )
                , expect "a new passenger starts without the previous passenger destination feedback"
                    (Maybe.map .destinationFeedback (planningExits secondPassenger) == Just NoDestinationFeedback)
                , expect "leaving an invalid unload choice drops its feedback and preserves saved orders"
                    (planningExits (TurnLifecycle.setSelection Nothing rejectedExit)
                        == Nothing
                        && TurnLifecycle.orders (TurnLifecycle.setSelection Nothing rejectedExit)
                        == TurnLifecycle.orders rejectedExit
                    )
                , expect "both passenger exits and the truck route survive workflow completion"
                    (TurnLifecycle.orders complete == [ completedOrder ] && planningExits complete == Nothing)
                , expect "leaving exit selection keeps exits already chosen"
                    (List.concatMap PlannedOrder.unloads (TurnLifecycle.orders (TurnLifecycle.setSelection Nothing secondPassenger)) == [ { unitId = first, destination = { x = 2, y = 2 } } ])
                , expect "ordinary order edits cannot replace or duplicate an active unload move"
                    (TurnLifecycle.setOrders [] checklist == checklist && TurnLifecycle.setOrders [] secondPassenger == secondPassenger)
                , expect "submission warnings and unload stages are mutually exclusive"
                    (TurnLifecycle.mapPlanning PlanningModel.showSubmissionWarning checklist == checklist && TurnLifecycle.mapPlanning PlanningModel.showSubmissionWarning secondPassenger == secondPassenger && planningChoice (TurnLifecycle.mapPlanning PlanningModel.showSubmissionWarning ordinary) == Nothing)
                , expect "unfinished unloading cannot be submitted"
                    (TurnLifecycle.startSubmission 1 checklist == checklist && TurnLifecycle.startSubmission 1 secondPassenger == secondPassenger)
                , expect "unsubmitted polls preserve both unload stages"
                    (TurnLifecycle.observeSubmission False checked == checked && TurnLifecycle.observeSubmission False secondPassenger == secondPassenger)
                , expect "submission confirmed elsewhere retains the move and drops the workflow"
                    (TurnLifecycle.orders (TurnLifecycle.observeSubmission True checklist) == [ order ] && planningExits (TurnLifecycle.observeSubmission True secondPassenger) == Nothing && List.concatMap PlannedOrder.unloads (TurnLifecycle.orders (TurnLifecycle.observeSubmission True secondPassenger)) == [ { unitId = first, destination = { x = 2, y = 2 } } ])
                , expect "advancing the turn discards the old unload workflow"
                    (TurnLifecycle.startTurn False [] == Planning PlanningModel.init)
                , expect "completed unload orders can be revoked normally"
                    (TurnLifecycle.orders (TurnLifecycle.setOrders [] complete) == [])
                , expect "submission warning dismissal preserves selection and drafts"
                    (TurnLifecycle.mapPlanning PlanningModel.dismissDialog (TurnLifecycle.mapPlanning PlanningModel.showSubmissionWarning ordinary) == ordinary)
                , expect "confirming submission accepts the warning state's drafts"
                    (TurnLifecycle.startSubmission 1 (TurnLifecycle.mapPlanning PlanningModel.showSubmissionWarning ordinary) == TurnLifecycle.startSubmission 1 ordinary)
                ]

        _ ->
            [ "could not construct unload workflow fixture IDs" ]


planningExits : Phase -> Maybe PlanningModel.UnloadPlanning
planningExits phase =
    TurnLifecycle.planning phase |> Maybe.andThen PlanningModel.unloadPlanning


planningChoice : Phase -> Maybe PlanningModel.UnloadChoice
planningChoice phase =
    TurnLifecycle.planning phase |> Maybe.andThen PlanningModel.unloadChoice


expect : String -> Bool -> List String
expect message condition =
    if condition then
        []

    else
        [ message ]
