module Game.OrderPlanning exposing
    ( Drafts
    , InvariantViolation(..)
    , Model(..)
    , applyCommand
    , canRevokeOrder
    , canSelectUnloadCargo
    , chooseUnloadSquare
    , choosingDirection
    , choosingIndirectFire
    , clearTargetPreview
    , commandGuideOpen
    , commandMenuUnit
    , confirmGroundPickup
    , confirmPassengers
    , confirmPath
    , confirmUnloadPassengers
    , destinationFeedback
    , dismissDialog
    , extendPath
    , focusCommand
    , focusedCommand
    , indirectTargetPreview
    , indirectTargets
    , init
    , isOwnUnit
    , missingOrders
    , moveOptions
    , movementPlanning
    , openCommandGuide
    , orders
    , pathPreview
    , previewDirection
    , previewTile
    , promptDismountedCommands
    , restoreCommands
    , revokeSelectedOrder
    , saveDirection
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
    , unloadChoice
    , unloadPlanning
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Enum.UnitKind as Kind
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot as Depot exposing (Depot)
import Game.DestinationFeedback exposing (DestinationFeedback(..))
import Game.DirectionPlanning as DirectionPlanning
import Game.IndirectFirePlanning as IndirectFirePlanning exposing (IndirectFirePlanning)
import Game.Inspection as Inspection exposing (Inspection(..))
import Game.Map as Map exposing (Map)
import Game.MovePlanning as MovePlanning
    exposing
        ( MovePlanning
        , MovePurpose(..)
        )
import Game.Movement as Movement
import Game.OrderDependencies as OrderDependencies
import Game.PlannedOrder as PlannedOrder exposing (PlannedOrder)
import Game.PlannedTransport as PlannedTransport
import Game.Selection as Selection
    exposing
        ( CommandMenuState(..)
        , Selection(..)
        , UnitInteraction(..)
        )
import Game.Supply as Supply
import Game.Unit as Unit exposing (Unit)
import Game.UnitCommand as UnitCommand
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnloadCargo as UnloadCargo exposing (UnloadCargo)
import Game.UnloadPlanning as UnloadPlanning
    exposing
        ( UnloadChoice
        , UnloadPlanning
        )
import Game.UnloadingTruck as UnloadingTruck exposing (UnloadingTruck)
import InvariantCheck as IC exposing (InvariantCheck)
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Planning has one active workflow. Unload stages own their truck plan and
only other units' orders; dialogs and board inspection are derived from the stage.
-}
type Model
    = OrdinaryPlanning Drafts
    | ConfirmingSubmission Drafts
    | ChoosingCrates UnitId Depot Drafts
    | ChoosingGroundFreight UnitId Supply.GroundCrate Drafts
    | ChoosingPassengers UnloadChoice
    | ChoosingExits UnloadPlanning


type alias Drafts =
    { orders : List PlannedOrder
    , selection : Maybe Selection
    }


type InvariantViolation
    = PlanningUnitNotFound UnitId
    | CommandUnitHasNoPosition UnitId
    | LoadingOrderNotFound UnitId
    | TransportInvariantViolated PlannedTransport.InvariantViolation
    | OrderDependenciesInvariantViolated OrderDependencies.InvariantViolation
    | DirectionInvariantViolated DirectionPlanning.InvariantViolation
    | IndirectFireInvariantViolated IndirectFirePlanning.InvariantViolation



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
orders model =
    case model of
        OrdinaryPlanning drafts ->
            drafts.orders

        ConfirmingSubmission drafts ->
            drafts.orders

        ChoosingCrates _ _ drafts ->
            drafts.orders

        ChoosingGroundFreight _ _ drafts ->
            drafts.orders

        ChoosingPassengers choice ->
            UnloadingTruck.toOrder choice.truck :: choice.otherOrders

        ChoosingExits unloading ->
            UnloadingTruck.toOrder unloading.truck :: unloading.otherOrders


setOrders : List PlannedOrder -> Model -> Model
setOrders draftsOrders model =
    case model of
        OrdinaryPlanning drafts ->
            OrdinaryPlanning { drafts | orders = draftsOrders }

        _ ->
            model


selection : Model -> Maybe Selection
selection model =
    case model of
        OrdinaryPlanning drafts ->
            drafts.selection

        ConfirmingSubmission drafts ->
            drafts.selection

        ChoosingCrates id _ _ ->
            Just (Inspecting (UnitInspection id))

        ChoosingGroundFreight id _ _ ->
            Just (Inspecting (UnitInspection id))

        ChoosingPassengers choice ->
            Just (Inspecting (UnitInspection (UnloadingTruck.unitId choice.truck)))

        ChoosingExits unloading ->
            Just (Inspecting (UnitInspection (UnloadCargo.inspectionUnit unloading.truck unloading.cargo)))


{-| Return to ordinary planning with this selection. Leaving passenger or exit
selection cancels the pending truck order and unload choices, keeping other orders.
-}
setSelection : Maybe Selection -> Model -> Model
setSelection selected model =
    let
        retainedOrders : List PlannedOrder
        retainedOrders =
            case model of
                ChoosingPassengers choice ->
                    choice.otherOrders

                ChoosingExits unloading ->
                    unloading.otherOrders

                _ ->
                    orders model
    in
    OrdinaryPlanning { orders = retainedOrders, selection = selected }


