module GamePage.OrderPlanning exposing
    ( Context
    , Drafts
    , Model(..)
    , UnloadChoice
    , UnloadPlanning
    , applyCommand
    , chooseUnloadSquare
    , choosingDirection
    , commandMenuUnit
    , confirmPassengers
    , confirmPath
    , confirmUnloadPassengers
    , destinationFeedback
    , dismissDialog
    , extendPath
    , focusCommand
    , focusedCommand
    , init
    , isOwnUnit
    , loadingTarget
    , missingOrders
    , moveOptions
    , movementPlanning
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
    , startStationaryUnload
    , startUnload
    , submissionDrafts
    , submissionOrders
    , submissionWarningOpen
    , toggleUnloadPassenger
    , truckDestination
    , unloadChoice
    , unloadPlanning
    )

import Api.Enum.Direction as DirectionEnum exposing (Direction)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Coordinate exposing (Coordinate)
import Direction
import GamePage.Selection as Selection
    exposing
        ( DestinationFeedback(..)
        , FacingPurpose(..)
        , Inspection(..)
        , MovePlanning
        , Selection(..)
        , UnitInteraction(..)
        )
import Map exposing (Map)
import Movement
import PlannedOrder exposing (MovePlan, PlannedOrder, StationaryUnload)
import Unit exposing (Unit)
import UnitCommand
import UnitId exposing (UnitId)
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Read-only board and player data needed for local planning. Lifecycle and
camera state remain with the page.
-}
type alias Context =
    { map : Map
    , units : List Unit
    , movementRules : List Movement.Rule
    , playerSides : List PlayerNumber
    }


{-| Planning has one active workflow. Unload stages own their truck plan and
only other units' orders; dialogs and board inspection are derived from the stage.
-}
type Model
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

        ChoosingPassengers choice ->
            Just (Inspecting (Selection.UnitInspection choice.truck.truckId))

        ChoosingExits unloading ->
            Just (Inspecting (Selection.UnitInspection unloading.passengerId))


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
        , plan = MovingTruck { move = move, unloads = [] }
        }
        state


