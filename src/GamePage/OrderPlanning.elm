module GamePage.OrderPlanning exposing
    ( Cargo(..)
    , Context
    , Drafts
    , Model(..)
    , UnloadChoice
    , UnloadPlanning
    , applyCommand
    , boardingPassengers
    , canSelectUnloadCargo
    , chooseUnloadSquare
    , choosingDirection
    , choosingIndirectFire
    , commandGuideOpen
    , commandMenuUnit
    , confirmPassengers
    , confirmPath
    , confirmUnloadPassengers
    , destinationFeedback
    , dismissDialog
    , extendPath
    , focusCommand
    , focusedCommand
    , indirectTargets
    , indirectTargetsInRange
    , init
    , isOwnUnit
    , loadingTarget
    , missingOrders
    , moveOptions
    , movementPlanning
    , openCommandGuide
    , orders
    , pathPreview
    , previewRotation
    , previewTile
    , receivingLoad
    , revokeSelectedOrder
    , saveRotation
    , saveUnloadDestination
    , selectNextUnorderedUnit
    , selectTile
    , selectUnit
    , selectedUnitFromSelection
    , selection
    , setOrders
    , setSelection
    , showSubmissionWarning
    , skipUnloading
    , startStationaryUnload
    , startUnload
    , submissionDrafts
    , submissionOrders
    , submissionWarningOpen
    , toggleAvailableUnloadCargo
    , toggleUnloadCargo
    , toggleUnloadPassenger
    , truckDestination
    , unloadChoice
    , unloadPlanning
    )

import Api.Enum.Direction as DirectionEnum exposing (Direction)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Enum.UnitKind as Kind
import Coordinate exposing (Coordinate)
import Depot exposing (Depot)
import Direction
import GamePage.Selection as Selection
    exposing
        ( CommandMenuState(..)
        , DestinationFeedback(..)
        , FacingPurpose(..)
        , Inspection(..)
        , MovePlanning
        , MovePurpose(..)
        , Selection(..)
        , UnitInteraction(..)
        )
import Map exposing (Map)
import Movement
import PlannedOrder exposing (MovePlan, PlannedOrder, StationaryUnload)
import Supply
import Unit exposing (Unit)
import Unit.Supplies
import UnitCommand
import UnitId exposing (UnitId)
import UnitResources
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Read-only board and player data needed for local planning. Lifecycle and
camera state remain with the page.
-}
type alias Context =
    { map : Map
    , depots : List Depot
    , units : List Unit
    , movementRules : List Movement.Rule
    , supplyCrates : List Supply.GroundCrate
    , playerNumbers : List PlayerNumber
    }


{-| Planning has one active workflow. Unload stages own their truck plan and
only other units' orders; dialogs and board inspection are derived from the stage.
-}
type Model
    = OrdinaryPlanning Drafts
    | ConfirmingSubmission Drafts
    | ChoosingCrates UnitId Drafts
    | ChoosingPassengers UnloadChoice
    | ChoosingExits UnloadPlanning


type alias Drafts =
    { orders : List PlannedOrder
    , selection : Maybe Selection
    }


{-| Crates use their original zero-based slot in the truck's supply cargo list.
Slots stay stable during planning; the server removes unloaded slots in descending order.
-}
type Cargo
    = Passenger UnitId
    | Crate Int


type alias UnloadingTruck =
    { truckId : UnitId
    , crateUnloads : List PlannedOrder.CrateUnload
    , plan : TruckPlan
    }


type TruckPlan
    = MovingTruck MovePlan
    | StationaryTruck StationaryUnload


type alias UnloadChoice =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , checked : List Cargo
    }


type alias UnloadPlanning =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , cargo : Cargo
    , remaining : List Cargo
    , options : List Movement.Option
    , destinationFeedback : DestinationFeedback
    }


type alias UnloadQueue =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , passengers : List Cargo
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Model
init =
    OrdinaryPlanning { orders = [], selection = Nothing }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


orders : Model -> List PlannedOrder
orders state =
    case state of
        OrdinaryPlanning drafts ->
            drafts.orders

        ConfirmingSubmission drafts ->
            drafts.orders

        ChoosingCrates _ drafts ->
            drafts.orders

        ChoosingPassengers choice ->
            truckOrder choice.truck :: choice.otherOrders

        ChoosingExits unloading ->
            truckOrder unloading.truck :: unloading.otherOrders


setOrders : List PlannedOrder -> Model -> Model
setOrders draftsOrders state =
    case state of
        OrdinaryPlanning drafts ->
            OrdinaryPlanning { drafts | orders = draftsOrders }

        _ ->
            state


selection : Model -> Maybe Selection
selection state =
    case state of
        OrdinaryPlanning drafts ->
            drafts.selection

        ConfirmingSubmission drafts ->
            drafts.selection

        ChoosingCrates id _ ->
            Just (Inspecting (Selection.UnitInspection id))

        ChoosingPassengers choice ->
            Just (Inspecting (Selection.UnitInspection choice.truck.truckId))

        ChoosingExits unloading ->
            case unloading.cargo of
                Passenger id ->
                    Just (Inspecting (Selection.UnitInspection id))

                Crate _ ->
                    Just (Inspecting (Selection.UnitInspection unloading.truck.truckId))


setSelection : Maybe Selection -> Model -> Model
setSelection selected state =
    OrdinaryPlanning { orders = orders state, selection = selected }


{-| Unfinished unloading cannot become a submission. The lifecycle consumes
these drafts only after planning is ready or its warning has been confirmed.
-}
submissionDrafts : Model -> Maybe Drafts
submissionDrafts state =
    case state of
        OrdinaryPlanning drafts ->
            if commandGuideOpen state then
                Nothing

            else
                Just drafts

        ConfirmingSubmission drafts ->
            Just drafts

        _ ->
            Nothing


truckDestination : UnloadingTruck -> Coordinate
truckDestination truck =
    truckOrder truck |> PlannedOrder.destination


startUnload : UnitId -> Movement.Option -> Model -> Model
startUnload truckId move state =
    startTruckUnload
        { truckId = truckId
        , crateUnloads = []
        , plan = MovingTruck { move = move, unloads = [] }
        }
        state


startStationaryUnload : UnitId -> Coordinate -> Model -> Model
startStationaryUnload truckId position state =
    startTruckUnload
        { truckId = truckId
        , crateUnloads = []
        , plan = StationaryTruck { position = position, unloads = [] }
        }
        state


