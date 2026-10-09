module Turn exposing
    ( Event
    , Playback
    , Snapshot
    , movingPosition
    , rewind
    , selection
    , start
    , tick
    )

import Api.Enum.TurnEventKind as EventKind exposing (TurnEventKind)
import Api.Object
import Api.Object.Coordinate as CoordinateApi
import Api.Object.GameSnapshot as GameApi
import Api.Object.TurnEvent as EventApi
import Api.Object.TurnResolution as ResolutionApi
import Coordinate exposing (Coordinate)
import GameBoard exposing (GameBoard)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Point exposing (Point)
import Unit exposing (Unit)
import UnitId exposing (UnitId)


type alias Snapshot =
    { number : Int
    , submitted : Bool
    , opponentSubmitted : Bool
    , resolution : Maybe Resolution
    }


type alias Resolution =
    { number : Int
    , events : List Event
    }


type alias Event =
    { kind : TurnEventKind
    , unitId : UnitId
    , path : List Coordinate
    }


type alias Playback =
    { events : List Event
    , elapsed : Float
    }


selection : SelectionSet Snapshot Api.Object.GameSnapshot
selection =
    let
        coordinate : SelectionSet Coordinate Api.Object.Coordinate
        coordinate =
            SS.map2 Coordinate CoordinateApi.x CoordinateApi.y

        event : SelectionSet Event Api.Object.TurnEvent
        event =
            SS.map3 Event EventApi.kind (EventApi.unitId |> SS.mapOrFail UnitId.parse) (EventApi.path coordinate)
    in
    SS.map4 Snapshot
        GameApi.turnNumber
        GameApi.submitted
        GameApi.opponentSubmitted
        (GameApi.lastResolution (SS.map2 Resolution ResolutionApi.turnNumber (ResolutionApi.events event)))


start : Snapshot -> Maybe Playback
start snapshot =
    snapshot.resolution
        |> Maybe.map (\resolution -> { events = List.filter (\event -> event.kind == EventKind.Move) resolution.events, elapsed = 0 })
        |> Maybe.andThen nonempty


nonempty : Playback -> Maybe Playback
nonempty playback =
    if List.isEmpty playback.events then
        Nothing

    else
        Just playback


rewind : Snapshot -> GameBoard -> GameBoard
rewind snapshot board =
    let
        resetUnit : Unit -> Unit
        resetUnit unit =
            snapshot.resolution
                |> Maybe.andThen (\resolution -> List.filter (\event -> event.unitId == unit.id) resolution.events |> List.head)
                |> Maybe.andThen (.path >> List.head)
                |> Maybe.map (\position -> { unit | position = position })
                |> Maybe.withDefault unit
    in
    { board | units = List.map resetUnit board.units }


{-| Each path edge takes 180ms. Only one event plays at a time.
-}
tick : Float -> Playback -> GameBoard -> ( Maybe Playback, GameBoard )
tick delta playback board =
    case playback.events of
        [] ->
            ( Nothing, board )

        event :: remaining ->
            let
                elapsed : Float
                elapsed =
                    playback.elapsed + delta

                duration : Float
                duration =
                    toFloat (List.length event.path - 1) * 180

                finishUnit : Unit -> Unit
                finishUnit unit =
                    if unit.id == event.unitId then
                        { unit
                            | position =
                                List.reverse event.path
                                    |> List.head
                                    |> Maybe.withDefault unit.position
                        }

                    else
                        unit
            in
            if elapsed >= duration then
                ( nonempty { events = remaining, elapsed = 0 }
                , { board | units = List.map finishUnit board.units }
                )

            else
                ( Just { playback | elapsed = elapsed }, board )


movingPosition : Maybe Playback -> Maybe { unitId : UnitId, position : Point }
movingPosition playback =
    let
        position : Playback -> Maybe { unitId : UnitId, position : Point }
        position playing =
            case playing.events of
                [] ->
                    Nothing

                event :: _ ->
                    let
                        edge : Int
                        edge =
                            floor (playing.elapsed / 180)

                        fraction : Float
                        fraction =
                            playing.elapsed / 180 - toFloat edge
                    in
                    case List.drop edge event.path of
                        from :: to :: _ ->
                            Just
                                { unitId = event.unitId
                                , position =
                                    { x = toFloat from.x + toFloat (to.x - from.x) * fraction
                                    , y = toFloat from.y + toFloat (to.y - from.y) * fraction
                                    }
                                }

                        _ ->
                            Nothing
    in
    Maybe.andThen position playback
