module TurnPlayback exposing
    ( CombatExchange
    , Encounter(..)
    , Frame
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
import CombatHealth exposing (CombatHealth)
import Coordinate exposing (Coordinate)
import Depot exposing (Depot)
import Direction
import Graphql.SelectionSet as SS exposing (SelectionSet)
import IndirectImpact exposing (IndirectImpact)
import Point exposing (Point)
import Shot exposing (Shot)
import SpriteFacing
import Supply
import Unit exposing (Unit)
import Unit.Location exposing (Location)
import UnitId exposing (UnitId)
import Util.List as ListUtil


type alias Frame =
    { durationMs : Int
    , units : List Unit
    , departures : List Departure
    , indirectImpacts : List IndirectImpact
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
    | Impact IndirectImpact


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
    | SuppliesExhausted
    | CarrierLost Unit LossCause


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
                            SuppliesExhausted

        unacknowledged : Unit -> Bool
        unacknowledged unit =
            Unit.isDying unit && not (List.member unit.id playback.acknowledgedLosses)

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
                    ListUtil.find (\loss -> loss.unit.id == carrierId) pending
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
                    }
                        :: remaining
    in
    collect frame.shots


{-| Impact scenes retain only observable attackers and never confirm a target.
Confirmed indirect shots already have their own exchange at the same landing.
-}
encounters : Frame -> List Encounter
encounters frame =
    let
        unconfirmed : IndirectImpact -> Bool
        unconfirmed impact =
            let
                confirmsLanding : Shot -> Bool
                confirmsLanding shot =
                    (shot.kind == CombatKind.IndirectFire) && (shot.destination == impact.destination)
            in
            not (List.any confirmsLanding frame.shots)

        unique : IndirectImpact -> List IndirectImpact -> List IndirectImpact
        unique impact impacts =
            if List.any (\existing -> existing.destination == impact.destination) impacts then
                impacts

            else
                impacts ++ [ impact ]
    in
    List.map Exchange (exchanges frame)
        ++ (frame.indirectImpacts
                |> List.filter unconfirmed
                |> List.foldl unique []
                |> List.map Impact
           )


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
            case encounters frames.next of
                encounter :: rest ->
                    Combat
                        { encounter = encounter
                        , remaining = rest
                        , before = { before | shots = [] }
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
Never cross movement, visibility changes, another encounter, or a casualty.
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

                            [ returnShot ] ->
                                let
                                    reciprocal : Bool
                                    reciprocal =
                                        (returnShot.attacker.id == shot.target.id)
                                            && (returnShot.target.id == shot.attacker.id)
                                            && (returnShot.origin == shot.destination)
                                            && (returnShot.destination == shot.origin)
                                in
                                if reciprocal then
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
                                            [ { shot
                                                | attackerHealth = attackerHealth
                                                , targetHealth = targetHealth
                                              }
                                            , { returnShot
                                                | attackerHealth = targetHealth
                                                , targetHealth = attackerHealth
                                              }
                                            ]
                                    in
                                    ( { frame | shots = shots }, rest )

                                else
                                    ( opening, pending )

                            _ ->
                                ( opening, pending )

                [] ->
                    ( opening, pending )
    in
    case opening.shots of
        [ shot ] ->
            if List.any Unit.isDying opening.units then
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
                |> SS.with (FrameApi.shots Shot.selection)
                |> SS.with (FrameApi.visibleTiles coordinate)
                |> SS.with (FrameApi.depots Depot.selection)
                |> SS.with (FrameApi.supplyCrates Supply.crateSelection)
            )
        )
        |> SS.map (Maybe.withDefault [])


initial : List Frame -> Frame -> Frame
initial frames fallback =
    List.head frames |> Maybe.withDefault fallback


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
            { frame | units = units }
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
                                    { before | units = List.filter keepSurvivor before.units }
                            }
                            { playback
                                | current =
                                    { current
                                        | units = List.filter keepSurvivor current.units
                                    }
                            }
                in
                ( Just advanced.animation, advanced.frame )

            else
                ( Just
                    { playback
                        | presentation = Deaths { deaths | elapsed = deaths.elapsed + delta }
                    }
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
                    -- Four staggered impacts, camera settling, and the automatic-close delay fit within this clock.
                    ShowingPanels { panel | elapsed = min 3000 (panel.elapsed + delta) }
    in
    ( Just { playback | presentation = Combat { focus | stage = stage } }
    , focus.before
    )


setMapView : MapView -> Playback -> Playback
setMapView mapView playback =
    case playback.presentation of
        Combat focus ->
            case focus.stage of
                ShowingPanels panel ->
                    { playback
                        | presentation =
                            Combat
                                { focus
                                    | stage = ShowingPanels { panel | mapView = mapView }
                                }
                    }

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
                            { animation = { playback | presentation = Deaths { focus = focus, frame = frame, elapsed = 0 } }
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
            case focus.encounter of
                Exchange exchange ->
                    [ ( exchange.attacker.id, exchange.attackerHealth.after.current )
                    , ( exchange.target.id, exchange.targetHealth.after.current )
                    ]
                        |> List.filter (\( _, health ) -> health == 0)
                        |> List.map Tuple.first

                Impact _ ->
                    []

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
            { unit | destroyed = destroyed }
    in
    { before | units = List.map present before.units }


advanceCombat : CombatFocus -> Playback -> { animation : Playback, frame : Frame }
advanceCombat focus playback =
    case focus.remaining of
        encounter :: rest ->
            { animation =
                { playback
                    | presentation =
                        Combat
                            { focus
                                | encounter = encounter
                                , remaining = rest
                                , stage = Spotlighting 0
                            }
                }
            , frame = focus.before
            }

        [] ->
            { animation = { playback | presentation = Battlefield, elapsed = 0 }
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
                    { playback | elapsed = elapsed }
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
                        { unit
                            | spriteFacing = SpriteFacing.turn movementDirection unit.spriteFacing
                            , entrenchment = Entrenchment.Exposed
                        }
                        |> Unit.setOnMap edge.origin

                Nothing ->
                    unit
    in
    { departures = playing.current.departures
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
                    impact.attacker
                        |> Maybe.andThen (\attacker -> ListUtil.find (\unit -> unit.id == attacker.unit.id) frame.units)
                        |> Maybe.andThen (Unit.physicalPosition frame.units)
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []
            in
            attackerPositions ++ [ impact.destination ]


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
