module Game.TurnPlayback exposing
    ( CombatExchange
    , Encounter(..)
    , Frame
    , ImpactEncounter
    , Loss
    , LossCause(..)
    , LossEvent
    , MapView(..)
    , Panel
    , Playback
    , Presentation(..)
    , acknowledgeLoss
    , activeEncounter
    , cameraPositions
    , combat
    , continueCombat
    , focusPositions
    , init
    , initial
    , lossEvent
    , losses
    , movingPositions
    , panels
    , selection
    , setFrameLosses
    , setFrameShots
    , setFrameUnits
    , setMapView
    , spotlight
    , start
    , tick
    , tickUntilLoss
    , unitOpacity
    , visibleIndirectImpacts
    , visibleShots
    )

import Api.Enum.CombatKind as CombatKind exposing (CombatKind)
import Api.Enum.Direction exposing (Direction)
import Api.Enum.Entrenchment as Entrenchment
import Api.Object
import Api.Object.CarrierUnitLoss as CarrierLossApi
import Api.Object.CombatUnitLoss as CombatLossApi
import Api.Object.ConcealedIndirectFireUnitLoss as ConcealedLossApi
import Api.Object.ExhaustedUnitLoss as ExhaustionLossApi
import Api.Object.GameSnapshot as GameApi
import Api.Object.TurnFrame as FrameApi
import Api.Object.TurnResolution as ResolutionApi
import Api.Object.UnitDeparture as DepartureApi
import Api.Union
import Api.Union.DirectUnitLoss as DirectLossApi
import Api.Union.UnitLoss as LossApi
import Game.CombatHealth as CombatHealth exposing (CombatHealth)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot as Depot exposing (Depot)
import Game.Direction as Direction
import Game.IndirectImpact as IndirectImpact exposing (IndirectImpact)
import Game.Shot as Shot exposing (Shot)
import Game.SpriteFacing as SpriteFacing
import Game.Supply as Supply
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Location exposing (Location)
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Point exposing (Point)
import Util.List as ListUtil


type alias Frame =
    { losses : List Loss
    , durationMs : Int
    , units : List Unit
    , departures : List Departure
    , indirectImpacts : List IndirectImpact
    , sabotages : List Coordinate
    , shots : List Shot
    , visibleTiles : List Coordinate
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    }


type alias Departure =
    { unitId : UnitId
    , direction : Direction
    }


type Encounter
    = Exchange CombatExchange
    | Impact ImpactEncounter
    | Sabotage Depot
    | Exhaustion Unit


{-| One landing scene combines target and depot damage while retaining every
observed firing participant. Concealed origins have no entry in attackers.
-}
type alias ImpactEncounter =
    { destination : Coordinate
    , attackers : List IndirectImpact.Attacker
    , target : Maybe IndirectImpact.Target
    , depot : Maybe IndirectImpact.BuildingImpact
    }


type alias Playback =
    { current : Frame
    , remaining : List PreparedFrame
    , elapsed : Float
    , presentation : Presentation
    , acknowledgedLosses : List UnitId
    , movement : FrameMovement
    }


{-| Movement is prepared once for each authoritative boundary. Its elapsed time
excludes the current frame's local clock, so pauses need no timeline changes.
-}
type alias FrameMovement =
    { segments : List MovementSegment
    , cameraPositions : List Point
    }


type alias MovementSegment =
    { unitId : UnitId
    , edge : MovementEdge
    , durationMs : Float
    , elapsedMs : Float
    }


{-| A combined volley retains its final snapshot, but entering it still uses
the opening frame's duration. Keep that arrival delay with the prepared frame.
-}
type alias PreparedFrame =
    { frame : Frame
    , arrivalDurationMs : Int
    , movement : FrameMovement
    }


type alias PreparedTurn =
    { current : PreparedFrame
    , remaining : List PreparedFrame
    }


{-| Time already traveled toward each unit's next arrival, before the current
shared frame. Other units' arrivals must not restart that edge's clock.
-}
type alias MovementElapsed =
    { unitId : UnitId
    , elapsedMs : Float
    }


type Presentation
    = Battlefield
    | Combat CombatFocus
    | Deaths { focus : CombatFocus, frame : Frame, elapsed : Float }


type alias CombatFocus =
    { encounter : Encounter
    , remaining : List Encounter
    , before : Frame
    , stage : CombatStage
    }


type CombatStage
    = Spotlighting Float
    | ShowingPanels { elapsed : Float, mapView : MapView }


type MapView
    = CardVisible
    | SeeingMap


type alias Panel =
    { encounter : Encounter
    , elapsed : Float
    , mapView : MapView
    }


type alias CombatExchange =
    { kind : CombatKind
    , attacker : Unit
    , target : Unit
    , attackerHealth : CombatHealth
    , targetHealth : CombatHealth
    , targetFired : Bool
    , attackerFlankBonus : Bool
    , targetFlankBonus : Bool
    }


type LossPolicy
    = AwaitAcknowledgment
    | ContinueAutomatically


type alias Loss =
    { unit : Unit
    , cause : LossCause
    }


type LossCause
    = Destroyed CombatKind Unit
    | ConcealedIndirectFire
    | SuppliesExhausted
    | CarrierLost Unit LossCause


setPresentation : Presentation -> Playback -> Playback
setPresentation presentation model =
    { model | presentation = presentation }


setElapsed : Float -> Playback -> Playback
setElapsed elapsed model =
    { model | elapsed = elapsed }


setFrameLosses : List Loss -> Frame -> Frame
setFrameLosses recordedLosses model =
    { model | losses = recordedLosses }


setFrameShots : List Shot -> Frame -> Frame
setFrameShots shots model =
    { model | shots = shots }


setFrameUnits : List Unit -> Frame -> Frame
setFrameUnits units model =
    { model | units = units }


setCombatFocusStage : CombatStage -> CombatFocus -> CombatFocus
setCombatFocusStage stage model =
    { model | stage = stage }