unloadChoice : Model -> Maybe UnloadChoice
unloadChoice state =
    case state of
        ChoosingPassengers choice ->
            Just choice

        _ ->
            Nothing


unloadPlanning : Model -> Maybe UnloadPlanning
unloadPlanning state =
    case state of
        ChoosingExits unloading ->
            Just unloading

        _ ->
            Nothing


{-| Check the whole selection, including scarce exits and passenger supplies.
Checked cargo always remains removable.
-}
canSelectUnloadCargo : Context -> Cargo -> Model -> Bool
canSelectUnloadCargo context cargo state =
    case state of
        ChoosingPassengers choice ->
            List.member cargo choice.checked
                || canCompleteUnload context
                    (confirmUnloadPassengers []
                        (unloadOptions context)
                        (toggleUnloadCargo cargo True state)
                    )

        _ ->
            False


toggleAvailableUnloadCargo : Context -> Cargo -> Bool -> Model -> Model
toggleAvailableUnloadCargo context cargo checked state =
    if not checked || canSelectUnloadCargo context cargo state then
        toggleUnloadCargo cargo checked state

    else
        state


{-| Search at most two cargo exits. Use raw options during simulation to avoid
recursing through the filtered board picker.
-}
canCompleteUnload : Context -> Model -> Bool
canCompleteUnload context state =
    case state of
        ChoosingExits unloading ->
            let
                completes : Movement.Option -> Bool
                completes option =
                    saveUnloadDestination []
                        (unloadOptions context)
                        option.destination
                        (ChoosingExits { unloading | options = unloadOptions context state unloading.cargo })
                        |> canCompleteUnload context
            in
            List.any completes (unloadOptions context state unloading.cargo)

        _ ->
            True


availableUnloadOptions : Context -> Model -> Cargo -> List Movement.Option
availableUnloadOptions context state cargo =
    let
        completes : Movement.Option -> Bool
        completes option =
            case state of
                ChoosingExits unloading ->
                    saveUnloadDestination []
                        (unloadOptions context)
                        option.destination
                        (ChoosingExits { unloading | options = unloadOptions context state cargo })
                        |> canCompleteUnload context

                _ ->
                    False
    in
    unloadOptions context state cargo |> List.filter completes


toggleUnloadPassenger : UnitId -> Bool -> Model -> Model
toggleUnloadPassenger id =
    toggleUnloadCargo (Passenger id)


toggleUnloadCargo : Cargo -> Bool -> Model -> Model
toggleUnloadCargo cargo checked state =
    case state of
        ChoosingPassengers choice ->
            let
                retained : List Cargo
                retained =
                    List.filter ((/=) cargo) choice.checked

                selected : List Cargo
                selected =
                    if checked then
                        cargo :: retained

                    else
                        retained
            in
            ChoosingPassengers { choice | checked = selected }

        _ ->
            state


confirmUnloadPassengers : List Depot -> (Model -> Cargo -> List Movement.Option) -> Model -> Model
confirmUnloadPassengers depots options state =
    case state of
        ChoosingPassengers choice ->
            nextUnloadPassenger depots
                options
                { truck = choice.truck
                , otherOrders = choice.otherOrders
                , passengers = List.reverse choice.checked
                }

        _ ->
            state


saveUnloadDestination : List Depot -> (Model -> Cargo -> List Movement.Option) -> Coordinate -> Model -> Model
saveUnloadDestination depots options destination state =
    case state of
        ChoosingExits unloading ->
            if
                List.any
                    (\option -> option.destination == destination)
                    unloading.options
            then
                let
                    truck : UnloadingTruck
                    truck =
                        unloading.truck

                    updated : UnloadingTruck
                    updated =
                        case unloading.cargo of
                            Passenger passengerId ->
                                let
                                    appendPassenger : List PlannedOrder.UnloadOrder -> List PlannedOrder.UnloadOrder
                                    appendPassenger unloads =
                                        let
                                            passengerExit : PlannedOrder.UnloadOrder
                                            passengerExit =
                                                { unitId = passengerId
                                                , destination = destination
                                                }

                                            exits : List PlannedOrder.UnloadOrder
                                            exits =
                                                [ passengerExit
                                                ]
                                        in
                                        unloads ++ exits

                                    plan : TruckPlan
                                    plan =
                                        case truck.plan of
                                            MovingTruck moving ->
                                                MovingTruck
                                                    { moving
                                                        | unloads = appendPassenger moving.unloads
                                                    }

                                            StationaryTruck stationary ->
                                                StationaryTruck
                                                    { stationary
                                                        | unloads = appendPassenger stationary.unloads
                                                    }
                                in
                                { truck
                                    | plan = plan
                                }

                            Crate index ->
                                let
                                    crateExit : PlannedOrder.CrateUnload
                                    crateExit =
                                        { cargoIndex = index
                                        , destination = destination
                                        }

                                    exits : List PlannedOrder.CrateUnload
                                    exits =
                                        [ crateExit
                                        ]
                                in
                                { truck
                                    | crateUnloads = truck.crateUnloads ++ exits
                                }
                in
                nextUnloadPassenger depots
                    options
                    { truck = updated
                    , otherOrders = unloading.otherOrders
                    , passengers = unloading.remaining
                    }

            else
                ChoosingExits
                    { unloading | destinationFeedback = DestinationUnavailable }

        _ ->
            state


showSubmissionWarning : Model -> Model
showSubmissionWarning state =
    case state of
        OrdinaryPlanning drafts ->
            if commandGuideOpen state then
                state

            else
                ConfirmingSubmission drafts

        _ ->
            state


submissionWarningOpen : Model -> Bool
submissionWarningOpen state =
    case state of
        ConfirmingSubmission _ ->
            True

        _ ->
            False


dismissDialog : List Depot -> Model -> Model
dismissDialog depots state =
    case state of
        OrdinaryPlanning drafts ->
            case drafts.selection of
                Just (UnitSelection selected) ->
                    case selected.interaction of
                        CommandMenu (ReadingGuide focused) ->
                            setSelection
                                (Just (UnitSelection { selected | interaction = CommandMenu (ChoosingCommand focused) }))
                                state

                        _ ->
                            state

                _ ->
                    state

        ConfirmingSubmission drafts ->
            OrdinaryPlanning drafts

        ChoosingCrates _ drafts ->
            OrdinaryPlanning drafts

        ChoosingPassengers choice ->
            finishUnloading depots choice.truck choice.otherOrders (selection state)

        _ ->
            state


