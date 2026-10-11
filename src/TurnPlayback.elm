module TurnPlayback exposing
    ( Frame
    , Playback
    , initial
    , movingPositions
    , selection
    , start
    , tick
    )

import Api.Object
import Api.Object.GameSnapshot as GameApi
import Api.Object.TurnFrame as FrameApi
import Api.Object.TurnResolution as ResolutionApi
import Coordinate exposing (Coordinate)
import Direction
import Graphql.SelectionSet as SS exposing (SelectionSet)
import ListUtil
import Point exposing (Point)
import Unit exposing (Unit)
import UnitId exposing (UnitId)


type alias Frame =
    { units : List Unit
    , visibleTiles : List Coordinate
    }


type alias Playback =
    { current : Frame
    , remaining : List Frame
    , elapsed : Float
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
                |> SS.with (FrameApi.units unit)
                |> SS.with (FrameApi.visibleTiles coordinate)
            )
        )
        |> SS.map (Maybe.withDefault [])


initial : List Frame -> Frame -> Frame
initial frames fallback =
    List.head frames |> Maybe.withDefault fallback


start : List Frame -> Maybe Playback
start frames =
    case frames of
        current :: next :: remaining ->
            Just
                { current = current
                , remaining = next :: remaining
                , elapsed = 0
                }

        _ ->
            Nothing


{-| Each sequential path edge takes 180ms. Visibility changes at tile boundaries.
Carry surplus time forward so frame rate does not change the timeline.
-}
tick : Float -> Playback -> ( Maybe Playback, Frame )
tick delta playback =
    case playback.remaining of
        [] ->
            ( Nothing, playback.current )

        next :: remaining ->
            let
                elapsed : Float
                elapsed =
                    playback.elapsed + delta
            in
            if elapsed >= 180 then
                case remaining of
                    [] ->
                        ( Nothing, next )

                    _ ->
                        tick (elapsed - 180)
                            { current = next
                            , remaining = remaining
                            , elapsed = 0
                            }

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
                    { unit
                        | direction =
                            unit.direction
                                |> Maybe.andThen
                                    (\_ ->
                                        Direction.between
                                            edge.origin
                                            edge.destination
                                    )
                    }
                        |> Unit.setOnMap edge.origin

                Nothing ->
                    unit
    in
    { units = List.map faceMovement playing.current.units
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
            case playing.remaining of
                next :: _ ->
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
                                            { x = toFloat edge.origin.x + toFloat (edge.destination.x - edge.origin.x) * playing.elapsed / 180
                                            , y = toFloat edge.origin.y + toFloat (edge.destination.y - edge.origin.y) * playing.elapsed / 180
                                            }
                                        }

                                Nothing ->
                                    Nothing
                    in
                    List.filterMap moving playing.current.units

                [] ->
                    []
    in
    Maybe.map positions playback |> Maybe.withDefault []