{-| Recorded causes supply meaning; the held board determines when each casualty
is ready for acknowledgment. Portraits never introduce concealed battlefield units.
-}
losses : Playback -> List Loss
losses playback =
    let
        frame : Frame
        frame =
            lossFrame playback

        pending : Loss -> Maybe Loss
        pending loss =
            let
                displayedCasualty : Unit -> Bool
                displayedCasualty unit =
                    (unit.id == loss.unit.id) && Unit.isDying unit
            in
            if List.member loss.unit.id playback.acknowledgedLosses then
                Nothing

            else
                ListUtil.find displayedCasualty frame.units
                    |> Maybe.map (\unit -> { loss | unit = unit })
    in
    List.filterMap pending frame.losses


type alias LossEvent =
    { loss : Loss
    , passengers : List Unit
    }


{-| A carrier and its projected passengers form one loss event, regardless of
unit ordering. Independent casualties in the same frame remain separate events.
-}
lossEvent : Playback -> Maybe LossEvent
lossEvent playback =
    let
        pending : List Loss
        pending =
            losses playback

        event : Loss -> LossEvent
        event first =
            let
                carrierId : UnitId
                carrierId =
                    case first.cause of
                        CarrierLost carrier _ ->
                            carrier.id

                        _ ->
                            first.unit.id

                primary : Loss
                primary =
                    ListUtil.find
                        (\loss -> loss.unit.id == carrierId)
                        pending
                        |> Maybe.withDefault first

                aboard : Loss -> Bool
                aboard loss =
                    case loss.cause of
                        CarrierLost carrier _ ->
                            carrier.id == primary.unit.id

                        _ ->
                            False
            in
            { loss = primary
            , passengers = List.filter aboard pending |> List.map .unit
            }
    in
    List.head pending |> Maybe.map event


lossFrame : Playback -> Frame
lossFrame playback =
    case playback.presentation of
        Deaths deaths ->
            deaths.frame

        Battlefield ->
            playback.current

        Combat focus ->
            focus.before


acknowledgeLoss : UnitId -> Playback -> Playback
acknowledgeLoss unitId playback =
    let
        acknowledged : List UnitId
        acknowledged =
            case lossEvent playback of
                Just event ->
                    if event.loss.unit.id == unitId then
                        unitId :: List.map .id event.passengers

                    else
                        [ unitId ]

                Nothing ->
                    [ unitId ]
    in
    { playback | acknowledgedLosses = acknowledged ++ playback.acknowledgedLosses }


{-| Stop at loss boundaries even when a delayed animation tick spans the whole
turn. Acknowledging a carrier also acknowledges its passengers; independent losses remain queued.
-}
tickUntilLoss : Float -> Playback -> ( Maybe Playback, Frame )
tickUntilLoss =
    tickWithLossPause AwaitAcknowledgment


combat : Playback -> Maybe CombatExchange
combat playback =
    case activeEncounter playback of
        Just (Exchange exchange) ->
            Just exchange

        _ ->
            Nothing


activeEncounter : Playback -> Maybe Encounter
activeEncounter playback =
    case playback.presentation of
        Combat focus ->
            Just focus.encounter

        Deaths _ ->
            Nothing

        Battlefield ->
            Nothing


spotlight : Playback -> Maybe (List Coordinate)
spotlight playback =
    case playback.presentation of
        Combat { encounter, before, stage } ->
            case stage of
                Spotlighting _ ->
                    Just (encounterPositions before encounter)

                ShowingPanels panel ->
                    case panel.mapView of
                        SeeingMap ->
                            Just (encounterPositions before encounter)

                        CardVisible ->
                            Nothing

        Deaths _ ->
            Nothing

        Battlefield ->
            Nothing


panels : Playback -> Maybe Panel
panels playback =
    case playback.presentation of
        Combat { encounter, stage } ->
            case stage of
                ShowingPanels panel ->
                    Just
                        { encounter = encounter
                        , elapsed = panel.elapsed
                        , mapView = panel.mapView
                        }

                Spotlighting _ ->
                    Nothing

        Deaths _ ->
            Nothing

        Battlefield ->
            Nothing


visibleShots : Playback -> List Shot
visibleShots playback =
    case playback.presentation of
        Combat _ ->
            []

        Deaths _ ->
            []

        Battlefield ->
            playback.current.shots


{-| Encounter participants remain available even when concealed on the board.
Reciprocal shots share one display; casualties clear after their own encounter.
-}
exchanges : Frame -> List CombatExchange
exchanges frame =
    let
        collect : List Shot -> List CombatExchange
        collect shots =
            case shots of
                [] ->
                    []

                shot :: rest ->
                    let
                        differentPair : Shot -> Bool
                        differentPair other =
                            not
                                ((other.origin == shot.origin && other.destination == shot.destination)
                                    || (other.origin == shot.destination && other.destination == shot.origin)
                                )

                        includesAttackMove : Shot -> Bool
                        includesAttackMove other =
                            not (differentPair other) && other.kind == CombatKind.AttackMove

                        kind : CombatKind
                        kind =
                            if shot.kind == CombatKind.IndirectFire then
                                CombatKind.IndirectFire

                            else if List.any includesAttackMove (shot :: rest) then
                                CombatKind.AttackMove

                            else
                                CombatKind.Ambush

                        remaining : List CombatExchange
                        remaining =
                            collect (List.filter differentPair rest)

                        flankingReturn : Shot -> Bool
                        flankingReturn other =
                            not (differentPair other)
                                && (other.attacker.id == shot.target.id)
                                && other.flankBonus
                    in
                    { kind = kind
                    , attacker = shot.attacker
                    , target = shot.target
                    , attackerHealth = shot.attackerHealth
                    , targetHealth = shot.targetHealth
                    , targetFired =
                        List.any (\other -> not (differentPair other) && other.attacker.id == shot.target.id) rest
                    , attackerFlankBonus = shot.flankBonus
                    , targetFlankBonus = List.any flankingReturn rest
                    }
                        :: remaining
    in
    collect frame.shots |> List.filter displayExchange


{-| Simultaneous shots can overkill a target already lost in an earlier pair.
Keep zero-damage encounters between living units and any reciprocal damage,
but do not open an empty scene for a redundant post-death pair.
-}
displayExchange : CombatExchange -> Bool
displayExchange exchange =
    let
        bothAlive : Bool
        bothAlive =
            (exchange.attackerHealth.before.current > 0) && (exchange.targetHealth.before.current > 0)

        healthChanged : CombatHealth -> Bool
        healthChanged health =
            health.before.current /= health.after.current
    in
    bothAlive || healthChanged exchange.attackerHealth || healthChanged exchange.targetHealth