chooseUnloadSquare : Context -> Coordinate -> Model -> Model
chooseUnloadSquare context destination state =
    state
        |> saveUnloadDestination context.depots (availableUnloadOptions context) destination


applyCommand : Context -> UnitCommand.Command -> Model -> Model
applyCommand context command model =
    case commandMenuUnit context model of
        Just unit ->
            let
                canApply : Bool
                canApply =
                    isOwnUnit context unit
                        && not (receivingLoad context unit (orders model))
                        && List.member command (UnitCommand.available unit)
                        && UnitCommand.canUse unit command
            in
            if canApply then
                case command of
                    UnitCommand.IndirectFire ->
                        setUnitInteraction unit.id ChoosingIndirectFire model

                    UnitCommand.Move ->
                        beginMovement NormalMove context unit model

                    UnitCommand.AttackMove ->
                        beginMovement AttackMove context unit model

                    UnitCommand.Rotate ->
                        model
                            |> setUnitInteraction
                                unit.id
                                (ChoosingDirection
                                    RotationFacing
                                    (Maybe.withDefault
                                        DirectionEnum.North
                                        unit.direction
                                    )
                                )

                    UnitCommand.Ambush ->
                        model
                            |> setUnitInteraction
                                unit.id
                                (ChoosingDirection
                                    AmbushFacing
                                    (Maybe.withDefault
                                        DirectionEnum.North
                                        unit.direction
                                    )
                                )

                    UnitCommand.StandGround ->
                        case Unit.boardPosition unit of
                            Just position ->
                                let
                                    newOrder : PlannedOrder
                                    newOrder =
                                        { unitId = unit.id
                                        , action =
                                            PlannedOrder.StandGround position
                                        }
                                in
                                model
                                    |> setOrders
                                        (newOrder
                                            :: List.filter
                                                (\plan -> plan.unitId /= unit.id)
                                                (orders model)
                                        )
                                    |> inspectSelectedUnit context

                            Nothing ->
                                model

                    UnitCommand.HoldPosition ->
                        holdPosition context unit model

                    _ ->
                        model

            else
                model

        _ ->
            model


commandGuideOpen : Model -> Bool
commandGuideOpen state =
    case state of
        OrdinaryPlanning drafts ->
            case drafts.selection of
                Just (UnitSelection { interaction }) ->
                    case interaction of
                        CommandMenu (ReadingGuide _) ->
                            True

                        _ ->
                            False

                _ ->
                    False

        _ ->
            False


openCommandGuide : Context -> Model -> Model
openCommandGuide context state =
    case ( state, commandMenuUnit context state ) of
        ( OrdinaryPlanning drafts, Just unit ) ->
            case drafts.selection of
                Just (UnitSelection selected) ->
                    case selected.interaction of
                        CommandMenu (ChoosingCommand focused) ->
                            if isOwnUnit context unit then
                                setSelection
                                    (Just (UnitSelection { selected | interaction = CommandMenu (ReadingGuide focused) }))
                                    state

                            else
                                state

                        _ ->
                            state

                _ ->
                    state

        _ ->
            state


commandMenuUnit : Context -> Model -> Maybe Unit
commandMenuUnit context state =
    case ( selection state, hasDialog state ) of
        ( Just (UnitSelection { interaction }), False ) ->
            case interaction of
                CommandMenu _ ->
                    selectedUnit context state

                _ ->
                    Nothing

        _ ->
            Nothing


{-| Trucks receive boarding units at their planned destination. Other departing
allies free their starting squares while their destinations remain reserved.
-}
loadingTarget : Context -> Unit -> Coordinate -> List PlannedOrder -> Maybe Unit
loadingTarget context mover destination drafts =
    Unit.loadingTarget (destinationUnits context drafts) mover destination


{-| Include arriving passengers and waiting pickups at the truck's destination.
Existing passengers remain separate because unloading does not free a berth yet.
-}
boardingPassengers : Context -> UnitId -> List PlannedOrder -> List UnitId
boardingPassengers context truckId drafts =
    let
        boardsTruck : PlannedOrder -> Bool
        boardsTruck plan =
            let
                receiver : Unit -> Maybe Unit
                receiver passenger =
                    loadingTarget context passenger (PlannedOrder.destination plan) drafts

                targetId : Maybe UnitId
                targetId =
                    context.units
                        |> ListUtil.find (\unit -> unit.id == plan.unitId)
                        |> Maybe.andThen receiver
                        |> Maybe.map .id
            in
            (plan.unitId /= truckId)
                && not (PlannedOrder.isAttackMove plan)
                && (targetId == Just truckId)
    in
    drafts
        |> List.filter boardsTruck
        |> List.map .unitId


destinationUnits : Context -> List PlannedOrder -> List Unit
destinationUnits context drafts =
    let
        destinationUnit : Unit -> Maybe Unit
        destinationUnit unit =
            let
                departure : PlannedOrder -> Bool
                departure plan =
                    (plan.unitId == unit.id) && PlannedOrder.isMoving plan
            in
            case ListUtil.find departure drafts of
                Just plan ->
                    if unit.kind == Kind.Truck then
                        Just (Unit.setOnMap (PlannedOrder.destination plan) unit)

                    else
                        Nothing

                Nothing ->
                    Just unit
    in
    List.filterMap destinationUnit context.units


receivingLoad : Context -> Unit -> List PlannedOrder -> Bool
receivingLoad context unit drafts =
    let
        receives : PlannedOrder -> Bool
        receives plan =
            if not (PlannedOrder.isMoving plan) || PlannedOrder.isAttackMove plan then
                False

            else
                case ListUtil.find (\mover -> mover.id == plan.unitId) context.units of
                    Just mover ->
                        if Unit.carrierId mover == Just unit.id then
                            True

                        else
                            loadingTarget
                                context
                                mover
                                (PlannedOrder.destination plan)
                                drafts
                                |> Maybe.map .id
                                |> (==) (Just unit.id)

                    Nothing ->
                        False
    in
    List.any receives drafts


