module Game.Turn exposing
    ( Event
    , Playback
    , Report
    , Resolution
    , Snapshot
    , movingPosition
    , resolutionSelection
    , rewind
    , selection
    , start
    , tick
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.SpriteFacing exposing (SpriteFacing)
import Api.Enum.TurnEventKind as EventKind exposing (TurnEventKind)
import Api.Object
import Api.Object.Coordinate as CoordinateApi
import Api.Object.GameSnapshot as GameApi
import Api.Object.TurnEvent as EventApi
import Api.Object.TurnReport as ReportApi
import Api.Object.TurnResolution as ResolutionApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Direction as Direction
import Game.Outcome as GameOutcome exposing (GameOutcome)
import Game.SpriteFacing as SpriteFacing
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Location as Location exposing (Location)
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Point exposing (Point)
import Util.List as ListUtil


type alias Snapshot =
    { number : Int
    , outcome : Maybe GameOutcome
    , submitted : Bool
    , opponentSubmitted : Bool
    , resolution : Maybe Resolution
    }


type alias Resolution =
    { number : Int
    , events : List Event
    , report : Maybe Report
    }


type alias Report =
    { unitsLost : Int
    , enemyUnitsDestroyed : Int
    , damageInflicted : Int
    , suppliesConsumed : Int
    }


type alias Event =
    { kind : TurnEventKind
    , unitId : UnitId
    , path : List Coordinate
    , initialSpriteFacing : SpriteFacing
    , initialDirection : Maybe Direction
    , initialCarrier : Maybe UnitId
    , rotationDirection : Maybe Direction
    , carrierId : Maybe UnitId
    }


type alias Playback =
    { events : List Event
    , elapsed : Float
    }


selection : SelectionSet Snapshot Api.Object.GameSnapshot
selection =
    SS.succeed Snapshot
        |> SS.with GameApi.turnNumber
        |> SS.with (GameApi.outcome GameOutcome.selection)
        |> SS.with GameApi.submitted
        |> SS.with GameApi.opponentSubmitted
        |> SS.with (GameApi.lastResolution resolutionSelection)


reportSelection : SelectionSet Report Api.Object.TurnReport
reportSelection =
    SS.succeed Report
        |> SS.with ReportApi.unitsLost
        |> SS.with ReportApi.enemyUnitsDestroyed
        |> SS.with ReportApi.damageInflicted
        |> SS.with ReportApi.suppliesConsumed


viewerReport : List Report -> Result String (Maybe Report)
viewerReport reports =
    case reports of
        [] ->
            Ok Nothing

        [ report ] ->
            Ok (Just report)

        _ ->
            Err "expected only the current player's turn report"


start : Snapshot -> Maybe Playback
start snapshot =
    let
        plays : Event -> Bool
        plays event =
            case event.kind of
                EventKind.Move ->
                    True

                EventKind.StandGround ->
                    False

                EventKind.Ambush ->
                    True

                EventKind.Load ->
                    True

                EventKind.Unload ->
                    True

                _ ->
                    False
    in
    snapshot.resolution
        |> Maybe.map (\resolution -> { events = List.filter plays resolution.events, elapsed = 0 })
        |> Maybe.andThen nonempty


nonempty : Playback -> Maybe Playback
nonempty playback =
    if List.isEmpty playback.events then
        Nothing

    else
        Just playback


rewind : Snapshot -> List Unit -> List Unit
rewind snapshot units =
    let
        resetUnit : Unit -> Unit
        resetUnit unit =
            snapshot.resolution
                |> Maybe.andThen (\resolution -> ListUtil.find (\event -> event.unitId == unit.id) resolution.events)
                |> Maybe.map
                    (\event ->
                        let
                            location : Location
                            location =
                                case event.initialCarrier of
                                    Just carrier ->
                                        Location.Aboard carrier

                                    Nothing ->
                                        List.head event.path
                                            |> Maybe.map Location.OnMap
                                            |> Maybe.withDefault unit.location
                        in
                        unit
                            |> Unit.setLocation location
                            |> Unit.setDirection event.initialDirection
                            |> Unit.setSpriteFacing event.initialSpriteFacing
                    )
                |> Maybe.withDefault unit
    in
    List.map resetUnit units


{-| Each path edge takes 180ms. Only one event plays at a time.
-}
tick : Float -> Playback -> List Unit -> ( Maybe Playback, List Unit )
tick delta playback units =
    case playback.events of
        [] ->
            ( Nothing, units )

        event :: remaining ->
            let
                elapsed : Float
                elapsed =
                    playback.elapsed + delta

                duration : Float
                duration =
                    if event.kind == EventKind.Ambush then
                        180

                    else
                        toFloat (List.length event.path - 1) * 180

                finishUnit : Unit -> Unit
                finishUnit unit =
                    if unit.id == event.unitId then
                        let
                            location : Location
                            location =
                                case event.kind of
                                    EventKind.Load ->
                                        event.carrierId
                                            |> Maybe.map Location.Aboard
                                            |> Maybe.withDefault unit.location

                                    EventKind.Hold ->
                                        unit.location

                                    _ ->
                                        List.reverse event.path
                                            |> List.head
                                            |> Maybe.map Location.OnMap
                                            |> Maybe.withDefault unit.location

                            facing : SpriteFacing
                            facing =
                                SpriteFacing.alongPath event.path unit.spriteFacing
                                    |> SpriteFacing.turn event.rotationDirection

                            direction : Maybe Direction
                            direction =
                                case event.rotationDirection of
                                    Just rotation ->
                                        Just rotation

                                    Nothing ->
                                        Direction.alongPath event.path unit.direction
                        in
                        unit
                            |> Unit.setLocation location
                            |> Unit.setSpriteFacing facing
                            |> Unit.setDirection direction

                    else
                        unit
            in
            if elapsed >= duration then
                ( nonempty { events = remaining, elapsed = 0 }
                , List.map finishUnit units
                )

            else
                let
                    turnUnit : Unit -> Unit
                    turnUnit unit =
                        if unit.id == event.unitId then
                            let
                                edge : Int
                                edge =
                                    floor (elapsed / 180)

                                direction : Maybe Direction
                                direction =
                                    case List.drop edge event.path of
                                        from :: to :: _ ->
                                            unit.direction
                                                |> Maybe.map
                                                    (\initial ->
                                                        Direction.between from to
                                                            |> Maybe.withDefault initial
                                                    )

                                        _ ->
                                            unit.direction
                            in
                            Unit.faceDirection direction unit

                        else
                            unit
                in
                ( Just { playback | elapsed = elapsed }
                , List.map turnUnit units
                )


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


parseOptionalId : Maybe String -> Result String (Maybe UnitId)
parseOptionalId value =
    case value of
        Nothing ->
            Ok Nothing

        Just id ->
            UnitId.parse id |> Result.map Just


resolutionSelection : SelectionSet Resolution Api.Object.TurnResolution
resolutionSelection =
    let
        coordinate : SelectionSet Coordinate Api.Object.Coordinate
        coordinate =
            Coordinate.selection

        event : SelectionSet Event Api.Object.TurnEvent
        event =
            SS.succeed Event
                |> SS.with EventApi.kind
                |> SS.with (EventApi.unitId |> SS.mapOrFail UnitId.parse)
                |> SS.with (EventApi.path coordinate)
                |> SS.with EventApi.initialSpriteFacing
                |> SS.with EventApi.initialDirection
                |> SS.with (EventApi.initialCarrier |> SS.mapOrFail parseOptionalId)
                |> SS.with EventApi.rotationDirection
                |> SS.with (EventApi.carrierId |> SS.mapOrFail parseOptionalId)
    in
    SS.succeed Resolution
        |> SS.with ResolutionApi.turnNumber
        |> SS.with (ResolutionApi.events event)
        |> SS.with (ResolutionApi.reports reportSelection |> SS.mapOrFail viewerReport)