{-| Impact scenes retain observable targets independently of firing origins.
Confirmed indirect shots already have their own exchange at the same landing.
-}
encounters : FrameTransition -> List Encounter
encounters frames =
    let
        frame : Frame
        frame =
            frames.next

        needsImpactScene : ImpactEncounter -> Bool
        needsImpactScene impact =
            let
                confirmsLanding : Shot -> Bool
                confirmsLanding shot =
                    (shot.kind == CombatKind.IndirectFire)
                        && (shot.destination == impact.destination)
            in
            (impact.depot /= Nothing) || not (List.any confirmsLanding frame.shots)

        needsExchange : CombatExchange -> Bool
        needsExchange exchange =
            let
                sharesDepotImpact : IndirectImpact -> Bool
                sharesDepotImpact impact =
                    (impact.depot /= Nothing) && (Unit.mapPosition exchange.target == Just impact.destination)

                includesDepotDamage : Bool
                includesDepotDamage =
                    (exchange.kind == CombatKind.IndirectFire) && List.any sharesDepotImpact frame.indirectImpacts
            in
            not includesDepotDamage

        unique : IndirectImpact -> List ImpactEncounter -> List ImpactEncounter
        unique impact impacts =
            let
                attackers : List IndirectImpact.Attacker
                attackers =
                    impact.attacker |> Maybe.map List.singleton |> Maybe.withDefault []

                merge : ImpactEncounter -> ImpactEncounter
                merge existing =
                    if existing.destination == impact.destination then
                        { existing
                            | attackers = existing.attackers ++ attackers
                            , target = combineImpactTargets existing.target impact.target
                            , depot =
                                case ( existing.depot, impact.depot ) of
                                    ( Just earlier, Just later ) ->
                                        Just { earlier | after = later.after }

                                    ( Nothing, later ) ->
                                        later

                                    ( earlier, Nothing ) ->
                                        earlier
                        }

                    else
                        existing
            in
            if List.any (\existing -> existing.destination == impact.destination) impacts then
                List.map merge impacts

            else
                impacts
                    ++ [ { destination = impact.destination
                         , attackers = attackers
                         , target = impact.target
                         , depot = impact.depot
                         }
                       ]

        combatEncounters : List Encounter
        combatEncounters =
            exchanges frame
                |> List.filter needsExchange
                |> List.map Exchange

        impactEncounters : List Encounter
        impactEncounters =
            frame.indirectImpacts
                |> List.foldl unique []
                |> List.filter needsImpactScene
                |> List.map Impact
    in
    orderEncounters frame (combatEncounters ++ impactEncounters)
        ++ sabotageEncounters frames
        ++ exhaustionEncounters frames.next


sabotageEncounters : FrameTransition -> List Encounter
sabotageEncounters frames =
    let
        encounter : Coordinate -> Maybe Encounter
        encounter position =
            ListUtil.find (\depot -> depot.position == position) frames.current.depots
                |> Maybe.map Sabotage
    in
    List.filterMap encounter frames.next.sabotages


exhaustionEncounters : Frame -> List Encounter
exhaustionEncounters frame =
    let
        encounter : Loss -> Maybe Encounter
        encounter loss =
            case loss.cause of
                SuppliesExhausted ->
                    if Unit.onMap loss.unit then
                        Just (Exhaustion loss.unit)

                    else
                        Nothing

                _ ->
                    Nothing
    in
    List.filterMap encounter frame.losses


{-| Impact-only shells belong to the same simultaneous volley as confirmed hits.
Show a gun's outgoing encounter before a scene that destroys it, including when
several landings merge into one scene. Only projected firing identities are used.
Keep the existing order where possible; simultaneous cycles retain stable order.
-}
orderEncounters : Frame -> List Encounter -> List Encounter
orderEncounters frame pending =
    let
        attackers : Encounter -> List UnitId
        attackers encounter =
            case encounter of
                Exchange exchange ->
                    let
                        samePair : Shot -> Bool
                        samePair shot =
                            ((shot.attacker.id == exchange.attacker.id)
                                && (shot.target.id == exchange.target.id)
                            )
                                || ((shot.attacker.id == exchange.target.id)
                                        && (shot.target.id == exchange.attacker.id)
                                   )
                    in
                    frame.shots |> List.filter samePair |> List.map (.attacker >> .id)

                Impact impact ->
                    List.map (.unit >> .id) impact.attackers

                Sabotage _ ->
                    []

                Exhaustion _ ->
                    []

        canPresent : Encounter -> Bool
        canPresent candidate =
            let
                casualties : List UnitId
                casualties =
                    encounterCasualties candidate

                isCasualty : UnitId -> Bool
                isCasualty id =
                    List.member id casualties

                stillFiring : Encounter -> Bool
                stillFiring other =
                    (other /= candidate)
                        && List.any isCasualty (attackers other)
            in
            not (List.any stillFiring pending)
    in
    case ListUtil.find canPresent pending of
        Just next ->
            next :: orderEncounters frame (List.filter ((/=) next) pending)

        Nothing ->
            pending


encounterCasualties : Encounter -> List UnitId
encounterCasualties encounter =
    case encounter of
        Exchange exchange ->
            let
                casualty : Unit -> CombatHealth -> Maybe UnitId
                casualty unit health =
                    if health.after.current == 0 then
                        Just unit.id

                    else
                        Nothing
            in
            List.filterMap identity
                [ casualty exchange.attacker exchange.attackerHealth
                , casualty exchange.target exchange.targetHealth
                ]

        Impact impact ->
            IndirectImpact.destroyedUnitId impact |> Maybe.map List.singleton |> Maybe.withDefault []

        Sabotage _ ->
            []

        Exhaustion unit ->
            [ unit.id ]


{-| Several concealed guns can hit the same observed unit in one volley. Its
single landing scene spans the complete health change, including a later kill.
-}
combineImpactTargets :
    Maybe IndirectImpact.Target
    -> Maybe IndirectImpact.Target
    -> Maybe IndirectImpact.Target