focusCommand : Context -> UnitCommand.MenuOption -> Model -> Model
focusCommand context command state =
    case ( selection state, commandMenuUnit context state ) of
        ( Just (UnitSelection selected), Just _ ) ->
            case selected.interaction of
                CommandMenu _ ->
                    state
                        |> setUnitInteraction
                            selected.id
                            (CommandMenu (ChoosingCommand (Just command)))

                _ ->
                    state

        _ ->
            state


revokeSelectedOrder : Context -> Model -> Model
revokeSelectedOrder context state =
    case selectedUnit context state of
        Just unit ->
            state
                |> setOrders
                    (revokeDependentOrders
                        context
                        [ unit.id ]
                        (orders state)
                    )
                |> restoreCommands context

        Nothing ->
            state


{-| Revoking a departure also revokes routes relying on the vacated square.
Each step removes orders, so chains and cycles terminate.
-}
revokeDependentOrders : Context -> List UnitId -> List PlannedOrder -> List PlannedOrder
revokeDependentOrders context revokedIds drafts =
    let
        removed : List PlannedOrder
        removed =
            List.filter (\plan -> List.member plan.unitId revokedIds) drafts

        origin : PlannedOrder -> Maybe Coordinate
        origin plan =
            if PlannedOrder.isMoving plan then
                context.units
                    |> ListUtil.find (\unit -> unit.id == plan.unitId)
                    |> Maybe.andThen Unit.boardPosition

            else
                Nothing

        occupiedAgain : List Coordinate
        occupiedAgain =
            List.filterMap origin removed

        retained : List PlannedOrder
        retained =
            List.filter
                (\plan -> not (List.member plan.unitId revokedIds))
                drafts

        dependsOnDeparture : PlannedOrder -> Bool
        dependsOnDeparture plan =
            let
                needsDestination : Bool
                needsDestination =
                    PlannedOrder.isMoving plan && List.member (PlannedOrder.destination plan) occupiedAgain

                needsPassengerExit : Bool
                needsPassengerExit =
                    List.any (\unload -> List.member unload.destination occupiedAgain) (PlannedOrder.unloads plan)

                needsTruck : Bool
                needsTruck =
                    context.units
                        |> ListUtil.find (\unit -> unit.id == plan.unitId)
                        |> Maybe.andThen boardingTarget
                        |> Maybe.map (\truck -> List.member truck.id revokedIds)
                        |> Maybe.withDefault False

                boardingTarget : Unit -> Maybe Unit
                boardingTarget unit =
                    loadingTarget context unit (PlannedOrder.destination plan) drafts

                needsCrateExit : Bool
                needsCrateExit =
                    List.any (\unload -> List.member unload.destination occupiedAgain) (PlannedOrder.crateUnloads plan)
            in
            needsDestination || needsPassengerExit || needsCrateExit || needsTruck

        dependentIds : List UnitId
        dependentIds =
            retained |> List.filter dependsOnDeparture |> List.map .unitId
    in
    if List.isEmpty dependentIds then
        retained

    else
        revokeDependentOrders context dependentIds retained


facingAction : Model -> PlannedOrder.Rotation -> PlannedOrder.Action
facingAction state facing =
    case selection state of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingDirection AmbushFacing _ ->
                    PlannedOrder.Ambush facing

                _ ->
                    PlannedOrder.Rotate facing

        _ ->
            PlannedOrder.Rotate facing


saveRotation : Context -> Direction -> Model -> Model
saveRotation context direction state =
    case selectedUnit context state of
        Just unit ->
            let
                canSave : Bool
                canSave =
                    choosingDirection state
                        && isOwnUnit context unit
                        && not (receivingLoad context unit (orders state))
            in
            if canSave then
                case Unit.boardPosition unit of
                    Just position ->
                        let
                            rotation : PlannedOrder
                            rotation =
                                { unitId = unit.id
                                , action =
                                    facingAction
                                        state
                                        { position = position
                                        , direction = direction
                                        }
                                }
                        in
                        setOrders
                            (rotation
                                :: List.filter
                                    (\plan -> plan.unitId /= unit.id)
                                    (orders state)
                            )
                            state
                            |> inspectSelectedUnit context

                    Nothing ->
                        state

            else
                state

        Nothing ->
            state


selectUnit : Context -> UnitId -> Model -> Model
selectUnit context id state =
    case ListUtil.find (\unit -> unit.id == id) context.units of
        Nothing ->
            state

        Just unit ->
            let
                choosingTransportDestination : Bool
                choosingTransportDestination =
                    ((pathPreview state /= Nothing) || (unloadPlanning state /= Nothing))
                        && (Maybe.map .id (selectedUnit context state) /= Just id)

                choosingOccupiedDestination : Bool
                choosingOccupiedDestination =
                    choosingIndirectFire state || choosingTransportDestination
            in
            if choosingOccupiedDestination then
                Unit.boardPosition unit
                    |> Maybe.map
                        (\position -> selectTile context position state)
                    |> Maybe.withDefault state

            else if Maybe.map .id (selectedUnit context state) == Just id then
                setSelection Nothing state

            else
                setSelection (Just (unitSelection context unit state)) state


selectNextUnorderedUnit : Context -> Model -> Model
selectNextUnorderedUnit context state =
    case ( state, hasDialog state ) of
        ( OrdinaryPlanning _, False ) ->
            let
                candidates : List Unit
                candidates =
                    missingOrders context (orders state)

                currentId : Maybe UnitId
                currentId =
                    selectedUnit context state |> Maybe.map .id

                afterCurrent : List Unit -> List Unit
                afterCurrent remaining =
                    case remaining of
                        [] ->
                            []

                        first :: rest ->
                            if Just first.id == currentId then
                                rest

                            else
                                afterCurrent rest

                next : Maybe Unit
                next =
                    case List.head (afterCurrent candidates) of
                        Just unit ->
                            Just unit

                        Nothing ->
                            List.head candidates
            in
            case next of
                Just unit ->
                    setSelection (Just (unitSelection context unit state)) state

                Nothing ->
                    state

        _ ->
            state


selectTile : Context -> Coordinate -> Model -> Model
selectTile context position state =
    if choosingIndirectFire state then
        saveIndirectFire context position state

    else
        selectTransportTile context position state


selectTransportTile : Context -> Coordinate -> Model -> Model
selectTransportTile context position state =
    case unloadPlanning state of
        Just _ ->
            chooseUnloadSquare context position state

        _ ->
            selectMovementTile context position state


