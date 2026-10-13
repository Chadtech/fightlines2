module TurnPlayback exposing
    ( Exchange
    , Frame
    , MapView(..)
    , Panel
    , Playback
    , Presentation(..)
    , combat
    , continueCombat
    , initial
    , movingPositions
    , panels
    , selection
    , setMapView
    , spotlight
    , start
    , tick
    , visibleShots
    )

import Api.Enum.CombatKind as CombatKind exposing (CombatKind)
import Api.Object
import Api.Object.GameSnapshot as GameApi
import Api.Object.TurnFrame as FrameApi
import Api.Object.TurnResolution as ResolutionApi
import CombatHealth exposing (CombatHealth)
import Coordinate exposing (Coordinate)
import Depot exposing (Depot)
import Direction
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Point exposing (Point)
import Shot exposing (Shot)
import Supply
import Unit exposing (Unit)
import UnitId exposing (UnitId)
import Util.List as ListUtil


type alias Frame =
    { durationMs : Int
    , units : List Unit
    , shots : List Shot
    , visibleTiles : List Coordinate
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    }


type alias Playback =
    { current : Frame
    , remaining : List Frame
    , elapsed : Float
    , presentation : Presentation
    }


type Presentation
    = Battlefield
    | Combat CombatFocus
    | Deaths { focus : CombatFocus, frame : Frame, elapsed : Float }


type alias CombatFocus =
    { exchange : Exchange
    , remaining : List Exchange
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
    { exchange : Exchange
    , elapsed : Float
    , mapView : MapView
    }


type alias Exchange =
    { kind : CombatKind
    , attacker : Unit
    , target : Unit
    , attackerHealth : CombatHealth
    , targetHealth : CombatHealth
    }


combat : Playback -> Maybe Exchange
combat playback =
    case playback.presentation of
        Combat focus ->
            Just focus.exchange

        Deaths _ ->
            Nothing

        Battlefield ->
            Nothing


spotlight : Playback -> Maybe Exchange
spotlight playback =
    case playback.presentation of
        Combat { exchange, stage } ->
            case stage of
                Spotlighting _ ->
                    Just exchange

                ShowingPanels panel ->
                    case panel.mapView of
                        SeeingMap ->
                            Just exchange

                        CardVisible ->
                            Nothing

        Deaths _ ->
            Nothing

        Battlefield ->
            Nothing


panels : Playback -> Maybe Panel
panels playback =
    case playback.presentation of
        Combat { exchange, stage } ->
            case stage of
                ShowingPanels panel ->
                    Just { exchange = exchange, elapsed = panel.elapsed, mapView = panel.mapView }

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
exchanges : Frame -> List Exchange
exchanges frame =
    let
        collect : List Shot -> List Exchange
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
                            if List.any includesAttackMove (shot :: rest) then
                                CombatKind.AttackMove

                            else
                                CombatKind.Ambush

                        remaining : List Exchange
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


beginFrame : FrameTransition -> List Frame -> Playback
beginFrame frames remaining =
    let
        before : Frame
        before =
            frames.current

        presentation : Presentation
        presentation =
            case exchanges frames.next of
                exchange :: rest ->
                    Combat
                        { exchange = exchange
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
    }


type alias FrameTransition =
    { current : Frame
    , next : Frame
    }


type alias MovementEdge =
    { origin : Coordinate
    , destination : Coordinate
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
            Just (beginFrame { current = current, next = current } (next :: remaining))

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
tick delta playback =
    case playback.presentation of
        Combat focus ->
            tickCombat delta focus playback

        Deaths deaths ->
            if deaths.elapsed + delta >= deathDuration playback then
                let
                    keepSurvivor : Unit -> Bool
                    keepSurvivor unit =
                        not (List.any (\dead -> Unit.isDying dead && dead.id == unit.id) deaths.frame.units)

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
            tickBattlefield delta playback


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
                    ShowingPanels { panel | elapsed = min 2500 (panel.elapsed + delta) }
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
                            exchangeDeathFrame focus
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


exchangeDeathFrame : CombatFocus -> Frame
exchangeDeathFrame focus =
    let
        casualties : List UnitId
        casualties =
            [ ( focus.exchange.attacker.id, focus.exchange.attackerHealth.after.current )
            , ( focus.exchange.target.id, focus.exchange.targetHealth.after.current )
            ]
                |> List.filter (\( _, health ) -> health == 0)
                |> List.map Tuple.first

        before : Frame
        before =
            focus.before

        present : Unit -> Unit
        present unit =
            let
                destroyed : Bool
                destroyed =
                    List.member unit.id casualties
                        || (Unit.carrierId unit |> Maybe.map (\id -> List.member id casualties) |> Maybe.withDefault False)
            in
            { unit | destroyed = destroyed }
    in
    { before | units = List.map present before.units }


advanceCombat : CombatFocus -> Playback -> { animation : Playback, frame : Frame }
advanceCombat focus playback =
    case focus.remaining of
        exchange :: rest ->
            { animation =
                { playback
                    | presentation = Combat { focus | exchange = exchange, remaining = rest, stage = Spotlighting 0 }
                }
            , frame = focus.before
            }

        [] ->
            { animation = { playback | presentation = Battlefield, elapsed = 0 }
            , frame = playback.current
            }


tickBattlefield : Float -> Playback -> ( Maybe Playback, Frame )
tickBattlefield delta playback =
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
                        tick (elapsed - toFloat next.durationMs) advanced

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
                    Unit.faceDirection
                        (unit.direction
                            |> Maybe.andThen
                                (\_ -> Direction.between edge.origin edge.destination)
                        )
                        unit
                        |> Unit.setOnMap edge.origin

                Nothing ->
                    unit
    in
    { depots = playing.current.depots
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
                |> Maybe.andThen Unit.boardPosition
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
                    }

            else
                Nothing

        _ ->
            Nothing


{-| Interpolate only sightings present at both ends of an edge. Entering or
leaving sight changes the unit list at the boundary, without revealing fog paths.
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
                                            { x = toFloat edge.origin.x + toFloat (edge.destination.x - edge.origin.x) * playing.elapsed / toFloat next.durationMs
                                            , y = toFloat edge.origin.y + toFloat (edge.destination.y - edge.origin.y) * playing.elapsed / toFloat next.durationMs
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