combineImpactTargets first second =
    case ( first, second ) of
        ( Just earlier, Just later ) ->
            if earlier.unit.id == later.unit.id then
                Just
                    { earlier
                        | health =
                            { before =
                                { current =
                                    max
                                        earlier.health.before.current
                                        later.health.before.current
                                , maximum = earlier.health.before.maximum
                                }
                            , after =
                                { current =
                                    min
                                        earlier.health.after.current
                                        later.health.after.current
                                , maximum = earlier.health.after.maximum
                                }
                            }
                    }

            else
                first

        ( Nothing, _ ) ->
            second

        ( _, Nothing ) ->
            first


beginFrame : Frame -> PreparedTurn -> Playback
beginFrame before prepared =
    let
        frames : FrameTransition
        frames =
            { current = before
            , next = prepared.current.frame
            }

        presentation : Presentation
        presentation =
            case encounters frames of
                encounter :: rest ->
                    Combat
                        { encounter = encounter
                        , remaining = rest
                        , before =
                            before
                                |> setFrameShots []
                        , stage = Spotlighting 0
                        }

                [] ->
                    Battlefield
    in
    { current = frames.next
    , remaining = prepared.remaining
    , elapsed = 0
    , presentation = presentation
    , acknowledgedLosses = []
    , movement = prepared.current.movement
    }


{-| A stationary head-on exchange can span two authoritative volleys. Present
both hits together while retaining the server's damage and final board state.
A return volley may include unrelated pairs. Never cross movement, visibility
changes, an intervening encounter, or a casualty.
-}
combineReturnFire : Frame -> List Frame -> ( Frame, List Frame )
combineReturnFire opening pending =
    let
        unitLocation : Unit -> { id : UnitId, location : Location }
        unitLocation unit =
            { id = unit.id
            , location = unit.location
            }

        stationary : Frame -> Bool
        stationary frame =
            (List.map unitLocation frame.units == List.map unitLocation opening.units)
                && List.isEmpty frame.indirectImpacts
                && List.isEmpty opening.indirectImpacts
                && (frame.visibleTiles == opening.visibleTiles)
                && (frame.depots == opening.depots)
                && (frame.supplyCrates == opening.supplyCrates)

        findReturn : Shot -> List Frame -> ( Frame, List Frame )
        findReturn shot remaining =
            case remaining of
                frame :: rest ->
                    if not (stationary frame) then
                        ( opening, pending )

                    else
                        case frame.shots of
                            [] ->
                                if List.any Unit.isDying frame.units then
                                    ( opening, pending )

                                else
                                    findReturn shot rest

                            returnShots ->
                                let
                                    reciprocal : Shot -> Bool
                                    reciprocal other =
                                        (other.kind /= CombatKind.IndirectFire)
                                            && (other.attacker.id == shot.target.id)
                                            && (other.target.id == shot.attacker.id)
                                            && (other.origin == shot.destination)
                                            && (other.destination == shot.origin)

                                    unrelated : Shot -> Bool
                                    unrelated other =
                                        not (List.member other.attacker.id [ shot.attacker.id, shot.target.id ])
                                            && not (List.member other.target.id [ shot.attacker.id, shot.target.id ])

                                    returns : List Shot
                                    returns =
                                        List.filter reciprocal returnShots

                                    otherShots : List Shot
                                    otherShots =
                                        List.filter (not << reciprocal) returnShots
                                in
                                case returns of
                                    [ returnShot ] ->
                                        if List.all unrelated otherShots then
                                            combine shot returnShot otherShots frame rest

                                        else
                                            ( opening, pending )

                                    _ ->
                                        ( opening, pending )

                [] ->
                    ( opening, pending )

        combine : Shot -> Shot -> List Shot -> Frame -> List Frame -> ( Frame, List Frame )
        combine shot returnShot otherShots frame rest =
            let
                attackerHealth : CombatHealth
                attackerHealth =
                    { before = shot.attackerHealth.before
                    , after = returnShot.targetHealth.after
                    }

                targetHealth : CombatHealth
                targetHealth =
                    { before = shot.targetHealth.before
                    , after = returnShot.attackerHealth.after
                    }

                shots : List Shot
                shots =
                    [ (shot
                        |> Shot.setTargetHealth
                            targetHealth
                      )
                        |> Shot.setAttackerHealth
                            attackerHealth
                    , (returnShot
                        |> Shot.setTargetHealth
                            attackerHealth
                      )
                        |> Shot.setAttackerHealth
                            targetHealth
                    ]
                        ++ otherShots
            in
            ( frame
                |> setFrameShots shots
                |> setFrameLosses (opening.losses ++ frame.losses)
            , rest
            )
    in
    case opening.shots of
        [ shot ] ->
            if (shot.kind == CombatKind.IndirectFire) || List.any Unit.isDying opening.units then
                ( opening, pending )

            else
                findReturn shot pending

        _ ->
            ( opening, pending )


type alias FrameTransition =
    { current : Frame
    , next : Frame
    }


type alias MovementEdge =
    { origin : Coordinate
    , destination : Coordinate
    , portion : Float -- One tile between sightings; half a tile to the fog boundary.
    }


selection :
    SelectionSet Unit Api.Object.Unit
    -> SelectionSet Coordinate Api.Object.Coordinate
    -> SelectionSet (List Frame) Api.Object.GameSnapshot
selection unit coordinate =
    GameApi.lastResolution
        (ResolutionApi.frames
            (SS.succeed Frame
                |> SS.with (FrameApi.losses (lossSelection unit))
                |> SS.with FrameApi.durationMs
                |> SS.with (FrameApi.units unit)
                |> SS.with
                    (FrameApi.departures
                        (SS.succeed Departure
                            |> SS.with (DepartureApi.unitId |> SS.mapOrFail UnitId.parse)
                            |> SS.with DepartureApi.direction
                        )
                    )
                |> SS.with (FrameApi.indirectImpacts IndirectImpact.selection)
                |> SS.with (FrameApi.sabotages Coordinate.selection)
                |> SS.with (FrameApi.shots Shot.selection)
                |> SS.with (FrameApi.visibleTiles coordinate)
                |> SS.with (FrameApi.depots Depot.selection)
                |> SS.with (FrameApi.supplyCrates Supply.crateSelection)
            )
        )
        |> SS.map (Maybe.withDefault [])