previewTile : Context -> Coordinate -> Model -> Model
previewTile context position state =
    case selection state of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingMove planning ->
                    case traceTo context position state of
                        Just preview ->
                            state
                                |> setUnitInteraction selected.id
                                    (ChoosingMove
                                        { planning
                                            | preview = preview
                                            , destinationFeedback = NoDestinationFeedback
                                        }
                                    )

                        Nothing ->
                            state

                _ ->
                    state

        _ ->
            state


extendPath : Context -> Direction -> Model -> Model
extendPath context direction state =
    case pathPreview state of
        Just preview ->
            previewTile context (Direction.step preview.destination direction) state

        Nothing ->
            state


confirmPath : Context -> Model -> Model
confirmPath context state =
    case pathPreview state of
        Just preview ->
            selectMovementTile context preview.destination state

        Nothing ->
            state


choosingIndirectFire : Model -> Bool
choosingIndirectFire state =
    case selection state of
        Just (UnitSelection { interaction }) ->
            interaction == ChoosingIndirectFire

        _ ->
            False


indirectTargets : Context -> Model -> List Coordinate
indirectTargets context model =
    if choosingIndirectFire model then
        case
            selectedUnit context model
                |> Maybe.andThen
                    (\unit ->
                        Unit.boardPosition unit
                            |> Maybe.map
                                (Tuple.pair
                                    unit.combatRules.indirectRange
                                )
                    )
        of
            Just ( indirectRange, origin ) ->
                indirectTargetsInRange context.map origin indirectRange

            Nothing ->
                []

    else
        []


indirectTargetsInRange : Map -> Coordinate -> Int -> List Coordinate
indirectTargetsInRange map origin indirectRange =
    let
        inRange : Coordinate -> Bool
        inRange target =
            ((target.x - origin.x) ^ 2 + (target.y - origin.y) ^ 2) <= (indirectRange ^ 2)
    in
    Map.positions map |> List.filter inRange


choosingDirection : Model -> Bool
choosingDirection state =
    case selection state of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingDirection _ _ ->
                    True

                CommandMenu _ ->
                    False

                ChoosingIndirectFire ->
                    False

                ChoosingMove _ ->
                    False

        _ ->
            False


previewFacing : UnitInteraction -> Direction -> UnitInteraction
previewFacing interaction direction =
    case interaction of
        ChoosingDirection purpose _ ->
            ChoosingDirection purpose direction

        _ ->
            interaction


previewRotation : Direction -> Model -> Model
previewRotation direction state =
    case selection state of
        Just (UnitSelection selected) ->
            let
                canPreview : Bool
                canPreview =
                    choosingDirection state
            in
            if canPreview then
                state
                    |> setUnitInteraction
                        selected.id
                        (previewFacing selected.interaction direction)

            else
                state

        _ ->
            state


movementPlanning : Model -> Maybe MovePlanning
movementPlanning state =
    case selection state of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingMove planning ->
                    Just planning

                _ ->
                    Nothing

        _ ->
            Nothing


destinationFeedback : Model -> DestinationFeedback
destinationFeedback state =
    case unloadPlanning state of
        Just planning ->
            planning.destinationFeedback

        Nothing ->
            movementPlanning state
                |> Maybe.map .destinationFeedback
                |> Maybe.withDefault NoDestinationFeedback


pathPreview : Model -> Maybe Movement.Option
pathPreview state =
    Maybe.map .preview (movementPlanning state)


moveOptions : Model -> List Movement.Option
moveOptions state =
    case unloadPlanning state of
        Just planning ->
            planning.options

        _ ->
            movementPlanning state
                |> Maybe.map .options
                |> Maybe.withDefault []


isOwnUnit : Context -> Unit -> Bool
isOwnUnit context unit =
    List.member unit.playerNumber context.playerNumbers


selectedUnitFromSelection : Context -> Maybe Selection -> Maybe Unit
selectedUnitFromSelection context selected =
    let
        id : Maybe UnitId
        id =
            case selected of
                Just (Inspecting (Selection.UnitInspection unitId)) ->
                    Just unitId

                Just (UnitSelection unit) ->
                    Just unit.id

                _ ->
                    Nothing
    in
    id |> Maybe.andThen (\unitId -> ListUtil.find (\unit -> unit.id == unitId) context.units)


missingOrders : Context -> List PlannedOrder -> List Unit
missingOrders context drafts =
    let
        missing : Unit -> Bool
        missing unit =
            isOwnUnit context unit && Unit.onBoard unit && not (List.any (\order -> order.unitId == unit.id) drafts)
    in
    List.filter missing context.units


submissionOrders : Context -> List PlannedOrder -> List PlannedOrder
submissionOrders context drafts =
    let
        missing : Unit -> Bool
        missing unit =
            isOwnUnit
                context
                unit
                && not (List.any (\order -> order.unitId == unit.id) drafts)

        holds : List PlannedOrder
        holds =
            context.units
                |> List.filter missing
                |> List.filterMap (holdOrder context.units)
    in
    drafts ++ holds


confirmPassengers : Context -> Model -> Model
confirmPassengers context state =
    if canCompleteUnload context (confirmUnloadPassengers [] (unloadOptions context) state) then
        confirmUnloadPassengers context.depots (availableUnloadOptions context) state

    else
        state


focusedCommand : Model -> Maybe UnitCommand.MenuOption
focusedCommand state =
    case selection state of
        Just (UnitSelection selected) ->
            case selected.interaction of
                CommandMenu (ChoosingCommand focused) ->
                    focused

                CommandMenu (ReadingGuide focused) ->
                    focused

                ChoosingIndirectFire ->
                    Nothing

                ChoosingMove _ ->
                    Nothing

                ChoosingDirection _ _ ->
                    Nothing

        _ ->
            Nothing



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