{-| Unfinished unloading cannot become a submission. The lifecycle consumes
these drafts only after planning is ready or its warning has been confirmed.
-}
submissionDrafts : Model -> Maybe Drafts
submissionDrafts model =
    case model of
        OrdinaryPlanning drafts ->
            if commandGuideOpen model || choosingDirection model then
                Nothing

            else
                Just drafts

        ConfirmingSubmission drafts ->
            Just drafts

        _ ->
            Nothing


startUnload : UnitId -> Movement.Option -> Model -> Model
startUnload truckId move model =
    startTruckUnload (UnloadingTruck.moving truckId move) model


startStationaryUnload : UnitId -> Coordinate -> Model -> Model
startStationaryUnload truckId position model =
    startTruckUnload (UnloadingTruck.stationary truckId position) model


unloadChoice : Model -> Maybe UnloadChoice
unloadChoice model =
    case model of
        ChoosingPassengers choice ->
            Just choice

        _ ->
            Nothing


unloadPlanning : Model -> Maybe UnloadPlanning
unloadPlanning model =
    case model of
        ChoosingExits unloading ->
            Just unloading

        _ ->
            Nothing


{-| Check the whole selection, including scarce exits and passenger supplies.
Checked cargo always remains removable.
-}
canSelectUnloadCargo :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> UnloadCargo
    -> Model
    -> InvariantCheck InvariantViolation Bool
canSelectUnloadCargo map units playerNumbers movementRules supplyCrates cargo model =
    case model of
        ChoosingPassengers choice ->
            UnloadPlanning.canSelectCargo
                (unloadOptions map units playerNumbers movementRules supplyCrates)
                cargo
                choice

        _ ->
            IC.happy False


toggleAvailableUnloadCargo :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> UnloadCargo
    -> Bool
    -> Model
    -> InvariantCheck InvariantViolation Model
toggleAvailableUnloadCargo map units playerNumbers movementRules supplyCrates cargo checked model =
    if not checked then
        IC.happy (toggleUnloadCargo cargo False model)

    else
        let
            toggleIfAvailable : Bool -> Model
            toggleIfAvailable available =
                if available then
                    toggleUnloadCargo cargo True model

                else
                    model
        in
        canSelectUnloadCargo map units playerNumbers movementRules supplyCrates cargo model
            |> IC.map toggleIfAvailable


toggleUnloadPassenger : UnitId -> Bool -> Model -> Model
toggleUnloadPassenger id =
    toggleUnloadCargo (UnloadCargo.Passenger id)


toggleUnloadCargo : UnloadCargo -> Bool -> Model -> Model
toggleUnloadCargo cargo checked model =
    case model of
        ChoosingPassengers choice ->
            ChoosingPassengers (UnloadPlanning.toggleCargo cargo checked choice)

        _ ->
            model


confirmUnloadPassengers :
    List Unit
    -> List Supply.GroundCrate
    -> List Depot
    -> (UnloadPlanning -> InvariantCheck InvariantViolation (List Movement.Option))
    -> Model
    -> InvariantCheck InvariantViolation Model
confirmUnloadPassengers units supplyCrates depots exitOptions model =
    case model of
        ChoosingPassengers choice ->
            UnloadPlanning.confirm exitOptions choice
                |> IC.map (applyUnloadStep units supplyCrates depots)

        _ ->
            IC.happy model


saveUnloadDestination :
    List Unit
    -> List Supply.GroundCrate
    -> List Depot
    -> (UnloadPlanning -> InvariantCheck InvariantViolation (List Movement.Option))
    -> Coordinate
    -> Model
    -> InvariantCheck InvariantViolation Model
saveUnloadDestination units supplyCrates depots exitOptions destination model =
    case model of
        ChoosingExits planning ->
            UnloadPlanning.saveDestination exitOptions destination planning
                |> IC.map (applyUnloadStep units supplyCrates depots)

        _ ->
            IC.happy model


showSubmissionWarning : Model -> Model
showSubmissionWarning model =
    case model of
        OrdinaryPlanning drafts ->
            if commandGuideOpen model || choosingDirection model then
                model

            else
                ConfirmingSubmission drafts

        _ ->
            model


submissionWarningOpen : Model -> Bool
submissionWarningOpen model =
    case model of
        ConfirmingSubmission _ ->
            True

        _ ->
            False


dismissDialog : Model -> Model
dismissDialog model =
    case model of
        OrdinaryPlanning drafts ->
            case drafts.selection of
                Just (UnitSelection selected) ->
                    case selected.interaction of
                        CommandMenu (ReadingGuide focused) ->
                            setSelection
                                (Just (UnitSelection { selected | interaction = CommandMenu (ChoosingCommand focused) }))
                                model

                        _ ->
                            model

                _ ->
                    model

        ConfirmingSubmission drafts ->
            OrdinaryPlanning drafts

        ChoosingCrates _ _ drafts ->
            OrdinaryPlanning drafts

        ChoosingGroundFreight _ _ drafts ->
            OrdinaryPlanning drafts

        ChoosingPassengers _ ->
            setSelection (selection model) model

        _ ->
            model


confirmGroundPickup : Model -> InvariantCheck InvariantViolation Model
confirmGroundPickup model =
    case model of
        ChoosingGroundFreight id freight drafts ->
            case ListUtil.find (\order -> order.unitId == id) drafts.orders of
                Just order ->
                    let
                        pickup : PlannedOrder
                        pickup =
                            { unitId = id
                            , action =
                                PlannedOrder.SupplyTransfer
                                    { route = PlannedOrder.path order
                                    , destination = PlannedOrder.destination order
                                    , passengers = PlannedOrder.unloads order
                                    , handling = PlannedOrder.PickingUpGroundFreight freight.stock.kind
                                    }
                            }
                    in
                    OrdinaryPlanning
                        { drafts
                            | orders =
                                pickup
                                    :: List.filter
                                        (\other -> other.unitId /= id)
                                        drafts.orders
                        }
                        |> IC.happy

                Nothing ->
                    IC.violated (LoadingOrderNotFound id) model

        _ ->
            IC.happy model