lossSelection : SelectionSet Unit Api.Object.Unit -> SelectionSet Loss Api.Union.UnitLoss
lossSelection unit =
    LossApi.fragments
        { onCombatUnitLoss = combatLossSelection unit
        , onExhaustedUnitLoss = exhaustionLossSelection unit
        , onConcealedIndirectFireUnitLoss = concealedLossSelection unit
        , onCarrierUnitLoss = carrierLossSelection unit
        }


combatLossSelection : SelectionSet Unit Api.Object.Unit -> SelectionSet Loss Api.Object.CombatUnitLoss
combatLossSelection unit =
    SS.succeed Loss
        |> SS.with (CombatLossApi.unit unit)
        |> SS.with
            (SS.succeed Destroyed
                |> SS.with CombatLossApi.kind
                |> SS.with (CombatLossApi.attacker unit)
            )


exhaustionLossSelection : SelectionSet Unit Api.Object.Unit -> SelectionSet Loss Api.Object.ExhaustedUnitLoss
exhaustionLossSelection unit =
    SS.succeed Loss
        |> SS.with (ExhaustionLossApi.unit unit)
        |> SS.with (SS.succeed SuppliesExhausted)


concealedLossSelection : SelectionSet Unit Api.Object.Unit -> SelectionSet Loss Api.Object.ConcealedIndirectFireUnitLoss
concealedLossSelection unit =
    SS.succeed Loss
        |> SS.with (ConcealedLossApi.unit unit)
        |> SS.with (SS.succeed ConcealedIndirectFire)


carrierLossSelection : SelectionSet Unit Api.Object.Unit -> SelectionSet Loss Api.Object.CarrierUnitLoss
carrierLossSelection unit =
    let
        carrierCause : Loss -> LossCause
        carrierCause carrier =
            CarrierLost carrier.unit carrier.cause
    in
    SS.succeed Loss
        |> SS.with (CarrierLossApi.unit unit)
        |> SS.with
            (CarrierLossApi.carrierLoss
                (DirectLossApi.fragments
                    { onCombatUnitLoss = combatLossSelection unit
                    , onExhaustedUnitLoss = exhaustionLossSelection unit
                    , onConcealedIndirectFireUnitLoss = concealedLossSelection unit
                    }
                )
                |> SS.map carrierCause
            )


initial : List Frame -> Frame -> Frame
initial frames fallback =
    List.head frames
        |> Maybe.withDefault fallback


{-| Prepare a nonempty sequence of projected snapshots for local playback.
All movement lookahead, boundary checks and camera routes are resolved here.
-}
init : Frame -> List Frame -> Playback
init current remaining =
    beginFrame current (prepareFrames [] current remaining)


start : List Frame -> Maybe Playback
start frames =
    case clearPresentedDeaths [] frames of
        current :: next :: remaining ->
            Just (init current (next :: remaining))

        _ ->
            Nothing


prepareFrames : List MovementElapsed -> Frame -> List Frame -> PreparedTurn
prepareFrames elapsed opening pending =
    let
        ( current, remaining ) =
            combineReturnFire opening pending

        frames : List Frame
        frames =
            movementFrames current remaining

        segments : List MovementSegment
        segments =
            List.filterMap (prepareMovementSegment frames elapsed current) current.units

        following : List PreparedFrame
        following =
            case remaining of
                next :: rest ->
                    let
                        prepared : PreparedTurn
                        prepared =
                            prepareFrames
                                (carryMovementElapsed elapsed
                                    { current = current
                                    , next = next
                                    }
                                )
                                next
                                rest
                    in
                    prepared.current :: prepared.remaining

                [] ->
                    []
    in
    { current =
        { frame = current
        , arrivalDurationMs = opening.durationMs
        , movement =
            { segments = segments
            , cameraPositions = movementCameraPositions current frames segments
            }
        }
    , remaining = following
    }


{-| Combat keeps casualties in authoritative snapshots until end-of-turn cleanup.
Use recorded loss IDs to show each death once, then omit the finished marker and corpse
from subsequent presentation frames so later movement can resume with focus.
The transition after a death frame already supplies the server's death pause.
-}
clearPresentedDeaths : List UnitId -> List Frame -> List Frame
clearPresentedDeaths presented frames =
    case frames of
        [] ->
            []

        frame :: remaining ->
            let
                deaths : List UnitId
                deaths =
                    List.map (.unit >> .id) frame.losses

                units : List Unit
                units =
                    List.filter
                        (\unit -> not (List.member unit.id presented))
                        frame.units
            in
            (frame
                |> setFrameUnits units
                |> setFrameLosses (List.filter (\loss -> not (List.member loss.unit.id presented)) frame.losses)
            )
                :: clearPresentedDeaths (deaths ++ presented) remaining


{-| Battlefield frames use server durations and retain surplus time between
boundaries. Combat adds a local pause before a volley and discards surplus there
so a delayed animation tick cannot skip its presentation.
-}
tick : Float -> Playback -> ( Maybe Playback, Frame )
tick =
    tickWithLossPause ContinueAutomatically


hasPendingLoss : LossPolicy -> Playback -> Bool
hasPendingLoss policy playback =
    case policy of
        AwaitAcknowledgment ->
            not (List.isEmpty (losses playback))

        ContinueAutomatically ->
            False


tickWithLossPause : LossPolicy -> Float -> Playback -> ( Maybe Playback, Frame )
tickWithLossPause lossPolicy delta playback =
    if hasPendingLoss lossPolicy playback then
        ( Just playback, lossFrame playback )

    else
        tickPresentation lossPolicy delta playback


tickPresentation : LossPolicy -> Float -> Playback -> ( Maybe Playback, Frame )
tickPresentation lossPolicy delta playback =
    case playback.presentation of
        Combat focus ->
            tickCombat delta focus playback

        Deaths deaths ->
            if deaths.elapsed + delta >= deathDuration playback then
                let
                    isCasualty : Unit -> Unit -> Bool
                    isCasualty unit dead =
                        Unit.isDying dead && dead.id == unit.id

                    keepSurvivor : Unit -> Bool
                    keepSurvivor unit =
                        not (List.any (isCasualty unit) deaths.frame.units)

                    focus : CombatFocus
                    focus =
                        deaths.focus

                    before : Frame
                    before =
                        deaths.frame

                    current : Frame
                    current =
                        playback.current

                    advanced : { animation : Playback, frame : Frame }
                    advanced =
                        advanceCombat
                            { focus
                                | before =
                                    before
                                        |> setFrameUnits (List.filter keepSurvivor before.units)
                            }
                            { playback
                                | current =
                                    current
                                        |> setFrameUnits (List.filter keepSurvivor current.units)
                            }
                in
                ( Just advanced.animation, advanced.frame )

            else
                ( Just
                    (playback
                        |> setPresentation (Deaths { deaths | elapsed = deaths.elapsed + delta })
                    )
                , deaths.frame
                )

        Battlefield ->
            tickBattlefield lossPolicy delta playback


