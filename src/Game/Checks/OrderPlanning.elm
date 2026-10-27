port module Game.Checks.OrderPlanning exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.BuildingKind as BuildingKind exposing (BuildingKind)
import Api.Enum.Direction as DirectionEnum
import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.MapTheme as Theme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.ResourceKind as ResourceKind exposing (ResourceKind)
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.Terrain as TerrainApi
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Error
import Game.CombatRules as CombatRules exposing (CombatRules)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.CurrentTurn as CurrentTurn
import Game.Depot as Depot exposing (Depot)
import Game.DestinationFeedback exposing (DestinationFeedback(..))
import Game.Direction as Direction
import Game.DirectionPlanning as DirectionPlanning exposing (DirectionPlanning)
import Game.IndirectFirePlanning as IndirectFirePlanning exposing (IndirectFirePlanning)
import Game.Inspection as Inspection exposing (Inspection(..))
import Game.Map as Map exposing (Map)
import Game.Movement as Movement
import Game.OrderDependencies as OrderDependencies
import Game.OrderPlanning as OrderPlanning
import Game.PlannedOrder as PlannedOrder
import Game.PlannedTransport as PlannedTransport
import Game.Selection exposing (CommandMenuState(..), Selection(..), UnitInteraction(..))
import Game.Supply as Supply exposing (CargoStock)
import Game.Terrain as Terrain
import Game.TurnLifecycle as TurnLifecycle
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Fuel as Fuel
import Game.Unit.Location as Location exposing (Location)
import Game.Unit.Supplies
import Game.UnitCommand as UnitCommand
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitResources as UnitResources exposing (UnitResources)
import Game.UnloadCargo as UnloadCargo
import InvariantCheck as IC exposing (InvariantCheck)
import Platform


port results : List String -> Cmd msg


setResourcesSupplyCargo : List CargoStock -> UnitResources -> UnitResources
setResourcesSupplyCargo supplyCargo model =
    { model | supplyCargo = supplyCargo }


setDepotKind : BuildingKind -> Depot -> Depot
setDepotKind kind model =
    { model | kind = kind }


setDepotHp : Depot.Hp -> Depot -> Depot
setDepotHp hp model =
    { model | hp = hp }


setBoardUnits : List Unit -> BoardFixture -> BoardFixture
setBoardUnits units model =
    { model | units = units }


setBoardSupplyCrates : List Supply.GroundCrate -> BoardFixture -> BoardFixture
setBoardSupplyCrates supplyCrates model =
    { model | supplyCrates = supplyCrates }


setBoardDepots : List Depot -> BoardFixture -> BoardFixture
setBoardDepots depots model =
    { model | depots = depots }


setBoardMap : Map -> BoardFixture -> BoardFixture
setBoardMap map model =
    { model | map = map }


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
                ++ cargoLoadingChecks infantryId truckId passengerId
                ++ groundPickupChecks infantryId truckId
                ++ mutualPickupChecks infantryId truckId passengerId
                ++ transportInvariantChecks infantryId truckId passengerId
                ++ dependencyInvariantChecks infantryId truckId passengerId
                ++ directionPlanningChecks infantryId truckId
                ++ indirectPlanningChecks infantryId truckId
                ++ sabotagePlanningChecks infantryId truckId
                ++ diggingTerrainChecks infantryId
                ++ interruptedDismountChecks infantryId truckId passengerId

        _ ->
            [ "could not construct planning fixture IDs" ]


interruptedDismountChecks : UnitId -> UnitId -> UnitId -> List String
interruptedDismountChecks infantryId truckId passengerId =
    case ( UnitId.parse "4", UnitId.parse "5", UnitId.parse "6" ) of
        ( Ok otherTruckId, Ok gunId, Ok otherUnitId ) ->
            let
                context : BoardFixture
                context =
                    board
                        [ unit truckId Kind.Truck (Location.OnMap { x = 1, y = 1 })
                        , unit infantryId Kind.Infantry (Location.Aboard truckId)
                        , unit passengerId Kind.Infantry (Location.Aboard truckId)
                        , unit otherTruckId Kind.Truck (Location.OnMap { x = 4, y = 3 })
                        , unit gunId Kind.FieldGun (Location.Aboard otherTruckId)
                        , unit otherUnitId Kind.Tank (Location.OnMap { x = 0, y = 0 })
                        ]

                ready : OrderPlanning.Model
                ready =
                    OrderPlanning.init
                        |> OrderPlanning.setOrders
                            [ { unitId = truckId
                              , action =
                                    PlannedOrder.Unload
                                        { position = { x = 1, y = 1 }
                                        , unloads =
                                            [ { unitId = infantryId, destination = { x = 1, y = 2 } }
                                            , { unitId = passengerId, destination = { x = 2, y = 1 } }
                                            ]
                                        }
                              }
                            , unrelatedOrder
                            ]
                        |> OrderPlanning.setSelection (Just (Inspecting (UnitInspection truckId)))
                        |> OrderPlanning.promptDismountedCommands context.map context.units

                unrelatedOrder : PlannedOrder.PlannedOrder
                unrelatedOrder =
                    { unitId = otherUnitId, action = PlannedOrder.Hold { x = 0, y = 0 } }

                cancel : OrderPlanning.Model -> OrderPlanning.Model
                cancel model =
                    OrderPlanning.cancelInteraction context.map context.units model |> fixtureValue

                hold : OrderPlanning.Model -> OrderPlanning.Model
                hold model =
                    OrderPlanning.applyCommand context.map context.units context.playerNumbers context.movementRules [] [] UnitCommand.HoldPosition model
                        |> fixtureValue

                escaped : OrderPlanning.Model
                escaped =
                    cancel ready

                firstCommand : OrderPlanning.Model
                firstCommand =
                    hold ready

                completed : OrderPlanning.Model
                completed =
                    hold firstCommand

                movingInfantry : OrderPlanning.Model
                movingInfantry =
                    OrderPlanning.applyCommand context.map context.units context.playerNumbers context.movementRules [] [] UnitCommand.Move ready
                        |> fixtureValue

                checklist : OrderPlanning.Model
                checklist =
                    OrderPlanning.startStationaryUnload truckId { x = 1, y = 1 } ready

                movingChecklist : OrderPlanning.Model
                movingChecklist =
                    OrderPlanning.startUnload truckId
                        { destination = { x = 1, y = 2 }
                        , path = [ { x = 1, y = 1 }, { x = 1, y = 2 } ]
                        , cost = 2
                        }
                        ready

                exits : OrderPlanning.Model
                exits =
                    checklist
                        |> OrderPlanning.toggleUnloadPassenger infantryId True
                        |> OrderPlanning.toggleUnloadPassenger passengerId True
                        |> (OrderPlanning.confirmPassengers context.map context.units context.playerNumbers context.movementRules [] [] >> fixtureValue)

                firstExit : OrderPlanning.Model
                firstExit =
                    OrderPlanning.chooseUnloadSquare context.map context.units context.playerNumbers context.movementRules [] [] { x = 1, y = 2 } exits
                        |> fixtureValue

                withPassengerKind : UnitKind -> BoardFixture
                withPassengerKind kind =
                    let
                        changePassenger : Unit -> Unit
                        changePassenger original =
                            if original.id == gunId then
                                { original | kind = kind }

                            else
                                original
                    in
                    context
                        |> setBoardUnits (List.map changePassenger context.units)

                deployOtherPassenger : BoardFixture -> OrderPlanning.Model
                deployOtherPassenger fixture =
                    escaped
                        |> (OrderPlanning.selectUnit fixture.map fixture.units fixture.playerNumbers fixture.movementRules [] [] otherTruckId >> fixtureValue)
                        |> (OrderPlanning.applyCommand fixture.map fixture.units fixture.playerNumbers fixture.movementRules [] [] UnitCommand.Move >> fixtureValue)
                        |> (OrderPlanning.selectTile fixture.map fixture.units fixture.playerNumbers fixture.movementRules [] [] { x = 5, y = 3 } >> fixtureValue)
                        |> OrderPlanning.toggleUnloadPassenger gunId True
                        |> (OrderPlanning.confirmPassengers fixture.map fixture.units fixture.playerNumbers fixture.movementRules [] [] >> fixtureValue)
                        |> (OrderPlanning.chooseUnloadSquare fixture.map fixture.units fixture.playerNumbers fixture.movementRules [] [] { x = 5, y = 2 } >> fixtureValue)

                gunDeployed : OrderPlanning.Model
                gunDeployed =
                    deployOtherPassenger context

                infantryContext : BoardFixture
                infantryContext =
                    withPassengerKind Kind.Infantry

                infantryDeployed : OrderPlanning.Model
                infantryDeployed =
                    deployOtherPassenger infantryContext
            in
            List.concat
                [ expect "the initial truck opens its infantry commands"
                    (Maybe.map .id (OrderPlanning.commandMenuUnit context.map context.units ready) == Just infantryId)
                , expect "Escape cancels the truck and both unloads while preserving unrelated orders"
                    (OrderPlanning.orders escaped
                        == [ unrelatedOrder ]
                        && OrderPlanning.selection escaped
                        == Nothing
                    )
                , expect "Escape during the second infantry command cancels the first infantry command too"
                    (OrderPlanning.orders (cancel firstCommand) == [ unrelatedOrder ])
                , expect "Escape during infantry movement selection cancels the entire truck sequence"
                    (OrderPlanning.orders (cancel movingInfantry) == [ unrelatedOrder ])
                , expect "Escape cancels the checklist, exit selection, and partially chosen exits"
                    (List.all (\model -> OrderPlanning.orders (cancel model) == [ unrelatedOrder ]) [ checklist, movingChecklist, exits, firstExit ])
                , expect "Escape after the last infantry command preserves the completed plan"
                    (OrderPlanning.orders (cancel completed)
                        == OrderPlanning.orders completed
                        && List.length (OrderPlanning.orders completed)
                        == 4
                        && OrderPlanning.selection (cancel completed)
                        == Nothing
                    )
                , expect "deploying another truck's field gun does not reopen skipped infantry menus"
                    (OrderPlanning.commandMenuUnit context.map context.units gunDeployed
                        == Nothing
                        && List.length (List.concatMap PlannedOrder.unloads (OrderPlanning.orders gunDeployed))
                        == 1
                        && List.map .id (OrderPlanning.missingOrders context.map context.units context.playerNumbers (OrderPlanning.orders gunDeployed))
                        == [ truckId ]
                    )
                , expect "Escape after unloading only a field gun keeps the completed truck plan"
                    (OrderPlanning.orders (cancel gunDeployed) == OrderPlanning.orders gunDeployed)
                , expect "closing the infantry command guide keeps the sequence but Escape cancels it"
                    (let
                        readingGuide : OrderPlanning.Model
                        readingGuide =
                            OrderPlanning.openCommandGuide context.map context.units context.playerNumbers ready
                     in
                     OrderPlanning.orders (cancel readingGuide)
                        == [ unrelatedOrder ]
                        && OrderPlanning.orders (OrderPlanning.dismissDialog readingGuide)
                        == OrderPlanning.orders ready
                    )
                , expect "another truck prompts only its own dismounting infantry"
                    (Maybe.map .id (OrderPlanning.commandMenuUnit infantryContext.map infantryContext.units infantryDeployed) == Just gunId)
                ]

        _ ->
            [ "could not construct interrupted dismount fixture IDs" ]


diggingTerrainChecks : UnitId -> List String
diggingTerrainChecks infantryId =
    let
        infantry : Unit
        infantry =
            unit infantryId Kind.Infantry (Location.OnMap { x = 1, y = 1 })

        base : BoardFixture
        base =
            board [ infantry ]

        checkTerrain : Bool -> Terrain.Terrain -> List String
        checkTerrain allowed terrain =
            let
                context : BoardFixture
                context =
                    { base
                        | map = Map.fromFeatures { width = 7, height = 7, baseTile = Terrain.Plain, theme = Theme.GreenForest, features = [ { position = { x = 1, y = 1 }, terrain = terrain } ] }
                    }

                selected : OrderPlanning.Model
                selected =
                    OrderPlanning.selectUnit context.map context.units context.playerNumbers context.movementRules [] [] infantryId OrderPlanning.init
                        |> fixtureValue

                applied : OrderPlanning.Model
                applied =
                    OrderPlanning.applyCommand context.map context.units context.playerNumbers context.movementRules [] [] UnitCommand.DigIn selected
                        |> fixtureValue
            in
            List.concat
                [ expect "dig in availability respects every road shape and preserves other land"
                    (UnitCommand.canUse context.map [] infantry UnitCommand.DigIn == allowed)
                , expect "keyboard command navigation excludes digging on roads"
                    (List.member (UnitCommand.CommandOption UnitCommand.DigIn) (UnitCommand.enabledOptions context.map [] infantry) == allowed)
                , expect "applying dig in on roads leaves planning unchanged"
                    (if allowed then
                        OrderPlanning.orders applied == [ { unitId = infantryId, action = PlannedOrder.DigIn { x = 1, y = 1 } } ]

                     else
                        applied == selected
                    )
                ]

        roads : List Terrain.Terrain
        roads =
            TerrainApi.list |> List.map Terrain.fromApi |> List.filter Terrain.isRoad

        land : List Terrain.Terrain
        land =
            [ Terrain.Plain, Terrain.Hills, Terrain.Forest, Terrain.Mountains, Terrain.Beach ]
    in
    List.concatMap (checkTerrain False) roads
        ++ List.concatMap (checkTerrain True) land


sabotagePlanningChecks : UnitId -> UnitId -> List String
sabotagePlanningChecks infantryId truckId =
    let
        infantry : Unit
        infantry =
            unit infantryId Kind.Infantry (Location.OnMap { x = 1, y = 1 })

        depot : Depot
        depot =
            { kind = BuildingKind.Supply
            , position =
                { x = 1
                , y = 1
                }
            , stock =
                Just
                    { current = 128
                    , maximum = 1024
                    }
            , hp =
                { current = 3
                , maximum = 3
                }
            }

        context : BoardFixture
        context =
            board [ infantry ]

        selected : OrderPlanning.Model
        selected =
            OrderPlanning.selectUnit context.map context.units context.playerNumbers context.movementRules [] [ depot ] infantryId OrderPlanning.init
                |> fixtureValue

        saved : OrderPlanning.Model
        saved =
            OrderPlanning.applyCommand context.map context.units context.playerNumbers context.movementRules [] [ depot ] UnitCommand.Sabotage selected
                |> fixtureValue

        blocked : List Unit
        blocked =
            [ infantry |> Unit.setLocation (Location.dismounting depot.position)
            , infantry |> Unit.setLocation (Location.Aboard truckId)
            , infantry |> Unit.setKind Kind.Tank
            , infantry |> Unit.setKind Kind.FieldGun
            , infantry
                |> Unit.mapResources
                    (\resources ->
                        resources
                            |> UnitResources.setSupplies (Game.Unit.Supplies.setCurrent 0 resources.supplies)
                    )
            ]

        fortress : Depot
        fortress =
            { depot | stock = Nothing }
                |> setDepotKind BuildingKind.Fortress
                |> setDepotHp
                    { current = 8
                    , maximum = 8
                    }

        fortressSelected : OrderPlanning.Model
        fortressSelected =
            OrderPlanning.selectUnit context.map context.units context.playerNumbers context.movementRules [] [ fortress ] infantryId OrderPlanning.init
                |> fixtureValue

        fortressSaved : OrderPlanning.Model
        fortressSaved =
            OrderPlanning.applyCommand context.map context.units context.playerNumbers context.movementRules [] [ fortress ] UnitCommand.Sabotage fortressSelected
                |> fixtureValue
    in
    List.concat
        [ expect "sabotage is offered only to infantry already on an operational depot"
            (List.member UnitCommand.Sabotage (UnitCommand.available [ depot ] infantry)
                && not (List.member UnitCommand.Sabotage (UnitCommand.available [] infantry))
                && not
                    (UnitCommand.canUse context.map
                        [ depot
                            |> setDepotHp
                                { current = 0, maximum = 3 }
                        ]
                        infantry
                        UnitCommand.Sabotage
                    )
                && List.all (\candidate -> not (UnitCommand.canUse context.map [ depot ] candidate UnitCommand.Sabotage)) blocked
            )
        , expect "intact fortresses support the same exclusive sabotage order"
            (UnitCommand.canUse context.map [ fortress ] infantry UnitCommand.Sabotage
                && not
                    (UnitCommand.canUse context.map
                        [ { fortress
                            | hp =
                                { current = 0
                                , maximum = 8
                                }
                          }
                        ]
                        infantry
                        UnitCommand.Sabotage
                    )
                && OrderPlanning.orders fortressSaved
                == [ { unitId = infantryId
                     , action = PlannedOrder.Sabotage fortress.position
                     }
                   ]
            )
        , expect "sabotage saves a revocable stationary order and closes commands"
            (OrderPlanning.orders saved
                == [ { unitId = infantryId, action = PlannedOrder.Sabotage depot.position } ]
                && OrderPlanning.commandMenuUnit context.map context.units saved
                == Nothing
                && List.isEmpty (OrderPlanning.orders (OrderPlanning.revokeSelectedOrder context.map context.units context.playerNumbers saved |> fixtureValue))
            )
        ]


