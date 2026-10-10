port module MovementChecks exposing (main)

import Api.Enum.Direction as Direction
import Api.Enum.Side as Side
import Api.Enum.Terrain as Terrain
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import GameBoard
import Json.Decode as D
import Movement
import Platform
import TerrainFeature
import Unit
import UnitId


port results : List String -> Cmd msg


type alias Case =
    { name : String
    , kind : UnitKind
    , sketch : String
    , origin : Coordinate
    , occupied : List Coordinate
    , allies : List Coordinate
    , expected : List (List Int)
    }


coordinate : D.Decoder Coordinate
coordinate =
    D.map2 Coordinate (D.index 0 D.int) (D.index 1 D.int)


caseDecoder : D.Decoder Case
caseDecoder =
    D.map7 Case
        (D.field "name" D.string)
        (D.field "kind" UnitKind.decoder)
        (D.field "sketch" D.string)
        (D.field "origin" coordinate)
        (D.field "occupied" (D.list coordinate))
        (D.field "allies" (D.list coordinate))
        (D.field "expected" (D.list (D.list D.int)))


ruleDecoder : D.Decoder Movement.Rule
ruleDecoder =
    D.map3 Movement.Rule
        (D.field "kind" UnitKind.decoder)
        (D.field "budget" D.int)
        (D.field "terrainCosts" (D.list (D.map2 Movement.TerrainCost (D.field "terrain" Terrain.decoder) (D.field "cost" D.int))))


check : List Movement.Rule -> Case -> List String
check rules fixture =
    case UnitId.parse "1" of
        Err error ->
            [ error ]

        Ok id ->
            let
                unit : Unit.Unit
                unit =
                    { id = id, kind = fixture.kind, position = fixture.origin, side = Side.West, direction = Direction.East }

                rows : List String
                rows =
                    String.lines fixture.sketch

                features : List TerrainFeature.TerrainFeature
                features =
                    rows
                        |> List.indexedMap
                            (\y row ->
                                String.toList row
                                    |> List.indexedMap
                                        (\x symbol ->
                                            { position = { x = x, y = y }
                                            , terrain =
                                                if symbol == '#' then
                                                    Terrain.Forest

                                                else if symbol == '%' then
                                                    Terrain.Hills

                                                else
                                                    Terrain.GrassPlain
                                            }
                                        )
                            )
                        |> List.concat

                board : GameBoard.GameBoard
                board =
                    { map = { width = rows |> List.head |> Maybe.map String.length |> Maybe.withDefault 0, height = List.length rows, baseTile = Terrain.GrassPlain, features = features }
                    , units = unit :: (List.map (\position -> { unit | position = position, side = Side.East }) fixture.occupied ++ List.map (\position -> { unit | position = position }) fixture.allies)
                    , depots = []
                    }

                options : List Movement.Option
                options =
                    Movement.options [] rules board unit

                actual : List (List Int)
                actual =
                    options |> List.map (\option -> [ option.destination.x, option.destination.y, option.cost ]) |> List.sort

                validPath : Movement.Option -> Bool
                validPath option =
                    let
                        steps : List ( Coordinate, Coordinate )
                        steps =
                            List.map2 Tuple.pair option.path (List.drop 1 option.path)

                        entryCost : Coordinate -> Int
                        entryCost position =
                            features |> List.filter (\feature -> feature.position == position) |> List.head |> Maybe.andThen (\feature -> rules |> List.filter (\rule -> rule.kind == fixture.kind) |> List.head |> Maybe.andThen (\rule -> rule.terrainCosts |> List.filter (\entry -> entry.terrain == feature.terrain) |> List.head |> Maybe.map .cost)) |> Maybe.withDefault 1000
                    in
                    List.head option.path
                        == Just fixture.origin
                        && (List.reverse option.path |> List.head)
                        == Just option.destination
                        && List.all (\( a, b ) -> abs (a.x - b.x) + abs (a.y - b.y) == 1 && not (List.member b fixture.occupied)) steps
                        && not (List.member option.destination fixture.allies)
                        && List.sum (List.map entryCost (List.drop 1 option.path))
                        == option.cost
            in
            if actual == fixture.expected && List.all validPath options then
                []

            else
                [ fixture.name ++ ": reachable costs or paths differ" ]


