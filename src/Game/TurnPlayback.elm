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
    , combat
    , continueCombat
    , focusPositions
    , initial
    , lossEvent
    , losses
    , movingPositions
    , panels
    , selection
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
import Api.Object.GameSnapshot as GameApi
import Api.Object.TurnFrame as FrameApi
import Api.Object.TurnResolution as ResolutionApi
import Api.Object.UnitDeparture as DepartureApi
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
    { durationMs : Int
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
    , remaining : List Frame
    , elapsed : Float
    , presentation : Presentation
    , acknowledgedLosses : List UnitId
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


setFrameShots : List Shot -> Frame -> Frame
setFrameShots shots model =
    { model | shots = shots }


setFrameUnits : List Unit -> Frame -> Frame
setFrameUnits units model =
    { model | units = units }


setCombatFocusStage : CombatStage -> CombatFocus -> CombatFocus
setCombatFocusStage stage model =
    { model | stage = stage }


{-| Only projected casualties are reported. Encounter portraits can explain a
loss but must never introduce a concealed unit onto the battlefield.
-}
losses : Playback -> List Loss
losses playback =
    let
        frame : Frame
        frame =
            lossFrame playback

        cause : Unit -> LossCause
        cause unit =
            let
                lethalShot : Shot -> Bool
                lethalShot shot =
                    shot.target.id == unit.id && shot.targetHealth.after.current == 0

                deadCarrier : Unit -> Bool
                deadCarrier carrier =
                    Unit.carrierId unit == Just carrier.id && Unit.isDying carrier
            in
            case ListUtil.find lethalShot playback.current.shots of
                Just shot ->
                    Destroyed shot.kind shot.attacker

                Nothing ->
                    case ListUtil.find deadCarrier frame.units of
                        Just carrier ->
                            CarrierLost carrier (cause carrier)

                        Nothing ->
                            if
                                List.any
                                    (\impact ->
                                        IndirectImpact.destroyedUnitId impact == Just unit.id
                                    )
                                    playback.current.indirectImpacts
                            then
                                ConcealedIndirectFire

                            else
                                SuppliesExhausted

        unacknowledged : Unit -> Bool
        unacknowledged unit =
            Unit.isDying unit
                && not (List.member unit.id playback.acknowledgedLosses)

        notice : Unit -> Loss
        notice unit =
            { unit = unit
            , cause = cause unit
            }
    in
    List.filter unacknowledged frame.units
        |> List.map notice


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
                    in
                    { kind = kind
                    , attacker = shot.attacker
                    , target = shot.target
                    , attackerHealth = shot.attackerHealth
                    , targetHealth = shot.targetHealth
                    , targetFired =
                        List.any (\other -> not (differentPair other) && other.attacker.id == shot.target.id) rest
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
        ++ exhaustionEncounters frames


sabotageEncounters : FrameTransition -> List Encounter
sabotageEncounters frames =
    let
        encounter : Coordinate -> Maybe Encounter
        encounter position =
            ListUtil.find (\depot -> depot.position == position) frames.current.depots
                |> Maybe.map Sabotage
    in
    List.filterMap encounter frames.next.sabotages


exhaustionEncounters : FrameTransition -> List Encounter
exhaustionEncounters frames =
    let
        frame : Frame
        frame =
            frames.next

        combatParticipants : List UnitId
        combatParticipants =
            List.concatMap (\shot -> [ shot.attacker.id, shot.target.id ]) frame.shots
                ++ List.filterMap IndirectImpact.destroyedUnitId frame.indirectImpacts

        exhausted : Unit -> Maybe Encounter
        exhausted unit =
            let
                exhaustedOnMap : Bool
                exhaustedOnMap =
                    Unit.isDying unit && Unit.onMap unit && not (List.member unit.id combatParticipants)
            in
            if exhaustedOnMap then
                frames.current.units
                    |> ListUtil.find (\earlier -> (earlier.id == unit.id) && not (Unit.isDying earlier))
                    |> Maybe.map (\earlier -> Exhaustion earlier)

            else
                Nothing
    in
    List.filterMap exhausted frame.units


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


beginFrame : FrameTransition -> List Frame -> Playback
beginFrame transition pending =
    let
        ( next, remaining ) =
            combineReturnFire transition.next pending

        frames : FrameTransition
        frames =
            { transition | next = next }

        before : Frame
        before =
            frames.current

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
    , remaining = remaining
    , elapsed = 0
    , presentation = presentation
    , acknowledgedLosses = []
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


initial : List Frame -> Frame -> Frame
initial frames fallback =
    List.head frames
        |> Maybe.withDefault fallback


start : List Frame -> Maybe Playback
start frames =
    case clearPresentedDeaths [] frames of
        current :: next :: remaining ->
            Just
                (beginFrame
                    { current = current
                    , next = current
                    }
                    (next :: remaining)
                )

        _ ->
            Nothing


{-| Combat keeps casualties in authoritative snapshots until end-of-turn cleanup.
Show each death in its first frame, then omit the finished marker and corpse
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
                    List.filter Unit.isDying frame.units |> List.map .id

                units : List Unit
                units =
                    List.filter
                        (\unit -> not (List.member unit.id presented))
                        frame.units
            in
            (frame
                |> setFrameUnits units
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
        |> Maybe.map (.durationMs >> toFloat)
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
            if elapsed >= toFloat next.durationMs then
                let
                    advanced : Playback
                    advanced =
                        beginFrame { current = playback.current, next = next } remaining
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
                            tickWithLossPause lossPolicy (elapsed - toFloat next.durationMs) advanced

            else
                ( Just
                    (playback
                        |> setElapsed elapsed
                    )
                , presentationFrame playback next
                )


presentationFrame : Playback -> Frame -> Frame
presentationFrame playing next =
    let
        faceMovement : Unit -> Unit
        faceMovement unit =
            case
                observedMovement
                    { current = playing.current
                    , next = next
                    }
                    unit
            of
                Just edge ->
                    let
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


{-| Interpolate shared sightings and server-projected exits. Exits stop at the
edge of the last visible square; hidden destinations and routes are never sent.
-}
movingPositions : Maybe Playback -> List { unitId : UnitId, position : Point }
movingPositions playback =
    let
        positions : Playback -> List { unitId : UnitId, position : Point }
        positions playing =
            case ( playing.presentation, playing.remaining ) of
                ( Battlefield, next :: _ ) ->
                    let
                        moving : Unit -> Maybe { unitId : UnitId, position : Point }
                        moving unit =
                            case
                                observedMovement
                                    { current = playing.current
                                    , next = next
                                    }
                                    unit
                            of
                                Just edge ->
                                    Just
                                        { unitId = unit.id
                                        , position =
                                            { x =
                                                toFloat edge.origin.x
                                                    + toFloat (edge.destination.x - edge.origin.x)
                                                    * edge.portion
                                                    * playing.elapsed
                                                    / toFloat next.durationMs
                                            , y =
                                                toFloat edge.origin.y
                                                    + toFloat (edge.destination.y - edge.origin.y)
                                                    * edge.portion
                                                    * playing.elapsed
                                                    / toFloat next.durationMs
                                            }
                                        }

                                Nothing ->
                                    Nothing
                    in
                    List.filterMap moving playing.current.units

                _ ->
                    []
    in
    Maybe.map positions playback |> Maybe.withDefault []


unitOpacity : Maybe Playback -> UnitId -> Float
unitOpacity playback unitId =
    case playback of
        Just playing ->
            case ( playing.presentation, playing.remaining ) of
                ( Battlefield, next :: _ ) ->
                    let
                        departing : Bool
                        departing =
                            List.any (\departure -> departure.unitId == unitId) playing.current.departures
                    in
                    if departing then
                        1 - clamp 0 1 (playing.elapsed / toFloat next.durationMs)

                    else
                        1

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


visibleIndirectImpacts : Playback -> List Coordinate
visibleIndirectImpacts playback =
    case playback.presentation of
        Battlefield ->
            List.map .destination playback.current.indirectImpacts

        _ ->
            []