chooseUnloadSquare :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> Coordinate
    -> Model
    -> InvariantCheck InvariantViolation Model
chooseUnloadSquare map units playerNumbers movementRules supplyCrates depots destination model =
    model
        |> saveUnloadDestination units
            supplyCrates
            depots
            (UnloadPlanning.availableOptions (unloadOptions map units playerNumbers movementRules supplyCrates))
            destination
        |> IC.map (promptDismountedCommands map units)


promptDismountedCommands : Map -> List Unit -> Model -> Model
promptDismountedCommands map units original =
    let
        model : Model
        model =
            case original of
                OrdinaryPlanning drafts ->
                    OrdinaryPlanning
                        { drafts
                            | orders =
                                PlannedTransport.withoutStalePassengerHolds map units drafts.orders
                        }

                ChoosingCrates id depot drafts ->
                    ChoosingCrates
                        id
                        depot
                        { drafts
                            | orders =
                                PlannedTransport.withoutStalePassengerHolds map units drafts.orders
                        }

                ChoosingGroundFreight id freight drafts ->
                    ChoosingGroundFreight
                        id
                        freight
                        { drafts
                            | orders =
                                PlannedTransport.withoutStalePassengerHolds map units drafts.orders
                        }

                _ ->
                    original
    in
    case model of
        OrdinaryPlanning _ ->
            case PlannedTransport.nextDismountedUnit map units (orders model) of
                Just unit ->
                    setUnitInteraction
                        unit.id
                        (CommandMenu (ChoosingCommand Nothing))
                        model

                Nothing ->
                    model

        _ ->
            model


applyCommand :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> UnitCommand.Command
    -> Model
    -> InvariantCheck InvariantViolation Model
applyCommand map units playerNumbers movementRules supplyCrates depots command model =
    case ( selection model, hasDialog model ) of
        ( Just (UnitSelection { interaction }), False ) ->
            case interaction of
                CommandMenu _ ->
                    case selectedUnit map units model of
                        Just unit ->
                            applyUnitCommand
                                map
                                units
                                playerNumbers
                                movementRules
                                supplyCrates
                                depots
                                command
                                unit
                                model

                        Nothing ->
                            missingSelectedUnit (selection model) model

                _ ->
                    IC.happy model

        _ ->
            IC.happy model


commandGuideOpen : Model -> Bool
commandGuideOpen model =
    case model of
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


openCommandGuide : Map -> List Unit -> List PlayerNumber -> Model -> Model
openCommandGuide map units playerNumbers model =
    case ( model, commandMenuUnit map units model ) of
        ( OrdinaryPlanning drafts, Just unit ) ->
            case drafts.selection of
                Just (UnitSelection selected) ->
                    case selected.interaction of
                        CommandMenu (ChoosingCommand focused) ->
                            if isOwnUnit playerNumbers unit then
                                setSelection
                                    (Just (UnitSelection { selected | interaction = CommandMenu (ReadingGuide focused) }))
                                    model

                            else
                                model

                        _ ->
                            model

                _ ->
                    model

        _ ->
            model


commandMenuUnit : Map -> List Unit -> Model -> Maybe Unit
commandMenuUnit map units model =
    case ( selection model, hasDialog model ) of
        ( Just (UnitSelection { interaction }), False ) ->
            case interaction of
                CommandMenu _ ->
                    selectedUnit map units model

                _ ->
                    Nothing

        _ ->
            Nothing


focusCommand : Map -> List Unit -> UnitCommand.MenuOption -> Model -> Model
focusCommand map units command model =
    case ( selection model, commandMenuUnit map units model ) of
        ( Just (UnitSelection selected), Just _ ) ->
            case selected.interaction of
                CommandMenu _ ->
                    model
                        |> setUnitInteraction
                            selected.id
                            (CommandMenu (ChoosingCommand (Just command)))

                _ ->
                    model

        _ ->
            model


canRevokeOrder : Map -> List Unit -> List PlayerNumber -> UnitId -> Model -> Bool
canRevokeOrder map units playerNumbers unitId model =
    case ( model, selectedUnit map units model ) of
        ( OrdinaryPlanning drafts, Just unit ) ->
            let
                selectionAllowsRevoking : Bool
                selectionAllowsRevoking =
                    case drafts.selection of
                        Just (Inspecting (UnitInspection _)) ->
                            True

                        Just (UnitSelection { interaction }) ->
                            case interaction of
                                CommandMenu _ ->
                                    True

                                _ ->
                                    False

                        _ ->
                            False
            in
            selectionAllowsRevoking
                && (unit.id == unitId)
                && isOwnUnit playerNumbers unit
                && (Unit.carrierId unit == Nothing)
                && List.any (\order -> order.unitId == unitId) drafts.orders

        _ ->
            False


revokeSelectedOrder :
    Map
    -> List Unit
    -> List PlayerNumber
    -> Model
    -> InvariantCheck InvariantViolation Model