saveIndirectFire : Context -> Coordinate -> Model -> Model
saveIndirectFire context target state =
    let
        aimedOrder : Unit -> Maybe PlannedOrder
        aimedOrder unit =
            let
                atOrigin : Coordinate -> PlannedOrder
                atOrigin origin =
                    { unitId = unit.id
                    , action =
                        PlannedOrder.IndirectFire
                            { position = origin
                            , target = target
                            }
                    }
            in
            Unit.boardPosition unit |> Maybe.map atOrigin
    in
    case selectedUnit context state |> Maybe.andThen aimedOrder of
        Just order ->
            let
                otherUnitOrder : PlannedOrder -> Bool
                otherUnitOrder plan =
                    plan.unitId /= order.unitId
            in
            if List.member target (indirectTargets context state) then
                state
                    |> setOrders (order :: List.filter otherUnitOrder (orders state))
                    |> inspectSelectedUnit context

            else
                state

        Nothing ->
            state


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
    if List.isEmpty truck.crateUnloads then
        { unitId = truck.truckId
        , action = action
        }

    else
        let
            order : PlannedOrder
            order =
                { unitId = truck.truckId
                , action = action
                }
        in
        { unitId = truck.truckId
        , action =
            PlannedOrder.SupplyTransfer
                { route = PlannedOrder.path order
                , destination = PlannedOrder.destination order
                , handling = PlannedOrder.UnloadingCrates truck.crateUnloads
                , passengers = PlannedOrder.unloads order
                }
        }


{-| A saved truck order enters loading only at its own depot destination.
Crate unloading already owns freight handling and cannot combine with loading.
-}
offerCrateLoading : List Depot -> PlannedOrder -> Drafts -> Model
offerCrateLoading depots order drafts =
    let
        atDestination : Depot -> Bool
        atDestination depot =
            depot.position == PlannedOrder.destination order

        endsAtDepot : Bool
        endsAtDepot =
            List.any atDestination depots
    in
    case order.action of
        PlannedOrder.SupplyTransfer _ ->
            OrdinaryPlanning drafts

        _ ->
            if endsAtDepot then
                ChoosingCrates order.unitId drafts

            else
                OrdinaryPlanning drafts


offerTruckLoading : Context -> Unit -> Model -> Model
offerTruckLoading context unit state =
    case ( unit.kind, state ) of
        ( Kind.Truck, OrdinaryPlanning drafts ) ->
            case ListUtil.find (\order -> order.unitId == unit.id) drafts.orders of
                Just order ->
                    offerCrateLoading context.depots order drafts

                Nothing ->
                    state

        _ ->
            state


finishUnloading : List Depot -> UnloadingTruck -> List PlannedOrder -> Maybe Selection -> Model
finishUnloading depots truck otherOrders selected =
    let
        order : PlannedOrder
        order =
            truckOrder truck
    in
    offerCrateLoading depots
        order
        { orders = order :: otherOrders
        , selection = selected
        }


skipUnloading : Context -> Model -> Model
skipUnloading context state =
    case state of
        ChoosingPassengers choice ->
            finishUnloading context.depots choice.truck choice.otherOrders Nothing

        ChoosingExits unloading ->
            finishUnloading context.depots unloading.truck unloading.otherOrders Nothing

        _ ->
            state


startTruckUnload : UnloadingTruck -> Model -> Model
startTruckUnload truck state =
    case state of
        OrdinaryPlanning drafts ->
            ChoosingPassengers
                { truck = truck
                , otherOrders =
                    List.filter
                        (\order -> order.unitId /= truck.truckId)
                        drafts.orders
                , checked = []
                }

        _ ->
            state


nextUnloadPassenger : List Depot -> (Model -> Cargo -> List Movement.Option) -> UnloadQueue -> Model
nextUnloadPassenger depots options queue =
    case queue.passengers of
        [] ->
            finishUnloading depots
                queue.truck
                queue.otherOrders
                (Just (Inspecting (Selection.UnitInspection queue.truck.truckId)))

        cargo :: remaining ->
            let
                unloading : UnloadPlanning
                unloading =
                    { truck = queue.truck
                    , otherOrders = queue.otherOrders
                    , cargo = cargo
                    , remaining = remaining
                    , options = []
                    , destinationFeedback = NoDestinationFeedback
                    }

                state : Model
                state =
                    ChoosingExits unloading
            in
            ChoosingExits
                { unloading
                    | options = options state cargo
                }


openUnloadPrompt : Context -> Unit -> Movement.Option -> Model -> Model
openUnloadPrompt context truck move state =
    if hasCargo context truck then
        state
            |> startUnload truck.id move

    else
        offerTruckLoading context truck state


hasCargo : Context -> Unit -> Bool
hasCargo context truck =
    let
        hasPassengers : Bool
        hasPassengers =
            List.any (\passenger -> Unit.carrierId passenger == Just truck.id) context.units

        hasCrates : Bool
        hasCrates =
            Unit.crateCount truck > 0
    in
    hasPassengers || hasCrates


holdPosition : Context -> Unit -> Model -> Model
holdPosition context unit state =
    case holdOrder context.units unit of
        Just hold ->
            let
                next : Model
                next =
                    setOrders
                        (hold
                            :: List.filter
                                (\plan -> plan.unitId /= unit.id)
                                (orders state)
                        )
                        state
                        |> inspectSelectedUnit context
            in
            if hasCargo context unit then
                next
                    |> startStationaryUnload
                        unit.id
                        (PlannedOrder.destination hold)

            else
                offerTruckLoading context unit next

        Nothing ->
            state


unloadOptions : Context -> Model -> Cargo -> List Movement.Option
unloadOptions context state cargo =
    case unloadPlanning state of
        Just planning ->
            let
                projectTruck : Unit -> Unit
                projectTruck unit =
                    if unit.id == planning.truck.truckId then
                        Unit.setOnMap (truckDestination planning.truck) unit

                    else
                        unit

                projectedUnits : List Unit
                projectedUnits =
                    List.map projectTruck context.units
            in
            case cargo of
                Passenger passengerId ->
                    case ListUtil.find (\unit -> unit.id == passengerId) projectedUnits of
                        Just passenger ->
                            Movement.optionsAvoiding [] context.movementRules context.map projectedUnits passenger
                                |> List.filter
                                    (Movement.canStop
                                        (reservedDestinations context passenger state)
                                        (List.map
                                            projectTruck
                                            (destinationUnits context (orders state))
                                        )
                                        passenger
                                    )

                        Nothing ->
                            []

                Crate _ ->
                    crateExitOptions context planning (orders state)

        Nothing ->
            []