tickCombat : Float -> CombatFocus -> Playback -> ( Maybe Playback, Frame )
tickCombat delta focus playback =
    let
        stage : CombatStage
        stage =
            case focus.stage of
                Spotlighting elapsed ->
                    if elapsed + delta >= 300 then
                        ShowingPanels { elapsed = 0, mapView = CardVisible }

                    else
                        Spotlighting (elapsed + delta)

                ShowingPanels panel ->
                    -- Allow staggered unit casualties followed by a depot strike and automatic-close pause.
                    ShowingPanels { panel | elapsed = min 6000 (panel.elapsed + delta) }
    in
    ( Just
        (playback
            |> setPresentation
                (Combat
                    (focus
                        |> setCombatFocusStage stage
                    )
                )
        )
    , focus.before
    )


setMapView : MapView -> Playback -> Playback
setMapView mapView playback =
    case playback.presentation of
        Combat focus ->
            case focus.stage of
                ShowingPanels panel ->
                    playback
                        |> setPresentation
                            (Combat
                                (focus
                                    |> setCombatFocusStage (ShowingPanels { panel | mapView = mapView })
                                )
                            )

                Spotlighting _ ->
                    playback

        Deaths _ ->
            playback

        Battlefield ->
            playback


continueCombat : Playback -> Maybe { animation : Playback, frame : Frame }
continueCombat playback =
    case playback.presentation of
        Combat focus ->
            case focus.stage of
                Spotlighting _ ->
                    Nothing

                ShowingPanels _ ->
                    let
                        frame : Frame
                        frame =
                            exchangeDeathFrame playback.current focus
                    in
                    if List.any Unit.isDying frame.units then
                        Just
                            { animation =
                                playback
                                    |> setPresentation (Deaths { focus = focus, frame = frame, elapsed = 0 })
                            , frame = frame
                            }

                    else
                        Just (advanceCombat focus playback)

        Deaths _ ->
            Nothing

        Battlefield ->
            Nothing


{-| Use the server's post-volley feedback duration for each encounter's deaths.
No concealed portrait is added to the battlefield, and cargo follows its carrier.
-}
deathDuration : Playback -> Float
deathDuration playback =
    List.head playback.remaining
        |> Maybe.map (.arrivalDurationMs >> toFloat)
        |> Maybe.withDefault 1400


exchangeDeathFrame : Frame -> CombatFocus -> Frame
exchangeDeathFrame projected focus =
    let
        casualties : List UnitId
        casualties =
            encounterCasualties focus.encounter

        before : Frame
        before =
            focus.before

        projectedCasualty : Unit -> Bool
        projectedCasualty unit =
            let
                dyingUnit : Unit -> Bool
                dyingUnit seen =
                    seen.id == unit.id && Unit.isDying seen
            in
            List.any dyingUnit projected.units

        present : Unit -> Unit
        present unit =
            let
                destroyed : Bool
                destroyed =
                    projectedCasualty unit
                        && (List.member unit.id casualties
                                || (Unit.carrierId unit |> Maybe.map (\id -> List.member id casualties) |> Maybe.withDefault False)
                           )
            in
            unit
                |> Unit.setDestroyed destroyed
    in
    before
        |> setFrameUnits (List.map present before.units)
        |> setFrameLosses projected.losses


advanceCombat : CombatFocus -> Playback -> { animation : Playback, frame : Frame }
advanceCombat focus playback =
    case focus.remaining of
        encounter :: rest ->
            { animation =
                playback
                    |> setPresentation
                        (Combat
                            ({ focus | encounter = encounter, remaining = rest }
                                |> setCombatFocusStage (Spotlighting 0)
                            )
                        )
            , frame = focus.before
            }

        [] ->
            { animation =
                playback
                    |> setPresentation Battlefield
                    |> setElapsed 0
            , frame = playback.current
            }


tickBattlefield : LossPolicy -> Float -> Playback -> ( Maybe Playback, Frame )
tickBattlefield lossPolicy delta playback =
    case playback.remaining of
        [] ->
            ( Nothing, playback.current )

        next :: remaining ->
            let
                elapsed : Float
                elapsed =
                    playback.elapsed + delta
            in
            if elapsed >= toFloat next.arrivalDurationMs then
                let
                    advanced : Playback
                    advanced =
                        beginFrame playback.current
                            { current = next
                            , remaining = remaining
                            }
                in
                case advanced.presentation of
                    Combat focus ->
                        ( Just advanced, focus.before )

                    Deaths deaths ->
                        ( Just advanced, deaths.frame )

                    Battlefield ->
                        if hasPendingLoss lossPolicy advanced then
                            ( Just advanced, advanced.current )

                        else
                            tickWithLossPause lossPolicy (elapsed - toFloat next.arrivalDurationMs) advanced

            else
                ( Just
                    (playback
                        |> setElapsed elapsed
                    )
                , presentationFrame playback
                )


presentationFrame : Playback -> Frame
presentationFrame playing =
    let
        faceMovement : Unit -> Unit
        faceMovement unit =
            case
                ListUtil.find (\segment -> segment.unitId == unit.id) playing.movement.segments
            of
                Just segment ->
                    let
                        edge : MovementEdge
                        edge =
                            segment.edge

                        movementDirection : Maybe Direction
                        movementDirection =
                            Direction.between edge.origin edge.destination
                    in
                    Unit.faceDirection
                        (unit.direction
                            |> Maybe.andThen
                                (\_ -> movementDirection)
                        )
                        (unit
                            |> Unit.setSpriteFacing (SpriteFacing.turn movementDirection unit.spriteFacing)
                            |> Unit.setEntrenchment Entrenchment.Exposed
                        )
                        |> Unit.setOnMap edge.origin

                Nothing ->
                    unit
    in
    { departures = playing.current.departures
    , losses = playing.current.losses
    , sabotages = playing.current.sabotages
    , indirectImpacts = playing.current.indirectImpacts
    , depots = playing.current.depots
    , supplyCrates = playing.current.supplyCrates
    , shots = playing.current.shots
    , durationMs = playing.current.durationMs
    , units = List.map faceMovement playing.current.units
    , visibleTiles = playing.current.visibleTiles
    }


