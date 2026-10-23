port module Game.Checks.TurnLifecycle exposing (main)

import Api.Enum.PlayerNumber as PlayerNumber
import Game.Coordinate as Coordinate
import Game.CurrentTurn as CurrentTurn
import Game.DestinationFeedback exposing (DestinationFeedback(..))
import Game.Inspection as Inspection exposing (Inspection(..))
import Game.MovePlanning as MovePlanning
import Game.Movement as Movement
import Game.OrderPlanning as OrderPlanning exposing (Model(..))
import Game.Outcome as GameOutcome exposing (GameOutcome)
import Game.PlannedOrder as PlannedOrder
import Game.Selection
    exposing
        ( Selection(..)
        , UnitInteraction(..)
        )
import Game.Turn as Turn
import Game.TurnLifecycle as TurnLifecycle exposing (Phase(..))
import Game.TurnPlayback as TurnPlayback
import Game.UnitId as UnitId
import Game.UnloadCargo as UnloadCargo
import Game.UnloadPlanning as UnloadPlanning exposing (UnloadChoice, UnloadPlanning)
import Game.UnloadingTruck as UnloadingTruck
import Graphql.Document
import Graphql.SelectionSet as SS
import InvariantCheck as IC exposing (InvariantCheck)
import Json.Decode as JD
import Json.Encode as JE
import Platform


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results (checks ++ unloadChecks ++ currentTurnChecks ++ outcomeChecks) )
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
                        , interaction = ChoosingMove { purpose = MovePlanning.NormalMove, preview = Movement.start { x = 1, y = 1 }, options = [], destinationFeedback = DestinationUnavailable }
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
                    [ { depots = []
                      , supplyCrates = []
                      , departures = []
                      , indirectImpacts = []
                      , shots = []
                      , durationMs = 180
                      , units = []
                      , visibleTiles = []
                      }
                    , { depots = []
                      , supplyCrates = []
                      , departures = []
                      , indirectImpacts = []
                      , shots = []
                      , durationMs = 180
                      , units = []
                      , visibleTiles =
                            [ { x = 1
                              , y = 1
                              }
                            ]
                      }
                    ]

                playing : Phase
                playing =
                    TurnLifecycle.startTurn False frames

                framedPlayback : Phase
                framedPlayback =
                    case playing of
                        Playing state ->
                            Playing { state | camera = Just { camera = { offset = { x = 48, y = 24 }, zoom = 1.25 }, remainingPanMs = 0 } }

                        _ ->
                            playing

                alreadySubmittedPlayback : Phase
                alreadySubmittedPlayback =
                    TurnLifecycle.startTurn True frames
            in
            List.concat
                [ expect "playback camera survives inspection changes and intermediate frames"
                    (case TurnLifecycle.tick 1 (TurnLifecycle.setSelection (Just inspectedTile) framedPlayback) of
                        Just { phase } ->
                            case ( phase, framedPlayback ) of
                                ( Playing next, Playing original ) ->
                                    next.camera == original.camera

                                _ ->
                                    False

                        Nothing ->
                            False
                    )
                , expect "finishing playback discards its camera in planning or waiting"
                    (TurnLifecycle.tick 1000 framedPlayback
                        == TurnLifecycle.tick 1000 playing
                        && TurnLifecycle.tick 1000 (TurnLifecycle.observeSubmission True framedPlayback)
                        == TurnLifecycle.tick 1000 alreadySubmittedPlayback
                    )
                , expect "starting submission must lock editing and retain the inspected unit"
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
                    (TurnLifecycle.tick 1000 playing
                        == Just
                            { phase =
                                Planning
                                    (OrdinaryPlanning
                                        { orders = []
                                        , selection = Nothing
                                        }
                                    )
                            , frame =
                                { depots = []
                                , supplyCrates = []
                                , departures = []
                                , indirectImpacts = []
                                , shots = []
                                , durationMs = 180
                                , units = []
                                , visibleTiles =
                                    [ { x = 1
                                      , y = 1
                                      }
                                    ]
                                }
                            }
                    )
                , expect "playback completion must retain submission of a turn submitted elsewhere"
                    (TurnLifecycle.tick 1000 alreadySubmittedPlayback
                        == Just
                            { phase =
                                WaitingForOpponent
                                    { orders = []
                                    , inspection = Nothing
                                    }
                            , frame =
                                { depots = []
                                , supplyCrates = []
                                , departures = []
                                , indirectImpacts = []
                                , shots = []
                                , durationMs = 180
                                , units = []
                                , visibleTiles =
                                    [ { x = 1
                                      , y = 1
                                      }
                                    ]
                                }
                            }
                    )
                , expect "submission observed during playback must lock the completed turn"
                    (TurnLifecycle.tick 1000 (TurnLifecycle.observeSubmission True playing)
                        == Just
                            { phase =
                                WaitingForOpponent
                                    { orders = []
                                    , inspection = Nothing
                                    }
                            , frame =
                                { depots = []
                                , supplyCrates = []
                                , departures = []
                                , indirectImpacts = []
                                , shots = []
                                , durationMs = 180
                                , units = []
                                , visibleTiles =
                                    [ { x = 1
                                      , y = 1
                                      }
                                    ]
                                }
                            }
                    )
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
                    TurnLifecycle.mapPlanning (OrderPlanning.startUnload truck move) ordinary

                checked : Phase
                checked =
                    checklist
                        |> TurnLifecycle.mapPlanning (OrderPlanning.toggleUnloadPassenger first True)
                        |> TurnLifecycle.mapPlanning (OrderPlanning.toggleUnloadPassenger second True)

                exitOptions :
                    UnloadPlanning
                    -> InvariantCheck OrderPlanning.InvariantViolation (List Movement.Option)
                exitOptions state =
                    let
                        reserved : List Coordinate.Coordinate
                        reserved =
                            UnloadPlanning.orders state |> List.concatMap (PlannedOrder.unloads >> List.map .destination)

                        option : Coordinate.Coordinate -> Movement.Option
                        option position =
                            { destination = position, path = [ move.destination, position ], cost = 2 }
                    in
                    [ { x = 2, y = 2 }, { x = 3, y = 1 } ]
                        |> List.filter (\position -> not (List.member position reserved))
                        |> List.map option
                        |> IC.happy

                firstPassenger : Phase
                firstPassenger =
                    TurnLifecycle.mapPlanning (OrderPlanning.confirmUnloadPassengers [] [] [] exitOptions >> fixtureValue) checked

                rejectedFirstExit : Phase
                rejectedFirstExit =
                    TurnLifecycle.mapPlanning (OrderPlanning.saveUnloadDestination [] [] [] exitOptions { x = 9, y = 9 } >> fixtureValue) firstPassenger

                secondPassenger : Phase
                secondPassenger =
                    TurnLifecycle.mapPlanning (OrderPlanning.saveUnloadDestination [] [] [] exitOptions { x = 2, y = 2 } >> fixtureValue) rejectedFirstExit

                rejectedExit : Phase
                rejectedExit =
                    TurnLifecycle.mapPlanning (OrderPlanning.saveUnloadDestination [] [] [] exitOptions { x = 2, y = 2 } >> fixtureValue) secondPassenger

                complete : Phase
                complete =
                    TurnLifecycle.mapPlanning (OrderPlanning.saveUnloadDestination [] [] [] exitOptions { x = 3, y = 1 } >> fixtureValue) rejectedExit

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
                    TurnLifecycle.mapPlanning (OrderPlanning.startStationaryUnload truck stationaryPosition) ordinary

                stationaryHold : PlannedOrder.PlannedOrder
                stationaryHold =
                    { unitId = truck, action = PlannedOrder.Hold stationaryPosition }

                stationaryOptions :
                    UnloadPlanning
                    -> InvariantCheck OrderPlanning.InvariantViolation (List Movement.Option)
                stationaryOptions state =
                    let
                        reserved : List Coordinate.Coordinate
                        reserved =
                            UnloadPlanning.orders state |> List.concatMap (PlannedOrder.unloads >> List.map .destination)

                        option : Coordinate.Coordinate -> Movement.Option
                        option position =
                            { destination = position, path = [ stationaryPosition, position ], cost = 2 }
                    in
                    [ { x = 0, y = 1 }, { x = 1, y = 2 } ]
                        |> List.filter (\position -> not (List.member position reserved))
                        |> List.map option
                        |> IC.happy

                stationaryFirst : Phase
                stationaryFirst =
                    stationaryChecklist
                        |> TurnLifecycle.mapPlanning (OrderPlanning.toggleUnloadPassenger first True)
                        |> TurnLifecycle.mapPlanning (OrderPlanning.toggleUnloadPassenger second True)
                        |> TurnLifecycle.mapPlanning (OrderPlanning.confirmUnloadPassengers [] [] [] stationaryOptions >> fixtureValue)

                stationarySecond : Phase
                stationarySecond =
                    TurnLifecycle.mapPlanning (OrderPlanning.saveUnloadDestination [] [] [] stationaryOptions { x = 0, y = 1 } >> fixtureValue) stationaryFirst

                stationaryComplete : Phase
                stationaryComplete =
                    TurnLifecycle.mapPlanning (OrderPlanning.saveUnloadDestination [] [] [] stationaryOptions { x = 1, y = 2 } >> fixtureValue) stationarySecond

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
                            List.isEmpty choice.otherOrders && UnloadingTruck.destination choice.truck == move.destination

                        _ ->
                            False

                reservesFirstExit : Bool
                reservesFirstExit =
                    case planningExits secondPassenger of
                        Just unloading ->
                            unloading.cargo
                                == UnloadCargo.Passenger second
                                && List.map .destination unloading.options
                                == [ { x = 3
                                     , y = 1
                                     }
                                   ]

                        Nothing ->
                            False
            in
            List.concat
                [ expect "stationary unloading replaces the truck move with one hold at its origin"
                    (TurnLifecycle.orders stationaryChecklist == [ stationaryHold ])
                , expect "canceling stationary unloading discards the hold while proceeding keeps it"
                    (TurnLifecycle.orders (TurnLifecycle.mapPlanning OrderPlanning.dismissDialog stationaryChecklist)
                        == []
                        && TurnLifecycle.orders (TurnLifecycle.mapPlanning (OrderPlanning.confirmUnloadPassengers [] [] [] stationaryOptions >> fixtureValue) stationaryChecklist)
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
                , expect "canceling the checklist discards the move and returns to ordinary planning"
                    (TurnLifecycle.mapPlanning OrderPlanning.dismissDialog checked
                        == Planning (OrdinaryPlanning { orders = [], selection = Just (Inspecting (UnitInspection truck)) })
                    )
                , expect "proceeding without passengers retains the move"
                    (TurnLifecycle.mapPlanning (OrderPlanning.confirmUnloadPassengers [] [] [] exitOptions >> fixtureValue) checklist == ordinary)
                , expect "the next passenger cannot reuse an exit already saved"
                    reservesFirstExit
                , expect "an unavailable exit cannot advance the workflow"
                    (Maybe.map .cargo (planningExits rejectedExit)
                        == Just (UnloadCargo.Passenger second)
                        && TurnLifecycle.orders rejectedExit
                        == TurnLifecycle.orders secondPassenger
                        && Maybe.map .destinationFeedback (planningExits rejectedExit)
                        == Just DestinationUnavailable
                    )
                , expect "a new passenger starts without the previous passenger destination feedback"
                    (Maybe.map .destinationFeedback (planningExits secondPassenger) == Just NoDestinationFeedback)
                , expect "leaving an invalid unload choice drops its feedback and the truck plan"
                    (planningExits (TurnLifecycle.setSelection Nothing rejectedExit)
                        == Nothing
                        && TurnLifecycle.orders (TurnLifecycle.setSelection Nothing rejectedExit)
                        == []
                    )
                , expect "both passenger exits and the truck route survive workflow completion"
                    (TurnLifecycle.orders complete == [ completedOrder ] && planningExits complete == Nothing)
                , expect "leaving exit selection discards the move and exits already chosen"
                    (TurnLifecycle.orders (TurnLifecycle.setSelection Nothing secondPassenger) == [])
                , expect "ordinary order edits cannot replace or duplicate an active unload move"
                    (TurnLifecycle.setOrders [] checklist == checklist && TurnLifecycle.setOrders [] secondPassenger == secondPassenger)
                , expect "submission warnings and unload stages are mutually exclusive"
                    (TurnLifecycle.mapPlanning OrderPlanning.showSubmissionWarning checklist == checklist && TurnLifecycle.mapPlanning OrderPlanning.showSubmissionWarning secondPassenger == secondPassenger && planningChoice (TurnLifecycle.mapPlanning OrderPlanning.showSubmissionWarning ordinary) == Nothing)
                , expect "unfinished unloading cannot be submitted"
                    (TurnLifecycle.startSubmission 1 checklist == checklist && TurnLifecycle.startSubmission 1 secondPassenger == secondPassenger)
                , expect "unsubmitted polls preserve both unload stages"
                    (TurnLifecycle.observeSubmission False checked == checked && TurnLifecycle.observeSubmission False secondPassenger == secondPassenger)
                , expect "submission confirmed elsewhere retains the move and drops the workflow"
                    (TurnLifecycle.orders (TurnLifecycle.observeSubmission True checklist) == [ order ] && planningExits (TurnLifecycle.observeSubmission True secondPassenger) == Nothing && List.concatMap PlannedOrder.unloads (TurnLifecycle.orders (TurnLifecycle.observeSubmission True secondPassenger)) == [ { unitId = first, destination = { x = 2, y = 2 } } ])
                , expect "advancing the turn discards the old unload workflow"
                    (TurnLifecycle.startTurn False [] == Planning OrderPlanning.init)
                , expect "completed unload orders can be revoked normally"
                    (TurnLifecycle.orders (TurnLifecycle.setOrders [] complete) == [])
                , expect "submission warning dismissal preserves selection and drafts"
                    (TurnLifecycle.mapPlanning OrderPlanning.dismissDialog (TurnLifecycle.mapPlanning OrderPlanning.showSubmissionWarning ordinary) == ordinary)
                , expect "confirming submission accepts the warning state's drafts"
                    (TurnLifecycle.startSubmission 1 (TurnLifecycle.mapPlanning OrderPlanning.showSubmissionWarning ordinary) == TurnLifecycle.startSubmission 1 ordinary)
                ]

        _ ->
            [ "could not construct unload workflow fixture IDs" ]


planningExits : Phase -> Maybe UnloadPlanning
planningExits phase =
    TurnLifecycle.planning phase |> Maybe.andThen OrderPlanning.unloadPlanning


planningChoice : Phase -> Maybe UnloadChoice
planningChoice phase =
    TurnLifecycle.planning phase |> Maybe.andThen OrderPlanning.unloadChoice


expect : String -> Bool -> List String
expect message condition =
    if condition then
        []

    else
        [ message ]


outcomeChecks : List String
outcomeChecks =
    let
        decodeOutcome : JE.Value -> Result JD.Error (Maybe GameOutcome)
        decodeOutcome outcome =
            JE.object
                [ ( "data"
                  , JE.object
                        [ ( "turnNumber", JE.int 2 )
                        , ( "outcome", outcome )
                        , ( "submitted", JE.bool False )
                        , ( "opponentSubmitted", JE.bool False )
                        , ( "lastResolution", JE.null )
                        ]
                  )
                ]
                |> JD.decodeValue (Graphql.Document.decoder (SS.map .outcome Turn.selection))
    in
    List.concat
        [ expect "ongoing game outcomes decode as absent"
            (decodeOutcome JE.null == Ok Nothing)
        , expect "draw outcomes decode distinctly from an ongoing game"
            (decodeOutcome (JE.object [ ( "winner", JE.null ) ]) == Ok (Just GameOutcome.Draw))
        , expect "victory outcomes retain player 1 as the winner"
            (decodeOutcome (JE.object [ ( "winner", JE.string "PLAYER1" ) ])
                == Ok (Just (GameOutcome.Victory PlayerNumber.Player1))
            )
        , expect "victory outcomes retain player 2 as the winner"
            (decodeOutcome (JE.object [ ( "winner", JE.string "PLAYER2" ) ])
                == Ok (Just (GameOutcome.Victory PlayerNumber.Player2))
            )
        ]


currentTurnChecks : List String
currentTurnChecks =
    let
        initial : CurrentTurn.Model
        initial =
            CurrentTurn.init { turn = { number = 1, submitted = False, opponentSubmitted = False, outcome = Nothing, resolution = Nothing }, playbackFrames = [] }

        observation : CurrentTurn.Observation
        observation =
            { turn = { number = 1, submitted = True, opponentSubmitted = True, outcome = Nothing, resolution = Nothing }
            , playbackFrames = []
            }

        pendingPoll : CurrentTurn.Model
        pendingPoll =
            { initial | refreshing = True }

        submitting : CurrentTurn.Model
        submitting =
            CurrentTurn.startSubmission pendingPoll |> Maybe.withDefault initial

        waiting : CurrentTurn.Model
        waiting =
            CurrentTurn.pollSucceeded observation submitting

        turn : Turn.Snapshot
        turn =
            observation.turn

        frames : List TurnPlayback.Frame
        frames =
            [ { depots = []
              , supplyCrates = []
              , departures = []
              , indirectImpacts = []
              , shots = []
              , durationMs = 180
              , units = []
              , visibleTiles = []
              }
            , { depots = []
              , supplyCrates = []
              , departures = []
              , indirectImpacts = []
              , shots = []
              , durationMs = 180
              , units = []
              , visibleTiles = [ { x = 1, y = 1 } ]
              }
            ]

        nextObservation : CurrentTurn.Observation
        nextObservation =
            { turn = { turn | number = 2, submitted = False, opponentSubmitted = False }
            , playbackFrames = frames
            }

        advanced : CurrentTurn.Model
        advanced =
            CurrentTurn.pollSucceeded nextObservation waiting

        recovered : CurrentTurn.Model
        recovered =
            CurrentTurn.submissionFailed 1 "request failed" submitting

        monotonic : CurrentTurn.Model
        monotonic =
            CurrentTurn.pollSucceeded { observation | turn = { turn | submitted = False, opponentSubmitted = False } } waiting

        finished : CurrentTurn.Model
        finished =
            CurrentTurn.pollSucceeded
                { observation | turn = { turn | number = 2, submitted = False, outcome = Just (GameOutcome.Victory PlayerNumber.Player1) }, playbackFrames = [] }
                waiting

        finishedOnRefresh : CurrentTurn.Model
        finishedOnRefresh =
            CurrentTurn.init { turn = { turn | outcome = Just (GameOutcome.Victory PlayerNumber.Player1), submitted = False }, playbackFrames = [] }

        completePlayback : CurrentTurn.Model -> CurrentTurn.Model
        completePlayback current =
            case TurnLifecycle.tick 1000 current.phase of
                Just next ->
                    { current | phase = next.phase }

                Nothing ->
                    current

        introduced : CurrentTurn.Model
        introduced =
            completePlayback advanced

        replayed : Maybe { currentTurn : CurrentTurn.Model, frame : TurnPlayback.Frame }
        replayed =
            CurrentTurn.replay introduced

        replayFinished : Maybe CurrentTurn.Model
        replayFinished =
            Maybe.map (.currentTurn >> completePlayback) replayed

        refreshed : CurrentTurn.Model
        refreshed =
            CurrentTurn.init nextObservation

        replayRewinds : { currentTurn : CurrentTurn.Model, frame : TurnPlayback.Frame } -> Bool
        replayRewinds replay =
            (replay.frame.visibleTiles == [])
                && (replay.currentTurn.phase == advanced.phase)
                && (replay.currentTurn.number == 2)

        replayLocksPlanning : { currentTurn : CurrentTurn.Model, frame : TurnPlayback.Frame } -> Bool
        replayLocksPlanning replay =
            not (CurrentTurn.introductionPending replay.currentTurn)
                && (CurrentTurn.startSubmission replay.currentTurn == Nothing)
                && (CurrentTurn.replay replay.currentTurn == Nothing)
    in
    List.concat
        [ expect "replay is absent on the first turn and during original playback"
            (not (CurrentTurn.canReplay initial) && CurrentTurn.replay initial == Nothing && CurrentTurn.replay advanced == Nothing)
        , expect "the completed turn is replayable only while its introduction is pending"
            (CurrentTurn.canReplay introduced && replayed /= Nothing)
        , expect "replay rewinds projected sight and starts the original animation"
            (Maybe.map replayRewinds replayed == Just True)
        , expect "replay locks planning, hides the introduction, and cannot restart mid-animation"
            (Maybe.map replayLocksPlanning replayed == Just True)
        , expect "replay finishes on the same introduction and supports repeated replay"
            (replayFinished == Just introduced && Maybe.andThen CurrentTurn.replay replayFinished == replayed)
        , expect "beginning the next turn permanently removes replay access for that introduction"
            (CurrentTurn.replay (CurrentTurn.acknowledgeIntroduction introduced)
                == Nothing
                && not (CurrentTurn.canReplay (CurrentTurn.pollSucceeded { observation | turn = { turn | number = 2, submitted = False } } (CurrentTurn.acknowledgeIntroduction introduced)))
            )
        , expect "same-turn polling preserves the retained replay frames"
            (CurrentTurn.replay (CurrentTurn.pollSucceeded { nextObservation | playbackFrames = [] } introduced) == replayed)
        , expect "refresh keeps replay available without starting playback automatically"
            (CurrentTurn.canReplay refreshed && TurnLifecycle.playback refreshed.phase == Nothing)
        , expect "the game conclusion does not offer next-turn replay"
            (CurrentTurn.replay { introduced | outcome = Just GameOutcome.Draw } == Nothing)
        , expect "the final result waits for playback before opening"
            (not (CurrentTurn.introductionPending { advanced | outcome = Just (GameOutcome.Victory PlayerNumber.Player1) }))
        , expect "finished games retain the authoritative winner and announce it"
            (finished.outcome == Just (GameOutcome.Victory PlayerNumber.Player1) && CurrentTurn.introductionPending finished)
        , expect "finished games cannot start another submission"
            (CurrentTurn.startSubmission finished == Nothing)
        , expect "refresh announces a finished game without replaying combat"
            (CurrentTurn.introductionPending finishedOnRefresh && TurnLifecycle.playback finishedOnRefresh.phase == Nothing)
        , expect "dismissed result stays dismissed during polling"
            (not (CurrentTurn.introductionPending (CurrentTurn.pollSucceeded { observation | turn = { turn | number = 2, submitted = False, outcome = Just (GameOutcome.Victory PlayerNumber.Player1) } } (CurrentTurn.acknowledgeIntroduction finished))))
        , expect "planning starts with a turn introduction"
            (CurrentTurn.introductionPending initial)
        , expect "acknowledgment survives same-turn polling"
            (not (CurrentTurn.introductionPending (CurrentTurn.pollSucceeded { observation | turn = { turn | submitted = False, opponentSubmitted = False } } (CurrentTurn.acknowledgeIntroduction initial))))
        , expect "submitted turns do not show an introduction"
            (not (CurrentTurn.introductionPending (CurrentTurn.init observation)))
        , expect "new introduction waits until playback finishes"
            (not (CurrentTurn.introductionPending advanced)
                && CurrentTurn.introductionPending { advanced | phase = Planning OrderPlanning.init }
            )
        , expect "submission retains a poll already in flight"
            submitting.refreshing
        , expect "poll confirmation locks submission and clears in-flight status"
            (TurnLifecycle.planningLocked waiting.phase && not waiting.refreshing)
        , expect "late submission failures cannot unlock confirmed submission"
            (CurrentTurn.submissionFailed 1 "late failure" waiting == waiting)
        , expect "same-turn observations preserve monotonic submission flags"
            (monotonic.opponentSubmitted && TurnLifecycle.planningLocked monotonic.phase)
        , expect "new turn clears submission state and starts playback"
            (advanced.number == 2 && not advanced.opponentSubmitted && TurnLifecycle.playback advanced.phase /= Nothing)
        , expect "stale observations cannot replace the current turn"
            (CurrentTurn.pollSucceeded observation advanced == advanced)
        , expect "late success from an older turn cannot alter playback"
            (CurrentTurn.submissionSucceeded 1 observation advanced == advanced)
        , expect "matching submission failure restores planning and exposes the error"
            (not (TurnLifecycle.planningLocked recovered.phase) && recovered.error == Just "request failed" && recovered.refreshing)
        , expect "poll failure clears in-flight status so polling can retry"
            (not (CurrentTurn.pollFailed "poll failed" pendingPoll).refreshing)
        , expect "initialization never replays prior resolution"
            (TurnLifecycle.playback (CurrentTurn.init observation).phase == Nothing)
        ]


{-| Retain fixture continuation values. Tests that exercise broken assumptions
assert the diagnostic separately; application code must resolve both together.
-}
fixtureValue : InvariantCheck error value -> value
fixtureValue checked =
    let
        retainFixture : Maybe error -> value -> value
        retainFixture _ usable =
            usable
    in
    IC.resolve retainFixture checked