crateExitOptions : Context -> UnloadPlanning -> List PlannedOrder -> List Movement.Option
crateExitOptions context planning plans =
    let
        origin : Coordinate
        origin =
            truckDestination planning.truck

        reserved : List Coordinate
        reserved =
            List.concatMap (PlannedOrder.crateUnloads >> List.map .destination) plans

        available : Coordinate -> Bool
        available exit =
            let
                insideMap : Bool
                insideMap =
                    (exit.x >= 0)
                        && (exit.y >= 0)
                        && (exit.x < context.map.width)
                        && (exit.y < context.map.height)

                blocksExit : Unit -> Bool
                blocksExit unit =
                    not (isOwnUnit context unit) && Unit.boardPosition unit == Just exit

                hasUnit : Bool
                hasUnit =
                    List.any blocksExit context.units

                hasCrate : Bool
                hasCrate =
                    List.any (\crate -> crate.position == exit) context.supplyCrates
            in
            insideMap && not (List.member exit reserved) && not hasUnit && not hasCrate

        option : Coordinate -> Movement.Option
        option exit =
            { destination = exit
            , path =
                [ origin
                , exit
                ]
            , cost = 0
            }
    in
    [ { x = origin.x
      , y = origin.y - 1
      }
    , { x = origin.x + 1
      , y = origin.y
      }
    , { x = origin.x
      , y = origin.y + 1
      }
    , { x = origin.x - 1
      , y = origin.y
      }
    ]
        |> List.filter available
        |> List.map option


selectedUnit : Context -> Model -> Maybe Unit
selectedUnit context state =
    selectedUnitFromSelection context (selection state)


traceTo : Context -> Coordinate -> Model -> Maybe Movement.Option
traceTo context position state =
    case ( selectedUnit context state, movementPlanning state ) of
        ( Just unit, Just planning ) ->
            if isOwnUnit context unit then
                Movement.preview
                    context.movementRules
                    context.map
                    context.units
                    (movementUnit planning.purpose unit)
                    planning.preview
                    position

            else
                Nothing

        _ ->
            Nothing


beginMovement : MovePurpose -> Context -> Unit -> Model -> Model
beginMovement purpose context unit state =
    case Unit.physicalPosition context.units unit of
        Just origin ->
            let
                planning : MovePlanning
                planning =
                    { purpose = purpose
                    , preview = Movement.start origin
                    , options =
                        Movement.optionsAvoiding
                            []
                            context.movementRules
                            context.map
                            context.units
                            (movementUnit purpose unit)
                            |> List.filter (canStop purpose context unit state)
                    , destinationFeedback = NoDestinationFeedback
                    }
            in
            state
                |> setUnitInteraction unit.id (ChoosingMove planning)

        Nothing ->
            state


boardingSpace : Context -> Unit -> Unit -> Model -> Bool
boardingSpace context mover truck state =
    let
        alreadyAboard : Int
        alreadyAboard =
            List.length
                (List.filter
                    (\unit -> Unit.carrierId unit == Just truck.id)
                    context.units
                )

        incomingPassengers : Int
        incomingPassengers =
            boardingPassengers context truck.id (orders state)
                |> List.filter ((/=) mover.id)
                |> List.length

        plannedCrates : Int
        plannedCrates =
            ListUtil.find (\order -> order.unitId == truck.id) (orders state)
                |> Maybe.map loadingCount
                |> Maybe.withDefault 0

        loadingCount : PlannedOrder -> Int
        loadingCount order =
            case order.action of
                PlannedOrder.SupplyTransfer plan ->
                    PlannedOrder.loadingCrates plan

                _ ->
                    0

        fitsCargo : Bool
        fitsCargo =
            alreadyAboard + Unit.crateCount truck + plannedCrates + incomingPassengers < truck.cargoCapacity

        compatible : Bool
        compatible =
            Unit.boardPosition truck
                |> Maybe.andThen
                    (\destination ->
                        loadingTarget context mover destination (orders state)
                    )
                |> Maybe.map .id
                |> (==) (Just truck.id)
    in
    compatible && fitsCargo


reservedDestinations : Context -> Unit -> Model -> List Coordinate
reservedDestinations context unit state =
    let
        reserves : PlannedOrder -> Bool
        reserves plan =
            let
                destinationTarget : Maybe Unit
                destinationTarget =
                    loadingTarget
                        context
                        unit
                        (PlannedOrder.destination plan)
                        (orders state)

                isWaitingTarget : Unit -> Bool
                isWaitingTarget target =
                    target.id
                        == plan.unitId
                        && not (receivingLoad context target (orders state) && target.cargoCapacity == 0)
                        && (target.cargoCapacity == 0 || boardingSpace context unit target state)

                waitingTarget : Bool
                waitingTarget =
                    not (PlannedOrder.isMoving plan) && (destinationTarget |> Maybe.map isWaitingTarget |> Maybe.withDefault False)

                boardingDestination : Bool
                boardingDestination =
                    destinationTarget |> Maybe.map (\target -> boardingSpace context unit target state) |> Maybe.withDefault False
            in
            plan.unitId /= unit.id && not waitingTarget && not boardingDestination

        unavailableReceiver : Unit -> Bool
        unavailableReceiver target =
            let
                boardingTarget : Coordinate -> Maybe Unit
                boardingTarget position =
                    loadingTarget context unit position (orders state)

                hasBoardingSpace : Unit -> Bool
                hasBoardingSpace truck =
                    boardingSpace context unit truck state

                canBoardAtTarget : Bool
                canBoardAtTarget =
                    Unit.boardPosition target
                        |> Maybe.andThen boardingTarget
                        |> Maybe.map hasBoardingSpace
                        |> Maybe.withDefault False
            in
            (target.id /= unit.id)
                && receivingLoad context target (orders state)
                && not canBoardAtTarget

        unavailableReceivers : List Coordinate
        unavailableReceivers =
            destinationUnits context (orders state)
                |> List.filter unavailableReceiver
                |> List.filterMap Unit.boardPosition

        savedDestinations : List Coordinate
        savedDestinations =
            destinations ++ passengerExits

        destinations : List Coordinate
        destinations =
            List.map PlannedOrder.destination (List.filter reserves (orders state))

        passengerExits : List Coordinate
        passengerExits =
            List.concatMap (PlannedOrder.unloads >> List.map .destination) (orders state)
    in
    savedDestinations ++ unavailableReceivers