revokeSelectedOrder map units playerNumbers model =
    case selectedUnit map units model of
        Just unit ->
            if canRevokeOrder map units playerNumbers unit.id model then
                let
                    saveOrders : List PlannedOrder -> Model
                    saveOrders retained =
                        setOrders retained model
                in
                OrderDependencies.revoke units [ unit.id ] (orders model)
                    |> IC.mapError OrderDependenciesInvariantViolated
                    |> IC.map saveOrders
                    |> IC.andThen (inspectSelectedUnit map units)

            else
                IC.happy model

        Nothing ->
            missingSelectedUnit (selection model) model


saveDirection :
    Map
    -> List Unit
    -> List PlayerNumber
    -> Direction
    -> Model
    -> InvariantCheck InvariantViolation Model
saveDirection map units playerNumbers direction model =
    case selection model of
        Just (UnitSelection { id, interaction }) ->
            let
                saveOrder : Maybe PlannedOrder -> InvariantCheck InvariantViolation Model
                saveOrder maybeOrder =
                    case maybeOrder of
                        Just order ->
                            model
                                |> setOrders (order :: List.filter (\other -> other.unitId /= id) (orders model))
                                |> finishUnitCommand map units

                        Nothing ->
                            IC.happy model
            in
            case interaction of
                ChoosingDirection planning ->
                    case planning of
                        DirectionPlanning.AttackMove move _ ->
                            DirectionPlanning.attackOrder id move direction
                                |> saveOrder

                        DirectionPlanning.Stationary purpose _ ->
                            case selectedUnit map units model of
                                Just unit ->
                                    let
                                        canSave : Bool
                                        canSave =
                                            isOwnUnit playerNumbers unit
                                                && not (PlannedTransport.receivingLoad units unit (orders model))
                                    in
                                    if canSave then
                                        DirectionPlanning.stationaryOrder purpose unit direction
                                            |> IC.mapError DirectionInvariantViolated
                                            |> IC.andThen saveOrder

                                    else
                                        IC.happy model

                                Nothing ->
                                    missingSelectedUnit (selection model) model

                _ ->
                    IC.happy model

        _ ->
            IC.happy model


selectUnit :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> UnitId
    -> Model
    -> InvariantCheck InvariantViolation Model
selectUnit map units playerNumbers movementRules supplyCrates depots id model =
    case ListUtil.find (\unit -> unit.id == id) units of
        Nothing ->
            IC.happy model

        Just unit ->
            let
                choosingTransportDestination : Bool
                choosingTransportDestination =
                    ((pathPreview model /= Nothing) || (unloadPlanning model /= Nothing))
                        && (Maybe.map .id (selectedUnit map units model) /= Just id)

                choosingOccupiedDestination : Bool
                choosingOccupiedDestination =
                    choosingIndirectFire model || choosingTransportDestination

                nextSelection : Selection
                nextSelection =
                    unitSelection map units playerNumbers unit model

                reopeningCommands : Bool
                reopeningCommands =
                    (selection model == Just (Inspecting (UnitInspection id)))
                        && (nextSelection /= Inspecting (UnitInspection id))
            in
            if choosingOccupiedDestination then
                Unit.mapPosition unit
                    |> Maybe.map
                        (\position ->
                            selectTile
                                map
                                units
                                playerNumbers
                                movementRules
                                supplyCrates
                                depots
                                position
                                model
                        )
                    |> Maybe.withDefault (IC.happy model)

            else if (Maybe.map .id (selectedUnit map units model) == Just id) && not reopeningCommands then
                IC.happy (setSelection Nothing model)

            else
                IC.happy (setSelection (Just nextSelection) model)


selectNextUnorderedUnit : Map -> List Unit -> List PlayerNumber -> Model -> Model
selectNextUnorderedUnit map units playerNumbers model =
    case ( model, hasDialog model ) of
        ( OrdinaryPlanning _, False ) ->
            let
                candidates : List Unit
                candidates =
                    missingOrders map units playerNumbers (orders model)

                currentId : Maybe UnitId
                currentId =
                    selectedUnit map units model |> Maybe.map .id

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
                    setSelection (Just (unitSelection map units playerNumbers unit model)) model

                Nothing ->
                    model

        _ ->
            model


selectTile :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> Coordinate
    -> Model
    -> InvariantCheck InvariantViolation Model
selectTile map units playerNumbers movementRules supplyCrates depots position model =
    if choosingIndirectFire model then
        saveIndirectFire map units position model

    else
        selectTransportTile map units playerNumbers movementRules supplyCrates depots position model


selectTransportTile :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> Coordinate
    -> Model
    -> InvariantCheck InvariantViolation Model
selectTransportTile map units playerNumbers movementRules supplyCrates depots position model =
    if unloadPlanning model /= Nothing then
        chooseUnloadSquare
            map
            units
            playerNumbers
            movementRules
            supplyCrates
            depots
            position
            model

    else
        selectMovementTile
            map
            units
            playerNumbers
            movementRules
            supplyCrates
            depots
            position
            model


previewTile :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> Coordinate
    -> Model
    -> Model
previewTile map units playerNumbers movementRules position model =
    case selection model of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingMove planning ->
                    let
                        savePreview : MovePlanning -> Model
                        savePreview updated =
                            setUnitInteraction selected.id (ChoosingMove updated) model
                    in
                    case selectedUnit map units model of
                        Just unit ->
                            if isOwnUnit playerNumbers unit then
                                MovePlanning.previewTo map units movementRules unit position planning
                                    |> Maybe.map savePreview
                                    |> Maybe.withDefault model

                            else
                                model

                        Nothing ->
                            model

                ChoosingIndirectFire planning ->
                    setUnitInteraction selected.id
                        (ChoosingIndirectFire (IndirectFirePlanning.previewTo map position planning))
                        model

                _ ->
                    model

        _ ->
            model