observedMovement : FrameTransition -> Unit -> Maybe MovementEdge
observedMovement frames unit =
    let
        sameUnit : Unit -> Bool
        sameUnit target =
            target.id == unit.id

        origin : Maybe Coordinate
        origin =
            Unit.physicalPosition frames.current.units unit

        destination : Maybe Coordinate
        destination =
            ListUtil.find sameUnit frames.next.units
                |> Maybe.andThen Unit.mapPosition
    in
    case ( origin, destination ) of
        ( Just from, Just to ) ->
            let
                isAdjacent : Bool
                isAdjacent =
                    abs (to.x - from.x) + abs (to.y - from.y) == 1
            in
            if isAdjacent then
                Just
                    { origin = from
                    , destination = to
                    , portion = 1
                    }

            else
                Nothing

        ( Just from, Nothing ) ->
            let
                exit : Departure -> MovementEdge
                exit departure =
                    { origin = from
                    , destination = Direction.step from departure.direction
                    , portion = 0.5
                    }
            in
            ListUtil.find (\departure -> departure.unitId == unit.id) frames.current.departures
                |> Maybe.map exit

        _ ->
            Nothing


frameHasFeedback : Frame -> Bool
frameHasFeedback frame =
    not (List.isEmpty frame.shots && List.isEmpty frame.losses && List.isEmpty frame.indirectImpacts && List.isEmpty frame.sabotages)


{-| Feedback and transport are real pauses. Visibility changes alone are not:
only sightings of the same unit at the same square may bridge a boundary.
-}
canContinueMovement : FrameTransition -> Bool
canContinueMovement frames =
    let
        passengers : List Unit
        passengers =
            (frames.current.units ++ frames.next.units)
                |> List.filter (\unit -> Unit.carrierId unit /= Nothing)

        changesCarrier : Unit -> Bool
        changesCarrier unit =
            case
                ( ListUtil.find (\other -> other.id == unit.id) frames.current.units
                , ListUtil.find (\other -> other.id == unit.id) frames.next.units
                )
            of
                ( Just before, Just after ) ->
                    Unit.carrierId before /= Unit.carrierId after

                _ ->
                    False
    in
    not
        (frameHasFeedback frames.current
            || frameHasFeedback frames.next
            || List.any changesCarrier passengers
        )


elapsedMovement : UnitId -> List MovementElapsed -> Float
elapsedMovement unitId elapsed =
    elapsed
        |> ListUtil.find (\movement -> movement.unitId == unitId)
        |> Maybe.map .elapsedMs
        |> Maybe.withDefault 0


{-| During preparation, include the boundary itself for direct movement such
as unloading. Movement never looks beyond feedback or transport pauses.
-}
movementFrames : Frame -> List Frame -> List Frame
movementFrames frame pending =
    let
        untilPause : Frame -> List Frame -> List Frame
        untilPause current remaining =
            case remaining of
                next :: rest ->
                    if canContinueMovement { current = current, next = next } then
                        next :: untilPause next rest

                    else
                        [ next ]

                [] ->
                    []
    in
    untilPause frame pending


carryMovementElapsed : List MovementElapsed -> FrameTransition -> List MovementElapsed
carryMovementElapsed elapsed frames =
    let
        carry : Unit -> Maybe MovementElapsed
        carry unit =
            let
                unchangedPosition : Unit -> Bool
                unchangedPosition other =
                    (other.id == unit.id)
                        && (Unit.mapPosition other == Unit.mapPosition unit)
            in
            if Unit.onMap unit && List.any unchangedPosition frames.next.units then
                Just
                    { unitId = unit.id
                    , elapsedMs = elapsedMovement unit.id elapsed + toFloat frames.next.durationMs
                    }

            else
                Nothing
    in
    if canContinueMovement frames then
        List.filterMap carry frames.current.units

    else
        []


prepareMovementSegment : List Frame -> List MovementElapsed -> Frame -> Unit -> Maybe MovementSegment
prepareMovementSegment frames elapsed frame unit =
    let
        findArrival : Frame -> List Frame -> Float -> Maybe MovementSegment
        findArrival current remaining durationMs =
            case remaining of
                next :: rest ->
                    let
                        transition : FrameTransition
                        transition =
                            { current = current, next = next }

                        totalMs : Float
                        totalMs =
                            durationMs + toFloat next.durationMs

                        sameSquare : Unit -> Bool
                        sameSquare other =
                            (other.id == unit.id)
                                && Unit.onMap other
                                && (Unit.mapPosition other == Unit.mapPosition unit)
                    in
                    case observedMovement transition unit of
                        Just edge ->
                            Just
                                { unitId = unit.id
                                , edge = edge
                                , durationMs = totalMs
                                , elapsedMs = elapsedMovement unit.id elapsed
                                }

                        Nothing ->
                            if Unit.onMap unit && List.any sameSquare next.units then
                                findArrival next rest totalMs

                            else
                                Nothing

                [] ->
                    Nothing
    in
    if Unit.isDying unit then
        Nothing

    else
        findArrival frame frames (elapsedMovement unit.id elapsed)


{-| Each unit uses the whole interval between its own arrivals, including
intervening arrivals by other units. Exits stop at the visible square's edge.
-}
movingPositions : Maybe Playback -> List { unitId : UnitId, position : Point }
movingPositions playback =
    let
        positions : Playback -> List { unitId : UnitId, position : Point }
        positions playing =
            let
                moving : MovementSegment -> { unitId : UnitId, position : Point }
                moving segment =
                    let
                        edge : MovementEdge
                        edge =
                            segment.edge

                        progress : Float
                        progress =
                            movementProgress playing.elapsed segment
                    in
                    { unitId = segment.unitId
                    , position =
                        { x =
                            toFloat edge.origin.x
                                + toFloat (edge.destination.x - edge.origin.x)
                                * edge.portion
                                * progress
                        , y =
                            toFloat edge.origin.y
                                + toFloat (edge.destination.y - edge.origin.y)
                                * edge.portion
                                * progress
                        }
                    }
            in
            case playing.presentation of
                Battlefield ->
                    List.map moving playing.movement.segments

                _ ->
                    []
    in
    Maybe.map positions playback |> Maybe.withDefault []


