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
import Direction
import Error
import GamePage.CurrentTurn as CurrentTurn
import GamePage.OrderPlanning as OrderPlanning
import GamePage.Selection exposing (CommandMenuState(..), DestinationFeedback(..), Inspection(..), Selection(..), UnitInteraction(..))
import InvariantCheck as IC exposing (InvariantCheck)
import Map exposing (Map)
import Movement
import PlannedOrder
import Platform
import TurnLifecycle
import Unit exposing (Unit)
import Unit.Fuel as Fuel
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
                |> (OrderPlanning.selectUnit attackContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand attackContext UnitCommand.AttackMove >> IC.value)
                |> OrderPlanning.extendPath attackContext DirectionEnum.East
                |> OrderPlanning.extendPath attackContext DirectionEnum.East

        attackAiming : OrderPlanning.Model
        attackAiming =
            (OrderPlanning.confirmPath attackContext >> IC.value) attacking

        attackSaved : OrderPlanning.Model
        attackSaved =
            attackAiming
                |> OrderPlanning.previewDirection DirectionEnum.West
                |> (OrderPlanning.saveDirection attackContext DirectionEnum.North >> IC.value)

        attackRevoked : OrderPlanning.Model
        attackRevoked =
            (OrderPlanning.revokeSelectedOrder attackContext >> IC.value) attackSaved

        reopenedCommands : OrderPlanning.Model
        reopenedCommands =
            (OrderPlanning.selectUnit attackContext infantryId >> IC.value) attackRevoked

        lowSupplyInfantry : Unit
        lowSupplyInfantry =
            { infantry | resources = Maybe.map (\resources -> { resources | supplies = { current = 6, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 } }) infantry.resources }

        lowSupplyContext : OrderPlanning.Context
        lowSupplyContext =
            board [ lowSupplyInfantry, enemy ]

        lowSupplyAttack : OrderPlanning.Model
        lowSupplyAttack =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit lowSupplyContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand lowSupplyContext UnitCommand.AttackMove >> IC.value)
                |> OrderPlanning.extendPath lowSupplyContext DirectionEnum.East
                |> OrderPlanning.extendPath lowSupplyContext DirectionEnum.East

        attackLoading : OrderPlanning.Model
        attackLoading =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.AttackMove >> IC.value)
                |> (OrderPlanning.selectTile context { x = 3, y = 1 } >> IC.value)

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
                |> (OrderPlanning.selectUnit indirectContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand indirectContext UnitCommand.IndirectFire >> IC.value)

        bombardment : OrderPlanning.Model
        bombardment =
            aiming
                |> (OrderPlanning.selectTile indirectContext
                        { x = 3
                        , y = 3
                        }
                        >> IC.value
                   )

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
            aiming |> (OrderPlanning.selectUnit indirectContext infantryId >> IC.value)

        rangeMap : Map
        rangeMap =
            Map.fromFeatures
                { width = 20
                , height = 3
                , baseTile = Terrain.Plain
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
                |> (OrderPlanning.selectUnit outOfRangeContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand outOfRangeContext UnitCommand.IndirectFire >> IC.value)

        choosingStandGround : OrderPlanning.Model
        choosingStandGround =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.StandGround >> IC.value)

        standingGround : OrderPlanning.Model
        standingGround =
            choosingStandGround
                |> OrderPlanning.previewDirection DirectionEnum.West
                |> (OrderPlanning.saveDirection context DirectionEnum.West >> IC.value)

        insufficientReadiness : Unit
        insufficientReadiness =
            { infantry | resources = Maybe.map (\resources -> { resources | supplies = { current = 2, maximum = 48, upkeepPerTurn = 1, roughTerrainSurcharge = 1, movementPerTile = 3 } }) infantry.resources }

        ambushing : OrderPlanning.Model
        ambushing =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Ambush >> IC.value)
                |> OrderPlanning.previewDirection DirectionEnum.East
                |> (OrderPlanning.saveDirection context DirectionEnum.East >> IC.value)

        truckAmbush : OrderPlanning.Model
        truckAmbush =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit context truckId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Ambush >> IC.value)
                |> (OrderPlanning.saveDirection context DirectionEnum.East >> IC.value)

        moving : OrderPlanning.Model
        moving =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> OrderPlanning.extendPath context DirectionEnum.South

        saved : OrderPlanning.Model
        saved =
            (OrderPlanning.confirmPath context >> IC.value) moving

        revocationBlocked : OrderPlanning.Context -> UnitId -> OrderPlanning.Model -> Bool
        revocationBlocked planningContext unitId state =
            not (OrderPlanning.canRevokeOrder planningContext unitId state)
                && ((OrderPlanning.revokeSelectedOrder planningContext >> IC.value) state == state)

        previewRevocationBlocked : OrderPlanning.Model -> Bool
        previewRevocationBlocked state =
            state
                |> OrderPlanning.setOrders (OrderPlanning.orders saved)
                |> revocationBlocked context infantryId

        crateChoice : OrderPlanning.Model
        crateChoice =
            OrderPlanning.ChoosingCrates truckId
                { kind = DepotKind.Supply, position = { x = 3, y = 1 }, stock = Nothing }
                { orders = OrderPlanning.orders saved
                , selection = Just (Inspecting (UnitInspection truckId))
                }

        dismissedCrates : OrderPlanning.Model
        dismissedCrates =
            OrderPlanning.dismissDialog crateChoice

        reserved : OrderPlanning.Model
        reserved =
            saved
                |> (OrderPlanning.selectUnit context truckId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context { x = 1, y = 2 } >> IC.value)

        enteringVacated : OrderPlanning.Model
        enteringVacated =
            saved
                |> (OrderPlanning.selectUnit context truckId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context { x = 1, y = 1 } >> IC.value)

        revokeDeparture : OrderPlanning.Model
        revokeDeparture =
            enteringVacated
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.revokeSelectedOrder context >> IC.value)

        truckDeparting : OrderPlanning.Model
        truckDeparting =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit context truckId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context { x = 3, y = 2 } >> IC.value)

        enteringTruckOrigin : OrderPlanning.Model
        enteringTruckOrigin =
            truckDeparting
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context { x = 3, y = 1 } >> IC.value)

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
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context
                        { x = 3
                        , y = 1
                        }
                        >> IC.value
                   )

        tryingFullTruck : OrderPlanning.Model
        tryingFullTruck =
            OrderPlanning.init
                |> OrderPlanning.setOrders [ fullFreight ]
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context
                        { x = 3
                        , y = 1
                        }
                        >> IC.value
                   )

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
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context
                        { x = 2
                        , y = 1
                        }
                        >> IC.value
                   )

        chainContext : OrderPlanning.Context
        chainContext =
            board [ infantry, truck, unit passengerId Kind.Infantry (Location.OnMap { x = 2, y = 1 }) ]

        chain : OrderPlanning.Model
        chain =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit chainContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand chainContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile chainContext { x = 3, y = 2 } >> IC.value)
                |> (OrderPlanning.selectUnit chainContext passengerId >> IC.value)
                |> (OrderPlanning.applyCommand chainContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile chainContext { x = 3, y = 1 } >> IC.value)
                |> (OrderPlanning.selectUnit chainContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand chainContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile chainContext { x = 2, y = 1 } >> IC.value)

        revokedChain : OrderPlanning.Model
        revokedChain =
            chain
                |> (OrderPlanning.selectUnit chainContext truckId >> IC.value)
                |> (OrderPlanning.revokeSelectedOrder chainContext >> IC.value)

        rendezvousContext : OrderPlanning.Context
        rendezvousContext =
            board [ infantry, truck, unit passengerId Kind.FieldGun (Location.OnMap { x = 2, y = 1 }) ]

        rendezvous : OrderPlanning.Model
        rendezvous =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit rendezvousContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand rendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile rendezvousContext { x = 2, y = 2 } >> IC.value)
                |> (OrderPlanning.selectUnit rendezvousContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand rendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile rendezvousContext { x = 2, y = 2 } >> IC.value)
                |> (OrderPlanning.selectUnit rendezvousContext passengerId >> IC.value)
                |> (OrderPlanning.applyCommand rendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile rendezvousContext { x = 2, y = 2 } >> IC.value)

        pickupRendezvous : OrderPlanning.Model
        pickupRendezvous =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit rendezvousContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand rendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile rendezvousContext { x = 2, y = 1 } >> IC.value)
                |> (OrderPlanning.selectUnit rendezvousContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand rendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile rendezvousContext { x = 2, y = 1 } >> IC.value)

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
                |> (OrderPlanning.selectUnit freightRendezvousContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand freightRendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile freightRendezvousContext { x = 2, y = 2 } >> IC.value)
                |> OrderPlanning.skipUnloading freightRendezvousContext
                |> (OrderPlanning.selectUnit freightRendezvousContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand freightRendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile freightRendezvousContext { x = 2, y = 2 } >> IC.value)

        overfullRendezvous : OrderPlanning.Model
        overfullRendezvous =
            freightRendezvous
                |> (OrderPlanning.selectUnit freightRendezvousContext passengerId >> IC.value)
                |> (OrderPlanning.applyCommand freightRendezvousContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile freightRendezvousContext { x = 2, y = 2 } >> IC.value)

        revokedRendezvous : OrderPlanning.Model
        revokedRendezvous =
            rendezvous
                |> (OrderPlanning.selectUnit rendezvousContext truckId >> IC.value)
                |> (OrderPlanning.revokeSelectedOrder rendezvousContext >> IC.value)

        loading : OrderPlanning.Model
        loading =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit context infantryId >> IC.value)
                |> (OrderPlanning.applyCommand context UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile context { x = 3, y = 1 } >> IC.value)

        receiving : OrderPlanning.Model
        receiving =
            (OrderPlanning.selectUnit context truckId >> IC.value) loading

        revoked : OrderPlanning.Model
        revoked =
            loading
                |> (OrderPlanning.revokeSelectedOrder context >> IC.value)
                |> (OrderPlanning.selectUnit context truckId >> IC.value)
                |> (OrderPlanning.revokeSelectedOrder context >> IC.value)

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
                |> (OrderPlanning.selectUnit cargoContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand cargoContext UnitCommand.HoldPosition >> IC.value)

        exits : OrderPlanning.Model
        exits =
            checklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> (OrderPlanning.confirmPassengers cargoContext >> IC.value)

        firstExit : OrderPlanning.Model
        firstExit =
            (OrderPlanning.chooseUnloadSquare cargoContext { x = 3, y = 2 } >> IC.value) exits

        rejectedExit : OrderPlanning.Model
        rejectedExit =
            (OrderPlanning.chooseUnloadSquare cargoContext { x = 3, y = 2 } >> IC.value) firstExit

        completed : OrderPlanning.Model
        completed =
            (OrderPlanning.chooseUnloadSquare cargoContext { x = 4, y = 1 } >> IC.value) rejectedExit

        truckMove : OrderPlanning.Model
        truckMove =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit cargoContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand cargoContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile cargoContext { x = 4, y = 1 } >> IC.value)
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> (OrderPlanning.confirmPassengers cargoContext >> IC.value)
                |> (OrderPlanning.chooseUnloadSquare cargoContext { x = 5, y = 1 } >> IC.value)

        twoInfantryContext : OrderPlanning.Context
        twoInfantryContext =
            board
                [ truck
                , unit infantryId Kind.Infantry (Location.Aboard truckId)
                , unit passengerId Kind.Infantry (Location.Aboard truckId)
                ]

        twoInfantryReady : OrderPlanning.Model
        twoInfantryReady =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit twoInfantryContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand twoInfantryContext UnitCommand.HoldPosition >> IC.value)
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> (OrderPlanning.confirmPassengers twoInfantryContext >> IC.value)
                |> (OrderPlanning.chooseUnloadSquare twoInfantryContext { x = 3, y = 2 } >> IC.value)
                |> (OrderPlanning.chooseUnloadSquare twoInfantryContext { x = 4, y = 1 } >> IC.value)

        secondInfantryCommand : OrderPlanning.Model
        secondInfantryCommand =
            twoInfantryReady
                |> (OrderPlanning.applyCommand twoInfantryContext UnitCommand.HoldPosition >> IC.value)

        bothInfantryCommanded : OrderPlanning.Model
        bothInfantryCommanded =
            secondInfantryCommand
                |> (OrderPlanning.applyCommand twoInfantryContext UnitCommand.StandGround >> IC.value)
                |> (OrderPlanning.saveDirection twoInfantryContext DirectionEnum.East >> IC.value)

        dismountAttack : OrderPlanning.Model
        dismountAttack =
            completed
                |> (OrderPlanning.applyCommand cargoContext UnitCommand.AttackMove >> IC.value)
                |> OrderPlanning.extendPath cargoContext DirectionEnum.South
                |> (OrderPlanning.confirmPath cargoContext >> IC.value)
                |> (OrderPlanning.saveDirection cargoContext DirectionEnum.East >> IC.value)

        dismountHold : OrderPlanning.Model
        dismountHold =
            completed |> (OrderPlanning.applyCommand cargoContext UnitCommand.HoldPosition >> IC.value)

        revokedDismount : OrderPlanning.Model
        revokedDismount =
            dismountHold
                |> (OrderPlanning.selectUnit cargoContext truckId >> IC.value)
                |> (OrderPlanning.revokeSelectedOrder cargoContext >> IC.value)

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
                |> (OrderPlanning.selectUnit mixedContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand mixedContext UnitCommand.HoldPosition >> IC.value)

        mixedExits : OrderPlanning.Model
        mixedExits =
            mixedChecklist
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> (OrderPlanning.confirmPassengers mixedContext >> IC.value)

        crateExit : OrderPlanning.Model
        crateExit =
            (OrderPlanning.chooseUnloadSquare mixedContext
                { x = 3
                , y = 2
                }
                >> IC.value
            )
                mixedExits

        mixedComplete : OrderPlanning.Model
        mixedComplete =
            (OrderPlanning.chooseUnloadSquare mixedContext
                { x = 4
                , y = 1
                }
                >> IC.value
            )
                crateExit

        passengerFirst : OrderPlanning.Model
        passengerFirst =
            mixedChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> (OrderPlanning.confirmPassengers mixedContext >> IC.value)
                |> (OrderPlanning.chooseUnloadSquare mixedContext
                        { x = 3
                        , y = 2
                        }
                        >> IC.value
                   )

        crateOnlyContext : OrderPlanning.Context
        crateOnlyContext =
            board [ freightTruck ]

        crateOnlyMove : OrderPlanning.Model
        crateOnlyMove =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit crateOnlyContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand crateOnlyContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile crateOnlyContext
                        { x = 4
                        , y = 1
                        }
                        >> IC.value
                   )

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
                |> (OrderPlanning.selectUnit twoCrateContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand twoCrateContext UnitCommand.HoldPosition >> IC.value)
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 1) True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) False
                |> (OrderPlanning.confirmPassengers twoCrateContext >> IC.value)
                |> (OrderPlanning.chooseUnloadSquare twoCrateContext
                        { x = 3
                        , y = 2
                        }
                        >> IC.value
                   )

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
                |> (OrderPlanning.selectUnit fuelContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand fuelContext UnitCommand.Move >> IC.value)
                |> OrderPlanning.extendPath fuelContext DirectionEnum.East
                |> (OrderPlanning.selectTile fuelContext { x = 4, y = 1 } >> IC.value)

        depotMovePreview : OrderPlanning.Model
        depotMovePreview =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit depotContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand depotContext UnitCommand.Move >> IC.value)
                |> OrderPlanning.extendPath depotContext DirectionEnum.East

        depotMove : OrderPlanning.Model
        depotMove =
            (OrderPlanning.selectTile depotContext { x = 4, y = 1 } >> IC.value) depotMovePreview

        depotKeyboardMove : OrderPlanning.Model
        depotKeyboardMove =
            (OrderPlanning.confirmPath depotContext >> IC.value) depotMovePreview

        depotBoarding : OrderPlanning.Model
        depotBoarding =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit depotContext infantryId >> IC.value)
                |> (OrderPlanning.applyCommand depotContext UnitCommand.Move >> IC.value)
                |> (OrderPlanning.selectTile depotContext { x = 3, y = 1 } >> IC.value)

        depotHold : OrderPlanning.Model
        depotHold =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit depotContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand depotContext UnitCommand.HoldPosition >> IC.value)

        dismissedDepot : OrderPlanning.Model
        dismissedDepot =
            OrderPlanning.dismissDialog depotMove

        depotCargoContext : OrderPlanning.Context
        depotCargoContext =
            { cargoContext | depots = depotContext.depots }

        depotChecklist : OrderPlanning.Model
        depotChecklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit depotCargoContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand depotCargoContext UnitCommand.HoldPosition >> IC.value)

        depotExits : OrderPlanning.Model
        depotExits =
            depotChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> (OrderPlanning.confirmPassengers depotCargoContext >> IC.value)

        depotFirstExit : OrderPlanning.Model
        depotFirstExit =
            (OrderPlanning.chooseUnloadSquare depotCargoContext { x = 3, y = 2 } >> IC.value) depotExits

        depotCompleted : OrderPlanning.Model
        depotCompleted =
            (OrderPlanning.chooseUnloadSquare depotCargoContext { x = 4, y = 1 } >> IC.value) depotFirstExit

        depotMixedContext : OrderPlanning.Context
        depotMixedContext =
            { mixedContext | depots = depotContext.depots }

        depotCrateUnloaded : OrderPlanning.Model
        depotCrateUnloaded =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit depotMixedContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand depotMixedContext UnitCommand.HoldPosition >> IC.value)
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> (OrderPlanning.confirmPassengers depotMixedContext >> IC.value)
                |> (OrderPlanning.chooseUnloadSquare depotMixedContext { x = 3, y = 2 } >> IC.value)

        choosingCrates : OrderPlanning.Model -> Bool
        choosingCrates state =
            case state of
                OrderPlanning.ChoosingCrates id depot _ ->
                    (id == truckId)
                        && List.member depot (depotContext.depots ++ fuelContext.depots)

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
                | map = Map.fromFeatures { width = 4, height = 1, baseTile = cargoContext.map.baseTile, features = [], theme = cargoContext.map.theme }
                , units =
                    List.map putTruckAtCorner
                        cargoContext.units
            }

        narrowChecklist : OrderPlanning.Model
        narrowChecklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit narrowContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand narrowContext UnitCommand.HoldPosition >> IC.value)
                |> OrderPlanning.toggleAvailableUnloadCargo narrowContext (OrderPlanning.Passenger infantryId) True

        narrowCrateContext : OrderPlanning.Context
        narrowCrateContext =
            { twoCrateContext | map = narrowContext.map, units = List.map (Unit.setOnMap { x = 3, y = 0 }) twoCrateContext.units }

        narrowCrateChecklist : OrderPlanning.Model
        narrowCrateChecklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit narrowCrateContext truckId >> IC.value)
                |> (OrderPlanning.applyCommand narrowCrateContext UnitCommand.HoldPosition >> IC.value)
                |> OrderPlanning.toggleAvailableUnloadCargo narrowCrateContext (OrderPlanning.Crate 0) True

        scarceCrateContext : OrderPlanning.Context
        scarceCrateContext =
            { mixedContext
                | map = Map.fromFeatures { width = 4, height = 2, baseTile = mixedContext.map.baseTile, theme = mixedContext.map.theme, features = [] }
                , supplyCrates = [ { position = { x = 3, y = 0 }, stock = { kind = DepotKind.Supply, current = 64, maximum = 64 } } ]
            }

        scarceCrateExits : OrderPlanning.Model
        scarceCrateExits =
            mixedChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True
                |> (OrderPlanning.confirmPassengers scarceCrateContext >> IC.value)

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

        missingContext : OrderPlanning.Context
        missingContext =
            board [ truck ]

        missingCommand : OrderPlanning.Model
        missingCommand =
            OrderPlanning.init
                |> OrderPlanning.setOrders [ { unitId = truckId, action = PlannedOrder.Hold { x = 3, y = 1 } } ]
                |> OrderPlanning.setSelection
                    (Just (UnitSelection { id = infantryId, interaction = CommandMenu (ChoosingCommand Nothing) }))

        missingCommandCheck : InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
        missingCommandCheck =
            OrderPlanning.applyCommand missingContext UnitCommand.Move missingCommand

        missingNextPassenger : InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
        missingNextPassenger =
            OrderPlanning.chooseUnloadSquare
                (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ])
                { x = 3, y = 2 }
                exits

        savedAttackWithMissingUnit : InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
        savedAttackWithMissingUnit =
            OrderPlanning.saveDirection missingContext DirectionEnum.North attackAiming

        initialTurn : CurrentTurn.Model
        initialTurn =
            CurrentTurn.init { number = 1, submitted = False, opponentSubmitted = False, outcome = Nothing, resolution = Nothing }

        brokenTurn : CurrentTurn.Model
        brokenTurn =
            { initialTurn | phase = TurnLifecycle.Planning missingCommand }

        checkedTurn : InvariantCheck Error.Error CurrentTurn.Model
        checkedTurn =
            CurrentTurn.mapPlanning (OrderPlanning.applyCommand missingContext UnitCommand.Move) brokenTurn
                |> IC.mapError Error.OrderPlanningInvariantViolated

        silentNoOp : (OrderPlanning.Model -> InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model) -> Bool
        silentNoOp transition =
            transition OrderPlanning.init == IC.happy OrderPlanning.init
    in
    List.concat
        [ expect "a failed command lookup reports the missing unit without changing selection or drafts"
            (missingCommandCheck == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) missingCommand)
        , expect "a checked transition does not inspect unrelated broken state"
            (CurrentTurn.mapPlanning (OrderPlanning.previewDirection DirectionEnum.North >> IC.happy) brokenTurn
                == IC.happy brokenTurn
            )
        , expect "planning diagnostics propagate through the turn to the shared error type"
            (IC.error checkedTurn
                == Just (Error.OrderPlanningInvariantViolated (OrderPlanning.PlanningUnitNotFound infantryId))
                && (IC.value checkedTurn).phase
                == brokenTurn.phase
            )
        , expect "failed direction lookup keeps its existing state"
            (OrderPlanning.saveDirection missingContext DirectionEnum.North choosingStandGround
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) choosingStandGround
            )
        , expect "missing required board positions are reported at the direction save"
            (OrderPlanning.saveDirection cargoContext DirectionEnum.North choosingStandGround
                == IC.violated (OrderPlanning.CommandUnitNotOnBoard infantryId) choosingStandGround
            )
        , expect "failed movement lookup retains the original tile-inspection fallback"
            (OrderPlanning.confirmPath missingContext moving
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId)
                    (OrderPlanning.setSelection (Just (Inspecting (TileInspection { x = 1, y = 2 }))) moving)
            )
        , expect "a failure after saving an attack order does not roll the order back"
            (IC.error savedAttackWithMissingUnit
                == Just (OrderPlanning.PlanningUnitNotFound infantryId)
                && List.map .unitId (OrderPlanning.orders (IC.value savedAttackWithMissingUnit))
                == [ infantryId ]
                && OrderPlanning.selection (IC.value savedAttackWithMissingUnit)
                == OrderPlanning.selection attackAiming
            )
        , expect "missing unload passengers report the failed option lookup without canceling the checklist"
            (let
                selected : OrderPlanning.Model
                selected =
                    OrderPlanning.toggleUnloadPassenger infantryId True checklist
             in
             OrderPlanning.confirmPassengers missingContext selected
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) selected
            )
        , expect "confirmation retains diagnostics encountered while checking later passenger exits"
            (let
                selected : OrderPlanning.Model
                selected =
                    checklist
                        |> OrderPlanning.toggleUnloadPassenger infantryId True
                        |> OrderPlanning.toggleUnloadPassenger passengerId True

                checked : InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
                checked =
                    OrderPlanning.confirmPassengers
                        (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ])
                        selected
             in
             checked == IC.violated (OrderPlanning.PlanningUnitNotFound passengerId) selected
            )
        , expect "a missing next passenger retains the exit already saved and the next empty picker"
            (IC.error missingNextPassenger
                == Just (OrderPlanning.PlanningUnitNotFound passengerId)
                && List.concatMap PlannedOrder.unloads (OrderPlanning.orders (IC.value missingNextPassenger))
                == [ { unitId = infantryId, destination = { x = 3, y = 2 } } ]
                && Maybe.map .cargo (OrderPlanning.unloadPlanning (IC.value missingNextPassenger))
                == Just (OrderPlanning.Passenger passengerId)
                && List.isEmpty (OrderPlanning.moveOptions (IC.value missingNextPassenger))
            )
        , expect "checked composition continues with the fallback value while retaining its diagnostic"
            (missingCommandCheck
                |> IC.andThen (OrderPlanning.selectUnit context truckId)
                |> IC.value
                |> OrderPlanning.selection
                |> (==) (Just (Inspecting (UnitInspection truckId)))
            )
        , expect "checked composition retains the first diagnostic"
            (missingCommandCheck
                |> IC.andThen (OrderPlanning.selectUnit context truckId)
                |> IC.error
                |> (==) (Just (OrderPlanning.PlanningUnitNotFound infantryId))
            )
        , expect "no selection, stale clicks, absent previews and out-of-phase actions remain silent"
            (List.all silentNoOp
                [ OrderPlanning.applyCommand context UnitCommand.Move
                , OrderPlanning.confirmPath context
                , OrderPlanning.saveDirection context DirectionEnum.North
                , OrderPlanning.confirmPassengers context
                , OrderPlanning.revokeSelectedOrder context
                , OrderPlanning.selectUnit context passengerId
                ]
            )
        , expect "unreachable destinations and reverse attack facing remain ordinary validation"
            (IC.error (OrderPlanning.selectTile context { x = -1, y = -1 } moving)
                == Nothing
                && OrderPlanning.saveDirection attackContext DirectionEnum.West attackAiming
                == IC.happy attackAiming
            )
        , expect "unavailable commands remain silent"
            (OrderPlanning.applyCommand context
                UnitCommand.Ambush
                (IC.value (OrderPlanning.selectUnit context truckId OrderPlanning.init))
                |> IC.error
                |> (==) Nothing
            )
        , expect "stale inspections remain silent"
            (let
                stale : OrderPlanning.Model
                stale =
                    OrderPlanning.setSelection (Just (Inspecting (UnitInspection passengerId))) OrderPlanning.init
             in
             OrderPlanning.restoreCommands context stale == IC.happy stale
            )
        , expect "command guide preserves orders and returns to the focused command menu"
            (OrderPlanning.commandGuideOpen readingGuide
                && OrderPlanning.orders readingGuide
                == OrderPlanning.orders guideMenu
                && OrderPlanning.focusedCommand readingGuide
                == Just (UnitCommand.CommandOption UnitCommand.Move)
                && OrderPlanning.dismissDialog readingGuide
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
            ((OrderPlanning.applyCommand context UnitCommand.HoldPosition >> IC.value) readingGuide
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
                        |> (OrderPlanning.chooseUnloadSquare scarceCrateContext { x = 2, y = 1 } >> IC.value)
                        |> (OrderPlanning.chooseUnloadSquare scarceCrateContext { x = 2, y = 1 } >> IC.value)
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
             (OrderPlanning.confirmPassengers narrowContext >> IC.value) invalidSelection == invalidSelection
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
                        |> (OrderPlanning.selectUnit contextWithFreight truckId >> IC.value)
                        |> (OrderPlanning.applyCommand contextWithFreight UnitCommand.HoldPosition >> IC.value)
                        |> OrderPlanning.toggleAvailableUnloadCargo contextWithFreight (OrderPlanning.Passenger infantryId) True
                        |> OrderPlanning.toggleAvailableUnloadCargo contextWithFreight (OrderPlanning.Crate 0) True
                        |> (OrderPlanning.confirmPassengers contextWithFreight >> IC.value)
                        |> (OrderPlanning.chooseUnloadSquare contextWithFreight { x = 2, y = 0 } >> IC.value)
                        |> (OrderPlanning.chooseUnloadSquare contextWithFreight { x = 2, y = 0 } >> IC.value)
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
                && not (choosingCrates ((OrderPlanning.selectUnit depotContext truckId >> IC.value) dismissedDepot))
                && OrderPlanning.orders dismissedDepot
                == OrderPlanning.orders depotMove
            )
        , expect "loaded trucks offer unloading before depot loading"
            (OrderPlanning.unloadChoice depotChecklist /= Nothing)
        , expect "confirming no unloads and skipping unloading offer depot loading"
            (choosingCrates ((OrderPlanning.confirmPassengers depotCargoContext >> IC.value) depotChecklist)
                && choosingCrates (OrderPlanning.skipUnloading depotCargoContext depotChecklist)
            )
        , expect "canceling stationary unloading discards the hold without offering depot loading"
            (OrderPlanning.orders (OrderPlanning.dismissDialog depotChecklist)
                == []
                && not (choosingCrates (OrderPlanning.dismissDialog depotChecklist))
                && OrderPlanning.unloadChoice (OrderPlanning.dismissDialog depotChecklist)
                == Nothing
            )
        , expect "canceling a truck move's unload checklist preserves unrelated orders"
            (let
                unrelatedOrder : PlannedOrder.PlannedOrder
                unrelatedOrder =
                    { unitId = passengerId
                    , action = PlannedOrder.Hold { x = 0, y = 0 }
                    }

                moveContext : OrderPlanning.Context
                moveContext =
                    { mixedContext | units = unit passengerId Kind.Infantry (Location.OnMap { x = 0, y = 0 }) :: mixedContext.units }

                movingChecklist : OrderPlanning.Model
                movingChecklist =
                    OrderPlanning.init
                        |> OrderPlanning.setOrders [ unrelatedOrder ]
                        |> (OrderPlanning.selectUnit moveContext truckId >> IC.value)
                        |> (OrderPlanning.applyCommand moveContext UnitCommand.Move >> IC.value)
                        |> (OrderPlanning.selectTile moveContext { x = 4, y = 1 } >> IC.value)
                        |> OrderPlanning.toggleUnloadCargo (OrderPlanning.Crate 0) True

                canceled : OrderPlanning.Model
                canceled =
                    OrderPlanning.dismissDialog movingChecklist
             in
             OrderPlanning.unloadChoice movingChecklist
                /= Nothing
                && OrderPlanning.orders canceled
                == [ unrelatedOrder ]
                && OrderPlanning.selection canceled
                == Just (Inspecting (UnitInspection truckId))
                && OrderPlanning.submissionDrafts canceled
                /= Nothing
            )
        , expect "leaving unload square selection discards the truck plan and partial exits"
            (List.isEmpty (OrderPlanning.orders (OrderPlanning.setSelection Nothing depotFirstExit))
                && OrderPlanning.unloadPlanning (OrderPlanning.setSelection Nothing depotFirstExit)
                == Nothing
                && List.isEmpty (OrderPlanning.orders (OrderPlanning.setSelection Nothing exits))
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
        , expect "attack route awaits direction and blocks submission before saving"
            (OrderPlanning.choosingDirection attackAiming
                && List.isEmpty (OrderPlanning.orders attackAiming)
                && OrderPlanning.submissionDrafts attackAiming
                == Nothing
            )
        , expect "attack move cannot preview or save a facing back along its final segment"
            (OrderPlanning.previewDirection DirectionEnum.West attackAiming
                == attackAiming
                && (OrderPlanning.saveDirection attackContext DirectionEnum.West >> IC.value) attackAiming
                == attackAiming
            )
        , expect "attack facing restriction follows the last segment of a turning route"
            (Direction.reversesPath [ { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 2, y = 2 } ] DirectionEnum.North
                && not (Direction.reversesPath [ { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 2, y = 2 } ] DirectionEnum.West)
            )
        , expect "attack move previews reserve readiness and firing supplies"
            (OrderPlanning.pathPreview lowSupplyAttack |> Maybe.map (\option -> option.path == [ { x = 1, y = 1 }, { x = 2, y = 1 } ]) |> Maybe.withDefault False)
        , expect "attack move command requires readiness supplies before walking"
            (not (UnitCommand.canUse { lowSupplyInfantry | resources = Maybe.map (\resources -> { resources | supplies = { current = 5, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 } }) lowSupplyInfantry.resources } UnitCommand.AttackMove))
        , expect "attack move cannot board an allied truck"
            (List.isEmpty (OrderPlanning.orders attackLoading) && OrderPlanning.destinationFeedback attackLoading == DestinationUnavailable)
        , expect "saved orders can be revoked from inspection or a command menu"
            (OrderPlanning.canRevokeOrder context infantryId saved
                && OrderPlanning.canRevokeOrder context infantryId ((OrderPlanning.restoreCommands context >> IC.value) saved)
                && not (OrderPlanning.canRevokeOrder context truckId saved)
                && revocationBlocked context infantryId attackRevoked
            )
        , expect "unfinished action selection blocks both revoke controls and revoke events"
            (List.all previewRevocationBlocked
                [ moving
                , attacking
                , attackAiming
                , aiming
                , choosingStandGround
                , (OrderPlanning.applyCommand context UnitCommand.Ambush >> IC.value) reopenedCommands
                ]
            )
        , expect "dialogs and unfinished unloading cannot be revoked through a stale event"
            (revocationBlocked context infantryId (OrderPlanning.showSubmissionWarning saved)
                && revocationBlocked context truckId crateChoice
                && revocationBlocked cargoContext truckId checklist
                && revocationBlocked cargoContext infantryId exits
            )
        , expect "enemy units and aboard passengers cannot revoke saved orders"
            (revocationBlocked { context | playerNumbers = [ PlayerNumber.Player2 ] } infantryId saved
                && revocationBlocked cargoContext infantryId saved
            )
        , expect "revoking retains inspection without commands or movement previews"
            (List.isEmpty (OrderPlanning.orders attackRevoked)
                && OrderPlanning.selection attackRevoked
                == Just (Inspecting (UnitInspection infantryId))
                && OrderPlanning.commandMenuUnit attackContext attackRevoked
                == Nothing
                && OrderPlanning.pathPreview attackRevoked
                == Nothing
            )
        , expect "back to commands drops movement previews and reopens the menu"
            (OrderPlanning.commandMenuUnit attackContext ((OrderPlanning.restoreCommands attackContext >> IC.value) attacking)
                == Just infantry
                && OrderPlanning.pathPreview ((OrderPlanning.restoreCommands attackContext >> IC.value) attacking)
                == Nothing
            )
        , expect "clicking the revoked unit reopens commands and clicking again deselects"
            (OrderPlanning.commandMenuUnit attackContext reopenedCommands
                == Just infantry
                && OrderPlanning.selection ((OrderPlanning.selectUnit attackContext infantryId >> IC.value) reopenedCommands)
                == Nothing
            )
        , expect "clicking a selected unit with a saved order still deselects without revoking"
            (OrderPlanning.selection ((OrderPlanning.selectUnit attackContext infantryId >> IC.value) attackSaved)
                == Nothing
                && OrderPlanning.orders ((OrderPlanning.selectUnit attackContext infantryId >> IC.value) attackSaved)
                == OrderPlanning.orders attackSaved
            )
        , expect "indirect fire chooses tiles without movement or occupancy restrictions"
            (OrderPlanning.choosingIndirectFire aiming
                && List.member { x = 3, y = 3 } (OrderPlanning.indirectTargets indirectContext aiming)
                && OrderPlanning.orders bombardment
                == [ aimedOrder { x = 3, y = 3 } ]
                && List.map PlannedOrder.path (OrderPlanning.orders bombardment)
                == [ [ { x = 1, y = 1 } ] ]
                && List.isEmpty (OrderPlanning.orders ((OrderPlanning.revokeSelectedOrder indirectContext >> IC.value) bombardment))
            )
        , expect "target previews are legal, transient, and do not save orders"
            (OrderPlanning.indirectTargetPreview aiming
                == Nothing
                && OrderPlanning.indirectTargetPreview (OrderPlanning.previewTile indirectContext { x = 3, y = 3 } aiming)
                == Just { x = 3, y = 3 }
                && List.isEmpty (OrderPlanning.orders (OrderPlanning.previewTile indirectContext { x = 3, y = 3 } aiming))
                && OrderPlanning.indirectTargetPreview (OrderPlanning.clearTargetPreview (OrderPlanning.previewTile indirectContext { x = 3, y = 3 } aiming))
                == Nothing
                && OrderPlanning.indirectTargetPreview (OrderPlanning.previewTile outOfRangeContext { x = 14, y = 1 } (OrderPlanning.previewTile outOfRangeContext { x = 13, y = 1 } edgeAim))
                == Nothing
                && OrderPlanning.indirectTargetPreview bombardment
                == Nothing
            )
        , expect "indirect fire on occupied tiles retains the firing gun"
            (OrderPlanning.orders ((OrderPlanning.selectUnit indirectContext truckId >> IC.value) aiming)
                == [ aimedOrder { x = 3, y = 1 } ]
            )
        , expect "indirect fire accepts the firing gun's own tile"
            (OrderPlanning.orders selfBombardment == [ aimedOrder { x = 1, y = 1 } ])
        , expect "indirect fire rejects out-of-range tiles without leaving targeting"
            ((OrderPlanning.selectTile outOfRangeContext { x = 14, y = 1 } >> IC.value) edgeAim == edgeAim)
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
        , expect "stand ground chooses direction before saving and can be revoked"
            (OrderPlanning.choosingDirection choosingStandGround
                && List.isEmpty (OrderPlanning.orders choosingStandGround)
                && OrderPlanning.orders standingGround
                == [ { unitId = infantryId, action = PlannedOrder.StandGround { position = { x = 1, y = 1 }, direction = DirectionEnum.West } } ]
                && List.isEmpty (OrderPlanning.orders ((OrderPlanning.revokeSelectedOrder context >> IC.value) standingGround))
            )
        , expect "stand ground requires readiness supplies and excludes trucks and passengers"
            (not (UnitCommand.canUse insufficientReadiness UnitCommand.StandGround)
                && not (List.member UnitCommand.StandGround (UnitCommand.available truck))
                && not (List.member UnitCommand.StandGround (UnitCommand.available { infantry | location = Location.Aboard truckId }))
            )
        , expect "ambush direction preview saves a stationary ambush instead of rotation"
            (OrderPlanning.orders ambushing == [ { unitId = infantryId, action = PlannedOrder.Ambush { position = { x = 1, y = 1 }, direction = DirectionEnum.East } } ])
        , expect "ambush can be revoked and trucks cannot ambush"
            (List.isEmpty (OrderPlanning.orders ((OrderPlanning.revokeSelectedOrder context >> IC.value) ambushing)) && List.isEmpty (OrderPlanning.orders truckAmbush))
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
        , expect "revoking loading and receiver holds keeps the truck inspected without commands"
            (List.isEmpty (OrderPlanning.orders revoked)
                && OrderPlanning.commandMenuUnit context revoked
                == Nothing
                && OrderPlanning.selection revoked
                == Just (Inspecting (UnitInspection truckId))
            )
        , expect "holding a loaded truck opens its stationary unload checklist"
            (OrderPlanning.unloadChoice checklist /= Nothing)
        , expect "each unload exit reserves its square for the next passenger"
            (OrderPlanning.orders firstExit == OrderPlanning.orders rejectedExit && OrderPlanning.destinationFeedback rejectedExit == DestinationUnavailable)
        , expect "stationary unloading completes with both passengers and releases the workflow"
            (List.concatMap PlannedOrder.unloads (OrderPlanning.orders completed) == [ { unitId = infantryId, destination = { x = 3, y = 2 } }, { unitId = passengerId, destination = { x = 4, y = 1 } } ] && OrderPlanning.unloadPlanning completed == Nothing)
        , expect "moving truck exits use the planned truck destination"
            (List.concatMap PlannedOrder.unloads (OrderPlanning.orders truckMove) == [ { unitId = infantryId, destination = { x = 5, y = 1 } } ])
        , expect "dismounted infantry needs a command while other cargo receives holds for submission"
            (List.map .id (OrderPlanning.missingOrders cargoContext (OrderPlanning.orders completed)) == [ infantryId ] && List.length ordersForSubmission == 3)
        , expect "saving the first infantry command opens commands for the second dismount"
            (OrderPlanning.commandMenuUnit twoInfantryContext secondInfantryCommand |> Maybe.map .id |> (==) (Just passengerId))
        , expect "both dismounted infantry can save independent commands"
            (List.isEmpty (OrderPlanning.missingOrders twoInfantryContext (OrderPlanning.orders bothInfantryCommanded))
                && OrderPlanning.commandMenuUnit twoInfantryContext bothInfantryCommanded
                == Nothing
                && List.length (OrderPlanning.orders bothInfantryCommanded)
                == 3
            )
        , expect "completing exits opens the dismounted infantry command menu"
            (OrderPlanning.commandMenuUnit cargoContext completed |> Maybe.map .id |> (==) (Just infantryId))
        , expect "dismounted attack tracing begins at the exit and saves normally"
            (OrderPlanning.orders dismountAttack
                |> List.any (\order -> order.unitId == infantryId && PlannedOrder.isAttackMove order && List.head (PlannedOrder.path order) == Just { x = 3, y = 2 })
            )
        , expect "dismounted hold uses the exit and clears the missing command"
            (List.isEmpty (OrderPlanning.missingOrders cargoContext (OrderPlanning.orders dismountHold))
                && List.any (\order -> order.unitId == infantryId && PlannedOrder.path order == [ { x = 3, y = 2 } ]) (OrderPlanning.orders dismountHold)
            )
        , expect "revoking transport also revokes its dismounted infantry command"
            (not (List.any (\order -> order.unitId == infantryId) (OrderPlanning.orders revokedDismount)))
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
                            ((OrderPlanning.confirmPassengers blockedCrateContext >> IC.value)
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
            (List.map .action (OrderPlanning.orders ((OrderPlanning.confirmPassengers mixedContext >> IC.value) mixedChecklist))
                == [ PlannedOrder.Hold
                        { x = 3
                        , y = 1
                        }
                   ]
            )
        , expect "lifecycle gating prevents editing submitted drafts"
            (TurnLifecycle.mapPlanning (OrderPlanning.selectTile context { x = 2, y = 2 } >> IC.value) submitted == submitted)
        ]


board : List Unit -> OrderPlanning.Context
board units =
    { map = Map.fromFeatures { width = 7, height = 7, baseTile = Terrain.Plain, theme = Theme.GreenForest, features = [] }
    , units = units
    , movementRules = List.map movementRule [ Kind.Infantry, Kind.Truck, Kind.FieldGun ]
    , depots = []
    , supplyCrates = []
    , playerNumbers = [ PlayerNumber.Player1 ]
    }


movementRule : UnitKind -> Movement.Rule
movementRule kind =
    { kind = kind, budget = 12, terrainCosts = [ { terrain = Terrain.Plain, cost = 2 } ] }


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

        fuel : Maybe Fuel.Fuel
        fuel =
            if vehicle then
                Just { current = 64, maximum = 64, movementPerTile = 1, movementPerCargoSlot = 0 }

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