extendPath :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> Direction
    -> Model
    -> Model
extendPath map units playerNumbers movementRules direction model =
    case ( selectedUnit map units model, movementPlanning model ) of
        ( Just unit, Just planning ) ->
            let
                savePreview : MovePlanning -> Model
                savePreview updated =
                    setUnitInteraction unit.id (ChoosingMove updated) model
            in
            if isOwnUnit playerNumbers unit then
                MovePlanning.extendPath map units movementRules unit direction planning
                    |> Maybe.map savePreview
                    |> Maybe.withDefault model

            else
                model

        _ ->
            model


confirmPath :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> Model
    -> InvariantCheck InvariantViolation Model
confirmPath map units playerNumbers movementRules supplyCrates depots model =
    case pathPreview model of
        Just preview ->
            selectMovementTile
                map
                units
                playerNumbers
                movementRules
                supplyCrates
                depots
                preview.destination
                model

        Nothing ->
            IC.happy model


choosingIndirectFire : Model -> Bool
choosingIndirectFire model =
    case selection model of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingIndirectFire _ ->
                    True

                _ ->
                    False

        _ ->
            False


indirectTargetPreview : Model -> Maybe Coordinate
indirectTargetPreview model =
    case selection model of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingIndirectFire planning ->
                    IndirectFirePlanning.targetPreview planning

                _ ->
                    Nothing

        _ ->
            Nothing


clearTargetPreview : Model -> Model
clearTargetPreview model =
    case selection model of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingIndirectFire planning ->
                    setUnitInteraction selected.id (ChoosingIndirectFire (IndirectFirePlanning.clearPreview planning)) model

                _ ->
                    model

        _ ->
            model


indirectTargets : Map -> Model -> List Coordinate
indirectTargets map model =
    case selection model of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingIndirectFire planning ->
                    IndirectFirePlanning.targets map planning

                _ ->
                    []

        _ ->
            []


choosingDirection : Model -> Bool
choosingDirection model =
    case selection model of
        Just (UnitSelection { interaction }) ->
            case interaction of
                ChoosingDirection _ ->
                    True

                _ ->
                    False

        _ ->
            False


previewDirection : Direction -> Model -> Model
previewDirection direction model =
    case selection model of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingDirection planning ->
                    setUnitInteraction selected.id
                        (ChoosingDirection (DirectionPlanning.preview direction planning))
                        model

                _ ->
                    model

        _ ->
            model


movementPlanning : Model -> Maybe MovePlanning
movementPlanning model =
    case selection model of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingMove planning ->
                    Just planning

                _ ->
                    Nothing

        _ ->
            Nothing


destinationFeedback : Model -> DestinationFeedback
destinationFeedback model =
    case unloadPlanning model of
        Just planning ->
            planning.destinationFeedback

        Nothing ->
            movementPlanning model
                |> Maybe.map .destinationFeedback
                |> Maybe.withDefault NoDestinationFeedback


pathPreview : Model -> Maybe Movement.Option
pathPreview model =
    Maybe.map .preview (movementPlanning model)


moveOptions : Model -> List Movement.Option
moveOptions model =
    case unloadPlanning model of
        Just planning ->
            planning.options

        _ ->
            movementPlanning model
                |> Maybe.map .options
                |> Maybe.withDefault []


isOwnUnit : List PlayerNumber -> Unit -> Bool
isOwnUnit playerNumbers unit =
    List.member unit.playerNumber playerNumbers


selectedUnitFromSelection : List Unit -> Maybe Selection -> Maybe Unit
selectedUnitFromSelection units selected =
    let
        id : Maybe UnitId
        id =
            case selected of
                Just (Inspecting (UnitInspection unitId)) ->
                    Just unitId

                Just (UnitSelection unit) ->
                    Just unit.id

                _ ->
                    Nothing
    in
    id |> Maybe.andThen (\unitId -> ListUtil.find (\unit -> unit.id == unitId) units)


missingOrders : Map -> List Unit -> List PlayerNumber -> List PlannedOrder -> List Unit
missingOrders map units playerNumbers drafts =
    let
        missing : Unit -> Bool
        missing unit =
            isOwnUnit
                playerNumbers
                unit
                && Unit.onMap unit
                && not (List.any (\order -> order.unitId == unit.id) drafts)
    in
    units
        |> List.map (PlannedTransport.planningUnit map drafts)
        |> List.filter missing


submissionOrders : Map -> List Unit -> List PlayerNumber -> List PlannedOrder -> List PlannedOrder
submissionOrders map units playerNumbers drafts =
    let
        missing : Unit -> Bool
        missing unit =
            isOwnUnit
                playerNumbers
                unit
                && not (List.any (\order -> order.unitId == unit.id) drafts)

        holds : List PlannedOrder
        holds =
            units
                |> List.map (PlannedTransport.planningUnit map drafts)
                |> List.filter missing
                |> List.filterMap (PlannedOrder.hold units)
    in
    drafts ++ holds


confirmPassengers :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> Model
    -> InvariantCheck InvariantViolation Model
confirmPassengers map units playerNumbers movementRules supplyCrates depots model =
    case model of
        ChoosingPassengers choice ->
            let
                rawOptions :
                    UnloadPlanning
                    -> InvariantCheck InvariantViolation (List Movement.Option)
                rawOptions =
                    unloadOptions map units playerNumbers movementRules supplyCrates

                confirmIfPossible : Bool -> InvariantCheck InvariantViolation Model
                confirmIfPossible possible =
                    if possible then
                        confirmUnloadPassengers units supplyCrates depots (UnloadPlanning.availableOptions rawOptions) model

                    else
                        IC.happy model
            in
            UnloadPlanning.canConfirm rawOptions choice
                |> IC.andThen confirmIfPossible

        _ ->
            IC.happy model


