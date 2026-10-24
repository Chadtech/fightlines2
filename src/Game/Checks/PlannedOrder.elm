port module Game.Checks.PlannedOrder exposing (main)

import Api.Enum.DepotKind as DepotKind
import Api.Enum.Direction as Direction
import Api.InputObject
import Game.PlannedOrder as PlannedOrder exposing (Action(..), PlannedOrder)
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Platform


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
    case ( UnitId.parse "1", UnitId.parse "2" ) of
        ( Ok unitId, Ok passengerId ) ->
            orderChecks unitId passengerId

        _ ->
            [ "could not construct order fixture IDs" ]


orderChecks : UnitId -> UnitId -> List String
orderChecks unitId passengerId =
    let
        hold : PlannedOrder
        hold =
            { unitId = unitId, action = Hold { x = 1, y = 1 } }

        diggingIn : PlannedOrder
        diggingIn =
            { unitId = unitId, action = DigIn { x = 1, y = 1 } }

        sabotaging : PlannedOrder
        sabotaging =
            { unitId = unitId, action = Sabotage { x = 1, y = 1 } }

        standingGround : PlannedOrder
        standingGround =
            { unitId = unitId, action = StandGround { position = { x = 1, y = 1 }, direction = Direction.West } }

        ambush : PlannedOrder
        ambush =
            { unitId = unitId
            , action =
                Ambush
                    { position = { x = 1, y = 1 }
                    , direction = Direction.East
                    }
            }

        move : PlannedOrder
        move =
            { unitId = unitId
            , action =
                Move
                    { move = { path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ], destination = { x = 2, y = 1 }, cost = 2 }
                    , unloads = [ { unitId = passengerId, destination = { x = 2, y = 2 } } ]
                    }
            }

        attackMove : PlannedOrder
        attackMove =
            { unitId = unitId, action = AttackMove { move = { path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ], destination = { x = 2, y = 1 }, cost = 2 }, direction = Direction.North } }

        stationaryUnload : PlannedOrder
        stationaryUnload =
            { unitId = unitId
            , action =
                Unload
                    { position = { x = 1, y = 1 }
                    , unloads = [ { unitId = passengerId, destination = { x = 1, y = 2 } } ]
                    }
            }

        freight : PlannedOrder
        freight =
            { unitId = unitId
            , action =
                SupplyTransfer
                    { route =
                        [ { x = 1
                          , y = 1
                          }
                        , { x = 2
                          , y = 1
                          }
                        ]
                    , destination =
                        { x = 2
                        , y = 1
                        }
                    , handling =
                        PlannedOrder.UnloadingCrates
                            [ { cargoIndex = 1
                              , destination =
                                    { x = 2
                                    , y = 0
                                    }
                              }
                            ]
                    , passengers =
                        [ { unitId = passengerId
                          , destination =
                                { x = 2
                                , y = 2
                                }
                          }
                        ]
                    }
            }

        pickupInput : Api.InputObject.MoveOrderInput
        pickupInput =
            PlannedOrder.toInput
                { unitId = unitId
                , action =
                    SupplyTransfer
                        { route = [ { x = 1, y = 1 }, { x = 2, y = 1 } ]
                        , destination = { x = 2, y = 1 }
                        , handling = PlannedOrder.PickingUpGroundFreight DepotKind.Fuel
                        , passengers = []
                        }
                }

        indirectInput : Api.InputObject.MoveOrderInput
        indirectInput =
            PlannedOrder.toInput
                { unitId = unitId
                , action =
                    IndirectFire
                        { position =
                            { x = 1
                            , y = 1
                            }
                        , target =
                            { x = 8
                            , y = 9
                            }
                        }
                }
    in
    List.concat
        [ expect "sabotage serializes an exclusive stationary action"
            ((PlannedOrder.toInput sabotaging).sabotage
                == Present True
                && (PlannedOrder.toInput sabotaging).digIn
                == Present False
                && (PlannedOrder.toInput sabotaging).ambush
                == Present False
                && (PlannedOrder.toInput sabotaging).attackMove
                == Present False
                && (PlannedOrder.toInput sabotaging).indirectFire
                == Absent
                && PlannedOrder.path sabotaging
                == [ { x = 1, y = 1 } ]
                && not (PlannedOrder.isMoving sabotaging)
                && List.isEmpty (PlannedOrder.unloads sabotaging)
            )
        , expect "ground pickup serializes its resource without requesting depot loads"
            (pickupInput.pickupGroundFreight
                == Present DepotKind.Fuel
                && pickupInput.loadCrates
                == Present 0
                && pickupInput.crateUnloads
                == Present []
            )
        , expect "digging serializes an exclusive stationary action"
            ((PlannedOrder.toInput diggingIn).digIn
                == Present True
                && (PlannedOrder.toInput diggingIn).ambush
                == Present False
                && (PlannedOrder.toInput diggingIn).path
                == [ { x = 1, y = 1 } ]
                && not (PlannedOrder.isMoving diggingIn)
            )
        , expect "supply runs preserve movement, passenger exits, and original crate slots in submission"
            (PlannedOrder.toInput freight
                == { pickupGroundFreight = Absent
                   , loadCrates = Present 0
                   , crateUnloads =
                        Present
                            [ { cargoIndex = 1
                              , destination =
                                    { x = 2
                                    , y = 0
                                    }
                              }
                            ]
                   , attackMove = Present False
                   , digIn = Present False
                   , sabotage = Present False
                   , standGround = Present False
                   , ambush = Present False
                   , unitId = UnitId.toString unitId
                   , path =
                        [ { x = 1
                          , y = 1
                          }
                        , { x = 2
                          , y = 1
                          }
                        ]
                   , indirectFire = Absent
                   , direction = Absent
                   , unloads =
                        Present
                            [ { unitId = UnitId.toString passengerId
                              , destination =
                                    { x = 2
                                    , y = 2
                                    }
                              }
                            ]
                   }
                && PlannedOrder.isMoving freight
            )
        , expect "indirect fire serializes a stationary route and a separate target"
            ((indirectInput.path == [ { x = 1, y = 1 } ])
                && (indirectInput.indirectFire == Present { x = 8, y = 9 })
                && (indirectInput.direction == Absent)
                && (indirectInput.ambush == Present False)
            )
        , expect "attack move preserves its route and sends its chosen final facing without unloading"
            (PlannedOrder.toInput attackMove
                == { pickupGroundFreight = Absent
                   , loadCrates = Present 0
                   , crateUnloads = Present []
                   , attackMove = Present True
                   , digIn = Present False
                   , sabotage = Present False
                   , standGround = Present False
                   , ambush = Present False
                   , unitId = UnitId.toString unitId
                   , path =
                        [ { x = 1
                          , y = 1
                          }
                        , { x = 2
                          , y = 1
                          }
                        ]
                   , indirectFire = Absent
                   , direction = Present Direction.North
                   , unloads = Present []
                   }
                && PlannedOrder.isMoving attackMove
                && PlannedOrder.unloads attackMove
                == []
            )
        , expect "stand ground submits chosen facing and defensive readiness without combat, movement, or cargo"
            (PlannedOrder.toInput standingGround
                == { unitId = UnitId.toString unitId
                   , path = [ { x = 1, y = 1 } ]
                   , indirectFire = Absent
                   , direction = Present Direction.West
                   , digIn = Present False
                   , sabotage = Present False
                   , standGround = Present True
                   , ambush = Present False
                   , attackMove = Present False
                   , unloads = Present []
                   , loadCrates = Present 0
                   , pickupGroundFreight = Absent
                   , crateUnloads = Present []
                   }
                && not (PlannedOrder.isMoving standingGround)
            )
        , expect "ambush submission must carry combat readiness and chosen facing without movement"
            (PlannedOrder.toInput ambush
                == { pickupGroundFreight = Absent
                   , loadCrates = Present 0
                   , crateUnloads = Present []
                   , attackMove = Present False
                   , digIn = Present False
                   , sabotage = Present False
                   , standGround = Present False
                   , ambush = Present True
                   , unitId = UnitId.toString unitId
                   , path =
                        [ { x = 1
                          , y = 1
                          }
                        ]
                   , indirectFire = Absent
                   , direction = Present Direction.East
                   , unloads = Present []
                   }
                && not (PlannedOrder.isMoving ambush)
            )
        , expect "hold submission must have one coordinate and no rotation or unloads"
            (PlannedOrder.toInput hold
                == { pickupGroundFreight = Absent
                   , loadCrates = Present 0
                   , crateUnloads = Present []
                   , attackMove = Present False
                   , digIn = Present False
                   , sabotage = Present False
                   , standGround = Present False
                   , ambush = Present False
                   , unitId = UnitId.toString unitId
                   , path =
                        [ { x = 1
                          , y = 1
                          }
                        ]
                   , indirectFire = Absent
                   , direction = Absent
                   , unloads = Present []
                   }
            )
        , expect "move submission must preserve the route and passenger exit without adding rotation"
            (PlannedOrder.toInput move
                == { pickupGroundFreight = Absent
                   , loadCrates = Present 0
                   , crateUnloads = Present []
                   , attackMove = Present False
                   , digIn = Present False
                   , sabotage = Present False
                   , standGround = Present False
                   , ambush = Present False
                   , unitId = UnitId.toString unitId
                   , path =
                        [ { x = 1
                          , y = 1
                          }
                        , { x = 2
                          , y = 1
                          }
                        ]
                   , indirectFire = Absent
                   , direction = Absent
                   , unloads =
                        Present
                            [ { unitId = UnitId.toString passengerId
                              , destination =
                                    { x = 2
                                    , y = 2
                                    }
                              }
                            ]
                   }
            )
        , expect "only a traversed move may consume a boarding berth or count as a moving receiver"
            (not (PlannedOrder.isMoving hold) && not (PlannedOrder.isMoving ambush) && PlannedOrder.isMoving move && not (PlannedOrder.isMoving stationaryUnload))
        , expect "stationary trucks must retain their unload choices"
            (PlannedOrder.toInput stationaryUnload
                == { pickupGroundFreight = Absent
                   , loadCrates = Present 0
                   , crateUnloads = Present []
                   , attackMove = Present False
                   , digIn = Present False
                   , sabotage = Present False
                   , standGround = Present False
                   , ambush = Present False
                   , unitId = UnitId.toString unitId
                   , path =
                        [ { x = 1
                          , y = 1
                          }
                        ]
                   , indirectFire = Absent
                   , direction = Absent
                   , unloads =
                        Present
                            [ { unitId = UnitId.toString passengerId
                              , destination =
                                    { x = 1
                                    , y = 2
                                    }
                              }
                            ]
                   }
            )
        , expect "reservations must use the order destination and transport unload exits"
            (PlannedOrder.destination move == { x = 2, y = 1 } && PlannedOrder.destination ambush == { x = 1, y = 1 } && PlannedOrder.destination stationaryUnload == { x = 1, y = 1 } && PlannedOrder.unloads hold == [] && PlannedOrder.unloads ambush == [] && List.length (PlannedOrder.unloads move) == 1)
        ]


expect : String -> Bool -> List String
expect message condition =
    if condition then
        []

    else
        [ message ]