saveMove : Context -> Unit -> Movement.Option -> Model -> List PlannedOrder
saveMove context unit move state =
    let
        receiver : Maybe Unit
        receiver =
            if movePurpose state == AttackMove then
                Nothing

            else
                moveReceiver context unit move state

        action : PlannedOrder.Action
        action =
            if movePurpose state == AttackMove then
                PlannedOrder.AttackMove move

            else
                PlannedOrder.Move { move = move, unloads = [] }

        retained : List PlannedOrder
        retained =
            orders state
                |> List.filter
                    (\plan ->
                        (plan.unitId /= unit.id)
                            && (Just plan.unitId /= Maybe.map .id receiver)
                    )

        receiverOrder : Unit -> Maybe PlannedOrder
        receiverOrder target =
            case ListUtil.find (\plan -> plan.unitId == target.id) (orders state) of
                Just plan ->
                    case plan.action of
                        PlannedOrder.SupplyTransfer _ ->
                            Just plan

                        _ ->
                            if PlannedOrder.isMoving plan then
                                Just plan

                            else
                                holdOrder context.units target

                Nothing ->
                    holdOrder context.units target

        receiverHold : List PlannedOrder
        receiverHold =
            receiver
                |> Maybe.andThen receiverOrder
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    { unitId = unit.id
    , action = action
    }
        :: (receiverHold ++ retained)


moveReceiver : Context -> Unit -> Movement.Option -> Model -> Maybe Unit
moveReceiver context unit move state =
    case Unit.carrierId unit of
        Just carrier ->
            context.units
                |> ListUtil.find
                    (\truck -> truck.id == carrier)

        Nothing ->
            loadingTarget
                context
                unit
                move.destination
                (orders state)


inspectSelectedUnit : Context -> Model -> Model
inspectSelectedUnit context state =
    case selectedUnit context state of
        Just unit ->
            setSelection (Just (Inspecting (UnitInspection unit.id))) state

        Nothing ->
            state


restoreCommands : Context -> Model -> Model
restoreCommands context state =
    case selectedUnit context state of
        Just unit ->
            setSelection (Just (unitSelection context unit state)) state

        Nothing ->
            state


unitSelection : Context -> Unit -> Model -> Selection
unitSelection context unit state =
    let
        hasOrder : Bool
        hasOrder =
            List.any (\order -> order.unitId == unit.id) (orders state)

        canChooseCommand : Bool
        canChooseCommand =
            isOwnUnit context unit
                && Unit.onBoard unit
                && not (receivingLoad context unit (orders state))
                && not hasOrder
    in
    if canChooseCommand then
        UnitSelection { id = unit.id, interaction = CommandMenu (ChoosingCommand Nothing) }

    else
        Inspecting (UnitInspection unit.id)


selectMovementTile : Context -> Coordinate -> Model -> Model
selectMovementTile context position model =
    let
        notOwnUnit : () -> Model
        notOwnUnit _ =
            setSelection (Just (Inspecting (TileInspection position))) model
    in
    case selectedUnit context model of
        Just unit ->
            if isOwnUnit context unit && pathPreview model /= Nothing then
                let
                    destinationOption : Movement.Option -> Maybe Movement.Option
                    destinationOption preview =
                        if canStop (movePurpose model) context unit model preview then
                            Just preview

                        else
                            Nothing
                in
                case
                    traceTo context position model
                        |> Maybe.andThen destinationOption
                of
                    Just move ->
                        let
                            offerReceiverLoading : Model -> Model
                            offerReceiverLoading =
                                if movePurpose model == AttackMove then
                                    identity

                                else
                                    case moveReceiver context unit move model of
                                        Just receiver ->
                                            offerTruckLoading context receiver

                                        Nothing ->
                                            identity
                        in
                        model
                            |> setOrders (saveMove context unit move model)
                            |> inspectSelectedUnit context
                            |> openUnloadPrompt context unit move
                            |> offerReceiverLoading

                    Nothing ->
                        setMoveDestinationFeedback DestinationUnavailable model

            else
                notOwnUnit ()

        Nothing ->
            notOwnUnit ()


setUnitInteraction : UnitId -> UnitInteraction -> Model -> Model
setUnitInteraction id interaction state =
    state
        |> setSelection (Just (UnitSelection { id = id, interaction = interaction }))


setMoveDestinationFeedback : DestinationFeedback -> Model -> Model
setMoveDestinationFeedback feedback state =
    case selection state of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingMove planning ->
                    state
                        |> setUnitInteraction
                            selected.id
                            (ChoosingMove
                                { planning | destinationFeedback = feedback }
                            )

                _ ->
                    state

        _ ->
            state


hasDialog : Model -> Bool
hasDialog state =
    case state of
        ChoosingCrates _ _ ->
            True

        _ ->
            commandGuideOpen state || submissionWarningOpen state || unloadChoice state /= Nothing


holdOrder : List Unit -> Unit -> Maybe PlannedOrder
holdOrder units unit =
    Unit.physicalPosition units unit
        |> Maybe.map
            (\position ->
                { unitId = unit.id
                , action = PlannedOrder.Hold position
                }
            )


movePurpose : Model -> MovePurpose
movePurpose state =
    movementPlanning state
        |> Maybe.map .purpose
        |> Maybe.withDefault NormalMove


movementUnit : MovePurpose -> Unit -> Unit
movementUnit purpose unit =
    let
        reserveCombatSupplies : UnitResources.UnitResources -> UnitResources.UnitResources
        reserveCombatSupplies resources =
            let
                supplies : Unit.Supplies.Supplies
                supplies =
                    resources.supplies
            in
            { resources
                | supplies =
                    { supplies
                        | current = supplies.current - unit.combatRules.readinessCost - unit.combatRules.shotCost
                    }
            }
    in
    case purpose of
        NormalMove ->
            unit

        AttackMove ->
            { unit
                | resources =
                    Maybe.map reserveCombatSupplies unit.resources
            }


canStop : MovePurpose -> Context -> Unit -> Model -> Movement.Option -> Bool
canStop purpose context unit state option =
    case purpose of
        NormalMove ->
            Movement.canStop
                (reservedDestinations context unit state)
                (destinationUnits context (orders state))
                unit
                option

        AttackMove ->
            let
                alliedOccupants : List Unit
                alliedOccupants =
                    destinationUnits
                        context
                        (orders state)
                        |> List.filter (\other -> other.playerNumber == unit.playerNumber)

                occupied : Bool
                occupied =
                    List.any
                        (\other ->
                            Unit.boardPosition other == Just option.destination
                        )
                        alliedOccupants
            in
            (option.cost > 0)
                && not occupied
                && not
                    (List.member
                        option.destination
                        (reservedDestinations context unit state)
                    )