focusedCommand : Model -> Maybe UnitCommand.MenuOption
focusedCommand model =
    case selection model of
        Just (UnitSelection selected) ->
            case selected.interaction of
                CommandMenu (ChoosingCommand focused) ->
                    focused

                CommandMenu (ReadingGuide focused) ->
                    focused

                ChoosingIndirectFire _ ->
                    Nothing

                ChoosingMove _ ->
                    Nothing

                ChoosingDirection _ ->
                    Nothing

        _ ->
            Nothing



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


applyUnitCommand :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> UnitCommand.Command
    -> Unit
    -> Model
    -> InvariantCheck InvariantViolation Model
applyUnitCommand map units playerNumbers movementRules supplyCrates depots command unit model =
    let
        canApply : Bool
        canApply =
            isOwnUnit playerNumbers unit
                && not (PlannedTransport.receivingLoad units unit (orders model))
                && List.member command (UnitCommand.available unit)
                && UnitCommand.canUse unit command
    in
    if canApply then
        case command of
            UnitCommand.IndirectFire ->
                let
                    beginTargeting : Maybe IndirectFirePlanning -> Model
                    beginTargeting maybePlanning =
                        case maybePlanning of
                            Just planning ->
                                setUnitInteraction unit.id (ChoosingIndirectFire planning) model

                            Nothing ->
                                model
                in
                IndirectFirePlanning.start unit
                    |> IC.mapError IndirectFireInvariantViolated
                    |> IC.map beginTargeting

            UnitCommand.Move ->
                beginMovement NormalMove map units movementRules unit model

            UnitCommand.AttackMove ->
                beginMovement AttackMove map units movementRules unit model

            UnitCommand.Ambush ->
                setUnitInteraction unit.id (ChoosingDirection (DirectionPlanning.ambush unit)) model
                    |> IC.happy

            UnitCommand.StandGround ->
                setUnitInteraction unit.id (ChoosingDirection (DirectionPlanning.standGround unit)) model
                    |> IC.happy

            UnitCommand.HoldPosition ->
                holdPosition map units supplyCrates depots unit model

            UnitCommand.DigIn ->
                case Unit.mapPosition unit of
                    Just position ->
                        let
                            planned : PlannedOrder
                            planned =
                                { unitId = unit.id
                                , action = PlannedOrder.DigIn position
                                }

                            otherOrders : List PlannedOrder
                            otherOrders =
                                List.filter (\other -> other.unitId /= unit.id) (orders model)
                        in
                        model
                            |> setOrders (planned :: otherOrders)
                            |> finishUnitCommand map units

                    Nothing ->
                        IC.violated (CommandUnitHasNoPosition unit.id) model

    else
        IC.happy model


{-| Called only after resolving the selected unit failed. An active command
requires that unit; an absent selection or stale inspection is an expected no-op.
Keep the caller's existing fallback value in either case.
-}
missingSelectedUnit : Maybe Selection -> value -> InvariantCheck InvariantViolation value
missingSelectedUnit selected fallback =
    case selected of
        Just (UnitSelection { id }) ->
            IC.violated (PlanningUnitNotFound id) fallback

        _ ->
            IC.happy fallback


saveIndirectFire :
    Map
    -> List Unit
    -> Coordinate
    -> Model
    -> InvariantCheck InvariantViolation Model
saveIndirectFire map units target model =
    case selectedUnit map units model of
        Just unit ->
            let
                saveOrder : Maybe PlannedOrder -> InvariantCheck InvariantViolation Model
                saveOrder maybeOrder =
                    case maybeOrder of
                        Just planned ->
                            model
                                |> setOrders (planned :: List.filter (\other -> other.unitId /= unit.id) (orders model))
                                |> finishUnitCommand map units

                        Nothing ->
                            IC.happy model
            in
            IndirectFirePlanning.order map unit target
                |> IC.mapError IndirectFireInvariantViolated
                |> IC.andThen saveOrder

        Nothing ->
            missingSelectedUnit (selection model) model


{-| A saved truck order offers the ground load or depot at its own destination.
The truck must have a free berth after accounting for planned boarding.
Crate unloading already owns freight handling and cannot combine with loading.
-}
offerCrateLoading :
    List Unit
    -> List Supply.GroundCrate
    -> List Depot
    -> PlannedOrder
    -> Drafts
    -> Model
offerCrateLoading units supplyCrates depots order drafts =
    let
        atDestination : Depot -> Bool
        atDestination depot =
            depot.position == PlannedOrder.destination order

        hasCargoRoom : Bool
        hasCargoRoom =
            List.any
                (\unit ->
                    (unit.id == order.unitId)
                        && (PlannedTransport.cargoRoom units unit drafts.orders > 0)
                )
                units

        destinationDepot : Maybe Depot
        destinationDepot =
            ListUtil.find atDestination depots

        offerGroundOrDepot : Maybe Depot -> Model
        offerGroundOrDepot depot =
            case ListUtil.find (\freight -> freight.position == PlannedOrder.destination order) supplyCrates of
                Just freight ->
                    ChoosingGroundFreight order.unitId freight drafts

                Nothing ->
                    case depot of
                        Just source ->
                            ChoosingCrates order.unitId source drafts

                        Nothing ->
                            OrdinaryPlanning drafts
    in
    case order.action of
        PlannedOrder.SupplyTransfer _ ->
            OrdinaryPlanning drafts

        _ ->
            if hasCargoRoom then
                offerGroundOrDepot destinationDepot

            else
                OrdinaryPlanning drafts