groundPickupChecks : UnitId -> UnitId -> List String
groundPickupChecks infantryId truckId =
    let
        truck : Unit
        truck =
            unit truckId Kind.Truck (Location.OnMap { x = 3, y = 1 })

        fixture : ResourceKind -> BoardFixture
        fixture kind =
            let
                base : BoardFixture
                base =
                    board [ truck ]
            in
            { base
                | supplyCrates =
                    [ { position = { x = 3, y = 1 }
                      , stock = { kind = kind, current = 23, maximum = 256 }
                      }
                    ]
            }

        hold : BoardFixture -> UnitId -> OrderPlanning.Model
        hold context id =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context.map context.units context.playerNumbers context.movementRules context.supplyCrates context.depots id
                |> IC.andThen (OrderPlanning.applyCommand context.map context.units context.playerNumbers context.movementRules context.supplyCrates context.depots UnitCommand.HoldPosition)
                |> fixtureValue

        asksFor : ResourceKind -> OrderPlanning.Model -> Bool
        asksFor kind state =
            case state of
                OrderPlanning.ChoosingGroundFreight id freight _ ->
                    id == truckId && freight.stock.kind == kind && freight.stock.current == 23

                _ ->
                    False

        checksFor : ResourceKind -> List String
        checksFor kind =
            let
                context : BoardFixture
                context =
                    fixture kind

                pending : OrderPlanning.Model
                pending =
                    hold context truckId

                confirmed : OrderPlanning.Model
                confirmed =
                    pending |> OrderPlanning.confirmGroundPickup |> fixtureValue

                expected : PlannedOrder.PlannedOrder
                expected =
                    { unitId = truckId
                    , action =
                        PlannedOrder.SupplyTransfer
                            { route = [ { x = 3, y = 1 } ]
                            , destination = { x = 3, y = 1 }
                            , handling = PlannedOrder.PickingUpGroundFreight kind
                            , passengers = []
                            }
                    }

                movingTruck : Unit
                movingTruck =
                    { truck | location = Location.OnMap { x = 2, y = 1 } }

                movingContext : BoardFixture
                movingContext =
                    context
                        |> setBoardUnits
                            [ movingTruck ]

                moving : OrderPlanning.Model
                moving =
                    OrderPlanning.init
                        |> OrderPlanning.selectUnit movingContext.map movingContext.units movingContext.playerNumbers movingContext.movementRules movingContext.supplyCrates movingContext.depots truckId
                        |> IC.andThen (OrderPlanning.applyCommand movingContext.map movingContext.units movingContext.playerNumbers movingContext.movementRules movingContext.supplyCrates movingContext.depots UnitCommand.Move)
                        |> IC.andThen (OrderPlanning.selectTile movingContext.map movingContext.units movingContext.playerNumbers movingContext.movementRules movingContext.supplyCrates movingContext.depots { x = 3, y = 1 })
                        |> fixtureValue

                full : Unit
                full =
                    truck
                        |> Unit.mapResources
                            (\resources ->
                                resources
                                    |> setResourcesSupplyCargo (List.repeat 2 { kind = kind, current = 8, maximum = 256 })
                            )

                fullContext : BoardFixture
                fullContext =
                    context
                        |> setBoardUnits
                            [ full ]

                fullSkipped : OrderPlanning.Model
                fullSkipped =
                    hold fullContext truckId
                        |> OrderPlanning.skipUnloading fullContext.map fullContext.units fullContext.supplyCrates fullContext.depots
            in
            List.concat
                [ expect "holding on either kind of ground freight offers a pickup choice" (asksFor kind pending)
                , expect "saving a truck route onto ground freight offers a pickup choice" (asksFor kind moving)
                , expect "confirming ground pickup saves the resource and route" (OrderPlanning.orders confirmed == [ expected ])
                , expect "declining ground pickup preserves the route without a freight order"
                    (OrderPlanning.orders (OrderPlanning.dismissDialog pending)
                        == [ { unitId = truckId, action = PlannedOrder.Hold { x = 3, y = 1 } } ]
                    )
                , expect "full trucks skip ground pickup after declining unloading" (not (asksFor kind fullSkipped))
                , expect "ground pickup confirmation outside its stage is a no-op"
                    (OrderPlanning.confirmGroundPickup confirmed |> fixtureValue |> (==) confirmed)
                ]

        nonTruck : BoardFixture
        nonTruck =
            let
                base : BoardFixture
                base =
                    fixture ResourceKind.Supply
            in
            { base | units = [ unit infantryId Kind.Infantry (Location.OnMap { x = 3, y = 1 }) ] }
    in
    checksFor ResourceKind.Supply
        ++ checksFor ResourceKind.Fuel
        ++ expect "infantry standing on ground freight do not get a truck pickup dialog"
            (not (asksFor ResourceKind.Supply (hold nonTruck infantryId)))


cargoLoadingChecks : UnitId -> UnitId -> UnitId -> List String
cargoLoadingChecks infantryId truckId passengerId =
    let
        freight : ResourceKind -> CargoStock
        freight kind =
            { kind = kind
            , current = 32
            , maximum = 64
            }

        truck : List CargoStock -> Unit
        truck cargo =
            unit truckId Kind.Truck (Location.OnMap { x = 3, y = 1 })
                |> Unit.mapResources
                    (\resources ->
                        resources
                            |> setResourcesSupplyCargo cargo
                    )

        context : BuildingKind -> List Unit -> BoardFixture
        context kind units =
            let
                fixture : BoardFixture
                fixture =
                    board units

                maximumHp : Int
                maximumHp =
                    case kind of
                        BuildingKind.Supply ->
                            3

                        BuildingKind.Fuel ->
                            1

                        BuildingKind.Fortress ->
                            8

                stock : Maybe Supply.Stock
                stock =
                    if kind == BuildingKind.Fortress then
                        Nothing

                    else
                        Just
                            { current = 256
                            , maximum = 256
                            }
            in
            { fixture
                | depots =
                    [ { kind = kind
                      , position =
                            { x = 3
                            , y = 1
                            }
                      , stock = stock
                      , hp =
                            { current = maximumHp
                            , maximum = maximumHp
                            }
                      }
                    ]
            }

        hold : BoardFixture -> OrderPlanning.Model
        hold fixture =
            OrderPlanning.init
                |> OrderPlanning.selectUnit fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots truckId
                |> IC.andThen (OrderPlanning.applyCommand fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots UnitCommand.HoldPosition)
                |> fixtureValue

        skipsLoading : OrderPlanning.Model -> Bool
        skipsLoading model =
            case model of
                OrderPlanning.OrdinaryPlanning _ ->
                    OrderPlanning.submissionDrafts model /= Nothing

                _ ->
                    False

        fullTruckChecks : BuildingKind -> List Unit -> List String
        fullTruckChecks kind units =
            let
                fixture : BoardFixture
                fixture =
                    context kind units

                checklist : OrderPlanning.Model
                checklist =
                    hold fixture

                skipped : OrderPlanning.Model
                skipped =
                    OrderPlanning.skipUnloading fixture.map fixture.units fixture.supplyCrates fixture.depots checklist

                confirmed : OrderPlanning.Model
                confirmed =
                    OrderPlanning.confirmPassengers fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots checklist
                        |> fixtureValue
            in
            expect "full trucks skip depot loading after declining unloading and retain their hold"
                (skipsLoading skipped
                    && skipsLoading confirmed
                    && OrderPlanning.orders skipped
                    == OrderPlanning.orders confirmed
                    && List.map .unitId (OrderPlanning.orders skipped)
                    == [ truckId ]
                )

        arriving : BoardFixture -> OrderPlanning.Model
        arriving fixture =
            OrderPlanning.init
                |> OrderPlanning.selectUnit fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots infantryId
                |> IC.andThen (OrderPlanning.applyCommand fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots UnitCommand.Move)
                |> IC.andThen (OrderPlanning.selectTile fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots { x = 3, y = 1 })
                |> fixtureValue

        reservedFixture : BoardFixture
        reservedFixture =
            context BuildingKind.Supply
                [ truck [ freight ResourceKind.Fuel ]
                , unit infantryId Kind.Infantry (Location.OnMap { x = 2, y = 1 })
                ]

        reserved : OrderPlanning.Model
        reserved =
            arriving reservedFixture

        spareFixture : BoardFixture
        spareFixture =
            context BuildingKind.Fuel [ truck [ freight ResourceKind.Supply ] ]

        spare : OrderPlanning.Model
        spare =
            OrderPlanning.skipUnloading spareFixture.map spareFixture.units spareFixture.supplyCrates spareFixture.depots (hold spareFixture)

        fortressFixture : BoardFixture
        fortressFixture =
            context BuildingKind.Fortress [ truck [] ]
    in
    List.concat
        [ fullTruckChecks BuildingKind.Supply [ truck [ freight ResourceKind.Supply, freight ResourceKind.Fuel ] ]
        , expect "empty trucks holding on fortresses never offer freight loading"
            (skipsLoading (hold fortressFixture))
        , fullTruckChecks BuildingKind.Fuel [ truck [ freight ResourceKind.Fuel ], unit infantryId Kind.Infantry (Location.Aboard truckId) ]
        , fullTruckChecks BuildingKind.Supply [ truck [], unit infantryId Kind.Infantry (Location.Aboard truckId), unit passengerId Kind.FieldGun (Location.Aboard truckId) ]
        , expect "a passenger reserving the last berth skips depot loading and preserves both orders"
            (skipsLoading reserved
                && List.length (OrderPlanning.orders reserved)
                == 2
                && PlannedTransport.boardingPassengers reservedFixture.units truckId (OrderPlanning.orders reserved)
                == [ infantryId ]
            )
        , expect "a truck with one free berth still offers depot loading"
            (case spare of
                OrderPlanning.ChoosingCrates id _ _ ->
                    id == truckId

                _ ->
                    False
            )
        ]


mutualPickupChecks : UnitId -> UnitId -> UnitId -> List String
mutualPickupChecks infantryId truckId gunId =
    let
        destination : Coordinate
        destination =
            { x = 2, y = 2 }

        truck : Unit
        truck =
            unit truckId Kind.Truck (Location.OnMap { x = 3, y = 1 })

        context : BoardFixture
        context =
            board
                [ truck
                , unit infantryId Kind.Infantry (Location.OnMap { x = 1, y = 1 })
                , unit gunId Kind.FieldGun (Location.OnMap { x = 2, y = 1 })
                ]

        startMove : BoardFixture -> UnitId -> OrderPlanning.Model -> OrderPlanning.Model
        startMove fixture id model =
            model
                |> OrderPlanning.selectUnit fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots id
                |> IC.andThen (OrderPlanning.applyCommand fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots UnitCommand.Move)
                |> fixtureValue

        saveMove : BoardFixture -> UnitId -> OrderPlanning.Model -> OrderPlanning.Model
        saveMove fixture id model =
            startMove fixture id model
                |> OrderPlanning.selectTile fixture.map fixture.units fixture.playerNumbers fixture.movementRules fixture.supplyCrates fixture.depots destination
                |> fixtureValue

        passengerFirst : OrderPlanning.Model
        passengerFirst =
            saveMove context infantryId OrderPlanning.init

        truckSecond : OrderPlanning.Model
        truckSecond =
            saveMove context truckId passengerFirst

        rejectedPassenger : OrderPlanning.Model
        rejectedPassenger =
            saveMove context gunId passengerFirst

        fieldGunFirst : OrderPlanning.Model
        fieldGunFirst =
            saveMove context gunId OrderPlanning.init

        keyboardPickup : OrderPlanning.Model
        keyboardPickup =
            startMove context truckId fieldGunFirst
                |> OrderPlanning.extendPath context.map context.units context.playerNumbers context.movementRules DirectionEnum.South
                |> OrderPlanning.extendPath context.map context.units context.playerNumbers context.movementRules DirectionEnum.West
                |> OrderPlanning.confirmPath context.map context.units context.playerNumbers context.movementRules context.supplyCrates context.depots
                |> fixtureValue

        fullContext : BoardFixture
        fullContext =
            board
                [ truck
                , unit infantryId Kind.Infantry (Location.OnMap { x = 1, y = 1 })
                , unit gunId Kind.FieldGun (Location.Aboard truckId)
                ]
                |> (\fixture -> { fixture | units = List.map addFreight fixture.units })

        addFreight : Unit -> Unit
        addFreight candidate =
            if candidate.id == truckId then
                Unit.mapResources
                    (\resources ->
                        resources
                            |> setResourcesSupplyCargo
                                [ { kind = ResourceKind.Supply
                                  , current = 64
                                  , maximum = 64
                                  }
                                ]
                    )
                    candidate

            else
                candidate

        fullPickup : OrderPlanning.Model
        fullPickup =
            saveMove fullContext truckId (saveMove fullContext infantryId OrderPlanning.init)

        attackOrder : PlannedOrder.PlannedOrder
        attackOrder =
            { unitId = infantryId
            , action = PlannedOrder.AttackMove { move = { destination = destination, path = [ { x = 1, y = 1 }, { x = 1, y = 2 }, destination ], cost = 4 }, direction = DirectionEnum.South }
            }

        rejectedAttackPickup : OrderPlanning.Model
        rejectedAttackPickup =
            saveMove context truckId (OrderPlanning.setOrders [ attackOrder ] OrderPlanning.init)

        revokedTruck : List PlannedOrder.PlannedOrder
        revokedTruck =
            OrderDependencies.revoke context.units [ truckId ] (OrderPlanning.orders truckSecond)
                |> fixtureValue

        revokedPassenger : List PlannedOrder.PlannedOrder
        revokedPassenger =
            OrderDependencies.revoke context.units [ infantryId ] (OrderPlanning.orders truckSecond)
                |> fixtureValue
    in
    List.concat
        [ expect "passenger-first pickup preserves the passenger route and reserves its berth"
            (List.length (OrderPlanning.orders truckSecond)
                == 2
                && List.all (\order -> List.member order (OrderPlanning.orders truckSecond)) (OrderPlanning.orders passengerFirst)
                && PlannedTransport.boardingPassengers context.units truckId (OrderPlanning.orders truckSecond)
                == [ infantryId ]
            )
        , expect "keyboard confirmation lets a truck pick up a field gun at its saved destination"
            (List.length (OrderPlanning.orders keyboardPickup)
                == 2
                && List.all (\order -> List.member order (OrderPlanning.orders keyboardPickup)) (OrderPlanning.orders fieldGunFirst)
                && PlannedTransport.boardingPassengers context.units truckId (OrderPlanning.orders keyboardPickup)
                == [ gunId ]
            )
        , expect "passengers cannot share a saved destination without a truck"
            (OrderPlanning.orders rejectedPassenger
                == OrderPlanning.orders passengerFirst
                && OrderPlanning.destinationFeedback rejectedPassenger
                == DestinationUnavailable
            )
        , expect "a full truck cannot claim an arriving passenger destination"
            (OrderPlanning.destinationFeedback fullPickup == DestinationUnavailable)
        , expect "trucks cannot board a passenger with an attack-move order"
            (OrderPlanning.orders rejectedAttackPickup
                == [ attackOrder ]
                && OrderPlanning.destinationFeedback rejectedAttackPickup
                == DestinationUnavailable
            )
        , expect "revoking either moving rendezvous partner clears dependent pickup orders"
            (List.isEmpty revokedTruck && List.isEmpty revokedPassenger)
        ]