traceChecks : List Movement.Rule -> List String
traceChecks rules =
    case UnitId.parse "1" of
        Err error ->
            [ error ]

        Ok id ->
            let
                origin : Coordinate
                origin =
                    { x = 0, y = 0 }

                unit : Unit.Unit
                unit =
                    { id = id, kind = UnitKind.Infantry, position = origin, side = Side.West, direction = Direction.East }

                board : GameBoard.GameBoard
                board =
                    { map = { width = 4, height = 4, baseTile = Terrain.GrassPlain, features = [] }
                    , units = [ unit ]
                    , depots = []
                    }

                down : Coordinate
                down =
                    { x = 0, y = 1 }

                right : Coordinate
                right =
                    { x = 1, y = 1 }

                up : Coordinate
                up =
                    { x = 1, y = 0 }

                traced : Maybe Movement.Option
                traced =
                    Just (Movement.start unit)
                        |> Maybe.andThen (\path -> Movement.trace rules board unit path down)
                        |> Maybe.andThen (\path -> Movement.trace rules board unit path right)

                traceFrom : Coordinate -> Maybe Movement.Option
                traceFrom destination =
                    traced |> Maybe.andThen (\path -> Movement.trace rules board unit path destination)

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "trace preserves a deliberate detour"
                    (Maybe.map .path traced == Just [ origin, down, right ] && Maybe.map .cost traced == Just 4)
                , test "backtracking trims and refunds terrain costs"
                    (traceFrom down |> Maybe.map (\path -> path.path == [ origin, down ] && path.cost == 2) |> Maybe.withDefault False)
                , test "hovering the tip leaves the path unchanged"
                    (traceFrom right == traced)
                , test "returning to origin resets the path"
                    (traceFrom origin == Just (Movement.start unit))
                , test "over-budget extension is rejected without rerouting"
                    (traceFrom { x = 3, y = 0 } == Nothing)
                , test "preview reroutes an over-budget detour to an affordable destination"
                    (traced
                        |> Maybe.andThen (\path -> Movement.preview rules board unit path up)
                        |> Maybe.map (\path -> path.cost == 2 && path.path == [ origin, up ])
                        |> Maybe.withDefault False
                    )
                , test "preview preserves the traced route when it fits"
                    (traced |> Maybe.andThen (\path -> Movement.preview rules board unit path right) |> (==) traced)
                , test "preview still rejects destinations beyond the full budget"
                    (traced |> Maybe.andThen (\path -> Movement.preview rules board unit path { x = 3, y = 3 }) |> (==) Nothing)
                , test "skipped cells extend the existing prefix"
                    (Movement.trace rules board unit (Movement.start unit) { x = 0, y = 2 }
                        |> Maybe.map (\path -> path.path == [ origin, down, { x = 0, y = 2 } ] && path.cost == 4)
                        |> Maybe.withDefault False
                    )
                , test "enemy cells reject extension"
                    (Movement.trace rules { board | units = [ unit, { unit | position = down, side = Side.East } ] } unit (Movement.start unit) down == Nothing)
                , test "allied squares can be traced through but cannot be destinations"
                    (let
                        alliedBoard : GameBoard.GameBoard
                        alliedBoard =
                            { board | units = [ unit, { unit | position = down } ] }
                     in
                     Movement.trace rules alliedBoard unit (Movement.start unit) down
                        |> Maybe.andThen
                            (\path ->
                                if Movement.canStop [] alliedBoard path then
                                    Nothing

                                else
                                    Movement.trace rules alliedBoard unit path { x = 0, y = 2 }
                            )
                        |> Maybe.map (\path -> path.path == [ origin, down, { x = 0, y = 2 } ] && path.cost == 4 && Movement.canStop [] alliedBoard path)
                        |> Maybe.withDefault False
                    )
                , test "fractional terrain cost is refunded on backtracking"
                    (let
                        roughBoard : GameBoard.GameBoard
                        roughBoard =
                            { board | map = { width = 4, height = 4, baseTile = Terrain.GrassPlain, features = [ { position = down, terrain = Terrain.Hills } ] } }
                     in
                     Movement.trace rules roughBoard unit (Movement.start unit) down
                        |> Maybe.andThen
                            (\path ->
                                if path.cost == 3 then
                                    Movement.trace rules roughBoard unit path origin

                                else
                                    Nothing
                            )
                        |> Maybe.map (\path -> path.cost == 0)
                        |> Maybe.withDefault False
                    )
                ]


reservationChecks : List Movement.Rule -> List String
reservationChecks rules =
    case UnitId.parse "1" of
        Err error ->
            [ error ]

        Ok id ->
            let
                unit : Unit.Unit
                unit =
                    { id = id, kind = UnitKind.Infantry, position = { x = 0, y = 0 }, side = Side.West, direction = Direction.East }

                board : GameBoard.GameBoard
                board =
                    { map = { width = 3, height = 1, baseTile = Terrain.GrassPlain, features = [] }
                    , units = [ unit ]
                    , depots = []
                    }

                reserved : Coordinate
                reserved =
                    { x = 1, y = 0 }

                beyond : Coordinate
                beyond =
                    { x = 2, y = 0 }

                options : List Movement.Option
                options =
                    Movement.options [ reserved ] rules board unit

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "reserved destinations are excluded from movement choices"
                    (not (List.any (\option -> option.destination == reserved) options))
                , test "reserved destinations reject saving a traced route"
                    (Movement.trace rules board unit (Movement.start unit) reserved
                        |> Maybe.map (Movement.canStop [ reserved ] board >> not)
                        |> Maybe.withDefault False
                    )
                , test "routes can pass through reserved destinations"
                    (List.any (\option -> option.destination == beyond && option.path == [ unit.position, reserved, beyond ]) options)
                , test "releasing a reservation restores its movement choice"
                    (Movement.options [] rules board unit
                        |> List.any (\option -> option.destination == reserved)
                    )
                ]


main : Program D.Value () Never
main =
    Platform.worker
        { init =
            \value ->
                ( ()
                , results
                    (case D.decodeValue (D.map2 Tuple.pair (D.field "rules" (D.list ruleDecoder)) (D.field "cases" (D.list caseDecoder))) value of
                        Err error ->
                            [ D.errorToString error ]

                        Ok ( rules, cases ) ->
                            List.concatMap (check rules) cases ++ traceChecks rules ++ reservationChecks rules
                    )
                )
        , update = \msg model -> never msg
        , subscriptions = \_ -> Sub.none
        }