offerTruckLoading :
    List Unit
    -> List Supply.GroundCrate
    -> List Depot
    -> Unit
    -> Model
    -> InvariantCheck InvariantViolation Model
offerTruckLoading units supplyCrates depots unit model =
    case ( unit.kind, model ) of
        ( Kind.Truck, OrdinaryPlanning drafts ) ->
            case ListUtil.find (\order -> order.unitId == unit.id) drafts.orders of
                Just order ->
                    IC.happy (offerCrateLoading units supplyCrates depots order drafts)

                Nothing ->
                    IC.violated (LoadingOrderNotFound unit.id) model

        _ ->
            IC.happy model


applyUnloadStep : List Unit -> List Supply.GroundCrate -> List Depot -> UnloadPlanning.Step -> Model
applyUnloadStep units supplyCrates depots step =
    case step of
        UnloadPlanning.ChoosingExit planning ->
            ChoosingExits planning

        UnloadPlanning.Finished truck otherOrders ->
            finishUnloading units
                supplyCrates
                depots
                truck
                otherOrders
                (Just (Inspecting (UnitInspection (UnloadingTruck.unitId truck))))


finishUnloading : List Unit -> List Supply.GroundCrate -> List Depot -> UnloadingTruck -> List PlannedOrder -> Maybe Selection -> Model
finishUnloading units supplyCrates depots truck otherOrders selected =
    let
        order : PlannedOrder
        order =
            UnloadingTruck.toOrder truck
    in
    offerCrateLoading units
        supplyCrates
        depots
        order
        { orders = order :: otherOrders
        , selection = selected
        }


skipUnloading : Map -> List Unit -> List Supply.GroundCrate -> List Depot -> Model -> Model
skipUnloading map units supplyCrates depots model =
    case model of
        ChoosingPassengers choice ->
            finishUnloading units supplyCrates depots choice.truck choice.otherOrders Nothing
                |> promptDismountedCommands map units

        ChoosingExits unloading ->
            finishUnloading units supplyCrates depots unloading.truck unloading.otherOrders Nothing
                |> promptDismountedCommands map units

        _ ->
            model


startTruckUnload : UnloadingTruck -> Model -> Model
startTruckUnload truck model =
    case model of
        OrdinaryPlanning drafts ->
            ChoosingPassengers (UnloadPlanning.startChoice truck drafts.orders)

        _ ->
            model


openUnloadPrompt :
    List Unit
    -> List Supply.GroundCrate
    -> List Depot
    -> Unit
    -> Movement.Option
    -> Model
    -> InvariantCheck InvariantViolation Model
openUnloadPrompt units supplyCrates depots truck move model =
    if PlannedTransport.hasCargo units truck then
        model
            |> startUnload truck.id move
            |> IC.happy

    else
        offerTruckLoading units supplyCrates depots truck model


holdPosition :
    Map
    -> List Unit
    -> List Supply.GroundCrate
    -> List Depot
    -> Unit
    -> Model
    -> InvariantCheck InvariantViolation Model
holdPosition map units supplyCrates depots unit model =
    case PlannedOrder.hold units unit of
        Just hold ->
            let
                next : InvariantCheck InvariantViolation Model
                next =
                    setOrders
                        (hold
                            :: List.filter
                                (\plan -> plan.unitId /= unit.id)
                                (orders model)
                        )
                        model
                        |> finishUnitCommand map units
            in
            if PlannedTransport.hasCargo units unit then
                next
                    |> IC.map (startStationaryUnload unit.id (PlannedOrder.destination hold))

            else
                next |> IC.andThen (offerTruckLoading units supplyCrates depots unit)

        Nothing ->
            IC.violated (CommandUnitHasNoPosition unit.id) model


unloadOptions :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> UnloadPlanning
    -> InvariantCheck InvariantViolation (List Movement.Option)
unloadOptions map units playerNumbers movementRules supplyCrates planning =
    let
        violation : UnloadPlanning.InvariantViolation -> InvariantViolation
        violation error =
            case error of
                UnloadPlanning.PassengerNotFound id ->
                    PlanningUnitNotFound id
    in
    UnloadPlanning.options map
        units
        playerNumbers
        movementRules
        supplyCrates
        (PlannedTransport.occupancy units)
        planning
        |> IC.mapError violation


selectedUnit : Map -> List Unit -> Model -> Maybe Unit
selectedUnit map units model =
    selectedUnitFromSelection units (selection model)
        |> Maybe.map (PlannedTransport.planningUnit map (orders model))


traceTo :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> Coordinate
    -> Model
    -> Maybe Movement.Option
traceTo map units playerNumbers movementRules position model =
    case ( selectedUnit map units model, movementPlanning model ) of
        ( Just unit, Just planning ) ->
            if isOwnUnit playerNumbers unit then
                MovePlanning.traceTo map units movementRules unit position planning

            else
                Nothing

        _ ->
            Nothing


beginMovement :
    MovePurpose
    -> Map
    -> List Unit
    -> List Movement.Rule
    -> Unit
    -> Model
    -> InvariantCheck InvariantViolation Model