indirectPlanningChecks : UnitId -> UnitId -> List String
indirectPlanningChecks unitId carrierId =
    let
        gun : Unit
        gun =
            let
                base : Unit
                base =
                    unit unitId Kind.FieldGun (Location.OnMap { x = 1, y = 1 })

                rules : CombatRules
                rules =
                    base.combatRules
            in
            base
                |> Unit.setCombatRules { rules | indirectRange = 2 }

        passenger : Unit
        passenger =
            gun
                |> Unit.setLocation (Location.Aboard carrierId)

        context : BoardFixture
        context =
            board [ gun ]

        invalidTarget : Coordinate
        invalidTarget =
            { x = -1, y = 1 }

        validTarget : Coordinate
        validTarget =
            { x = 2, y = 1 }

        checkPlanning : Maybe IndirectFirePlanning -> InvariantCheck IndirectFirePlanning.InvariantViolation Bool
        checkPlanning maybePlanning =
            case maybePlanning of
                Just planning ->
                    let
                        previewed : IndirectFirePlanning
                        previewed =
                            IndirectFirePlanning.previewTo context.map validTarget planning
                    in
                    IC.happy
                        (IndirectFirePlanning.targetPreview planning
                            == Nothing
                            && IndirectFirePlanning.targetPreview previewed
                            == Just validTarget
                            && IndirectFirePlanning.targetPreview (IndirectFirePlanning.clearPreview previewed)
                            == Nothing
                            && IndirectFirePlanning.targetPreview (IndirectFirePlanning.previewTo context.map invalidTarget previewed)
                            == Nothing
                        )

                Nothing ->
                    IC.happy False
    in
    List.concat
        [ expect "indirect targeting requires a map position at initialization"
            (IndirectFirePlanning.start passenger
                == IC.violated (IndirectFirePlanning.CommandUnitNotOnMap unitId) Nothing
            )
        , expect "indirect order construction requires a current map position"
            (IndirectFirePlanning.order context.map passenger validTarget
                == IC.violated (IndirectFirePlanning.CommandUnitNotOnMap unitId) Nothing
            )
        , expect "indirect targeting owns legal preview selection and clearing"
            ((IndirectFirePlanning.start gun |> IC.andThen checkPlanning) == IC.happy True)
        , expect "off-map indirect targets are unavailable without a diagnostic"
            (IndirectFirePlanning.order context.map gun invalidTarget == IC.happy Nothing)
        , expect "indirect order construction retains the firing position"
            (IndirectFirePlanning.order context.map gun validTarget
                == IC.happy (Just { unitId = unitId, action = PlannedOrder.IndirectFire { position = { x = 1, y = 1 }, target = validTarget } })
            )
        ]


directionPlanningChecks : UnitId -> UnitId -> List String
directionPlanningChecks unitId carrierId =
    let
        infantry : Unit
        infantry =
            unit unitId Kind.Infantry (Location.OnMap { x = 1, y = 1 })

        passenger : Unit
        passenger =
            infantry
                |> Unit.setLocation (Location.Aboard carrierId)

        move : Movement.Option
        move =
            { destination = { x = 2, y = 1 }
            , path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ]
            , cost = 2
            }

        attack : DirectionPlanning
        attack =
            DirectionPlanning.attackMove move infantry
    in
    List.concat
        [ expect "attack facing starts along the final route segment"
            (attack == DirectionPlanning.AttackMove move DirectionEnum.East)
        , expect "reverse attack facing leaves the preview unchanged"
            (DirectionPlanning.preview DirectionEnum.West attack == attack)
        , expect "reverse attack facing is unavailable without an invariant violation"
            (DirectionPlanning.attackOrder unitId move DirectionEnum.West == Nothing)
        , expect "valid attack facing constructs the completed order"
            (DirectionPlanning.attackOrder unitId move DirectionEnum.North
                == Just { unitId = unitId, action = PlannedOrder.AttackMove { move = move, direction = DirectionEnum.North } }
            )
        , expect "ambush constructs its stationary position and chosen facing"
            (DirectionPlanning.stationaryOrder DirectionPlanning.AmbushPurpose infantry DirectionEnum.South
                == IC.happy (Just { unitId = unitId, action = PlannedOrder.Ambush { position = { x = 1, y = 1 }, direction = DirectionEnum.South } })
            )
        , expect "stand ground constructs its stationary position and chosen facing"
            (DirectionPlanning.stationaryOrder DirectionPlanning.StandGroundPurpose infantry DirectionEnum.West
                == IC.happy (Just { unitId = unitId, action = PlannedOrder.StandGround { position = { x = 1, y = 1 }, direction = DirectionEnum.West } })
            )
        , expect "both stationary direction commands require a map position"
            (List.all
                (\planning ->
                    DirectionPlanning.stationaryOrder planning passenger DirectionEnum.North
                        == IC.violated (DirectionPlanning.CommandUnitNotOnMap unitId) Nothing
                )
                [ DirectionPlanning.AmbushPurpose, DirectionPlanning.StandGroundPurpose ]
            )
        ]


dependencyInvariantChecks : UnitId -> UnitId -> UnitId -> List String
dependencyInvariantChecks moverId missingId passengerId =
    let
        mover : Unit
        mover =
            unit moverId Kind.Truck (Location.OnMap { x = 1, y = 1 })

        passenger : Unit
        passenger =
            unit passengerId Kind.Infantry (Location.Aboard moverId)

        departure : PlannedOrder.PlannedOrder
        departure =
            { unitId = moverId
            , action = PlannedOrder.Move { move = { destination = { x = 2, y = 1 }, path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ], cost = 2 }, unloads = [] }
            }

        missingHold : PlannedOrder.PlannedOrder
        missingHold =
            { unitId = missingId, action = PlannedOrder.Hold { x = 4, y = 4 } }

        missingDeparture : PlannedOrder.PlannedOrder
        missingDeparture =
            { departure | unitId = missingId }

        passengerHold : PlannedOrder.PlannedOrder
        passengerHold =
            { unitId = passengerId, action = PlannedOrder.Hold { x = 1, y = 1 } }

        drafts : List PlannedOrder.PlannedOrder
        drafts =
            [ departure, missingHold ]

        violation : OrderDependencies.InvariantViolation
        violation =
            OrderDependencies.OrderUnitNotFound missingId

        context : BoardFixture
        context =
            board [ mover ]

        model : OrderPlanning.Model
        model =
            OrderPlanning.OrdinaryPlanning
                { orders = drafts
                , selection = Just (Inspecting (UnitInspection moverId))
                }
    in
    List.concat
        [ expect "a missing retained order unit reports its identity and prevents partial revocation"
            (OrderDependencies.revoke [ mover ] [ moverId ] drafts
                == IC.violated violation drafts
            )
        , expect "a missing revoked order unit retains every original draft"
            (OrderDependencies.revoke [ mover ] [ missingId ] [ missingDeparture, departure ]
                == IC.violated violation [ missingDeparture, departure ]
            )
        , expect "ordinary departures without boarding partners revoke successfully"
            (OrderDependencies.revoke [ mover ] [ moverId ] [ departure ]
                == IC.happy []
            )
        , expect "an aboard passenger order does not require an authoritative map position"
            (OrderDependencies.revoke [ mover, passenger ] [ moverId ] [ departure, passengerHold ]
                == IC.happy [ passengerHold ]
            )
        , expect "revocation propagates dependency diagnostics through the planning coordinator"
            (OrderPlanning.revokeSelectedOrder context.map context.units context.playerNumbers model
                == IC.violated (OrderPlanning.OrderDependenciesInvariantViolated violation) model
            )
        ]


transportInvariantChecks : UnitId -> UnitId -> UnitId -> List String
transportInvariantChecks otherId truckId passengerId =
    let
        passenger : Unit
        passenger =
            unit passengerId Kind.Infantry (Location.Aboard truckId)

        carrier : Unit
        carrier =
            unit truckId Kind.Truck (Location.OnMap { x = 1, y = 1 })

        nestedCarrier : Unit
        nestedCarrier =
            carrier
                |> Unit.setLocation (Location.Aboard otherId)

        mover : Unit
        mover =
            Unit.setOnMap { x = 1, y = 1 } passenger

        move : Movement.Option
        move =
            { destination = { x = 2, y = 1 }
            , path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ]
            , cost = 2
            }

        drafts : List PlannedOrder.PlannedOrder
        drafts =
            [ { unitId = otherId, action = PlannedOrder.Hold { x = 5, y = 5 } } ]

        missingCarrier : PlannedTransport.InvariantViolation
        missingCarrier =
            PlannedTransport.CarrierNotFound { passengerId = passengerId, carrierId = truckId }

        aboardCarrier : PlannedTransport.InvariantViolation
        aboardCarrier =
            PlannedTransport.CarrierNotOnMap { passengerId = passengerId, carrierId = truckId }

        expectedMove : PlannedOrder.PlannedOrder
        expectedMove =
            { unitId = passengerId, action = PlannedOrder.Move { move = move, unloads = [] } }
    in
    List.concat
        [ expect "an explicit missing carrier reports both passenger and carrier identities"
            (PlannedTransport.moveReceiver [] passenger move drafts
                == IC.violated missingCarrier Nothing
            )
        , expect "a missing carrier cannot save an incomplete transport move or discard unrelated orders"
            (PlannedTransport.moveOrders [] passenger move drafts
                == IC.violated missingCarrier drafts
            )
        , expect "a carrier that is itself aboard is an invariant violation, not an absent boarding partner"
            (PlannedTransport.moveReceiver [ nestedCarrier ] passenger move drafts
                == IC.violated aboardCarrier Nothing
            )
        , expect "a carrier that is not on the map leaves transport drafts unchanged"
            (PlannedTransport.moveOrders [ nestedCarrier ] passenger move drafts
                == IC.violated aboardCarrier drafts
            )
        , expect "ordinary moves without boarding partners satisfy the invariant"
            (PlannedTransport.moveReceiver [ mover ] mover move drafts
                == IC.happy Nothing
            )
        , expect "an ordinary move is still saved without a receiving hold"
            (PlannedTransport.moveOrders [ mover ] mover move drafts
                == IC.happy (expectedMove :: drafts)
            )
        , expect "an explicit carrier on the map resolves successfully"
            (PlannedTransport.moveReceiver [ carrier ] passenger move drafts
                == IC.happy (Just carrier)
            )
        ]


