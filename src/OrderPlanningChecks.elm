port module OrderPlanningChecks exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.DepotKind as DepotKind
import Api.Enum.Direction as DirectionEnum
import Api.Enum.MapTheme as Theme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.Terrain as Terrain
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import GamePage.OrderPlanning as OrderPlanning
import GamePage.Selection exposing (DestinationFeedback(..), Inspection(..), Selection(..))
import Map exposing (Map)
import Movement
import PlannedOrder
import Platform
import TurnLifecycle
import Unit exposing (Unit)
import Unit.Location as Location exposing (Location)
import Unit.Supplies
import UnitCommand
import UnitId exposing (UnitId)
import UnitResources exposing (UnitResources)


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

        lowSupplyInfantry : Unit
        lowSupplyInfantry =
            { infantry | resources = Maybe.map (\resources -> { resources | supplies = { current = 6, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 } }) infantry.resources }

        lowSupplyContext : OrderPlanning.Context
        lowSupplyContext =
            board [ lowSupplyInfantry, enemy ]

        lowSupplyAttack : OrderPlanning.Model
        lowSupplyAttack =
            OrderPlanning.init
                |> OrderPlanning.selectUnit lowSupplyContext infantryId
                |> OrderPlanning.applyCommand lowSupplyContext UnitCommand.AttackMove
                |> OrderPlanning.extendPath lowSupplyContext DirectionEnum.East
                |> OrderPlanning.extendPath lowSupplyContext DirectionEnum.East

        attackLoading : OrderPlanning.Model
        attackLoading =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.AttackMove
                |> OrderPlanning.selectTile context { x = 3, y = 1 }

        fieldGun : Unit
        fieldGun =
            { infantry
                | kind = Kind.FieldGun
                , combatRules =
                    { range = 3
                    , indirectRange = 12
                    , shape = AmbushShape.Cross
                    , damage = 12
                    , readinessCost = 2
                    , shotCost = 3
                    }
            }

        indirectContext : OrderPlanning.Context
        indirectContext =
            { context
                | units = [ fieldGun, truck ]
            }

        aiming : OrderPlanning.Model
        aiming =
            OrderPlanning.init
                |> OrderPlanning.selectUnit indirectContext infantryId
                |> OrderPlanning.applyCommand indirectContext UnitCommand.IndirectFire

        bombardment : OrderPlanning.Model
        bombardment =
            aiming
                |> OrderPlanning.selectTile indirectContext
                    { x = 3
                    , y = 3
                    }

        aimedOrder : Coordinate -> PlannedOrder.PlannedOrder
        aimedOrder target =
            { unitId = infantryId
            , action =
                PlannedOrder.IndirectFire
                    { position =
                        { x = 1
                        , y = 1
                        }
                    , target = target
                    }
            }

        selfBombardment : OrderPlanning.Model
        selfBombardment =
            aiming |> OrderPlanning.selectUnit indirectContext infantryId

        rangeMap : Map
        rangeMap =
            { width = 20
            , height = 3
            , baseTile = Terrain.GrassPlain
            , theme = Theme.GreenForest
            , features = []
            }

        outOfRangeContext : OrderPlanning.Context
        outOfRangeContext =
            { indirectContext
                | map = rangeMap
            }

        edgeAim : OrderPlanning.Model
        edgeAim =
            OrderPlanning.init
                |> OrderPlanning.selectUnit outOfRangeContext infantryId
                |> OrderPlanning.applyCommand outOfRangeContext UnitCommand.IndirectFire

        standingGround : OrderPlanning.Model
        standingGround =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.StandGround

        insufficientReadiness : Unit
        insufficientReadiness =
            { infantry | resources = Maybe.map (\resources -> { resources | supplies = { current = 2, maximum = 48, upkeepPerTurn = 1, roughTerrainSurcharge = 1, movementPerTile = 3 } }) infantry.resources }

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

        rendezvousContext : OrderPlanning.Context
        rendezvousContext =
            board [ infantry, truck, unit passengerId Kind.FieldGun (Location.OnMap { x = 2, y = 1 }) ]

        rendezvous : OrderPlanning.Model
        rendezvous =
            OrderPlanning.init
                |> OrderPlanning.selectUnit rendezvousContext truckId
                |> OrderPlanning.applyCommand rendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile rendezvousContext { x = 2, y = 2 }
                |> OrderPlanning.selectUnit rendezvousContext infantryId
                |> OrderPlanning.applyCommand rendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile rendezvousContext { x = 2, y = 2 }
                |> OrderPlanning.selectUnit rendezvousContext passengerId
                |> OrderPlanning.applyCommand rendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile rendezvousContext { x = 2, y = 2 }

        pickupRendezvous : OrderPlanning.Model
        pickupRendezvous =
            OrderPlanning.init
                |> OrderPlanning.selectUnit rendezvousContext truckId
                |> OrderPlanning.applyCommand rendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile rendezvousContext { x = 2, y = 1 }
                |> OrderPlanning.selectUnit rendezvousContext infantryId
                |> OrderPlanning.applyCommand rendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile rendezvousContext { x = 2, y = 1 }

        freightRendezvousContext : OrderPlanning.Context
        freightRendezvousContext =
            let
                addCrate : UnitResources -> UnitResources
                addCrate resources =
                    { resources
                        | supplyCargo =
                            [ { kind = DepotKind.Supply
                              , current = 64
                              , maximum = 64
                              }
                            ]
                    }

                withCrate : Unit -> Unit
                withCrate cargoUnit =
                    if cargoUnit.id == truckId then
                        { cargoUnit | resources = Maybe.map addCrate cargoUnit.resources }

                    else
                        cargoUnit
            in
            { rendezvousContext | units = List.map withCrate rendezvousContext.units }

        freightRendezvous : OrderPlanning.Model
        freightRendezvous =
            OrderPlanning.init
                |> OrderPlanning.selectUnit freightRendezvousContext truckId
                |> OrderPlanning.applyCommand freightRendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile freightRendezvousContext { x = 2, y = 2 }
                |> OrderPlanning.skipUnloading freightRendezvousContext
                |> OrderPlanning.selectUnit freightRendezvousContext infantryId
                |> OrderPlanning.applyCommand freightRendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile freightRendezvousContext { x = 2, y = 2 }

        overfullRendezvous : OrderPlanning.Model
        overfullRendezvous =
            freightRendezvous
                |> OrderPlanning.selectUnit freightRendezvousContext passengerId
                |> OrderPlanning.applyCommand freightRendezvousContext UnitCommand.Move
                |> OrderPlanning.selectTile freightRendezvousContext { x = 2, y = 2 }

        revokedRendezvous : OrderPlanning.Model
        revokedRendezvous =
            rendezvous
                |> OrderPlanning.selectUnit rendezvousContext truckId
                |> OrderPlanning.revokeSelectedOrder rendezvousContext

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
                                        [ { kind = DepotKind.Supply
                                          , current = 48
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
                                        [ { kind = DepotKind.Supply
                                          , current = 48
                                          , maximum = 64
                                          }
                                        , { kind = DepotKind.Supply
                                          , current = 16
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
                            { kind = DepotKind.Supply
                            , current = 32
                            , maximum = 64
                            }
                      }
                    ]
            }

        depotContext : OrderPlanning.Context
        depotContext =
            { context
                | depots =
                    [ { kind = DepotKind.Supply, position = { x = 3, y = 1 }, stock = Just { current = 256, maximum = 256 } }
                    , { kind = DepotKind.Supply, position = { x = 4, y = 1 }, stock = Nothing }
                    ]
            }

        fuelContext : OrderPlanning.Context
        fuelContext =
            { depotContext | depots = List.map (\depot -> { depot | kind = DepotKind.Fuel }) depotContext.depots }

        fuelMove : OrderPlanning.Model
        fuelMove =
            OrderPlanning.init
                |> OrderPlanning.selectUnit fuelContext truckId
                |> OrderPlanning.applyCommand fuelContext UnitCommand.Move
                |> OrderPlanning.extendPath fuelContext DirectionEnum.East
                |> OrderPlanning.selectTile fuelContext { x = 4, y = 1 }

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

        putTruckAtCorner : Unit -> Unit
        putTruckAtCorner current =
            if current.id == truckId then
                Unit.setOnMap { x = 3, y = 0 } current

            else
                current

        narrowContext : OrderPlanning.Context
        narrowContext =
            { cargoContext
                | map = { width = 4, height = 1, baseTile = cargoContext.map.baseTile, features = [], theme = cargoContext.map.theme }
                , units =
                    List.map putTruckAtCorner
                        cargoContext.units
            }

        narrowChecklist : OrderPlanning.Model
        narrowChecklist =
            OrderPlanning.init
                |> OrderPlanning.selectUnit narrowContext truckId
                |> OrderPlanning.applyCommand narrowContext UnitCommand.HoldPosition
                |> OrderPlanning.toggleAvailableUnloadCargo narrowContext (OrderPlanning.Passenger infantryId) True

        narrowCrateContext : OrderPlanning.Context
        narrowCrateContext =
            { twoCrateContext | map = narrowContext.map, units = List.map (Unit.setOnMap { x = 3, y = 0 }) twoCrateContext.units }

        narrowCrateChecklist : OrderPlanning.Model
        narrowCrateChecklist =
            OrderPlanning.init
                |> OrderPlanning.selectUnit narrowCrateContext truckId
                |> OrderPlanning.applyCommand narrowCrateContext UnitCommand.HoldPosition
                |> OrderPlanning.toggleAvailableUnloadCargo narrowCrateContext (OrderPlanning.Crate 0) True

        scarceCrateContext : OrderPlanning.Context
        scarceCrateContext =
            { mixedContext
                | map = { width = 4, height = 2, baseTile = mixedContext.map.baseTile, theme = mixedContext.map.theme, features = [] }
                , supplyCrates = [ { position = { x = 3, y = 0 }, stock = { kind = DepotKind.Supply, current = 64, maximum = 64 } } ]
            }

        scarceCrateExits : OrderPlanning.Model
        scarceCrateExits =
            mixedChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> OrderPlanning.confirmPassengers scarceCrateContext

        exhaustedContext : OrderPlanning.Context
        exhaustedContext =
            let
                exhaustPassenger : Unit -> Unit
                exhaustPassenger passenger =
                    if passenger.id == infantryId then
                        { passenger | resources = Maybe.map exhaustResources passenger.resources }

                    else
                        passenger

                exhaustResources : UnitResources.UnitResources -> UnitResources.UnitResources
                exhaustResources resources =
                    let
                        supplies : Unit.Supplies.Supplies
                        supplies =
                            resources.supplies
                    in
                    { resources | supplies = { supplies | current = 1 } }
            in
            { cargoContext | units = List.map exhaustPassenger cargoContext.units }

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

        guideMenu : OrderPlanning.Model
        guideMenu =
            afterOrder
                |> OrderPlanning.focusCommand context (UnitCommand.CommandOption UnitCommand.Move)

        readingGuide : OrderPlanning.Model
        readingGuide =
            OrderPlanning.openCommandGuide context guideMenu

        guideLocked : TurnLifecycle.Phase
        guideLocked =
            TurnLifecycle.observeSubmission True (TurnLifecycle.Planning readingGuide)
    in
    List.concat
        [ expect "command guide preserves orders and returns to the focused command menu"
            (OrderPlanning.commandGuideOpen readingGuide
                && OrderPlanning.orders readingGuide
                == OrderPlanning.orders guideMenu
                && OrderPlanning.focusedCommand readingGuide
                == Just (UnitCommand.CommandOption UnitCommand.Move)
                && OrderPlanning.dismissDialog [] readingGuide
                == guideMenu
            )
        , expect "command guide only opens from an ordinary command menu"
            (OrderPlanning.openCommandGuide context OrderPlanning.init
                == OrderPlanning.init
                && OrderPlanning.openCommandGuide context moving
                == moving
                && OrderPlanning.openCommandGuide context crateChoice
                == crateChoice
                && OrderPlanning.openCommandGuide context (OrderPlanning.showSubmissionWarning guideMenu)
                == OrderPlanning.showSubmissionWarning guideMenu
            )
        , expect "command guide blocks command edits, unit cycling and submission"
            (OrderPlanning.applyCommand context UnitCommand.HoldPosition readingGuide
                == readingGuide
                && OrderPlanning.focusCommand context UnitCommand.CancelOption readingGuide
                == readingGuide
                && OrderPlanning.selectNextUnorderedUnit context readingGuide
                == readingGuide
                && OrderPlanning.submissionDrafts readingGuide
                == Nothing
                && OrderPlanning.showSubmissionWarning readingGuide
                == readingGuide
                && TurnLifecycle.startSubmission 1 (TurnLifecycle.Planning readingGuide)
                == TurnLifecycle.Planning readingGuide
            )
        , expect "locking planning discards the guide interaction and keeps only inspection"
            (TurnLifecycle.planning guideLocked
                == Nothing
                && TurnLifecycle.selection guideLocked
                == Just (Inspecting (UnitInspection truckId))
                && not (OrderPlanning.commandGuideOpen (OrderPlanning.setSelection Nothing readingGuide))
            )
        , expect "passenger and crate share the only crate-compatible exit"
            (let
                complete : OrderPlanning.Model
                complete =
                    scarceCrateExits
                        |> OrderPlanning.chooseUnloadSquare scarceCrateContext { x = 2, y = 1 }
                        |> OrderPlanning.chooseUnloadSquare scarceCrateContext { x = 2, y = 1 }
             in
             OrderPlanning.unloadPlanning complete
                == Nothing
                && List.length (List.concatMap PlannedOrder.crateUnloads (OrderPlanning.orders complete))
                == 1
            )
        , expect "passengers without walking supplies cannot be selected"
            (not (OrderPlanning.canSelectUnloadCargo exhaustedContext (OrderPlanning.Passenger infantryId) checklist))
        , expect "invalid full selections stay in the checklist on confirmation"
            (let
                invalidSelection : OrderPlanning.Model
                invalidSelection =
                    narrowChecklist |> OrderPlanning.toggleUnloadPassenger passengerId True
             in
             OrderPlanning.confirmPassengers narrowContext invalidSelection == invalidSelection
            )
        , expect "one passenger exit disables the second passenger and rejects its toggle"
            (not (OrderPlanning.canSelectUnloadCargo narrowContext (OrderPlanning.Passenger passengerId) narrowChecklist)
                && OrderPlanning.toggleAvailableUnloadCargo narrowContext (OrderPlanning.Passenger passengerId) True narrowChecklist
                == narrowChecklist
                && OrderPlanning.canSelectUnloadCargo narrowContext (OrderPlanning.Passenger infantryId) narrowChecklist
            )
        , expect "one crate exit disables the second crate"
            (not (OrderPlanning.canSelectUnloadCargo narrowCrateContext (OrderPlanning.Crate 1) narrowCrateChecklist))
        , expect "unchecking cargo frees the only exit for the other passenger"
            (OrderPlanning.canSelectUnloadCargo narrowContext
                (OrderPlanning.Passenger passengerId)
                (OrderPlanning.toggleAvailableUnloadCargo narrowContext (OrderPlanning.Passenger infantryId) False narrowChecklist)
            )
        , expect "mixed cargo shares the only adjacent square"
            (let
                contextWithFreight : OrderPlanning.Context
                contextWithFreight =
                    { narrowContext | units = Unit.setOnMap { x = 3, y = 0 } freightTruck :: List.filter (\u -> u.id == infantryId) narrowContext.units }

                selectionWithFreight : OrderPlanning.Model
                selectionWithFreight =
                    OrderPlanning.init
                        |> OrderPlanning.selectUnit contextWithFreight truckId
                        |> OrderPlanning.applyCommand contextWithFreight UnitCommand.HoldPosition
                        |> OrderPlanning.toggleAvailableUnloadCargo contextWithFreight (OrderPlanning.Passenger infantryId) True
                        |> OrderPlanning.toggleAvailableUnloadCargo contextWithFreight (OrderPlanning.Crate 0) True
                        |> OrderPlanning.confirmPassengers contextWithFreight
                        |> OrderPlanning.chooseUnloadSquare contextWithFreight { x = 2, y = 0 }
                        |> OrderPlanning.chooseUnloadSquare contextWithFreight { x = 2, y = 0 }
             in
             List.length (List.concatMap PlannedOrder.unloads (OrderPlanning.orders selectionWithFreight))
                == 1
                && List.length (List.concatMap PlannedOrder.crateUnloads (OrderPlanning.orders selectionWithFreight))
                == 1
            )
        , expect "fuel depot destinations offer fuel drum loading"
            (choosingCrates fuelMove && List.length (OrderPlanning.orders fuelMove) == 1)
        , expect "saving an empty truck move on a depot opens loading through mouse and keyboard"
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
        , expect "attack move previews reserve readiness and firing supplies"
            (OrderPlanning.pathPreview lowSupplyAttack |> Maybe.map (\option -> option.path == [ { x = 1, y = 1 }, { x = 2, y = 1 } ]) |> Maybe.withDefault False)
        , expect "attack move command requires readiness supplies before walking"
            (not (UnitCommand.canUse { lowSupplyInfantry | resources = Maybe.map (\resources -> { resources | supplies = { current = 5, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 } }) lowSupplyInfantry.resources } UnitCommand.AttackMove))
        , expect "attack move cannot board an allied truck"
            (List.isEmpty (OrderPlanning.orders attackLoading) && OrderPlanning.destinationFeedback attackLoading == DestinationUnavailable)
        , expect "attack move revocation restores commands"
            (OrderPlanning.commandMenuUnit attackContext (OrderPlanning.revokeSelectedOrder attackContext attackSaved) == Just infantry)
        , expect "indirect fire chooses tiles without movement or occupancy restrictions"
            (OrderPlanning.choosingIndirectFire aiming
                && List.member { x = 3, y = 3 } (OrderPlanning.indirectTargets indirectContext aiming)
                && OrderPlanning.orders bombardment
                == [ aimedOrder { x = 3, y = 3 } ]
                && List.map PlannedOrder.path (OrderPlanning.orders bombardment)
                == [ [ { x = 1, y = 1 } ] ]
                && List.isEmpty (OrderPlanning.orders (OrderPlanning.revokeSelectedOrder indirectContext bombardment))
            )
        , expect "indirect fire on occupied tiles retains the firing gun"
            (OrderPlanning.orders (OrderPlanning.selectUnit indirectContext truckId aiming)
                == [ aimedOrder { x = 3, y = 1 } ]
            )
        , expect "indirect fire accepts the firing gun's own tile"
            (OrderPlanning.orders selfBombardment == [ aimedOrder { x = 1, y = 1 } ])
        , expect "indirect fire rejects out-of-range tiles without leaving targeting"
            (OrderPlanning.selectTile outOfRangeContext { x = 14, y = 1 } edgeAim == edgeAim)
        , expect "indirect fire includes the circular range boundary"
            (List.member { x = 13, y = 1 } (OrderPlanning.indirectTargets outOfRangeContext edgeAim)
                && not (List.member { x = 13, y = 2 } (OrderPlanning.indirectTargets outOfRangeContext edgeAim))
            )
        , expect "indirect fire excludes other kinds, passengers, and insufficient supplies"
            (not (UnitCommand.canUse infantry UnitCommand.IndirectFire)
                && not (UnitCommand.canUse truck UnitCommand.IndirectFire)
                && not (UnitCommand.canUse { fieldGun | location = Location.Aboard truckId } UnitCommand.IndirectFire)
                && not (UnitCommand.canUse { insufficientReadiness | kind = Kind.FieldGun } UnitCommand.IndirectFire)
            )
        , expect "stand ground saves immediately and can be revoked"
            (OrderPlanning.orders standingGround
                == [ { unitId = infantryId, action = PlannedOrder.StandGround { x = 1, y = 1 } } ]
                && List.isEmpty (OrderPlanning.orders (OrderPlanning.revokeSelectedOrder context standingGround))
            )
        , expect "stand ground requires readiness supplies and excludes trucks and passengers"
            (not (UnitCommand.canUse insufficientReadiness UnitCommand.StandGround)
                && not (List.member UnitCommand.StandGround (UnitCommand.available truck))
                && not (List.member UnitCommand.StandGround (UnitCommand.available { infantry | location = Location.Aboard truckId }))
            )
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
        , expect "two arriving passengers preserve the moving truck route"
            (List.length (OrderPlanning.orders rendezvous) == 3 && List.all PlannedOrder.isMoving (OrderPlanning.orders rendezvous) && List.all (\plan -> PlannedOrder.destination plan == { x = 2, y = 2 }) (OrderPlanning.orders rendezvous))
        , expect "a moving truck can pick up a waiting unit and an arriving passenger together"
            (List.length (OrderPlanning.orders pickupRendezvous) == 3 && List.length (List.filter PlannedOrder.isMoving (OrderPlanning.orders pickupRendezvous)) == 2)
        , expect "freight capacity reserves arriving passengers at the moving truck destination"
            (List.length (OrderPlanning.boardingPassengers rendezvousContext truckId (OrderPlanning.orders rendezvous)) == 2)
        , expect "freight capacity reserves waiting pickups as well as arriving passengers"
            (List.length (OrderPlanning.boardingPassengers rendezvousContext truckId (OrderPlanning.orders pickupRendezvous)) == 2)
        , expect "a carried crate leaves only one berth at a moving truck destination"
            (List.length (OrderPlanning.orders freightRendezvous) == 2 && OrderPlanning.orders overfullRendezvous == OrderPlanning.orders freightRendezvous && OrderPlanning.destinationFeedback overfullRendezvous == DestinationUnavailable)
        , expect "revoking the moving truck clears both dependent boarding orders"
            (List.isEmpty (OrderPlanning.orders revokedRendezvous))
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
        , expect "units can move onto planned crate exits"
            (List.length (OrderPlanning.orders tryingCrateExit) == 2)
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
        , expect "crate and passenger exits can share squares in either selection order"
            (List.member
                { x = 3
                , y = 2
                }
                (List.map .destination (OrderPlanning.moveOptions crateExit))
                && List.member
                    { x = 3
                    , y = 2
                    }
                    (List.map .destination (OrderPlanning.moveOptions passengerFirst))
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
    , playerNumbers = [ PlayerNumber.Player1 ]
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

        fuel : Maybe { current : Int, maximum : Int, movementPerTile : Int }
        fuel =
            if vehicle then
                Just { current = 64, maximum = 64, movementPerTile = 1 }

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
        , indirectRange = 0
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
                , roughTerrainSurcharge = 0
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