beginMovement purpose map units movementRules unit model =
    case Unit.physicalPosition units unit of
        Just origin ->
            let
                planning : MovePlanning
                planning =
                    MovePlanning.start purpose map units movementRules (orders model) unit origin
            in
            model
                |> setUnitInteraction unit.id (ChoosingMove planning)
                |> IC.happy

        Nothing ->
            IC.violated (CommandUnitHasNoPosition unit.id) model


inspectSelectedUnit : Map -> List Unit -> Model -> InvariantCheck InvariantViolation Model
inspectSelectedUnit map units model =
    case selectedUnit map units model of
        Just unit ->
            IC.happy (setSelection (Just (Inspecting (UnitInspection unit.id))) model)

        Nothing ->
            missingSelectedUnit (selection model) model


finishUnitCommand : Map -> List Unit -> Model -> InvariantCheck InvariantViolation Model
finishUnitCommand map units model =
    inspectSelectedUnit map units model
        |> IC.map (promptDismountedCommands map units)


restoreCommands :
    Map
    -> List Unit
    -> List PlayerNumber
    -> Model
    -> InvariantCheck InvariantViolation Model
restoreCommands map units playerNumbers model =
    case selectedUnit map units model of
        Just unit ->
            IC.happy (setSelection (Just (unitSelection map units playerNumbers unit model)) model)

        Nothing ->
            missingSelectedUnit (selection model) model


unitSelection : Map -> List Unit -> List PlayerNumber -> Unit -> Model -> Selection
unitSelection map units playerNumbers original model =
    let
        unit : Unit
        unit =
            PlannedTransport.planningUnit map (orders model) original

        hasOrder : Bool
        hasOrder =
            List.any (\order -> order.unitId == unit.id) (orders model)

        canChooseCommand : Bool
        canChooseCommand =
            isOwnUnit playerNumbers unit
                && Unit.onMap unit
                && not (PlannedTransport.receivingLoad units unit (orders model))
                && not hasOrder
    in
    if canChooseCommand then
        UnitSelection { id = unit.id, interaction = CommandMenu (ChoosingCommand Nothing) }

    else
        Inspecting (UnitInspection unit.id)


selectMovementTile :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> List Depot
    -> Coordinate
    -> Model
    -> InvariantCheck InvariantViolation Model
selectMovementTile map units playerNumbers movementRules supplyCrates depots position model =
    let
        notOwnUnit : () -> Model
        notOwnUnit _ =
            setSelection (Just (Inspecting (TileInspection position))) model
    in
    case selectedUnit map units model of
        Just unit ->
            if isOwnUnit playerNumbers unit && pathPreview model /= Nothing then
                let
                    destinationOption : Movement.Option -> Maybe Movement.Option
                    destinationOption preview =
                        if MovePlanning.canStop (movePurpose model) units unit (orders model) preview then
                            Just preview

                        else
                            Nothing
                in
                case
                    traceTo map units playerNumbers movementRules position model
                        |> Maybe.andThen destinationOption
                of
                    Just move ->
                        let
                            offerReceiverLoading : Model -> InvariantCheck InvariantViolation Model
                            offerReceiverLoading state =
                                let
                                    offerToReceiver : Maybe Unit -> InvariantCheck InvariantViolation Model
                                    offerToReceiver receiver =
                                        case receiver of
                                            Just target ->
                                                offerTruckLoading units supplyCrates depots target state

                                            Nothing ->
                                                IC.happy state
                                in
                                PlannedTransport.moveReceiver units unit move (orders model)
                                    |> IC.mapError TransportInvariantViolated
                                    |> IC.andThen offerToReceiver

                            saveOrders : List PlannedOrder -> Model
                            saveOrders drafts =
                                setOrders drafts model
                        in
                        if movePurpose model == AttackMove then
                            setUnitInteraction unit.id
                                (ChoosingDirection (DirectionPlanning.attackMove move unit))
                                model
                                |> IC.happy

                        else
                            PlannedTransport.moveOrders units unit move (orders model)
                                |> IC.mapError TransportInvariantViolated
                                |> IC.map saveOrders
                                |> IC.andThen (finishUnitCommand map units)
                                |> IC.andThen (openUnloadPrompt units supplyCrates depots unit move)
                                |> IC.andThen offerReceiverLoading

                    Nothing ->
                        IC.happy (setMoveDestinationFeedback DestinationUnavailable model)

            else
                IC.happy (notOwnUnit ())

        Nothing ->
            missingSelectedUnit (selection model) (notOwnUnit ())


setUnitInteraction : UnitId -> UnitInteraction -> Model -> Model
setUnitInteraction id interaction model =
    model
        |> setSelection (Just (UnitSelection { id = id, interaction = interaction }))


setMoveDestinationFeedback : DestinationFeedback -> Model -> Model
setMoveDestinationFeedback feedback model =
    case selection model of
        Just (UnitSelection selected) ->
            case selected.interaction of
                ChoosingMove planning ->
                    model
                        |> setUnitInteraction
                            selected.id
                            (ChoosingMove
                                (MovePlanning.setDestinationFeedback feedback planning)
                            )

                _ ->
                    model

        _ ->
            model


hasDialog : Model -> Bool
hasDialog model =
    case model of
        ChoosingCrates _ _ _ ->
            True

        ChoosingGroundFreight _ _ _ ->
            True

        _ ->
            commandGuideOpen model || submissionWarningOpen model || unloadChoice model /= Nothing


movePurpose : Model -> MovePurpose
movePurpose model =
    movementPlanning model
        |> Maybe.map .purpose
        |> Maybe.withDefault NormalMove
