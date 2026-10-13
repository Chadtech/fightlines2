port module OrderPlanningChecks exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.Direction as DirectionEnum
import Api.Enum.MapTheme as Theme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.Terrain as Terrain
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import GamePage.OrderPlanning as OrderPlanning
import GamePage.Selection exposing (DestinationFeedback(..), Inspection(..), Selection(..))
import Movement
import PlannedOrder
import Platform
import TurnLifecycle
import Unit exposing (Unit)
import Unit.Location as Location exposing (Location)
import UnitCommand
import UnitId exposing (UnitId)


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    case ( UnitId.parse "1", UnitId.parse "2", UnitId.parse "3" ) of
        ( Ok infantryId, Ok truckId, Ok passengerId ) ->
            planningChecks infantryId truckId passengerId

        _ ->
            [ "could not construct planning fixture IDs" ]


planningChecks : UnitId -> UnitId -> UnitId -> List String
planningChecks infantryId truckId passengerId =
    let
        infantry : Unit
        infantry =
            unit infantryId Kind.Infantry (Location.OnMap { x = 1, y = 1 })

        truck : Unit
        truck =
            unit truckId Kind.Truck (Location.OnMap { x = 3, y = 1 })

        context : OrderPlanning.Context
        context =
            board [ infantry, truck ]

        enemy : Unit
        enemy =
            { truck | playerNumber = PlayerNumber.Player2 }

        attackContext : OrderPlanning.Context
        attackContext =
            board [ infantry, enemy ]

        attacking : OrderPlanning.Model
        attacking =
            OrderPlanning.init
                |> OrderPlanning.selectUnit attackContext infantryId
                |> OrderPlanning.applyCommand attackContext UnitCommand.AttackMove
                |> OrderPlanning.extendPath attackContext DirectionEnum.East
                |> OrderPlanning.extendPath attackContext DirectionEnum.East

        attackSaved : OrderPlanning.Model
        attackSaved =
            OrderPlanning.confirmPath attackContext attacking

        attackLoading : OrderPlanning.Model
        attackLoading =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.AttackMove
                |> OrderPlanning.selectTile context { x = 3, y = 1 }

        ambushing : OrderPlanning.Model
        ambushing =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Ambush
                |> OrderPlanning.previewRotation DirectionEnum.East
                |> OrderPlanning.saveRotation context DirectionEnum.East

        truckAmbush : OrderPlanning.Model
        truckAmbush =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context truckId
                |> OrderPlanning.applyCommand context UnitCommand.Ambush
                |> OrderPlanning.saveRotation context DirectionEnum.East

        moving : OrderPlanning.Model
        moving =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.extendPath context DirectionEnum.South

        saved : OrderPlanning.Model
        saved =
            OrderPlanning.confirmPath context moving

        crateChoice : OrderPlanning.Model
        crateChoice =
            OrderPlanning.ChoosingCrates truckId
                { orders = OrderPlanning.orders saved
                , selection = Just (Inspecting (UnitInspection truckId))
                }

        dismissedCrates : OrderPlanning.Model
        dismissedCrates =
            OrderPlanning.dismissDialog [] crateChoice

        reserved : OrderPlanning.Model
        reserved =
            saved
                |> OrderPlanning.selectUnit context truckId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context { x = 1, y = 2 }

        enteringVacated : OrderPlanning.Model
        enteringVacated =
            saved
                |> OrderPlanning.selectUnit context truckId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context { x = 1, y = 1 }

        revokeDeparture : OrderPlanning.Model
        revokeDeparture =
            enteringVacated
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.revokeSelectedOrder context

        truckDeparting : OrderPlanning.Model
        truckDeparting =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context truckId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context { x = 3, y = 2 }

        enteringTruckOrigin : OrderPlanning.Model
        enteringTruckOrigin =
            truckDeparting
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context { x = 3, y = 1 }

        fullFreight : PlannedOrder.PlannedOrder
        fullFreight =
            { unitId = truckId
            , action =
                PlannedOrder.SupplyTransfer
                    { route =
                        [ { x = 3
                          , y = 1
                          }
                        ]
                    , destination =
                        { x = 3
                        , y = 1
                        }
                    , handling = PlannedOrder.LoadingCrates 2
                    , passengers = []
                    }
            }

        mixedFreight : PlannedOrder.PlannedOrder
        mixedFreight =
            { fullFreight
                | action =
                    PlannedOrder.SupplyTransfer
                        { route =
                            [ { x = 3
                              , y = 1
                              }
                            ]
                        , destination =
                            { x = 3
                            , y = 1
                            }
                        , handling = PlannedOrder.LoadingCrates 1
                        , passengers = []
                        }
            }

        boardingWithFreight : OrderPlanning.Model
        boardingWithFreight =
            OrderPlanning.init
                |> OrderPlanning.setOrders [ mixedFreight ]
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context
                    { x = 3
                    , y = 1
                    }

        tryingFullTruck : OrderPlanning.Model
        tryingFullTruck =
            OrderPlanning.init
                |> OrderPlanning.setOrders [ fullFreight ]
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context
                    { x = 3
                    , y = 1
                    }

        cacheFreight : PlannedOrder.PlannedOrder
        cacheFreight =
            { unitId = truckId
            , action =
                PlannedOrder.SupplyTransfer
                    { route =
                        [ { x = 3
                          , y = 1
                          }
                        ]
                    , destination =
                        { x = 3
                        , y = 1
                        }
                    , handling =
                        PlannedOrder.UnloadingCrates
                            [ { cargoIndex = 0
                              , destination =
                                    { x = 2
                                    , y = 1
                                    }
                              }
                            ]
                    , passengers = []
                    }
            }

        tryingCrateExit : OrderPlanning.Model
        tryingCrateExit =
            OrderPlanning.init
                |> OrderPlanning.setOrders [ cacheFreight ]
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context
                    { x = 2
                    , y = 1
                    }

        chainContext : OrderPlanning.Context
        chainContext =
            board [ infantry, truck, unit passengerId Kind.Infantry (Location.OnMap { x = 2, y = 1 }) ]

        chain : OrderPlanning.Model
        chain =
            OrderPlanning.init
                |> OrderPlanning.selectUnit chainContext truckId
                |> OrderPlanning.applyCommand chainContext UnitCommand.Move
                |> OrderPlanning.selectTile chainContext { x = 3, y = 2 }
                |> OrderPlanning.selectUnit chainContext passengerId
                |> OrderPlanning.applyCommand chainContext UnitCommand.Move
                |> OrderPlanning.selectTile chainContext { x = 3, y = 1 }
                |> OrderPlanning.selectUnit chainContext infantryId
                |> OrderPlanning.applyCommand chainContext UnitCommand.Move
                |> OrderPlanning.selectTile chainContext { x = 2, y = 1 }

        revokedChain : OrderPlanning.Model
        revokedChain =
            chain
                |> OrderPlanning.selectUnit chainContext truckId
                |> OrderPlanning.revokeSelectedOrder chainContext

        loading : OrderPlanning.Model
        loading =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context { x = 3, y = 1 }

        receiving : OrderPlanning.Model
        receiving =
            OrderPlanning.selectUnit context truckId loading

        revoked : OrderPlanning.Model
        revoked =
            loading
                |> OrderPlanning.revokeSelectedOrder context
                |> OrderPlanning.selectUnit context truckId
                |> OrderPlanning.revokeSelectedOrder context

        rotated : OrderPlanning.Model
        rotated =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Rotate
                |> OrderPlanning.previewRotation DirectionEnum.West
                |> OrderPlanning.saveRotation context DirectionEnum.West

        cargoContext : OrderPlanning.Context
        cargoContext =
            board
                [ truck
                , unit infantryId Kind.Infantry (Location.Aboard truckId)
                , unit passengerId Kind.FieldGun (Location.Aboard truckId)
                ]

        checklist : OrderPlanning.Model
        checklist =
            OrderPlanning.init
                |> OrderPlanning.selectUnit cargoContext truckId
                |> OrderPlanning.applyCommand cargoContext UnitCommand.HoldPosition

        exits : OrderPlanning.Model
        exits =
            checklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> OrderPlanning.confirmPassengers cargoContext

        firstExit : OrderPlanning.Model
        firstExit =
            OrderPlanning.chooseUnloadSquare cargoContext { x = 3, y = 2 } exits

        rejectedExit : OrderPlanning.Model
        rejectedExit =
            OrderPlanning.chooseUnloadSquare cargoContext { x = 3, y = 2 } firstExit

        completed : OrderPlanning.Model
        completed =
            OrderPlanning.chooseUnloadSquare cargoContext { x = 4, y = 1 } rejectedExit

        truckMove : OrderPlanning.Model
        truckMove =
            OrderPlanning.init
                |> OrderPlanning.selectUnit cargoContext truckId
                |> OrderPlanning.applyCommand cargoContext UnitCommand.Move
                |> OrderPlanning.selectTile cargoContext { x = 4, y = 1 }
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.confirmPassengers cargoContext
                |> OrderPlanning.chooseUnloadSquare cargoContext { x = 5, y = 1 }

        freightTruck : Unit
        freightTruck =
            { truck
                | resources =
                    truck.resources
                        |> Maybe.map
                            (\resources ->
                                { resources
                                    | supplyCargo =
                                        [ { current = 48
                                          , maximum = 64
                                          }
                                        ]
                                }
                            )
            }

        mixedContext : OrderPlanning.Context
        mixedContext =
            board [ freightTruck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]

        mixedChecklist : OrderPlanning.Model
        mixedChecklist =
            OrderPlanning.init
                |> OrderPlanning.selectUnit mixedContext truckId
                |> OrderPlanning.applyCommand mixedContext UnitCommand.HoldPosition

        mixedExits : OrderPlanning.Model
        mixedExits =
            mixedChecklist
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.confirmPassengers mixedContext

        crateExit : OrderPlanning.Model
        crateExit =
            OrderPlanning.chooseUnloadSquare mixedContext
                { x = 3
                , y = 2
                }
                mixedExits

        mixedComplete : OrderPlanning.Model
        mixedComplete =
            OrderPlanning.chooseUnloadSquare mixedContext
                { x = 4
                , y = 1
                }
                crateExit

        passengerFirst : OrderPlanning.Model
        passengerFirst =
            mixedChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> OrderPlanning.confirmPassengers mixedContext
                |> OrderPlanning.chooseUnloadSquare mixedContext
                    { x = 3
                    , y = 2
                    }

        crateOnlyContext : OrderPlanning.Context
        crateOnlyContext =
            board [ freightTruck ]

        crateOnlyMove : OrderPlanning.Model
        crateOnlyMove =
            OrderPlanning.init
                |> OrderPlanning.selectUnit crateOnlyContext truckId
                |> OrderPlanning.applyCommand crateOnlyContext UnitCommand.Move
                |> OrderPlanning.selectTile crateOnlyContext
                    { x = 4
                    , y = 1
                    }

        twoCrateTruck : Unit
        twoCrateTruck =
            { truck
                | resources =
                    truck.resources
                        |> Maybe.map
                            (\resources ->
                                { resources
                                    | supplyCargo =
                                        [ { current = 48
                                          , maximum = 64
                                          }
                                        , { current = 16
                                          , maximum = 64
                                          }
                                        ]
                                }
                            )
            }

        twoCrateContext : OrderPlanning.Context
        twoCrateContext =
            board [ twoCrateTruck ]

        selectedSecondCrate : OrderPlanning.Model
        selectedSecondCrate =
            OrderPlanning.init
                |> OrderPlanning.selectUnit twoCrateContext truckId
                |> OrderPlanning.applyCommand twoCrateContext UnitCommand.HoldPosition
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 1) True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) False
                |> OrderPlanning.confirmPassengers twoCrateContext
                |> OrderPlanning.chooseUnloadSquare twoCrateContext
                    { x = 3
                    , y = 2
                    }

        blockedCrateContext : OrderPlanning.Context
        blockedCrateContext =
            { mixedContext
                | supplyCrates =
                    [ { position =
                            { x = 3
                            , y = 2
                            }
                      , stock =
                            { current = 32
                            , maximum = 64
                            }
                      }
                    ]
            }

        depotContext : OrderPlanning.Context
        depotContext =
            { context
                | depots =
                    [ { position = { x = 3, y = 1 }, stock = Just { current = 256, maximum = 256 } }
                    , { position = { x = 4, y = 1 }, stock = Nothing }
                    ]
            }

        depotMovePreview : OrderPlanning.Model
        depotMovePreview =
            OrderPlanning.init
                |> OrderPlanning.selectUnit depotContext truckId
                |> OrderPlanning.applyCommand depotContext UnitCommand.Move
                |> OrderPlanning.extendPath depotContext DirectionEnum.East

        depotMove : OrderPlanning.Model
        depotMove =
            OrderPlanning.selectTile depotContext { x = 4, y = 1 } depotMovePreview

        depotKeyboardMove : OrderPlanning.Model
        depotKeyboardMove =
            OrderPlanning.confirmPath depotContext depotMovePreview

        depotBoarding : OrderPlanning.Model
        depotBoarding =
            OrderPlanning.init
                |> OrderPlanning.selectUnit depotContext infantryId
                |> OrderPlanning.applyCommand depotContext UnitCommand.Move
                |> OrderPlanning.selectTile depotContext { x = 3, y = 1 }

        depotHold : OrderPlanning.Model
        depotHold =
            OrderPlanning.init
                |> OrderPlanning.selectUnit depotContext truckId
                |> OrderPlanning.applyCommand depotContext UnitCommand.HoldPosition

        dismissedDepot : OrderPlanning.Model
        dismissedDepot =
            OrderPlanning.dismissDialog depotContext.depots depotMove

        depotCargoContext : OrderPlanning.Context
        depotCargoContext =
            { cargoContext | depots = depotContext.depots }

        depotChecklist : OrderPlanning.Model
        depotChecklist =
            OrderPlanning.init
                |> OrderPlanning.selectUnit depotCargoContext truckId
                |> OrderPlanning.applyCommand depotCargoContext UnitCommand.HoldPosition

        depotExits : OrderPlanning.Model
        depotExits =
            depotChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> OrderPlanning.confirmPassengers depotCargoContext

        depotFirstExit : OrderPlanning.Model
        depotFirstExit =
            OrderPlanning.chooseUnloadSquare depotCargoContext { x = 3, y = 2 } depotExits

        depotCompleted : OrderPlanning.Model
        depotCompleted =
            OrderPlanning.chooseUnloadSquare depotCargoContext { x = 4, y = 1 } depotFirstExit

        depotMixedContext : OrderPlanning.Context
        depotMixedContext =
            { mixedContext | depots = depotContext.depots }

        depotCrateUnloaded : OrderPlanning.Model
        depotCrateUnloaded =
            OrderPlanning.init
                |> OrderPlanning.selectUnit depotMixedContext truckId
                |> OrderPlanning.applyCommand depotMixedContext UnitCommand.HoldPosition
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> OrderPlanning.confirmPassengers depotMixedContext
                |> OrderPlanning.chooseUnloadSquare depotMixedContext { x = 3, y = 2 }

        choosingCrates : OrderPlanning.Model -> Bool
        choosingCrates state =
            case state of
                OrderPlanning.ChoosingCrates id _ ->
                    id == truckId

                _ ->
                    False

        submitted : TurnLifecycle.Phase
        submitted =
            TurnLifecycle.startSubmission 1 (TurnLifecycle.Planning saved)

        ordersForSubmission : List PlannedOrder.PlannedOrder
        ordersForSubmission =
            OrderPlanning.submissionOrders cargoContext (OrderPlanning.orders completed)

        firstUnordered : OrderPlanning.Model
        firstUnordered =
            OrderPlanning.selectNextUnorderedUnit context OrderPlanning.init

        secondUnordered : OrderPlanning.Model
        secondUnordered =
            OrderPlanning.selectNextUnorderedUnit context firstUnordered

        wrappedUnordered : OrderPlanning.Model
        wrappedUnordered =
            OrderPlanning.selectNextUnorderedUnit context secondUnordered

        afterPreview : OrderPlanning.Model
        afterPreview =
            OrderPlanning.selectNextUnorderedUnit context moving

        afterOrder : OrderPlanning.Model
        afterOrder =
            OrderPlanning.selectNextUnorderedUnit context saved
    in
    List.concat
        [ expect "saving an empty truck move on a depot opens loading through mouse and keyboard"
            (choosingCrates depotMove && depotKeyboardMove == depotMove)
        , expect "boarding a truck on a depot offers loading for its automatically saved hold"
            (choosingCrates depotBoarding)
        , expect "holding an empty truck on a depot opens loading"
            (choosingCrates depotHold)
        , expect "hovering, selecting, and dismissing preserve drafts without reopening loading"
            (not (choosingCrates depotMovePreview)
                && not (choosingCrates (OrderPlanning.previewTile depotContext { x = 4, y = 1 } dismissedDepot))
                && not (choosingCrates (OrderPlanning.selectUnit depotContext truckId dismissedDepot))
                && OrderPlanning.orders dismissedDepot
                == OrderPlanning.orders depotMove
            )
        , expect "loaded trucks offer unloading before depot loading"
            (OrderPlanning.unloadChoice depotChecklist /= Nothing)
        , expect "confirming no unloads, skipping, and dismissing unloading offer depot loading"
            (choosingCrates (OrderPlanning.confirmPassengers depotCargoContext depotChecklist)
                && choosingCrates (OrderPlanning.skipUnloading depotCargoContext depotChecklist)
                && choosingCrates (OrderPlanning.dismissDialog depotCargoContext.depots depotChecklist)
            )
        , expect "finishing or skipping remaining passenger exits preserves them before depot loading"
            (choosingCrates depotCompleted
                && List.concatMap PlannedOrder.unloads (OrderPlanning.orders depotCompleted)
                == List.concatMap PlannedOrder.unloads (OrderPlanning.orders completed)
                && choosingCrates (OrderPlanning.skipUnloading depotCargoContext depotFirstExit)
                && List.concatMap PlannedOrder.unloads (OrderPlanning.orders (OrderPlanning.skipUnloading depotCargoContext depotFirstExit))
                == [ { unitId = infantryId, destination = { x = 3, y = 2 } } ]
            )
        , expect "crate unloading on a depot completes without offering incompatible loading"
            (not (choosingCrates depotCrateUnloaded)
                && List.concatMap PlannedOrder.crateUnloads (OrderPlanning.orders depotCrateUnloaded)
                == [ { cargoIndex = 0, destination = { x = 3, y = 2 } } ]
            )
        , expect "crate loading dialog preserves drafts and blocks submission until dismissed"
            (OrderPlanning.selectNextUnorderedUnit context crateChoice
                == crateChoice
                && OrderPlanning.orders crateChoice
                == OrderPlanning.orders saved
                && OrderPlanning.submissionDrafts crateChoice
                == Nothing
                && OrderPlanning.orders dismissedCrates
                == OrderPlanning.orders saved
                && OrderPlanning.submissionDrafts dismissedCrates
                /= Nothing
            )
        , expect "attack move traces and saves an occupied enemy destination without creating loading holds"
            (List.map PlannedOrder.path (OrderPlanning.orders attackSaved) == [ [ { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 3, y = 1 } ] ] && List.all PlannedOrder.isAttackMove (OrderPlanning.orders attackSaved) && OrderPlanning.pathPreview attackSaved == Nothing)
        , expect "attack move cannot board an allied truck"
            (List.isEmpty (OrderPlanning.orders attackLoading) && OrderPlanning.destinationFeedback attackLoading == DestinationUnavailable)
        , expect "attack move revocation restores commands"
            (OrderPlanning.commandMenuUnit attackContext (OrderPlanning.revokeSelectedOrder attackContext attackSaved) == Just infantry)
        , expect "ambush direction preview saves a stationary ambush instead of rotation"
            (OrderPlanning.orders ambushing == [ { unitId = infantryId, action = PlannedOrder.Ambush { position = { x = 1, y = 1 }, direction = DirectionEnum.East } } ])
        , expect "ambush can be revoked and trucks cannot ambush"
            (List.isEmpty (OrderPlanning.orders (OrderPlanning.revokeSelectedOrder context ambushing)) && List.isEmpty (OrderPlanning.orders truckAmbush))
        , expect "unordered selection cycles through eligible units and wraps"
            (OrderPlanning.commandMenuUnit context firstUnordered == Just infantry && OrderPlanning.commandMenuUnit context secondUnordered == Just truck && OrderPlanning.commandMenuUnit context wrappedUnordered == Just infantry)
        , expect "unordered selection leaves a preview without saving a move"
            (OrderPlanning.commandMenuUnit context afterPreview == Just truck && List.isEmpty (OrderPlanning.orders afterPreview))
        , expect "unordered selection skips saved orders and keeps the last eligible unit selected"
            (OrderPlanning.commandMenuUnit context afterOrder == Just truck && OrderPlanning.orders afterOrder == OrderPlanning.orders saved && OrderPlanning.selectNextUnorderedUnit context afterOrder == afterOrder)
        , expect "unordered selection does nothing when all on-board units have orders"
            (OrderPlanning.selectNextUnorderedUnit cargoContext completed == completed)
        , expect "unordered selection cannot leave a submission or unload dialog"
            (OrderPlanning.selectNextUnorderedUnit context (OrderPlanning.showSubmissionWarning firstUnordered) == OrderPlanning.showSubmissionWarning firstUnordered && OrderPlanning.selectNextUnorderedUnit cargoContext checklist == checklist)
        , expect "path confirmation saves the traced route and closes editing"
            (List.map PlannedOrder.path (OrderPlanning.orders saved) == [ [ { x = 1, y = 1 }, { x = 1, y = 2 } ] ] && OrderPlanning.pathPreview saved == Nothing)
        , expect "another unit cannot claim a reserved destination and receives feedback"
            (OrderPlanning.orders reserved == OrderPlanning.orders saved && OrderPlanning.destinationFeedback reserved == DestinationUnavailable)
        , expect "a truck can move onto a departing infantry square without changing its order"
            (List.length (OrderPlanning.orders enteringVacated) == 2 && List.all PlannedOrder.isMoving (OrderPlanning.orders enteringVacated))
        , expect "revoking a departure also revokes the move depending on its freed square"
            (List.isEmpty (OrderPlanning.orders revokeDeparture))
        , expect "departure revocation clears a whole dependent chain"
            (List.length (OrderPlanning.orders chain) == 3 && List.isEmpty (OrderPlanning.orders revokedChain))
        , expect "moving onto a departing truck keeps both moves and creates no loading target"
            (List.length (OrderPlanning.orders enteringTruckOrigin) == 2 && List.all PlannedOrder.isMoving (OrderPlanning.orders enteringTruckOrigin) && OrderPlanning.loadingTarget context infantry { x = 3, y = 1 } (OrderPlanning.orders enteringTruckOrigin) == Nothing)
        , expect "loading saves the mover and a holding receiver"
            (List.length (OrderPlanning.orders loading) == 2 && OrderPlanning.receivingLoad context truck (OrderPlanning.orders loading))
        , expect "a receiving truck is inspection only"
            (OrderPlanning.commandMenuUnit context receiving == Nothing && OrderPlanning.selection receiving == Just (Inspecting (UnitInspection truckId)))
        , expect "revoking loading and receiver holds restores truck commands"
            (List.isEmpty (OrderPlanning.orders revoked) && OrderPlanning.commandMenuUnit context revoked == Just truck)
        , expect "rotation becomes a revocable draft without moving"
            (List.map .action (OrderPlanning.orders rotated) == [ PlannedOrder.Rotate { position = { x = 1, y = 1 }, direction = DirectionEnum.West } ])
        , expect "holding a loaded truck opens its stationary unload checklist"
            (OrderPlanning.unloadChoice checklist /= Nothing)
        , expect "each unload exit reserves its square for the next passenger"
            (OrderPlanning.orders firstExit == OrderPlanning.orders rejectedExit && OrderPlanning.destinationFeedback rejectedExit == DestinationUnavailable)
        , expect "stationary unloading completes with both passengers and releases the workflow"
            (List.concatMap PlannedOrder.unloads (OrderPlanning.orders completed) == [ { unitId = infantryId, destination = { x = 3, y = 2 } }, { unitId = passengerId, destination = { x = 4, y = 1 } } ] && OrderPlanning.unloadPlanning completed == Nothing)
        , expect "moving truck exits use the planned truck destination"
            (List.concatMap PlannedOrder.unloads (OrderPlanning.orders truckMove) == [ { unitId = infantryId, destination = { x = 5, y = 1 } } ])
        , expect "cargo needs no explicit ready order but receives holds for submission"
            (List.isEmpty (OrderPlanning.missingOrders cargoContext (OrderPlanning.orders completed)) && List.length ordersForSubmission == 3)
        , expect "explicit crate loading reserves the truck berths against later boarding drafts"
            (List.map .unitId (OrderPlanning.orders tryingFullTruck) == [ truckId ])
        , expect "boarding into a spare berth preserves an explicit crate-loading order"
            (List.member mixedFreight (OrderPlanning.orders boardingWithFreight) && List.length (OrderPlanning.orders boardingWithFreight) == 2)
        , expect "planned ground crate exits reserve their destination against later unit moves"
            (List.map .unitId (OrderPlanning.orders tryingCrateExit) == [ truckId ])
        , expect "mixed cargo can unload a crate then a passenger in one stationary order"
            (List.concatMap PlannedOrder.crateUnloads (OrderPlanning.orders mixedComplete)
                == [ { cargoIndex = 0
                     , destination =
                        { x = 3
                        , y = 2
                        }
                     }
                   ]
                && List.concatMap PlannedOrder.unloads (OrderPlanning.orders mixedComplete)
                == [ { unitId = infantryId
                     , destination =
                        { x = 4
                        , y = 1
                        }
                     }
                   ]
                && OrderPlanning.unloadPlanning mixedComplete
                == Nothing
            )
        , expect "crate and passenger exits reserve squares in either selection order"
            (not
                (List.member
                    { x = 3
                    , y = 2
                    }
                    (List.map .destination (OrderPlanning.moveOptions crateExit))
                )
                && not
                    (List.member
                        { x = 3
                        , y = 2
                        }
                        (List.map .destination (OrderPlanning.moveOptions passengerFirst))
                    )
            )
        , expect "trucks carrying only crates open the unload checklist after moving"
            (OrderPlanning.unloadChoice crateOnlyMove /= Nothing)
        , expect "existing ground crates block crate exits"
            (not
                (List.member
                    { x = 3
                    , y = 2
                    }
                    (List.map .destination
                        (OrderPlanning.moveOptions
                            (OrderPlanning.confirmPassengers blockedCrateContext
                                (mixedChecklist
                                    |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                                )
                            )
                        )
                    )
                )
            )
        , expect "unchecking one crate preserves the selected original cargo slot"
            (List.concatMap PlannedOrder.crateUnloads (OrderPlanning.orders selectedSecondCrate)
                == [ { cargoIndex = 1
                     , destination =
                        { x = 3
                        , y = 2
                        }
                     }
                   ]
                && OrderPlanning.unloadPlanning selectedSecondCrate
                == Nothing
            )
        , expect "declining mixed unloading preserves an ordinary hold"
            (List.map .action (OrderPlanning.orders (OrderPlanning.confirmPassengers mixedContext mixedChecklist))
                == [ PlannedOrder.Hold
                        { x = 3
                        , y = 1
                        }
                   ]
            )
        , expect "lifecycle gating prevents editing submitted drafts"
            (TurnLifecycle.mapPlanning (OrderPlanning.selectTile context { x = 2, y = 2 }) submitted == submitted)
        ]