movementProgress : Float -> MovementSegment -> Float
movementProgress elapsed segment =
    clamp 0 1 ((segment.elapsedMs + elapsed) / max 1 segment.durationMs)


unitOpacity : Maybe Playback -> UnitId -> Float
unitOpacity playback unitId =
    case playback of
        Just playing ->
            case playing.presentation of
                Battlefield ->
                    playing.movement.segments
                        |> ListUtil.find (\segment -> (segment.unitId == unitId) && (segment.edge.portion < 1))
                        |> Maybe.map (\segment -> 1 - movementProgress playing.elapsed segment)
                        |> Maybe.withDefault 1

                _ ->
                    1

        Nothing ->
            1


{-| Resolve encounter subjects from battlefield sightings, never portrait locations.
Impact-only scenes may highlight the projected landing even in fog.
-}
encounterPositions : Frame -> Encounter -> List Coordinate
encounterPositions frame encounter =
    case encounter of
        Exchange exchange ->
            let
                participant : Unit -> Bool
                participant unit =
                    (unit.id == exchange.attacker.id) || (unit.id == exchange.target.id)
            in
            frame.units
                |> List.filter participant
                |> List.filterMap (Unit.physicalPosition frame.units)

        Impact impact ->
            let
                attackerPositions : List Coordinate
                attackerPositions =
                    impact.attackers
                        |> List.filterMap attackerPosition

                attackerPosition : IndirectImpact.Attacker -> Maybe Coordinate
                attackerPosition attacker =
                    ListUtil.find (\unit -> unit.id == attacker.unit.id) frame.units
                        |> Maybe.andThen (Unit.physicalPosition frame.units)
            in
            attackerPositions ++ [ impact.destination ]

        Sabotage sabotage ->
            [ sabotage.position ]

        Exhaustion exhausted ->
            frame.units
                |> ListUtil.find (\unit -> unit.id == exhausted.id)
                |> Maybe.andThen (Unit.physicalPosition frame.units)
                |> Maybe.map List.singleton
                |> Maybe.withDefault []


{-| Frame only projected battlefield sightings. Theater portraits can contain
concealed positions, so resolve participant IDs against the held frame instead.
Movement uses only currently interpolated sightings. Empty idle frames leave
the playback camera where it settled.
-}
focusPositions : Playback -> List Point
focusPositions playback =
    let
        point : Coordinate -> Point
        point position =
            { x = toFloat position.x, y = toFloat position.y }

        participants : Frame -> List UnitId -> List Point
        participants frame ids =
            frame.units
                |> List.filter (\unit -> List.member unit.id ids)
                |> List.filterMap (Unit.physicalPosition frame.units)
                |> List.map point
    in
    case playback.presentation of
        Combat focus ->
            encounterPositions focus.before focus.encounter |> List.map point

        Deaths { focus } ->
            encounterPositions focus.before focus.encounter |> List.map point

        Battlefield ->
            let
                combatantIds : List UnitId
                combatantIds =
                    List.concatMap (\shot -> [ shot.attacker.id, shot.target.id ]) playback.current.shots

                casualtyPositions : List Point
                casualtyPositions =
                    losses playback
                        |> List.filterMap (\loss -> Unit.physicalPosition playback.current.units loss.unit)
                        |> List.map point

                feedback : List Point
                feedback =
                    participants playback.current combatantIds
                        ++ List.map (.destination >> point) playback.current.indirectImpacts
                        ++ List.map point playback.current.sabotages
                        ++ casualtyPositions
            in
            if List.isEmpty feedback then
                movingPositions (Just playback) |> List.map .position

            else
                feedback


{-| Frame the upcoming visible travel before it starts. Stop at feedback,
transport, or a gap in a unit's sightings, and never use a newly revealed tile
or a future-only unit to aim the camera.
-}
cameraPositions : Playback -> List Point
cameraPositions playback =
    case playback.presentation of
        Battlefield ->
            focusPositions playback ++ playback.movement.cameraPositions

        _ ->
            focusPositions playback


movementCameraPositions : Frame -> List Frame -> List MovementSegment -> List Point
movementCameraPositions frame frames segments =
    let
        route : Unit -> Frame -> List Frame -> List Point
        route unit current remaining =
            case remaining of
                next :: rest ->
                    let
                        transition : FrameTransition
                        transition =
                            { current = current, next = next }

                        nextUnit : Maybe Unit
                        nextUnit =
                            ListUtil.find (\other -> other.id == unit.id) next.units

                        continue : List Point
                        continue =
                            nextUnit |> Maybe.map (\other -> route other next rest) |> Maybe.withDefault []
                    in
                    case observedMovement transition unit of
                        Just edge ->
                            if
                                List.member
                                    edge.origin
                                    frame.visibleTiles
                                    && List.member edge.destination frame.visibleTiles
                            then
                                { x = toFloat edge.origin.x, y = toFloat edge.origin.y }
                                    :: { x = toFloat edge.destination.x, y = toFloat edge.destination.y }
                                    :: continue

                            else
                                []

                        Nothing ->
                            if
                                Unit.onMap unit
                                    && (Maybe.andThen Unit.mapPosition nextUnit == Unit.mapPosition unit)
                            then
                                continue

                            else
                                []

                [] ->
                    []

        movingRoute : Unit -> List Point
        movingRoute unit =
            if List.any (\segment -> segment.unitId == unit.id) segments then
                route unit frame frames

            else
                []
    in
    if frameHasFeedback frame then
        []

    else
        List.concatMap movingRoute frame.units


visibleIndirectImpacts : Playback -> List Coordinate
visibleIndirectImpacts playback =
    case playback.presentation of
        Battlefield ->
            List.map .destination playback.current.indirectImpacts

        _ ->
            []