startStationaryUnload : UnitId -> Coordinate -> Model -> Model
startStationaryUnload truckId position state =
    startTruckUnload
        { truckId = truckId
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


toggleUnloadPassenger : UnitId -> Bool -> Model -> Model
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


confirmUnloadPassengers : (Model -> UnitId -> List Movement.Option) -> Model -> Model
confirmUnloadPassengers options state =
    case state of
        ChoosingPassengers choice ->
            nextUnloadPassenger options
                { truck = choice.truck
                , otherOrders = choice.otherOrders
                , passengers = List.reverse choice.checked
                }

        _ ->
            state


saveUnloadDestination : (Model -> UnitId -> List Movement.Option) -> Coordinate -> Model -> Model
saveUnloadDestination options destination state =
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

                    appendUnload : List PlannedOrder.UnloadOrder -> List PlannedOrder.UnloadOrder
                    appendUnload unloads =
                        unloads
                            ++ [ { unitId = unloading.passengerId
                                 , destination = destination
                                 }
                               ]

                    plan : TruckPlan
                    plan =
                        case truck.plan of
                            MovingTruck moving ->
                                MovingTruck
                                    { moving
                                        | unloads = appendUnload moving.unloads
                                    }

                            StationaryTruck stationary ->
                                StationaryTruck
                                    { stationary
                                        | unloads = appendUnload stationary.unloads
                                    }

                    updated : UnloadingTruck
                    updated =
                        { truck | plan = plan }
                in
                nextUnloadPassenger options
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


dismissDialog : Model -> Model
dismissDialog state =
    case state of
        ConfirmingSubmission drafts ->
            OrdinaryPlanning drafts

        ChoosingPassengers _ ->
            setSelection (selection state) state

        _ ->
            state


chooseUnloadSquare : Context -> Coordinate -> Model -> Model
chooseUnloadSquare context destination state =
    state
        |> saveUnloadDestination (unloadOptions context) destination


applyCommand : Context -> UnitCommand.Command -> Model -> Model
applyCommand context command state =
    case commandMenuUnit context state of
        Just unit ->
            let
                canApply : Bool
                canApply =
                    isOwnUnit context unit
                        && not (receivingLoad context unit (orders state))
                        && List.member command (UnitCommand.available unit)
                        && UnitCommand.canUse unit command
            in
            if canApply then
                case command of
                    UnitCommand.Move ->
                        beginMovement context unit state

                    UnitCommand.Rotate ->
                        state
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
                        state
                            |> setUnitInteraction
                                unit.id
                                (ChoosingDirection
                                    AmbushFacing
                                    (Maybe.withDefault
                                        DirectionEnum.North
                                        unit.direction
                                    )
                                )

                    UnitCommand.HoldPosition ->
                        holdPosition context unit state

                    _ ->
                        state

            else
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


{-| Only stationary units can receive a load. Departing allies free their
starting squares while their planned destinations remain reserved.
-}
loadingTarget : Context -> Unit -> Coordinate -> List PlannedOrder -> Maybe Unit
loadingTarget context mover destination drafts =
    Unit.loadingTarget (destinationUnits context drafts) mover destination


destinationUnits : Context -> List PlannedOrder -> List Unit
destinationUnits context drafts =
    let
        departing : Unit -> Bool
        departing unit =
            List.any
                (\plan ->
                    (plan.unitId == unit.id)
                        && PlannedOrder.isMoving plan
                )
                drafts
    in
    List.filter (departing >> not) context.units


receivingLoad : Context -> Unit -> List PlannedOrder -> Bool
receivingLoad context unit drafts =
    let
        receives : PlannedOrder -> Bool
        receives plan =
            if not (PlannedOrder.isMoving plan) then
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
                            (CommandMenu (Just command))

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
            (PlannedOrder.isMoving plan && List.member (PlannedOrder.destination plan) occupiedAgain)
                || List.any (\unload -> List.member unload.destination occupiedAgain) (PlannedOrder.unloads plan)

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
                choosingOccupiedDestination : Bool
                choosingOccupiedDestination =
                    ((pathPreview state /= Nothing)
                        || (unloadPlanning state /= Nothing)
                    )
                        && (Maybe.map .id (selectedUnit context state) /= Just id)
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
    case state of
        OrdinaryPlanning _ ->
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


choosingDirection : Model -> Bool
choosingDirection state =
    case selection state of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingDirection _ _ ->
                    True

                CommandMenu _ ->
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
    List.member unit.playerNumber context.playerSides


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
    confirmUnloadPassengers (unloadOptions context) state


focusedCommand : Model -> Maybe UnitCommand.MenuOption
focusedCommand state =
    case selection state of
        Just (UnitSelection selected) ->
            case selected.interaction of
                CommandMenu focused ->
                    focused

                ChoosingMove _ ->
                    Nothing

                ChoosingDirection _ _ ->
                    Nothing

        _ ->
            Nothing



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


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


nextUnloadPassenger : (Model -> UnitId -> List Movement.Option) -> UnloadQueue -> Model
nextUnloadPassenger options queue =
    case queue.passengers of
        [] ->
            OrdinaryPlanning
                { orders = truckOrder queue.truck :: queue.otherOrders
                , selection =
                    queue.truck.truckId
                        |> Selection.UnitInspection
                        |> Inspecting
                        |> Just
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

                state : Model
                state =
                    ChoosingExits unloading
            in
            ChoosingExits { unloading | options = options state passengerId }


openUnloadPrompt : Context -> Unit -> Movement.Option -> Model -> Model
openUnloadPrompt context truck move state =
    if hasPassengers context truck then
        state
            |> startUnload truck.id move

    else
        state


hasPassengers : Context -> Unit -> Bool
hasPassengers context truck =
    List.any (\passenger -> Unit.carrierId passenger == Just truck.id) context.units


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
            if hasPassengers context unit then
                next
                    |> startStationaryUnload
                        unit.id
                        (PlannedOrder.destination hold)

            else
                next

        Nothing ->
            state


unloadOptions : Context -> Model -> UnitId -> List Movement.Option
unloadOptions context state passengerId =
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

        Nothing ->
            []


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
                    unit
                    planning.preview
                    position

            else
                Nothing

        _ ->
            Nothing


beginMovement : Context -> Unit -> Model -> Model
beginMovement context unit state =
    case Unit.physicalPosition context.units unit of
        Just origin ->
            let
                planning : MovePlanning
                planning =
                    { preview = Movement.start origin
                    , options =
                        Movement.optionsAvoiding
                            []
                            context.movementRules
                            context.map
                            context.units
                            unit
                            |> List.filter
                                (Movement.canStop
                                    (reservedDestinations context unit state)
                                    (destinationUnits context (orders state))
                                    unit
                                )
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

        boarding : PlannedOrder -> Bool
        boarding plan =
            (plan.unitId /= mover.id)
                && PlannedOrder.isMoving plan
                && (Just (PlannedOrder.destination plan) == Unit.boardPosition truck)

        truckMoving : Bool
        truckMoving =
            List.any
                (\plan ->
                    plan.unitId == truck.id && PlannedOrder.isMoving plan
                )
                (orders state)

        fitsCargo : Bool
        fitsCargo =
            alreadyAboard + List.length (List.filter boarding (orders state)) < truck.cargoCapacity

        compatible : Bool
        compatible =
            Unit.boardPosition truck
                |> Maybe.andThen
                    (\destination ->
                        loadingTarget context mover destination (orders state)
                    )
                |> (==) (Just truck)
    in
    compatible && not truckMoving && fitsCargo


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
                    target.id == plan.unitId && not (receivingLoad context target (orders state) && target.cargoCapacity == 0)

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
            (target.id /= unit.id)
                && receivingLoad context target (orders state)
                && not (boardingSpace context unit target state)

        unavailableReceivers : List Coordinate
        unavailableReceivers =
            context.units
                |> List.filter unavailableReceiver
                |> List.filterMap Unit.boardPosition

        savedDestinations : List Coordinate
        savedDestinations =
            List.map
                PlannedOrder.destination
                (List.filter reserves (orders state))
                ++ List.concatMap
                    (PlannedOrder.unloads >> List.map .destination)
                    (orders state)
    in
    savedDestinations ++ unavailableReceivers


saveMove : Context -> Unit -> Movement.Option -> Model -> List PlannedOrder
saveMove context unit move state =
    let
        receiver : Maybe Unit
        receiver =
            case Unit.carrierId unit of
                Just carrier ->
                    context.units
                        |> ListUtil.find
                            (\truck -> truck.id == carrier)

                Nothing ->
                    loadingTarget context unit move.destination (orders state)

        retained : List PlannedOrder
        retained =
            orders state
                |> List.filter
                    (\plan ->
                        (plan.unitId /= unit.id)
                            && (Just plan.unitId /= Maybe.map .id receiver)
                    )

        receiverHold : List PlannedOrder
        receiverHold =
            receiver
                |> Maybe.andThen (holdOrder context.units)
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    { unitId = unit.id, action = PlannedOrder.Move { move = move, unloads = [] } } :: receiverHold ++ retained


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
        UnitSelection { id = unit.id, interaction = CommandMenu Nothing }

    else
        Inspecting (UnitInspection unit.id)


selectMovementTile : Context -> Coordinate -> Model -> Model
selectMovementTile context position state =
    let
        notOwnUnit : () -> Model
        notOwnUnit _ =
            setSelection (Just (Inspecting (TileInspection position))) state
    in
    case selectedUnit context state of
        Just unit ->
            if isOwnUnit context unit && pathPreview state /= Nothing then
                let
                    destinationOption : Movement.Option -> Maybe Movement.Option
                    destinationOption preview =
                        if
                            Movement.canStop
                                (reservedDestinations context unit state)
                                (destinationUnits context (orders state))
                                unit
                                preview
                        then
                            Just preview

                        else
                            Nothing
                in
                case
                    traceTo context position state
                        |> Maybe.andThen destinationOption
                of
                    Just move ->
                        setOrders (saveMove context unit move state) state
                            |> inspectSelectedUnit context
                            |> openUnloadPrompt context unit move

                    Nothing ->
                        setMoveDestinationFeedback DestinationUnavailable state

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
    submissionWarningOpen state || unloadChoice state /= Nothing


holdOrder : List Unit -> Unit -> Maybe PlannedOrder
holdOrder units unit =
    Unit.physicalPosition units unit
        |> Maybe.map
            (\position ->
                { unitId = unit.id
                , action = PlannedOrder.Hold position
                }
            )