board : List Unit -> OrderPlanning.Context
board units =
    { map = { width = 7, height = 7, baseTile = Terrain.GrassPlain, theme = Theme.GreenForest, features = [] }
    , units = units
    , movementRules = List.map movementRule [ Kind.Infantry, Kind.Truck, Kind.FieldGun ]
    , depots = []
    , supplyCrates = []
    , playerSides = [ PlayerNumber.Player1 ]
    }


movementRule : UnitKind -> Movement.Rule
movementRule kind =
    { kind = kind, budget = 12, terrainCosts = [ { terrain = Terrain.GrassPlain, cost = 2 } ] }


unit : UnitId -> UnitKind -> Location -> Unit
unit id kind location =
    let
        vehicle : Bool
        vehicle =
            kind == Kind.Truck

        direction : Maybe DirectionEnum.Direction
        direction =
            if vehicle then
                Nothing

            else
                Just DirectionEnum.North

        fuel : Maybe { current : Int, maximum : Int }
        fuel =
            if vehicle then
                Just { current = 64, maximum = 64 }

            else
                Nothing

        capacity : Int
        capacity =
            if vehicle then
                2

            else
                0
    in
    { id = id
    , playerNumber = PlayerNumber.Player1
    , spriteFacing = SpriteFacing.Right
    , kind = kind
    , direction = direction
    , destroyed = False
    , combatRules =
        { range = 1
        , shape = AmbushShape.Line
        , damage = 4
        , readinessCost = 2
        , shotCost = 2
        }
    , cargoCapacity = capacity
    , location = location
    , resources =
        Just
            { supplyCargo = []
            , hitPoints =
                { current = 16
                , maximum = 16
                }
            , supplies =
                { current = 64
                , maximum = 64
                , upkeepPerTurn = 1
                , movementPerTile = 1
                }
            , fuel = fuel
            }
    }


expect : String -> Bool -> List String
expect label condition =
    if condition then
        []

    else
        [ label ]