planningChecks : UnitId -> UnitId -> UnitId -> List String
planningChecks infantryId truckId passengerId =
    let
        infantry : Unit
        infantry =
            unit infantryId Kind.Infantry (Location.OnMap { x = 1, y = 1 })

        truck : Unit
        truck =
            unit truckId Kind.Truck (Location.OnMap { x = 3, y = 1 })

        context : BoardFixture
        context =
            board [ infantry, truck ]

        enemy : Unit
        enemy =
            truck
                |> Unit.setPlayerNumber PlayerNumber.Player2

        attackContext : BoardFixture
        attackContext =
            board [ infantry, enemy ]

        attacking : OrderPlanning.Model
        attacking =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        attackContext.map
                        attackContext.units
                        attackContext.playerNumbers
                        attackContext.movementRules
                        attackContext.supplyCrates
                        attackContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        attackContext.map
                        attackContext.units
                        attackContext.playerNumbers
                        attackContext.movementRules
                        attackContext.supplyCrates
                        attackContext.depots
                        UnitCommand.AttackMove
                        >> fixtureValue
                   )
                |> OrderPlanning.extendPath
                    attackContext.map
                    attackContext.units
                    attackContext.playerNumbers
                    attackContext.movementRules
                    DirectionEnum.East
                |> OrderPlanning.extendPath
                    attackContext.map
                    attackContext.units
                    attackContext.playerNumbers
                    attackContext.movementRules
                    DirectionEnum.East

        attackAiming : OrderPlanning.Model
        attackAiming =
            (OrderPlanning.confirmPath
                attackContext.map
                attackContext.units
                attackContext.playerNumbers
                attackContext.movementRules
                attackContext.supplyCrates
                attackContext.depots
                >> fixtureValue
            )
                attacking

        attackSaved : OrderPlanning.Model
        attackSaved =
            attackAiming
                |> OrderPlanning.previewDirection DirectionEnum.West
                |> (OrderPlanning.saveDirection
                        attackContext.map
                        attackContext.units
                        attackContext.playerNumbers
                        DirectionEnum.North
                        >> fixtureValue
                   )

        attackRevoked : OrderPlanning.Model
        attackRevoked =
            (OrderPlanning.revokeSelectedOrder
                attackContext.map
                attackContext.units
                attackContext.playerNumbers
                >> fixtureValue
            )
                attackSaved

        reopenedCommands : OrderPlanning.Model
        reopenedCommands =
            (OrderPlanning.selectUnit
                attackContext.map
                attackContext.units
                attackContext.playerNumbers
                attackContext.movementRules
                attackContext.supplyCrates
                attackContext.depots
                infantryId
                >> fixtureValue
            )
                attackRevoked

        lowSupplyInfantry : Unit
        lowSupplyInfantry =
            infantry
                |> Unit.setResources
                    (Maybe.map
                        (\resources ->
                            resources
                                |> UnitResources.setSupplies
                                    { current = 6, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 }
                        )
                        infantry.resources
                    )

        lowSupplyContext : BoardFixture
        lowSupplyContext =
            board [ lowSupplyInfantry, enemy ]

        lowSupplyAttack : OrderPlanning.Model
        lowSupplyAttack =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        lowSupplyContext.map
                        lowSupplyContext.units
                        lowSupplyContext.playerNumbers
                        lowSupplyContext.movementRules
                        lowSupplyContext.supplyCrates
                        lowSupplyContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        lowSupplyContext.map
                        lowSupplyContext.units
                        lowSupplyContext.playerNumbers
                        lowSupplyContext.movementRules
                        lowSupplyContext.supplyCrates
                        lowSupplyContext.depots
                        UnitCommand.AttackMove
                        >> fixtureValue
                   )
                |> OrderPlanning.extendPath
                    lowSupplyContext.map
                    lowSupplyContext.units
                    lowSupplyContext.playerNumbers
                    lowSupplyContext.movementRules
                    DirectionEnum.East
                |> OrderPlanning.extendPath
                    lowSupplyContext.map
                    lowSupplyContext.units
                    lowSupplyContext.playerNumbers
                    lowSupplyContext.movementRules
                    DirectionEnum.East

        attackLoading : OrderPlanning.Model
        attackLoading =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.AttackMove
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 3, y = 1 }
                        >> fixtureValue
                   )

        fieldGun : Unit
        fieldGun =
            infantry
                |> Unit.setKind Kind.FieldGun
                |> Unit.setCombatRules
                    { range = 3
                    , indirectRange = 9
                    , shape = AmbushShape.Cross
                    , damage = 12
                    , readinessCost = 2
                    , digInCost = 16
                    , shotCost = 3
                    }

        indirectContext : BoardFixture
        indirectContext =
            context
                |> setBoardUnits
                    [ fieldGun, truck ]

        aiming : OrderPlanning.Model
        aiming =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        indirectContext.map
                        indirectContext.units
                        indirectContext.playerNumbers
                        indirectContext.movementRules
                        indirectContext.supplyCrates
                        indirectContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        indirectContext.map
                        indirectContext.units
                        indirectContext.playerNumbers
                        indirectContext.movementRules
                        indirectContext.supplyCrates
                        indirectContext.depots
                        UnitCommand.IndirectFire
                        >> fixtureValue
                   )

        bombardment : OrderPlanning.Model
        bombardment =
            aiming
                |> (OrderPlanning.selectTile indirectContext.map
                        indirectContext.units
                        indirectContext.playerNumbers
                        indirectContext.movementRules
                        indirectContext.supplyCrates
                        indirectContext.depots
                        { x = 3
                        , y = 3
                        }
                        >> fixtureValue
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
            aiming
                |> (OrderPlanning.selectUnit
                        indirectContext.map
                        indirectContext.units
                        indirectContext.playerNumbers
                        indirectContext.movementRules
                        indirectContext.supplyCrates
                        indirectContext.depots
                        infantryId
                        >> fixtureValue
                   )

        rangeMap : Map
        rangeMap =
            Map.fromFeatures
                { width = 20
                , height = 3
                , baseTile = Terrain.Plain
                , theme = Theme.GreenForest
                , features = []
                }

        outOfRangeContext : BoardFixture
        outOfRangeContext =
            { indirectContext
                | map = rangeMap
            }

        edgeAim : OrderPlanning.Model
        edgeAim =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        outOfRangeContext.map
                        outOfRangeContext.units
                        outOfRangeContext.playerNumbers
                        outOfRangeContext.movementRules
                        outOfRangeContext.supplyCrates
                        outOfRangeContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        outOfRangeContext.map
                        outOfRangeContext.units
                        outOfRangeContext.playerNumbers
                        outOfRangeContext.movementRules
                        outOfRangeContext.supplyCrates
                        outOfRangeContext.depots
                        UnitCommand.IndirectFire
                        >> fixtureValue
                   )

        diggingIn : OrderPlanning.Model
        diggingIn =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.DigIn
                        >> fixtureValue
                   )

        choosingStandGround : OrderPlanning.Model
        choosingStandGround =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.StandGround
                        >> fixtureValue
                   )

        standingGround : OrderPlanning.Model
        standingGround =
            choosingStandGround
                |> OrderPlanning.previewDirection DirectionEnum.West
                |> (OrderPlanning.saveDirection
                        context.map
                        context.units
                        context.playerNumbers
                        DirectionEnum.West
                        >> fixtureValue
                   )

        insufficientReadiness : Unit
        insufficientReadiness =
            infantry
                |> Unit.setResources
                    (Maybe.map
                        (\resources ->
                            resources
                                |> UnitResources.setSupplies
                                    { current = 2, maximum = 48, upkeepPerTurn = 1, roughTerrainSurcharge = 1, movementPerTile = 3 }
                        )
                        infantry.resources
                    )

        ambushing : OrderPlanning.Model
        ambushing =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Ambush
                        >> fixtureValue
                   )
                |> OrderPlanning.previewDirection DirectionEnum.East
                |> (OrderPlanning.saveDirection
                        context.map
                        context.units
                        context.playerNumbers
                        DirectionEnum.East
                        >> fixtureValue
                   )

        truckAmbush : OrderPlanning.Model
        truckAmbush =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Ambush
                        >> fixtureValue
                   )
                |> (OrderPlanning.saveDirection
                        context.map
                        context.units
                        context.playerNumbers
                        DirectionEnum.East
                        >> fixtureValue
                   )

        moving : OrderPlanning.Model
        moving =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> OrderPlanning.extendPath
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    DirectionEnum.South

        saved : OrderPlanning.Model
        saved =
            (OrderPlanning.confirmPath
                context.map
                context.units
                context.playerNumbers
                context.movementRules
                context.supplyCrates
                context.depots
                >> fixtureValue
            )
                moving

        revocationBlocked : BoardFixture -> UnitId -> OrderPlanning.Model -> Bool
        revocationBlocked planningContext unitId state =
            not
                (OrderPlanning.canRevokeOrder
                    planningContext.map
                    planningContext.units
                    planningContext.playerNumbers
                    unitId
                    state
                )
                && ((OrderPlanning.revokeSelectedOrder
                        planningContext.map
                        planningContext.units
                        planningContext.playerNumbers
                        >> fixtureValue
                    )
                        state
                        == state
                   )

        previewRevocationBlocked : OrderPlanning.Model -> Bool
        previewRevocationBlocked state =
            state
                |> OrderPlanning.setOrders (OrderPlanning.orders saved)
                |> revocationBlocked context infantryId

        crateChoice : OrderPlanning.Model
        crateChoice =
            OrderPlanning.ChoosingCrates truckId
                { kind = ResourceKind.Supply
                , stock = Nothing
                }
                { orders = OrderPlanning.orders saved
                , selection = Just (Inspecting (UnitInspection truckId))
                }

        dismissedCrates : OrderPlanning.Model
        dismissedCrates =
            OrderPlanning.dismissDialog crateChoice

        reserved : OrderPlanning.Model
        reserved =
            saved
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 1, y = 2 }
                        >> fixtureValue
                   )

        enteringVacated : OrderPlanning.Model
        enteringVacated =
            saved
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 1, y = 1 }
                        >> fixtureValue
                   )

        revokeDeparture : OrderPlanning.Model
        revokeDeparture =
            enteringVacated
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.revokeSelectedOrder context.map context.units context.playerNumbers >> fixtureValue)

        truckDeparting : OrderPlanning.Model
        truckDeparting =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 3, y = 2 }
                        >> fixtureValue
                   )

        enteringTruckOrigin : OrderPlanning.Model
        enteringTruckOrigin =
            truckDeparting
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 3, y = 1 }
                        >> fixtureValue
                   )

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
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 3
                        , y = 1
                        }
                        >> fixtureValue
                   )

        tryingFullTruck : OrderPlanning.Model
        tryingFullTruck =
            OrderPlanning.init
                |> OrderPlanning.setOrders [ fullFreight ]
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 3
                        , y = 1
                        }
                        >> fixtureValue
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
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 2
                        , y = 1
                        }
                        >> fixtureValue
                   )

        chainContext : BoardFixture
        chainContext =
            board [ infantry, truck, unit passengerId Kind.Infantry (Location.OnMap { x = 2, y = 1 }) ]

        chain : OrderPlanning.Model
        chain =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        { x = 3, y = 2 }
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectUnit
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        passengerId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        { x = 3, y = 1 }
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectUnit
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        { x = 2, y = 1 }
                        >> fixtureValue
                   )

        revokedChain : OrderPlanning.Model
        revokedChain =
            chain
                |> (OrderPlanning.selectUnit
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        chainContext.movementRules
                        chainContext.supplyCrates
                        chainContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.revokeSelectedOrder
                        chainContext.map
                        chainContext.units
                        chainContext.playerNumbers
                        >> fixtureValue
                   )

        rendezvousContext : BoardFixture
        rendezvousContext =
            board [ infantry, truck, unit passengerId Kind.FieldGun (Location.OnMap { x = 2, y = 1 }) ]

        rendezvous : OrderPlanning.Model
        rendezvous =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        { x = 2, y = 2 }
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectUnit
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        { x = 2, y = 2 }
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectUnit
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        passengerId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        { x = 2, y = 2 }
                        >> fixtureValue
                   )

        pickupRendezvous : OrderPlanning.Model
        pickupRendezvous =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        { x = 2, y = 1 }
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectUnit
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        { x = 2, y = 1 }
                        >> fixtureValue
                   )

        freightRendezvousContext : BoardFixture
        freightRendezvousContext =
            let
                addCrate : UnitResources -> UnitResources
                addCrate resources =
                    resources
                        |> setResourcesSupplyCargo
                            [ { kind = ResourceKind.Supply
                              , current = 64
                              , maximum = 64
                              }
                            ]

                withCrate : Unit -> Unit
                withCrate cargoUnit =
                    if cargoUnit.id == truckId then
                        cargoUnit
                            |> Unit.setResources (Maybe.map addCrate cargoUnit.resources)

                    else
                        cargoUnit
            in
            { rendezvousContext | units = List.map withCrate rendezvousContext.units }

        freightRendezvous : OrderPlanning.Model
        freightRendezvous =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        { x = 2, y = 2 }
                        >> fixtureValue
                   )
                |> OrderPlanning.skipUnloading
                    freightRendezvousContext.map
                    freightRendezvousContext.units
                    freightRendezvousContext.supplyCrates
                    freightRendezvousContext.depots
                |> (OrderPlanning.selectUnit
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        { x = 2, y = 2 }
                        >> fixtureValue
                   )

        overfullRendezvous : OrderPlanning.Model
        overfullRendezvous =
            freightRendezvous
                |> (OrderPlanning.selectUnit
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        passengerId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        freightRendezvousContext.map
                        freightRendezvousContext.units
                        freightRendezvousContext.playerNumbers
                        freightRendezvousContext.movementRules
                        freightRendezvousContext.supplyCrates
                        freightRendezvousContext.depots
                        { x = 2, y = 2 }
                        >> fixtureValue
                   )

        revokedRendezvous : OrderPlanning.Model
        revokedRendezvous =
            rendezvous
                |> (OrderPlanning.selectUnit
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        rendezvousContext.movementRules
                        rendezvousContext.supplyCrates
                        rendezvousContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.revokeSelectedOrder
                        rendezvousContext.map
                        rendezvousContext.units
                        rendezvousContext.playerNumbers
                        >> fixtureValue
                   )

        loading : OrderPlanning.Model
        loading =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        { x = 3, y = 1 }
                        >> fixtureValue
                   )

        receiving : OrderPlanning.Model
        receiving =
            (OrderPlanning.selectUnit
                context.map
                context.units
                context.playerNumbers
                context.movementRules
                context.supplyCrates
                context.depots
                truckId
                >> fixtureValue
            )
                loading

        revoked : OrderPlanning.Model
        revoked =
            loading
                |> (OrderPlanning.revokeSelectedOrder context.map context.units context.playerNumbers >> fixtureValue)
                |> (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.revokeSelectedOrder context.map context.units context.playerNumbers >> fixtureValue)

        cargoContext : BoardFixture
        cargoContext =
            board
                [ truck
                , unit infantryId Kind.Infantry (Location.Aboard truckId)
                , unit passengerId Kind.FieldGun (Location.Aboard truckId)
                ]

        checklist : OrderPlanning.Model
        checklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )

        exits : OrderPlanning.Model
        exits =
            checklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> (OrderPlanning.confirmPassengers
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        >> fixtureValue
                   )

        firstExit : OrderPlanning.Model
        firstExit =
            (OrderPlanning.chooseUnloadSquare
                cargoContext.map
                cargoContext.units
                cargoContext.playerNumbers
                cargoContext.movementRules
                cargoContext.supplyCrates
                cargoContext.depots
                { x = 3, y = 2 }
                >> fixtureValue
            )
                exits

        rejectedExit : OrderPlanning.Model
        rejectedExit =
            (OrderPlanning.chooseUnloadSquare
                cargoContext.map
                cargoContext.units
                cargoContext.playerNumbers
                cargoContext.movementRules
                cargoContext.supplyCrates
                cargoContext.depots
                { x = 3, y = 2 }
                >> fixtureValue
            )
                firstExit

        completed : OrderPlanning.Model
        completed =
            (OrderPlanning.chooseUnloadSquare
                cargoContext.map
                cargoContext.units
                cargoContext.playerNumbers
                cargoContext.movementRules
                cargoContext.supplyCrates
                cargoContext.depots
                { x = 4, y = 1 }
                >> fixtureValue
            )
                rejectedExit

        truckMove : OrderPlanning.Model
        truckMove =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        { x = 4, y = 1 }
                        >> fixtureValue
                   )
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> (OrderPlanning.confirmPassengers
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        >> fixtureValue
                   )
                |> (OrderPlanning.chooseUnloadSquare
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        { x = 5, y = 1 }
                        >> fixtureValue
                   )

        twoInfantryContext : BoardFixture
        twoInfantryContext =
            board
                [ truck
                , unit infantryId Kind.Infantry (Location.Aboard truckId)
                , unit passengerId Kind.Infantry (Location.Aboard truckId)
                ]

        twoInfantryReady : OrderPlanning.Model
        twoInfantryReady =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        twoInfantryContext.movementRules
                        twoInfantryContext.supplyCrates
                        twoInfantryContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        twoInfantryContext.movementRules
                        twoInfantryContext.supplyCrates
                        twoInfantryContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> (OrderPlanning.confirmPassengers
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        twoInfantryContext.movementRules
                        twoInfantryContext.supplyCrates
                        twoInfantryContext.depots
                        >> fixtureValue
                   )
                |> (OrderPlanning.chooseUnloadSquare
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        twoInfantryContext.movementRules
                        twoInfantryContext.supplyCrates
                        twoInfantryContext.depots
                        { x = 3, y = 2 }
                        >> fixtureValue
                   )
                |> (OrderPlanning.chooseUnloadSquare
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        twoInfantryContext.movementRules
                        twoInfantryContext.supplyCrates
                        twoInfantryContext.depots
                        { x = 4, y = 1 }
                        >> fixtureValue
                   )

        secondInfantryCommand : OrderPlanning.Model
        secondInfantryCommand =
            twoInfantryReady
                |> (OrderPlanning.applyCommand
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        twoInfantryContext.movementRules
                        twoInfantryContext.supplyCrates
                        twoInfantryContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )

        bothInfantryCommanded : OrderPlanning.Model
        bothInfantryCommanded =
            secondInfantryCommand
                |> (OrderPlanning.applyCommand
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        twoInfantryContext.movementRules
                        twoInfantryContext.supplyCrates
                        twoInfantryContext.depots
                        UnitCommand.StandGround
                        >> fixtureValue
                   )
                |> (OrderPlanning.saveDirection
                        twoInfantryContext.map
                        twoInfantryContext.units
                        twoInfantryContext.playerNumbers
                        DirectionEnum.East
                        >> fixtureValue
                   )

        dismountAttack : OrderPlanning.Model
        dismountAttack =
            completed
                |> (OrderPlanning.applyCommand
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        UnitCommand.AttackMove
                        >> fixtureValue
                   )
                |> OrderPlanning.extendPath
                    cargoContext.map
                    cargoContext.units
                    cargoContext.playerNumbers
                    cargoContext.movementRules
                    DirectionEnum.South
                |> (OrderPlanning.confirmPath
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        >> fixtureValue
                   )
                |> (OrderPlanning.saveDirection
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        DirectionEnum.East
                        >> fixtureValue
                   )

        dismountHold : OrderPlanning.Model
        dismountHold =
            completed
                |> (OrderPlanning.applyCommand
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )

        revokedDismount : OrderPlanning.Model
        revokedDismount =
            dismountHold
                |> (OrderPlanning.selectUnit
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        cargoContext.movementRules
                        cargoContext.supplyCrates
                        cargoContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.revokeSelectedOrder
                        cargoContext.map
                        cargoContext.units
                        cargoContext.playerNumbers
                        >> fixtureValue
                   )

        freightTruck : Unit
        freightTruck =
            truck
                |> Unit.setResources
                    (truck.resources
                        |> Maybe.map
                            (\resources ->
                                resources
                                    |> setResourcesSupplyCargo
                                        [ { kind = ResourceKind.Supply
                                          , current = 48
                                          , maximum = 64
                                          }
                                        ]
                            )
                    )

        mixedContext : BoardFixture
        mixedContext =
            board [ freightTruck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]

        mixedChecklist : OrderPlanning.Model
        mixedChecklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        mixedContext.map
                        mixedContext.units
                        mixedContext.playerNumbers
                        mixedContext.movementRules
                        mixedContext.supplyCrates
                        mixedContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        mixedContext.map
                        mixedContext.units
                        mixedContext.playerNumbers
                        mixedContext.movementRules
                        mixedContext.supplyCrates
                        mixedContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )

        mixedExits : OrderPlanning.Model
        mixedExits =
            mixedChecklist
                |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) True
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> (OrderPlanning.confirmPassengers
                        mixedContext.map
                        mixedContext.units
                        mixedContext.playerNumbers
                        mixedContext.movementRules
                        mixedContext.supplyCrates
                        mixedContext.depots
                        >> fixtureValue
                   )

        crateExit : OrderPlanning.Model
        crateExit =
            (OrderPlanning.chooseUnloadSquare mixedContext.map
                mixedContext.units
                mixedContext.playerNumbers
                mixedContext.movementRules
                mixedContext.supplyCrates
                mixedContext.depots
                { x = 3
                , y = 2
                }
                >> fixtureValue
            )
                mixedExits

        mixedComplete : OrderPlanning.Model
        mixedComplete =
            (OrderPlanning.chooseUnloadSquare mixedContext.map
                mixedContext.units
                mixedContext.playerNumbers
                mixedContext.movementRules
                mixedContext.supplyCrates
                mixedContext.depots
                { x = 4
                , y = 1
                }
                >> fixtureValue
            )
                crateExit

        passengerFirst : OrderPlanning.Model
        passengerFirst =
            mixedChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) True
                |> (OrderPlanning.confirmPassengers
                        mixedContext.map
                        mixedContext.units
                        mixedContext.playerNumbers
                        mixedContext.movementRules
                        mixedContext.supplyCrates
                        mixedContext.depots
                        >> fixtureValue
                   )
                |> (OrderPlanning.chooseUnloadSquare mixedContext.map
                        mixedContext.units
                        mixedContext.playerNumbers
                        mixedContext.movementRules
                        mixedContext.supplyCrates
                        mixedContext.depots
                        { x = 3
                        , y = 2
                        }
                        >> fixtureValue
                   )

        crateOnlyContext : BoardFixture
        crateOnlyContext =
            board [ freightTruck ]

        crateOnlyMove : OrderPlanning.Model
        crateOnlyMove =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        crateOnlyContext.map
                        crateOnlyContext.units
                        crateOnlyContext.playerNumbers
                        crateOnlyContext.movementRules
                        crateOnlyContext.supplyCrates
                        crateOnlyContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        crateOnlyContext.map
                        crateOnlyContext.units
                        crateOnlyContext.playerNumbers
                        crateOnlyContext.movementRules
                        crateOnlyContext.supplyCrates
                        crateOnlyContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile crateOnlyContext.map
                        crateOnlyContext.units
                        crateOnlyContext.playerNumbers
                        crateOnlyContext.movementRules
                        crateOnlyContext.supplyCrates
                        crateOnlyContext.depots
                        { x = 4
                        , y = 1
                        }
                        >> fixtureValue
                   )

        twoCrateTruck : Unit
        twoCrateTruck =
            truck
                |> Unit.setResources
                    (truck.resources
                        |> Maybe.map
                            (\resources ->
                                resources
                                    |> setResourcesSupplyCargo
                                        [ { kind = ResourceKind.Supply
                                          , current = 48
                                          , maximum = 64
                                          }
                                        , { kind = ResourceKind.Supply
                                          , current = 16
                                          , maximum = 64
                                          }
                                        ]
                            )
                    )

        twoCrateContext : BoardFixture
        twoCrateContext =
            board [ twoCrateTruck ]

        selectedSecondCrate : OrderPlanning.Model
        selectedSecondCrate =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        twoCrateContext.map
                        twoCrateContext.units
                        twoCrateContext.playerNumbers
                        twoCrateContext.movementRules
                        twoCrateContext.supplyCrates
                        twoCrateContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        twoCrateContext.map
                        twoCrateContext.units
                        twoCrateContext.playerNumbers
                        twoCrateContext.movementRules
                        twoCrateContext.supplyCrates
                        twoCrateContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )
                |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) True
                |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 1) True
                |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) False
                |> (OrderPlanning.confirmPassengers
                        twoCrateContext.map
                        twoCrateContext.units
                        twoCrateContext.playerNumbers
                        twoCrateContext.movementRules
                        twoCrateContext.supplyCrates
                        twoCrateContext.depots
                        >> fixtureValue
                   )
                |> (OrderPlanning.chooseUnloadSquare twoCrateContext.map
                        twoCrateContext.units
                        twoCrateContext.playerNumbers
                        twoCrateContext.movementRules
                        twoCrateContext.supplyCrates
                        twoCrateContext.depots
                        { x = 3
                        , y = 2
                        }
                        >> fixtureValue
                   )

        blockedCrateContext : BoardFixture
        blockedCrateContext =
            mixedContext
                |> setBoardSupplyCrates
                    [ { position =
                            { x = 3
                            , y = 2
                            }
                      , stock =
                            { kind = ResourceKind.Supply
                            , current = 32
                            , maximum = 64
                            }
                      }
                    ]

        depotContext : BoardFixture
        depotContext =
            context
                |> setBoardDepots
                    [ { kind = BuildingKind.Supply
                      , position =
                            { x = 3
                            , y = 1
                            }
                      , stock =
                            Just
                                { current = 256
                                , maximum = 256
                                }
                      , hp =
                            { current = 3
                            , maximum = 3
                            }
                      }
                    , { kind = BuildingKind.Supply
                      , position =
                            { x = 4
                            , y = 1
                            }
                      , stock = Nothing
                      , hp =
                            { current = 3
                            , maximum = 3
                            }
                      }
                    ]

        fuelContext : BoardFixture
        fuelContext =
            { depotContext
                | depots =
                    List.map
                        (\depot ->
                            depot
                                |> setDepotKind BuildingKind.Fuel
                        )
                        depotContext.depots
            }

        fuelMove : OrderPlanning.Model
        fuelMove =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        fuelContext.map
                        fuelContext.units
                        fuelContext.playerNumbers
                        fuelContext.movementRules
                        fuelContext.supplyCrates
                        fuelContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        fuelContext.map
                        fuelContext.units
                        fuelContext.playerNumbers
                        fuelContext.movementRules
                        fuelContext.supplyCrates
                        fuelContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> OrderPlanning.extendPath
                    fuelContext.map
                    fuelContext.units
                    fuelContext.playerNumbers
                    fuelContext.movementRules
                    DirectionEnum.East
                |> (OrderPlanning.selectTile
                        fuelContext.map
                        fuelContext.units
                        fuelContext.playerNumbers
                        fuelContext.movementRules
                        fuelContext.supplyCrates
                        fuelContext.depots
                        { x = 4, y = 1 }
                        >> fixtureValue
                   )

        depotMovePreview : OrderPlanning.Model
        depotMovePreview =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        depotContext.map
                        depotContext.units
                        depotContext.playerNumbers
                        depotContext.movementRules
                        depotContext.supplyCrates
                        depotContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        depotContext.map
                        depotContext.units
                        depotContext.playerNumbers
                        depotContext.movementRules
                        depotContext.supplyCrates
                        depotContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> OrderPlanning.extendPath
                    depotContext.map
                    depotContext.units
                    depotContext.playerNumbers
                    depotContext.movementRules
                    DirectionEnum.East

        depotMove : OrderPlanning.Model
        depotMove =
            (OrderPlanning.selectTile
                depotContext.map
                depotContext.units
                depotContext.playerNumbers
                depotContext.movementRules
                depotContext.supplyCrates
                depotContext.depots
                { x = 4, y = 1 }
                >> fixtureValue
            )
                depotMovePreview

        depotKeyboardMove : OrderPlanning.Model
        depotKeyboardMove =
            (OrderPlanning.confirmPath
                depotContext.map
                depotContext.units
                depotContext.playerNumbers
                depotContext.movementRules
                depotContext.supplyCrates
                depotContext.depots
                >> fixtureValue
            )
                depotMovePreview

        depotBoarding : OrderPlanning.Model
        depotBoarding =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        depotContext.map
                        depotContext.units
                        depotContext.playerNumbers
                        depotContext.movementRules
                        depotContext.supplyCrates
                        depotContext.depots
                        infantryId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        depotContext.map
                        depotContext.units
                        depotContext.playerNumbers
                        depotContext.movementRules
                        depotContext.supplyCrates
                        depotContext.depots
                        UnitCommand.Move
                        >> fixtureValue
                   )
                |> (OrderPlanning.selectTile
                        depotContext.map
                        depotContext.units
                        depotContext.playerNumbers
                        depotContext.movementRules
                        depotContext.supplyCrates
                        depotContext.depots
                        { x = 3, y = 1 }
                        >> fixtureValue
                   )

        depotHold : OrderPlanning.Model
        depotHold =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        depotContext.map
                        depotContext.units
                        depotContext.playerNumbers
                        depotContext.movementRules
                        depotContext.supplyCrates
                        depotContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        depotContext.map
                        depotContext.units
                        depotContext.playerNumbers
                        depotContext.movementRules
                        depotContext.supplyCrates
                        depotContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )

        dismissedDepot : OrderPlanning.Model
        dismissedDepot =
            OrderPlanning.dismissDialog depotMove

        depotCargoContext : BoardFixture
        depotCargoContext =
            cargoContext
                |> setBoardDepots depotContext.depots

        depotChecklist : OrderPlanning.Model
        depotChecklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        depotCargoContext.map
                        depotCargoContext.units
                        depotCargoContext.playerNumbers
                        depotCargoContext.movementRules
                        depotCargoContext.supplyCrates
                        depotCargoContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        depotCargoContext.map
                        depotCargoContext.units
                        depotCargoContext.playerNumbers
                        depotCargoContext.movementRules
                        depotCargoContext.supplyCrates
                        depotCargoContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )

        depotExits : OrderPlanning.Model
        depotExits =
            depotChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> (OrderPlanning.confirmPassengers
                        depotCargoContext.map
                        depotCargoContext.units
                        depotCargoContext.playerNumbers
                        depotCargoContext.movementRules
                        depotCargoContext.supplyCrates
                        depotCargoContext.depots
                        >> fixtureValue
                   )

        depotFirstExit : OrderPlanning.Model
        depotFirstExit =
            (OrderPlanning.chooseUnloadSquare
                depotCargoContext.map
                depotCargoContext.units
                depotCargoContext.playerNumbers
                depotCargoContext.movementRules
                depotCargoContext.supplyCrates
                depotCargoContext.depots
                { x = 3, y = 2 }
                >> fixtureValue
            )
                depotExits

        depotCompleted : OrderPlanning.Model
        depotCompleted =
            (OrderPlanning.chooseUnloadSquare
                depotCargoContext.map
                depotCargoContext.units
                depotCargoContext.playerNumbers
                depotCargoContext.movementRules
                depotCargoContext.supplyCrates
                depotCargoContext.depots
                { x = 4, y = 1 }
                >> fixtureValue
            )
                depotFirstExit

        depotMixedContext : BoardFixture
        depotMixedContext =
            mixedContext
                |> setBoardDepots depotContext.depots

        depotCrateUnloaded : OrderPlanning.Model
        depotCrateUnloaded =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        depotMixedContext.map
                        depotMixedContext.units
                        depotMixedContext.playerNumbers
                        depotMixedContext.movementRules
                        depotMixedContext.supplyCrates
                        depotMixedContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        depotMixedContext.map
                        depotMixedContext.units
                        depotMixedContext.playerNumbers
                        depotMixedContext.movementRules
                        depotMixedContext.supplyCrates
                        depotMixedContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )
                |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) True
                |> (OrderPlanning.confirmPassengers
                        depotMixedContext.map
                        depotMixedContext.units
                        depotMixedContext.playerNumbers
                        depotMixedContext.movementRules
                        depotMixedContext.supplyCrates
                        depotMixedContext.depots
                        >> fixtureValue
                   )
                |> (OrderPlanning.chooseUnloadSquare
                        depotMixedContext.map
                        depotMixedContext.units
                        depotMixedContext.playerNumbers
                        depotMixedContext.movementRules
                        depotMixedContext.supplyCrates
                        depotMixedContext.depots
                        { x = 3, y = 2 }
                        >> fixtureValue
                   )

        choosingCrates : OrderPlanning.Model -> Bool
        choosingCrates state =
            case state of
                OrderPlanning.ChoosingCrates id source _ ->
                    (id == truckId)
                        && List.member source (List.filterMap Depot.loadingSource (depotContext.depots ++ fuelContext.depots))

                _ ->
                    False

        putTruckAtCorner : Unit -> Unit
        putTruckAtCorner current =
            if current.id == truckId then
                Unit.setOnMap { x = 3, y = 0 } current

            else
                current

        narrowContext : BoardFixture
        narrowContext =
            cargoContext
                |> setBoardMap (Map.fromFeatures { width = 4, height = 1, baseTile = cargoContext.map.baseTile, features = [], theme = cargoContext.map.theme })
                |> setBoardUnits
                    (List.map putTruckAtCorner
                        cargoContext.units
                    )

        narrowChecklist : OrderPlanning.Model
        narrowChecklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        narrowContext.map
                        narrowContext.units
                        narrowContext.playerNumbers
                        narrowContext.movementRules
                        narrowContext.supplyCrates
                        narrowContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        narrowContext.map
                        narrowContext.units
                        narrowContext.playerNumbers
                        narrowContext.movementRules
                        narrowContext.supplyCrates
                        narrowContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )
                |> (OrderPlanning.toggleAvailableUnloadCargo
                        narrowContext.map
                        narrowContext.units
                        narrowContext.playerNumbers
                        narrowContext.movementRules
                        narrowContext.supplyCrates
                        (UnloadCargo.Passenger infantryId)
                        True
                        >> fixtureValue
                   )

        narrowCrateContext : BoardFixture
        narrowCrateContext =
            { twoCrateContext | map = narrowContext.map, units = List.map (Unit.setOnMap { x = 3, y = 0 }) twoCrateContext.units }

        narrowCrateChecklist : OrderPlanning.Model
        narrowCrateChecklist =
            OrderPlanning.init
                |> (OrderPlanning.selectUnit
                        narrowCrateContext.map
                        narrowCrateContext.units
                        narrowCrateContext.playerNumbers
                        narrowCrateContext.movementRules
                        narrowCrateContext.supplyCrates
                        narrowCrateContext.depots
                        truckId
                        >> fixtureValue
                   )
                |> (OrderPlanning.applyCommand
                        narrowCrateContext.map
                        narrowCrateContext.units
                        narrowCrateContext.playerNumbers
                        narrowCrateContext.movementRules
                        narrowCrateContext.supplyCrates
                        narrowCrateContext.depots
                        UnitCommand.HoldPosition
                        >> fixtureValue
                   )
                |> (OrderPlanning.toggleAvailableUnloadCargo
                        narrowCrateContext.map
                        narrowCrateContext.units
                        narrowCrateContext.playerNumbers
                        narrowCrateContext.movementRules
                        narrowCrateContext.supplyCrates
                        (UnloadCargo.Crate 0)
                        True
                        >> fixtureValue
                   )

        scarceCrateContext : BoardFixture
        scarceCrateContext =
            mixedContext
                |> setBoardMap (Map.fromFeatures { width = 4, height = 2, baseTile = mixedContext.map.baseTile, theme = mixedContext.map.theme, features = [] })
                |> setBoardSupplyCrates
                    [ { position =
                            { x = 3
                            , y = 0
                            }
                      , stock =
                            { kind = ResourceKind.Supply
                            , current = 64
                            , maximum = 64
                            }
                      }
                    ]

        scarceCrateExits : OrderPlanning.Model
        scarceCrateExits =
            mixedChecklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) True
                |> (OrderPlanning.confirmPassengers
                        scarceCrateContext.map
                        scarceCrateContext.units
                        scarceCrateContext.playerNumbers
                        scarceCrateContext.movementRules
                        scarceCrateContext.supplyCrates
                        scarceCrateContext.depots
                        >> fixtureValue
                   )

        exhaustedContext : BoardFixture
        exhaustedContext =
            let
                exhaustPassenger : Unit -> Unit
                exhaustPassenger passenger =
                    if passenger.id == infantryId then
                        passenger
                            |> Unit.setResources (Maybe.map exhaustResources passenger.resources)

                    else
                        passenger

                exhaustResources : UnitResources.UnitResources -> UnitResources.UnitResources
                exhaustResources resources =
                    let
                        supplies : Game.Unit.Supplies.Supplies
                        supplies =
                            resources.supplies
                    in
                    resources
                        |> UnitResources.setSupplies
                            { supplies | current = 1 }
            in
            cargoContext
                |> setBoardUnits (List.map exhaustPassenger cargoContext.units)

        submitted : TurnLifecycle.Phase
        submitted =
            TurnLifecycle.startSubmission 1 (TurnLifecycle.Planning saved)

        ordersForSubmission : List PlannedOrder.PlannedOrder
        ordersForSubmission =
            OrderPlanning.submissionOrders
                cargoContext.map
                cargoContext.units
                cargoContext.playerNumbers
                (OrderPlanning.orders completed)

        firstUnordered : OrderPlanning.Model
        firstUnordered =
            OrderPlanning.selectNextUnorderedUnit context.map context.units context.playerNumbers OrderPlanning.init

        secondUnordered : OrderPlanning.Model
        secondUnordered =
            OrderPlanning.selectNextUnorderedUnit context.map context.units context.playerNumbers firstUnordered

        wrappedUnordered : OrderPlanning.Model
        wrappedUnordered =
            OrderPlanning.selectNextUnorderedUnit context.map context.units context.playerNumbers secondUnordered

        afterPreview : OrderPlanning.Model
        afterPreview =
            OrderPlanning.selectNextUnorderedUnit context.map context.units context.playerNumbers moving

        afterOrder : OrderPlanning.Model
        afterOrder =
            OrderPlanning.selectNextUnorderedUnit context.map context.units context.playerNumbers saved

        guideMenu : OrderPlanning.Model
        guideMenu =
            afterOrder
                |> OrderPlanning.focusCommand context.map context.units (UnitCommand.CommandOption UnitCommand.Move)

        readingGuide : OrderPlanning.Model
        readingGuide =
            OrderPlanning.openCommandGuide context.map context.units context.playerNumbers guideMenu

        guideLocked : TurnLifecycle.Phase
        guideLocked =
            TurnLifecycle.observeSubmission True (TurnLifecycle.Planning readingGuide)

        missingContext : BoardFixture
        missingContext =
            board [ truck ]

        missingCommand : OrderPlanning.Model
        missingCommand =
            OrderPlanning.init
                |> OrderPlanning.setOrders [ { unitId = truckId, action = PlannedOrder.Hold { x = 3, y = 1 } } ]
                |> OrderPlanning.setSelection (Just (UnitSelection { id = infantryId, interaction = CommandMenu (ChoosingCommand Nothing) }))

        missingCommandCheck : InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
        missingCommandCheck =
            OrderPlanning.applyCommand
                missingContext.map
                missingContext.units
                missingContext.playerNumbers
                missingContext.movementRules
                missingContext.supplyCrates
                missingContext.depots
                UnitCommand.Move
                missingCommand

        missingNextPassenger : InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
        missingNextPassenger =
            OrderPlanning.chooseUnloadSquare
                (.map (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                (.units (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                (.playerNumbers (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                (.movementRules (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                (.supplyCrates (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                (.depots (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                { x = 3, y = 2 }
                exits

        savedAttackWithMissingUnit : InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
        savedAttackWithMissingUnit =
            OrderPlanning.saveDirection
                missingContext.map
                missingContext.units
                missingContext.playerNumbers
                DirectionEnum.North
                attackAiming

        initialTurn : CurrentTurn.Model
        initialTurn =
            CurrentTurn.init { turn = { number = 1, submitted = False, opponentSubmitted = False, outcome = Nothing, resolution = Nothing }, playbackFrames = [] }

        brokenTurn : CurrentTurn.Model
        brokenTurn =
            initialTurn
                |> CurrentTurn.setPhase (TurnLifecycle.Planning missingCommand)

        checkedTurn : InvariantCheck Error.Error CurrentTurn.Model
        checkedTurn =
            CurrentTurn.mapPlanning
                (OrderPlanning.applyCommand
                    missingContext.map
                    missingContext.units
                    missingContext.playerNumbers
                    missingContext.movementRules
                    missingContext.supplyCrates
                    missingContext.depots
                    UnitCommand.Move
                )
                brokenTurn
                |> IC.mapError Error.OrderPlanningInvariantViolated

        silentNoOp : (OrderPlanning.Model -> InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model) -> Bool
        silentNoOp transition =
            transition OrderPlanning.init == IC.happy OrderPlanning.init

        missingPassengerAvailability : InvariantCheck OrderPlanning.InvariantViolation Bool
        missingPassengerAvailability =
            OrderPlanning.canSelectUnloadCargo
                missingContext.map
                missingContext.units
                missingContext.playerNumbers
                missingContext.movementRules
                missingContext.supplyCrates
                (UnloadCargo.Passenger infantryId)
                checklist

        toggleMissingPassenger : Bool -> OrderPlanning.Model -> InvariantCheck OrderPlanning.InvariantViolation OrderPlanning.Model
        toggleMissingPassenger =
            OrderPlanning.toggleAvailableUnloadCargo
                missingContext.map
                missingContext.units
                missingContext.playerNumbers
                missingContext.movementRules
                missingContext.supplyCrates
                (UnloadCargo.Passenger infantryId)

        resolvedMissingPassenger : Maybe OrderPlanning.InvariantViolation -> Bool -> Bool
        resolvedMissingPassenger violation available =
            (violation == Just (OrderPlanning.PlanningUnitNotFound infantryId))
                && not available
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
                && (fixtureValue checkedTurn).phase
                == brokenTurn.phase
            )
        , expect "failed direction lookup keeps its existing state"
            (OrderPlanning.saveDirection
                missingContext.map
                missingContext.units
                missingContext.playerNumbers
                DirectionEnum.North
                choosingStandGround
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) choosingStandGround
            )
        , expect "missing required board positions are reported at the direction save"
            (OrderPlanning.saveDirection
                cargoContext.map
                cargoContext.units
                cargoContext.playerNumbers
                DirectionEnum.North
                choosingStandGround
                == IC.violated (OrderPlanning.DirectionInvariantViolated (DirectionPlanning.CommandUnitNotOnMap infantryId)) choosingStandGround
            )
        , expect "a missing indirect firing unit retains targeting and existing drafts"
            (OrderPlanning.selectTile missingContext.map missingContext.units missingContext.playerNumbers missingContext.movementRules missingContext.supplyCrates missingContext.depots { x = 2, y = 1 } aiming
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) aiming
            )
        , expect "indirect firing position diagnostics propagate without changing targeting or drafts"
            (OrderPlanning.selectTile cargoContext.map cargoContext.units cargoContext.playerNumbers cargoContext.movementRules cargoContext.supplyCrates cargoContext.depots { x = 2, y = 1 } aiming
                == IC.violated (OrderPlanning.IndirectFireInvariantViolated (IndirectFirePlanning.CommandUnitNotOnMap infantryId)) aiming
            )
        , expect "failed movement lookup retains the original tile-inspection fallback"
            (OrderPlanning.confirmPath
                missingContext.map
                missingContext.units
                missingContext.playerNumbers
                missingContext.movementRules
                missingContext.supplyCrates
                missingContext.depots
                moving
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId)
                    (OrderPlanning.setSelection (Just (Inspecting (TileInspection { x = 1, y = 2 }))) moving)
            )
        , expect "a failure after saving an attack order does not roll the order back"
            (IC.error savedAttackWithMissingUnit
                == Just (OrderPlanning.PlanningUnitNotFound infantryId)
                && List.map .unitId (OrderPlanning.orders (fixtureValue savedAttackWithMissingUnit))
                == [ infantryId ]
                && OrderPlanning.selection (fixtureValue savedAttackWithMissingUnit)
                == OrderPlanning.selection attackAiming
            )
        , expect "missing unload passengers report the failed option lookup without canceling the checklist"
            (let
                selected : OrderPlanning.Model
                selected =
                    OrderPlanning.toggleUnloadPassenger infantryId True checklist
             in
             OrderPlanning.confirmPassengers
                missingContext.map
                missingContext.units
                missingContext.playerNumbers
                missingContext.movementRules
                missingContext.supplyCrates
                missingContext.depots
                selected
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) selected
            )
        , expect "cargo eligibility preserves a missing passenger diagnostic and its unavailable fallback"
            (missingPassengerAvailability
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) False
            )
        , expect "resolving a check receives both the diagnostic and retained value"
            (IC.resolve resolvedMissingPassenger missingPassengerAvailability)
        , expect "toggling cargo preserves eligibility diagnostics without changing the checklist"
            (toggleMissingPassenger True checklist
                == IC.violated (OrderPlanning.PlanningUnitNotFound infantryId) checklist
            )
        , expect "broken cargo can still be unchecked without a lookup or diagnostic"
            (toggleMissingPassenger False (OrderPlanning.toggleUnloadPassenger infantryId True checklist)
                == IC.happy checklist
            )
        , expect "cargo toggle diagnostics propagate through the current turn"
            (CurrentTurn.mapPlanning (toggleMissingPassenger True)
                (initialTurn
                    |> CurrentTurn.setPhase (TurnLifecycle.Planning checklist)
                )
                |> IC.error
                |> (==) (Just (OrderPlanning.PlanningUnitNotFound infantryId))
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
                        (.map (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                        (.units (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                        (.playerNumbers (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                        (.movementRules (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                        (.supplyCrates (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                        (.depots (board [ truck, unit infantryId Kind.Infantry (Location.Aboard truckId) ]))
                        selected
             in
             checked == IC.violated (OrderPlanning.PlanningUnitNotFound passengerId) selected
            )
        , expect "a missing next passenger retains the exit already saved and the next empty picker"
            (IC.error missingNextPassenger
                == Just (OrderPlanning.PlanningUnitNotFound passengerId)
                && List.concatMap PlannedOrder.unloads (OrderPlanning.orders (fixtureValue missingNextPassenger))
                == [ { unitId = infantryId, destination = { x = 3, y = 2 } } ]
                && Maybe.map .cargo (OrderPlanning.unloadPlanning (fixtureValue missingNextPassenger))
                == Just (UnloadCargo.Passenger passengerId)
                && List.isEmpty (OrderPlanning.moveOptions (fixtureValue missingNextPassenger))
            )
        , expect "checked composition continues with the fallback value while retaining its diagnostic"
            (missingCommandCheck
                |> IC.andThen
                    (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                    )
                |> fixtureValue
                |> OrderPlanning.selection
                |> (==) (Just (Inspecting (UnitInspection truckId)))
            )
        , expect "checked composition retains the first diagnostic"
            (missingCommandCheck
                |> IC.andThen
                    (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                    )
                |> IC.error
                |> (==) (Just (OrderPlanning.PlanningUnitNotFound infantryId))
            )
        , expect "no selection, stale clicks, absent previews and out-of-phase actions remain silent"
            (List.all silentNoOp
                [ OrderPlanning.applyCommand
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    context.supplyCrates
                    context.depots
                    UnitCommand.Move
                , OrderPlanning.confirmPath
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    context.supplyCrates
                    context.depots
                , OrderPlanning.saveDirection context.map context.units context.playerNumbers DirectionEnum.North
                , OrderPlanning.confirmPassengers
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    context.supplyCrates
                    context.depots
                , OrderPlanning.revokeSelectedOrder context.map context.units context.playerNumbers
                , OrderPlanning.selectUnit
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    context.supplyCrates
                    context.depots
                    passengerId
                ]
            )
        , expect "unreachable destinations and reverse attack facing remain ordinary validation"
            (IC.error
                (OrderPlanning.selectTile
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    context.supplyCrates
                    context.depots
                    { x = -1, y = -1 }
                    moving
                )
                == Nothing
                && OrderPlanning.saveDirection
                    attackContext.map
                    attackContext.units
                    attackContext.playerNumbers
                    DirectionEnum.West
                    attackAiming
                == IC.happy attackAiming
            )
        , expect "unavailable commands remain silent"
            (OrderPlanning.applyCommand context.map
                context.units
                context.playerNumbers
                context.movementRules
                context.supplyCrates
                context.depots
                UnitCommand.Ambush
                (fixtureValue
                    (OrderPlanning.selectUnit
                        context.map
                        context.units
                        context.playerNumbers
                        context.movementRules
                        context.supplyCrates
                        context.depots
                        truckId
                        OrderPlanning.init
                    )
                )
                |> IC.error
                |> (==) Nothing
            )
        , expect "stale inspections remain silent"
            (let
                stale : OrderPlanning.Model
                stale =
                    OrderPlanning.setSelection (Just (Inspecting (UnitInspection passengerId))) OrderPlanning.init
             in
             OrderPlanning.restoreCommands context.map context.units context.playerNumbers stale == IC.happy stale
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
            (OrderPlanning.openCommandGuide context.map context.units context.playerNumbers OrderPlanning.init
                == OrderPlanning.init
                && OrderPlanning.openCommandGuide context.map context.units context.playerNumbers moving
                == moving
                && OrderPlanning.openCommandGuide context.map context.units context.playerNumbers crateChoice
                == crateChoice
                && OrderPlanning.openCommandGuide
                    context.map
                    context.units
                    context.playerNumbers
                    (OrderPlanning.showSubmissionWarning guideMenu)
                == OrderPlanning.showSubmissionWarning guideMenu
            )
        , expect "command guide blocks command edits, unit cycling and submission"
            ((OrderPlanning.applyCommand
                context.map
                context.units
                context.playerNumbers
                context.movementRules
                context.supplyCrates
                context.depots
                UnitCommand.HoldPosition
                >> fixtureValue
             )
                readingGuide
                == readingGuide
                && OrderPlanning.focusCommand context.map context.units UnitCommand.CancelOption readingGuide
                == readingGuide
                && OrderPlanning.selectNextUnorderedUnit context.map context.units context.playerNumbers readingGuide
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
                        |> (OrderPlanning.chooseUnloadSquare
                                scarceCrateContext.map
                                scarceCrateContext.units
                                scarceCrateContext.playerNumbers
                                scarceCrateContext.movementRules
                                scarceCrateContext.supplyCrates
                                scarceCrateContext.depots
                                { x = 2, y = 1 }
                                >> fixtureValue
                           )
                        |> (OrderPlanning.chooseUnloadSquare
                                scarceCrateContext.map
                                scarceCrateContext.units
                                scarceCrateContext.playerNumbers
                                scarceCrateContext.movementRules
                                scarceCrateContext.supplyCrates
                                scarceCrateContext.depots
                                { x = 2, y = 1 }
                                >> fixtureValue
                           )
             in
             OrderPlanning.unloadPlanning complete
                == Nothing
                && List.length (List.concatMap PlannedOrder.crateUnloads (OrderPlanning.orders complete))
                == 1
            )
        , expect "passengers without walking supplies cannot be selected"
            (not
                (fixtureValue
                    (OrderPlanning.canSelectUnloadCargo
                        exhaustedContext.map
                        exhaustedContext.units
                        exhaustedContext.playerNumbers
                        exhaustedContext.movementRules
                        exhaustedContext.supplyCrates
                        (UnloadCargo.Passenger infantryId)
                        checklist
                    )
                )
            )
        , expect "invalid full selections stay in the checklist on confirmation"
            (let
                invalidSelection : OrderPlanning.Model
                invalidSelection =
                    narrowChecklist |> OrderPlanning.toggleUnloadPassenger passengerId True
             in
             (OrderPlanning.confirmPassengers
                narrowContext.map
                narrowContext.units
                narrowContext.playerNumbers
                narrowContext.movementRules
                narrowContext.supplyCrates
                narrowContext.depots
                >> fixtureValue
             )
                invalidSelection
                == invalidSelection
            )
        , expect "one passenger exit disables the second passenger and rejects its toggle"
            (not
                (fixtureValue
                    (OrderPlanning.canSelectUnloadCargo
                        narrowContext.map
                        narrowContext.units
                        narrowContext.playerNumbers
                        narrowContext.movementRules
                        narrowContext.supplyCrates
                        (UnloadCargo.Passenger passengerId)
                        narrowChecklist
                    )
                )
                && fixtureValue
                    (OrderPlanning.toggleAvailableUnloadCargo
                        narrowContext.map
                        narrowContext.units
                        narrowContext.playerNumbers
                        narrowContext.movementRules
                        narrowContext.supplyCrates
                        (UnloadCargo.Passenger passengerId)
                        True
                        narrowChecklist
                    )
                == narrowChecklist
                && fixtureValue
                    (OrderPlanning.canSelectUnloadCargo
                        narrowContext.map
                        narrowContext.units
                        narrowContext.playerNumbers
                        narrowContext.movementRules
                        narrowContext.supplyCrates
                        (UnloadCargo.Passenger infantryId)
                        narrowChecklist
                    )
            )
        , expect "one crate exit disables the second crate"
            (not
                (fixtureValue
                    (OrderPlanning.canSelectUnloadCargo
                        narrowCrateContext.map
                        narrowCrateContext.units
                        narrowCrateContext.playerNumbers
                        narrowCrateContext.movementRules
                        narrowCrateContext.supplyCrates
                        (UnloadCargo.Crate 1)
                        narrowCrateChecklist
                    )
                )
            )
        , expect "unchecking cargo frees the only exit for the other passenger"
            (fixtureValue
                (OrderPlanning.canSelectUnloadCargo narrowContext.map
                    narrowContext.units
                    narrowContext.playerNumbers
                    narrowContext.movementRules
                    narrowContext.supplyCrates
                    (UnloadCargo.Passenger passengerId)
                    (fixtureValue
                        (OrderPlanning.toggleAvailableUnloadCargo
                            narrowContext.map
                            narrowContext.units
                            narrowContext.playerNumbers
                            narrowContext.movementRules
                            narrowContext.supplyCrates
                            (UnloadCargo.Passenger infantryId)
                            False
                            narrowChecklist
                        )
                    )
                )
            )
        , expect "mixed cargo shares the only adjacent square"
            (let
                contextWithFreight : BoardFixture
                contextWithFreight =
                    { narrowContext | units = Unit.setOnMap { x = 3, y = 0 } freightTruck :: List.filter (\u -> u.id == infantryId) narrowContext.units }

                selectionWithFreight : OrderPlanning.Model
                selectionWithFreight =
                    OrderPlanning.init
                        |> (OrderPlanning.selectUnit
                                contextWithFreight.map
                                contextWithFreight.units
                                contextWithFreight.playerNumbers
                                contextWithFreight.movementRules
                                contextWithFreight.supplyCrates
                                contextWithFreight.depots
                                truckId
                                >> fixtureValue
                           )
                        |> (OrderPlanning.applyCommand
                                contextWithFreight.map
                                contextWithFreight.units
                                contextWithFreight.playerNumbers
                                contextWithFreight.movementRules
                                contextWithFreight.supplyCrates
                                contextWithFreight.depots
                                UnitCommand.HoldPosition
                                >> fixtureValue
                           )
                        |> (OrderPlanning.toggleAvailableUnloadCargo
                                contextWithFreight.map
                                contextWithFreight.units
                                contextWithFreight.playerNumbers
                                contextWithFreight.movementRules
                                contextWithFreight.supplyCrates
                                (UnloadCargo.Passenger infantryId)
                                True
                                >> fixtureValue
                           )
                        |> (OrderPlanning.toggleAvailableUnloadCargo
                                contextWithFreight.map
                                contextWithFreight.units
                                contextWithFreight.playerNumbers
                                contextWithFreight.movementRules
                                contextWithFreight.supplyCrates
                                (UnloadCargo.Crate 0)
                                True
                                >> fixtureValue
                           )
                        |> (OrderPlanning.confirmPassengers
                                contextWithFreight.map
                                contextWithFreight.units
                                contextWithFreight.playerNumbers
                                contextWithFreight.movementRules
                                contextWithFreight.supplyCrates
                                contextWithFreight.depots
                                >> fixtureValue
                           )
                        |> (OrderPlanning.chooseUnloadSquare
                                contextWithFreight.map
                                contextWithFreight.units
                                contextWithFreight.playerNumbers
                                contextWithFreight.movementRules
                                contextWithFreight.supplyCrates
                                contextWithFreight.depots
                                { x = 2, y = 0 }
                                >> fixtureValue
                           )
                        |> (OrderPlanning.chooseUnloadSquare
                                contextWithFreight.map
                                contextWithFreight.units
                                contextWithFreight.playerNumbers
                                contextWithFreight.movementRules
                                contextWithFreight.supplyCrates
                                contextWithFreight.depots
                                { x = 2, y = 0 }
                                >> fixtureValue
                           )
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
                && not
                    (choosingCrates
                        (OrderPlanning.previewTile
                            depotContext.map
                            depotContext.units
                            depotContext.playerNumbers
                            depotContext.movementRules
                            { x = 4, y = 1 }
                            dismissedDepot
                        )
                    )
                && not
                    (choosingCrates
                        ((OrderPlanning.selectUnit
                            depotContext.map
                            depotContext.units
                            depotContext.playerNumbers
                            depotContext.movementRules
                            depotContext.supplyCrates
                            depotContext.depots
                            truckId
                            >> fixtureValue
                         )
                            dismissedDepot
                        )
                    )
                && OrderPlanning.orders dismissedDepot
                == OrderPlanning.orders depotMove
            )
        , expect "loaded trucks offer unloading before depot loading"
            (OrderPlanning.unloadChoice depotChecklist /= Nothing)
        , expect "full passenger trucks skip depot loading when unloading is declined"
            (not
                (choosingCrates
                    ((OrderPlanning.confirmPassengers
                        depotCargoContext.map
                        depotCargoContext.units
                        depotCargoContext.playerNumbers
                        depotCargoContext.movementRules
                        depotCargoContext.supplyCrates
                        depotCargoContext.depots
                        >> fixtureValue
                     )
                        depotChecklist
                    )
                )
                && not
                    (choosingCrates
                        (OrderPlanning.skipUnloading
                            depotCargoContext.map
                            depotCargoContext.units
                            depotCargoContext.supplyCrates
                            depotCargoContext.depots
                            depotChecklist
                        )
                    )
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

                moveContext : BoardFixture
                moveContext =
                    mixedContext
                        |> setBoardUnits (unit passengerId Kind.Infantry (Location.OnMap { x = 0, y = 0 }) :: mixedContext.units)

                movingChecklist : OrderPlanning.Model
                movingChecklist =
                    OrderPlanning.init
                        |> OrderPlanning.setOrders [ unrelatedOrder ]
                        |> (OrderPlanning.selectUnit
                                moveContext.map
                                moveContext.units
                                moveContext.playerNumbers
                                moveContext.movementRules
                                moveContext.supplyCrates
                                moveContext.depots
                                truckId
                                >> fixtureValue
                           )
                        |> (OrderPlanning.applyCommand
                                moveContext.map
                                moveContext.units
                                moveContext.playerNumbers
                                moveContext.movementRules
                                moveContext.supplyCrates
                                moveContext.depots
                                UnitCommand.Move
                                >> fixtureValue
                           )
                        |> (OrderPlanning.selectTile
                                moveContext.map
                                moveContext.units
                                moveContext.playerNumbers
                                moveContext.movementRules
                                moveContext.supplyCrates
                                moveContext.depots
                                { x = 4, y = 1 }
                                >> fixtureValue
                           )
                        |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) True

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
        , expect "passenger exits preserve the plan without offering loading into occupied berths"
            (not (choosingCrates depotCompleted)
                && List.concatMap PlannedOrder.unloads (OrderPlanning.orders depotCompleted)
                == List.concatMap PlannedOrder.unloads (OrderPlanning.orders completed)
                && not
                    (choosingCrates
                        (OrderPlanning.skipUnloading
                            depotCargoContext.map
                            depotCargoContext.units
                            depotCargoContext.supplyCrates
                            depotCargoContext.depots
                            depotFirstExit
                        )
                    )
                && List.concatMap PlannedOrder.unloads
                    (OrderPlanning.orders
                        (OrderPlanning.skipUnloading
                            depotCargoContext.map
                            depotCargoContext.units
                            depotCargoContext.supplyCrates
                            depotCargoContext.depots
                            depotFirstExit
                        )
                    )
                == [ { unitId = infantryId, destination = { x = 3, y = 2 } } ]
            )
        , expect "crate unloading on a depot completes without offering incompatible loading"
            (not (choosingCrates depotCrateUnloaded)
                && List.concatMap PlannedOrder.crateUnloads (OrderPlanning.orders depotCrateUnloaded)
                == [ { cargoIndex = 0, destination = { x = 3, y = 2 } } ]
            )
        , expect "crate loading dialog preserves drafts and blocks submission until dismissed"
            (OrderPlanning.selectNextUnorderedUnit context.map context.units context.playerNumbers crateChoice
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
                && (OrderPlanning.saveDirection
                        attackContext.map
                        attackContext.units
                        attackContext.playerNumbers
                        DirectionEnum.West
                        >> fixtureValue
                   )
                    attackAiming
                == attackAiming
            )
        , expect "attack facing restriction follows the last segment of a turning route"
            (Direction.reversesPath [ { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 2, y = 2 } ] DirectionEnum.North
                && not (Direction.reversesPath [ { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 2, y = 2 } ] DirectionEnum.West)
            )
        , expect "attack move previews reserve readiness and firing supplies"
            (OrderPlanning.pathPreview lowSupplyAttack |> Maybe.map (\option -> option.path == [ { x = 1, y = 1 }, { x = 2, y = 1 } ]) |> Maybe.withDefault False)
        , expect "attack move command requires readiness supplies before walking"
            (not
                (UnitCommand.canUse context.map
                    []
                    (lowSupplyInfantry
                        |> Unit.setResources
                            (Maybe.map
                                (\resources ->
                                    resources
                                        |> UnitResources.setSupplies
                                            { current = 5, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 }
                                )
                                lowSupplyInfantry.resources
                            )
                    )
                    UnitCommand.AttackMove
                )
            )
        , expect "attack move cannot board an allied truck"
            (List.isEmpty (OrderPlanning.orders attackLoading) && OrderPlanning.destinationFeedback attackLoading == DestinationUnavailable)
        , expect "saved orders can be revoked from inspection or a command menu"
            (OrderPlanning.canRevokeOrder context.map context.units context.playerNumbers infantryId saved
                && OrderPlanning.canRevokeOrder
                    context.map
                    context.units
                    context.playerNumbers
                    infantryId
                    ((OrderPlanning.restoreCommands
                        context.map
                        context.units
                        context.playerNumbers
                        >> fixtureValue
                     )
                        saved
                    )
                && not (OrderPlanning.canRevokeOrder context.map context.units context.playerNumbers truckId saved)
                && revocationBlocked context infantryId attackRevoked
            )
        , expect "unfinished action selection blocks both revoke controls and revoke events"
            (List.all previewRevocationBlocked
                [ moving
                , attacking
                , attackAiming
                , aiming
                , choosingStandGround
                , (OrderPlanning.applyCommand
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    context.supplyCrates
                    context.depots
                    UnitCommand.Ambush
                    >> fixtureValue
                  )
                    reopenedCommands
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
                && OrderPlanning.commandMenuUnit attackContext.map attackContext.units attackRevoked
                == Nothing
                && OrderPlanning.pathPreview attackRevoked
                == Nothing
            )
        , expect "back to commands drops movement previews and reopens the menu"
            (OrderPlanning.commandMenuUnit
                attackContext.map
                attackContext.units
                ((OrderPlanning.restoreCommands
                    attackContext.map
                    attackContext.units
                    attackContext.playerNumbers
                    >> fixtureValue
                 )
                    attacking
                )
                == Just infantry
                && OrderPlanning.pathPreview
                    ((OrderPlanning.restoreCommands
                        attackContext.map
                        attackContext.units
                        attackContext.playerNumbers
                        >> fixtureValue
                     )
                        attacking
                    )
                == Nothing
            )
        , expect "clicking the revoked unit reopens commands and clicking again deselects"
            (OrderPlanning.commandMenuUnit attackContext.map attackContext.units reopenedCommands
                == Just infantry
                && OrderPlanning.selection
                    ((OrderPlanning.selectUnit
                        attackContext.map
                        attackContext.units
                        attackContext.playerNumbers
                        attackContext.movementRules
                        attackContext.supplyCrates
                        attackContext.depots
                        infantryId
                        >> fixtureValue
                     )
                        reopenedCommands
                    )
                == Nothing
            )
        , expect "clicking a selected unit with a saved order still deselects without revoking"
            (OrderPlanning.selection
                ((OrderPlanning.selectUnit
                    attackContext.map
                    attackContext.units
                    attackContext.playerNumbers
                    attackContext.movementRules
                    attackContext.supplyCrates
                    attackContext.depots
                    infantryId
                    >> fixtureValue
                 )
                    attackSaved
                )
                == Nothing
                && OrderPlanning.orders
                    ((OrderPlanning.selectUnit
                        attackContext.map
                        attackContext.units
                        attackContext.playerNumbers
                        attackContext.movementRules
                        attackContext.supplyCrates
                        attackContext.depots
                        infantryId
                        >> fixtureValue
                     )
                        attackSaved
                    )
                == OrderPlanning.orders attackSaved
            )
        , expect "indirect fire chooses tiles without movement or occupancy restrictions"
            (OrderPlanning.choosingIndirectFire aiming
                && List.member { x = 3, y = 3 }
                    (OrderPlanning.indirectTargets
                        indirectContext.map
                        aiming
                    )
                && OrderPlanning.orders bombardment
                == [ aimedOrder { x = 3, y = 3 } ]
                && List.map PlannedOrder.path (OrderPlanning.orders bombardment)
                == [ [ { x = 1, y = 1 } ] ]
                && List.isEmpty
                    (OrderPlanning.orders
                        ((OrderPlanning.revokeSelectedOrder
                            indirectContext.map
                            indirectContext.units
                            indirectContext.playerNumbers
                            >> fixtureValue
                         )
                            bombardment
                        )
                    )
            )
        , expect "target previews are legal, transient, and do not save orders"
            (OrderPlanning.indirectTargetPreview aiming
                == Nothing
                && OrderPlanning.indirectTargetPreview
                    (OrderPlanning.previewTile
                        indirectContext.map
                        indirectContext.units
                        indirectContext.playerNumbers
                        indirectContext.movementRules
                        { x = 3, y = 3 }
                        aiming
                    )
                == Just { x = 3, y = 3 }
                && List.isEmpty
                    (OrderPlanning.orders
                        (OrderPlanning.previewTile
                            indirectContext.map
                            indirectContext.units
                            indirectContext.playerNumbers
                            indirectContext.movementRules
                            { x = 3, y = 3 }
                            aiming
                        )
                    )
                && OrderPlanning.indirectTargetPreview
                    (OrderPlanning.clearTargetPreview
                        (OrderPlanning.previewTile
                            indirectContext.map
                            indirectContext.units
                            indirectContext.playerNumbers
                            indirectContext.movementRules
                            { x = 3, y = 3 }
                            aiming
                        )
                    )
                == Nothing
                && OrderPlanning.indirectTargetPreview
                    (OrderPlanning.previewTile
                        outOfRangeContext.map
                        outOfRangeContext.units
                        outOfRangeContext.playerNumbers
                        outOfRangeContext.movementRules
                        { x = 11, y = 1 }
                        (OrderPlanning.previewTile
                            outOfRangeContext.map
                            outOfRangeContext.units
                            outOfRangeContext.playerNumbers
                            outOfRangeContext.movementRules
                            { x = 10, y = 1 }
                            edgeAim
                        )
                    )
                == Nothing
                && OrderPlanning.indirectTargetPreview bombardment
                == Nothing
            )
        , expect "indirect fire on occupied tiles retains the firing gun"
            (OrderPlanning.orders
                ((OrderPlanning.selectUnit
                    indirectContext.map
                    indirectContext.units
                    indirectContext.playerNumbers
                    indirectContext.movementRules
                    indirectContext.supplyCrates
                    indirectContext.depots
                    truckId
                    >> fixtureValue
                 )
                    aiming
                )
                == [ aimedOrder { x = 3, y = 1 } ]
            )
        , expect "indirect fire accepts the firing gun's own tile"
            (OrderPlanning.orders selfBombardment == [ aimedOrder { x = 1, y = 1 } ])
        , expect "indirect fire rejects out-of-range tiles without leaving targeting"
            ((OrderPlanning.selectTile
                outOfRangeContext.map
                outOfRangeContext.units
                outOfRangeContext.playerNumbers
                outOfRangeContext.movementRules
                outOfRangeContext.supplyCrates
                outOfRangeContext.depots
                { x = 11, y = 1 }
                >> fixtureValue
             )
                edgeAim
                == edgeAim
            )
        , expect "indirect fire includes the circular range boundary"
            (List.member { x = 10, y = 1 }
                (OrderPlanning.indirectTargets
                    outOfRangeContext.map
                    edgeAim
                )
                && not
                    (List.member { x = 10, y = 2 }
                        (OrderPlanning.indirectTargets
                            outOfRangeContext.map
                            edgeAim
                        )
                    )
            )
        , expect "indirect fire excludes other kinds, passengers, and insufficient supplies"
            (not (UnitCommand.canUse context.map [] infantry UnitCommand.IndirectFire)
                && not (UnitCommand.canUse context.map [] truck UnitCommand.IndirectFire)
                && not
                    (UnitCommand.canUse context.map
                        []
                        (fieldGun
                            |> Unit.setLocation (Location.Aboard truckId)
                        )
                        UnitCommand.IndirectFire
                    )
                && not
                    (UnitCommand.canUse context.map
                        []
                        (insufficientReadiness
                            |> Unit.setKind Kind.FieldGun
                        )
                        UnitCommand.IndirectFire
                    )
            )
        , expect "stand ground chooses direction before saving and can be revoked"
            (OrderPlanning.choosingDirection choosingStandGround
                && List.isEmpty (OrderPlanning.orders choosingStandGround)
                && OrderPlanning.orders standingGround
                == [ { unitId = infantryId, action = PlannedOrder.StandGround { position = { x = 1, y = 1 }, direction = DirectionEnum.West } } ]
                && List.isEmpty
                    (OrderPlanning.orders
                        ((OrderPlanning.revokeSelectedOrder
                            context.map
                            context.units
                            context.playerNumbers
                            >> fixtureValue
                         )
                            standingGround
                        )
                    )
            )
        , expect "dig in saves a stationary order and can be revoked"
            (OrderPlanning.orders diggingIn
                == [ { unitId = infantryId, action = PlannedOrder.DigIn { x = 1, y = 1 } } ]
                && List.isEmpty (OrderPlanning.orders (OrderPlanning.revokeSelectedOrder context.map context.units context.playerNumbers diggingIn |> fixtureValue))
            )
        , expect "dig in excludes entrenched infantry, dismounts, field guns, trucks and insufficient supplies"
            (not
                (UnitCommand.canUse context.map
                    []
                    (infantry
                        |> Unit.setEntrenchment Entrenchment.Entrenched
                    )
                    UnitCommand.DigIn
                )
                && not
                    (UnitCommand.canUse context.map
                        []
                        (infantry
                            |> Unit.setLocation (Location.dismounting { x = 1, y = 1 })
                        )
                        UnitCommand.DigIn
                    )
                && not (UnitCommand.canUse context.map [] insufficientReadiness UnitCommand.DigIn)
                && not (UnitCommand.canUse context.map [] fieldGun UnitCommand.DigIn)
                && not (UnitCommand.canUse context.map [] truck UnitCommand.DigIn)
                && not (List.member UnitCommand.DigIn (UnitCommand.available [] fieldGun))
            )
        , expect "stand ground requires readiness supplies and excludes trucks and passengers"
            (not (UnitCommand.canUse context.map [] insufficientReadiness UnitCommand.StandGround)
                && not (List.member UnitCommand.StandGround (UnitCommand.available [] truck))
                && not
                    (List.member UnitCommand.StandGround
                        (UnitCommand.available []
                            (infantry
                                |> Unit.setLocation (Location.Aboard truckId)
                            )
                        )
                    )
            )
        , expect "ambush direction preview saves a stationary ambush instead of rotation"
            (OrderPlanning.orders ambushing == [ { unitId = infantryId, action = PlannedOrder.Ambush { position = { x = 1, y = 1 }, direction = DirectionEnum.East } } ])
        , expect "ambush can be revoked and trucks cannot ambush"
            (List.isEmpty
                (OrderPlanning.orders
                    ((OrderPlanning.revokeSelectedOrder
                        context.map
                        context.units
                        context.playerNumbers
                        >> fixtureValue
                     )
                        ambushing
                    )
                )
                && List.isEmpty (OrderPlanning.orders truckAmbush)
            )
        , expect "unordered selection cycles through eligible units and wraps"
            (OrderPlanning.commandMenuUnit
                context.map
                context.units
                firstUnordered
                == Just infantry
                && OrderPlanning.commandMenuUnit
                    context.map
                    context.units
                    secondUnordered
                == Just truck
                && OrderPlanning.commandMenuUnit
                    context.map
                    context.units
                    wrappedUnordered
                == Just infantry
            )
        , expect "unordered selection leaves a preview without saving a move"
            (OrderPlanning.commandMenuUnit
                context.map
                context.units
                afterPreview
                == Just truck
                && List.isEmpty (OrderPlanning.orders afterPreview)
            )
        , expect "unordered selection skips saved orders and keeps the last eligible unit selected"
            (OrderPlanning.commandMenuUnit
                context.map
                context.units
                afterOrder
                == Just truck
                && OrderPlanning.orders afterOrder
                == OrderPlanning.orders saved
                && OrderPlanning.selectNextUnorderedUnit
                    context.map
                    context.units
                    context.playerNumbers
                    afterOrder
                == afterOrder
            )
        , expect "unordered selection does nothing when all on-board units have orders"
            (OrderPlanning.selectNextUnorderedUnit
                cargoContext.map
                cargoContext.units
                cargoContext.playerNumbers
                completed
                == completed
            )
        , expect "unordered selection cannot leave a submission or unload dialog"
            (OrderPlanning.selectNextUnorderedUnit
                context.map
                context.units
                context.playerNumbers
                (OrderPlanning.showSubmissionWarning firstUnordered)
                == OrderPlanning.showSubmissionWarning firstUnordered
                && OrderPlanning.selectNextUnorderedUnit
                    cargoContext.map
                    cargoContext.units
                    cargoContext.playerNumbers
                    checklist
                == checklist
            )
        , expect "path confirmation saves the traced route and closes editing"
            (List.map PlannedOrder.path (OrderPlanning.orders saved) == [ [ { x = 1, y = 1 }, { x = 1, y = 2 } ] ] && OrderPlanning.pathPreview saved == Nothing)
        , expect "a truck can pick up infantry at its saved destination without replacing its route"
            (List.length (OrderPlanning.orders reserved)
                == 2
                && List.all (\order -> List.member order (OrderPlanning.orders reserved)) (OrderPlanning.orders saved)
                && List.all (\order -> PlannedOrder.destination order == { x = 1, y = 2 }) (OrderPlanning.orders reserved)
            )
        , expect "a truck can move onto a departing infantry square without changing its order"
            (List.length (OrderPlanning.orders enteringVacated) == 2 && List.all PlannedOrder.isMoving (OrderPlanning.orders enteringVacated))
        , expect "revoking a departure also revokes the move depending on its freed square"
            (List.isEmpty (OrderPlanning.orders revokeDeparture))
        , expect "departure revocation clears a whole dependent chain"
            (List.length (OrderPlanning.orders chain) == 3 && List.isEmpty (OrderPlanning.orders revokedChain))
        , expect "moving onto a departing truck keeps both moves and creates no loading target"
            (List.length (OrderPlanning.orders enteringTruckOrigin)
                == 2
                && List.all PlannedOrder.isMoving (OrderPlanning.orders enteringTruckOrigin)
                && PlannedTransport.loadingTarget
                    context.units
                    infantry
                    { x = 3, y = 1 }
                    (OrderPlanning.orders enteringTruckOrigin)
                == Nothing
            )
        , expect "two arriving passengers preserve the moving truck route"
            (List.length (OrderPlanning.orders rendezvous) == 3 && List.all PlannedOrder.isMoving (OrderPlanning.orders rendezvous) && List.all (\plan -> PlannedOrder.destination plan == { x = 2, y = 2 }) (OrderPlanning.orders rendezvous))
        , expect "a moving truck can pick up a waiting unit and an arriving passenger together"
            (List.length (OrderPlanning.orders pickupRendezvous) == 3 && List.length (List.filter PlannedOrder.isMoving (OrderPlanning.orders pickupRendezvous)) == 2)
        , expect "freight capacity reserves arriving passengers at the moving truck destination"
            (List.length
                (PlannedTransport.boardingPassengers
                    rendezvousContext.units
                    truckId
                    (OrderPlanning.orders rendezvous)
                )
                == 2
            )
        , expect "freight capacity reserves waiting pickups as well as arriving passengers"
            (List.length
                (PlannedTransport.boardingPassengers
                    rendezvousContext.units
                    truckId
                    (OrderPlanning.orders pickupRendezvous)
                )
                == 2
            )
        , expect "a carried crate leaves only one berth at a moving truck destination"
            (List.length (OrderPlanning.orders freightRendezvous) == 2 && OrderPlanning.orders overfullRendezvous == OrderPlanning.orders freightRendezvous && OrderPlanning.destinationFeedback overfullRendezvous == DestinationUnavailable)
        , expect "revoking the moving truck clears both dependent boarding orders"
            (List.isEmpty (OrderPlanning.orders revokedRendezvous))
        , expect "loading saves the mover and a holding receiver"
            (List.length (OrderPlanning.orders loading)
                == 2
                && PlannedTransport.receivingLoad
                    context.units
                    truck
                    (OrderPlanning.orders loading)
            )
        , expect "a receiving truck is inspection only"
            (OrderPlanning.commandMenuUnit
                context.map
                context.units
                receiving
                == Nothing
                && OrderPlanning.selection receiving
                == Just (Inspecting (UnitInspection truckId))
            )
        , expect "revoking loading and receiver holds keeps the truck inspected without commands"
            (List.isEmpty (OrderPlanning.orders revoked)
                && OrderPlanning.commandMenuUnit context.map context.units revoked
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
            (List.map .id
                (OrderPlanning.missingOrders
                    cargoContext.map
                    cargoContext.units
                    cargoContext.playerNumbers
                    (OrderPlanning.orders completed)
                )
                == [ infantryId ]
                && List.length ordersForSubmission
                == 3
            )
        , expect "saving the first infantry command opens commands for the second dismount"
            (OrderPlanning.commandMenuUnit
                twoInfantryContext.map
                twoInfantryContext.units
                secondInfantryCommand
                |> Maybe.map .id
                |> (==) (Just passengerId)
            )
        , expect "both dismounted infantry can save independent commands"
            (List.isEmpty
                (OrderPlanning.missingOrders
                    twoInfantryContext.map
                    twoInfantryContext.units
                    twoInfantryContext.playerNumbers
                    (OrderPlanning.orders bothInfantryCommanded)
                )
                && OrderPlanning.commandMenuUnit twoInfantryContext.map twoInfantryContext.units bothInfantryCommanded
                == Nothing
                && List.length (OrderPlanning.orders bothInfantryCommanded)
                == 3
            )
        , expect "completing exits opens the dismounted infantry command menu"
            (OrderPlanning.commandMenuUnit
                cargoContext.map
                cargoContext.units
                completed
                |> Maybe.map .id
                |> (==) (Just infantryId)
            )
        , expect "dismounted attack tracing begins at the exit and saves normally"
            (OrderPlanning.orders dismountAttack
                |> List.any (\order -> order.unitId == infantryId && PlannedOrder.isAttackMove order && List.head (PlannedOrder.path order) == Just { x = 3, y = 2 })
            )
        , expect "dismounted hold uses the exit and clears the missing command"
            (List.isEmpty
                (OrderPlanning.missingOrders
                    cargoContext.map
                    cargoContext.units
                    cargoContext.playerNumbers
                    (OrderPlanning.orders dismountHold)
                )
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
                            ((OrderPlanning.confirmPassengers
                                blockedCrateContext.map
                                blockedCrateContext.units
                                blockedCrateContext.playerNumbers
                                blockedCrateContext.movementRules
                                blockedCrateContext.supplyCrates
                                blockedCrateContext.depots
                                >> fixtureValue
                             )
                                (mixedChecklist
                                    |> OrderPlanning.toggleUnloadCargo (UnloadCargo.Crate 0) True
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
            (List.map .action
                (OrderPlanning.orders
                    ((OrderPlanning.confirmPassengers
                        mixedContext.map
                        mixedContext.units
                        mixedContext.playerNumbers
                        mixedContext.movementRules
                        mixedContext.supplyCrates
                        mixedContext.depots
                        >> fixtureValue
                     )
                        mixedChecklist
                    )
                )
                == [ PlannedOrder.Hold
                        { x = 3
                        , y = 1
                        }
                   ]
            )
        , expect "lifecycle gating prevents editing submitted drafts"
            (TurnLifecycle.mapPlanning
                (OrderPlanning.selectTile
                    context.map
                    context.units
                    context.playerNumbers
                    context.movementRules
                    context.supplyCrates
                    context.depots
                    { x = 2, y = 2 }
                    >> fixtureValue
                )
                submitted
                == submitted
            )
        ]


{-| Test setup only. Each planning operation receives the individual fixture
fields it uses.
-}
type alias BoardFixture =
    { map : Map
    , units : List Unit
    , playerNumbers : List PlayerNumber.PlayerNumber
    , movementRules : List Movement.Rule
    , supplyCrates : List Supply.GroundCrate
    , depots : List Depot
    }


board : List Unit -> BoardFixture
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
    { kind = kind, budget = 12, terrainCosts = [ { terrain = Terrain.Plain, cost = 2 } ], roadFuelPerTile = 5, roadFuelPerCargoSlot = 0 }


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
    , entrenchment = Entrenchment.Exposed
    , spriteFacing = SpriteFacing.Right
    , kind = kind
    , direction = direction
    , destroyed = False
    , combatState = Nothing
    , combatRules =
        { range = 1
        , indirectRange = 0
        , shape = AmbushShape.Line
        , damage = 4
        , readinessCost = 2
        , digInCost = 16
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
