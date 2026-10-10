port module MovementChecks exposing (main)

import Api.Enum.Direction as Direction
import Api.Enum.Side as Side
import Api.Enum.Terrain as Terrain
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import GameBoard
import Json.Decode as D
import ListUtil
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
                fuel : Maybe Unit.Fuel
                fuel =
                    case fixture.kind of
                        UnitKind.Tank ->
                            Just { current = 64, maximum = 64 }

                        UnitKind.SupplyTruck ->
                            Just { current = 64, maximum = 64 }

                        _ ->
                            Nothing

                unit : Unit.Unit
                unit =
                    { cargoCapacity = 0
                    , hitPoints = { current = 16, maximum = 16 }
                    , supplies =
                        { current = 64
                        , maximum = 64
                        , upkeepPerTurn = 1
                        , movementPerTile =
                            if fixture.kind == UnitKind.Infantry || fixture.kind == UnitKind.FieldGun then
                                1

                            else
                                0
                        }
                    , fuel = fuel
                    , id = id
                    , kind = fixture.kind
                    , location = Unit.OnMap fixture.origin
                    , side = Side.Player1
                    , direction = Just Direction.East
                    }

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
                    , units = unit :: (List.map (\position -> { unit | location = Unit.OnMap position, side = Side.Player2 }) fixture.occupied ++ List.map (\position -> { unit | location = Unit.OnMap position }) fixture.allies)
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
                            features |> ListUtil.find (\feature -> feature.position == position) |> Maybe.andThen (\feature -> rules |> ListUtil.find (\rule -> rule.kind == fixture.kind) |> Maybe.andThen (\rule -> rule.terrainCosts |> ListUtil.find (\entry -> entry.terrain == feature.terrain) |> Maybe.map .cost)) |> Maybe.withDefault 1000
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
                    { cargoCapacity = 0, hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }, fuel = Nothing, id = id, kind = UnitKind.Infantry, location = Unit.OnMap origin, side = Side.Player1, direction = Just Direction.East }

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
                    Just (Movement.start origin)
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
                    (traceFrom origin == Just (Movement.start origin))
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
                    (Movement.trace rules board unit (Movement.start origin) { x = 0, y = 2 }
                        |> Maybe.map (\path -> path.path == [ origin, down, { x = 0, y = 2 } ] && path.cost == 4)
                        |> Maybe.withDefault False
                    )
                , test "enemy cells reject extension"
                    (Movement.trace rules { board | units = [ unit, { unit | location = Unit.OnMap down, side = Side.Player2 } ] } unit (Movement.start origin) down == Nothing)
                , test "allied squares can be traced through but cannot be destinations"
                    (let
                        alliedBoard : GameBoard.GameBoard
                        alliedBoard =
                            { board | units = [ unit, { unit | location = Unit.OnMap down } ] }
                     in
                     Movement.trace rules alliedBoard unit (Movement.start origin) down
                        |> Maybe.andThen
                            (\path ->
                                if Movement.canStop [] alliedBoard unit path then
                                    Nothing

                                else
                                    Movement.trace rules alliedBoard unit path { x = 0, y = 2 }
                            )
                        |> Maybe.map (\path -> path.path == [ origin, down, { x = 0, y = 2 } ] && path.cost == 4 && Movement.canStop [] alliedBoard unit path)
                        |> Maybe.withDefault False
                    )
                , test "fractional terrain cost is refunded on backtracking"
                    (let
                        roughBoard : GameBoard.GameBoard
                        roughBoard =
                            { board | map = { width = 4, height = 4, baseTile = Terrain.GrassPlain, features = [ { position = down, terrain = Terrain.Hills } ] } }
                     in
                     Movement.trace rules roughBoard unit (Movement.start origin) down
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
                    { cargoCapacity = 0, hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }, fuel = Nothing, id = id, kind = UnitKind.Infantry, location = Unit.OnMap { x = 0, y = 0 }, side = Side.Player1, direction = Just Direction.East }

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
                    (Movement.trace rules board unit (Movement.start { x = 0, y = 0 }) reserved
                        |> Maybe.map (Movement.canStop [ reserved ] board unit >> not)
                        |> Maybe.withDefault False
                    )
                , test "routes can pass through reserved destinations"
                    (List.any (\option -> option.destination == beyond && option.path == [ { x = 0, y = 0 }, reserved, beyond ]) options)
                , test "releasing a reservation restores its movement choice"
                    (Movement.options [] rules board unit
                        |> List.any (\option -> option.destination == reserved)
                    )
                ]


fuelChecks : List Movement.Rule -> List String
fuelChecks rules =
    case UnitId.parse "1" of
        Err error ->
            [ error ]

        Ok id ->
            let
                unit : Unit.Unit
                unit =
                    { cargoCapacity = 0, hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 0 }, id = id, kind = UnitKind.Tank, location = Unit.OnMap { x = 0, y = 0 }, side = Side.Player1, direction = Just Direction.East, fuel = Just { current = 2, maximum = 64 } }

                board : GameBoard.GameBoard
                board =
                    { map = { width = 5, height = 3, baseTile = Terrain.GrassPlain, features = [ { position = { x = 1, y = 0 }, terrain = Terrain.Forest } ] }, units = [ unit ], depots = [] }

                reachable : List Movement.Option
                reachable =
                    Movement.options [] rules board unit

                emptyUnit : Unit.Unit
                emptyUnit =
                    { unit | fuel = Just { current = 0, maximum = 64 } }

                traced : Maybe Movement.Option
                traced =
                    Movement.trace rules board unit (Movement.start { x = 0, y = 0 }) { x = 0, y = 1 }
                        |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 1, y = 1 })

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "empty vehicles have no movement choices" (List.isEmpty (Movement.options [] rules board emptyUnit))
                , test "fuel bounds every returned path" (List.all (\option -> List.length option.path <= 3) reachable)
                , test "short expensive routes remain reachable when cheaper detours exceed fuel"
                    (List.any (\option -> option.destination == { x = 2, y = 0 } && option.cost == 8 && List.length option.path == 3) reachable)
                , test "tracing spends remaining fuel across extensions"
                    (traced |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 2, y = 1 }) |> (==) Nothing)
                , test "backtracking refunds fuel for later extensions"
                    (traced
                        |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 0, y = 1 })
                        |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 0, y = 2 })
                        |> Maybe.map (\path -> List.length path.path == 3)
                        |> Maybe.withDefault False
                    )
                , test "fuel-limited previews reroute to an affordable path"
                    (traced |> Maybe.andThen (\path -> Movement.preview rules board unit path { x = 1, y = 0 }) |> Maybe.map (\path -> List.length path.path == 2) |> Maybe.withDefault False)
                , test "full fuel does not override the movement budget"
                    (Movement.options [] rules board { unit | fuel = Just { current = 64, maximum = 64 } } |> List.all (\option -> option.cost <= 12))
                ]


supplyChecks : List Movement.Rule -> List String
supplyChecks rules =
    case UnitId.parse "1" of
        Err error ->
            [ error ]

        Ok id ->
            let
                supplies : Unit.Supplies
                supplies =
                    { current = 3, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }

                unit : Unit.Unit
                unit =
                    { cargoCapacity = 0, hitPoints = { current = 16, maximum = 16 }, id = id, kind = UnitKind.Infantry, location = Unit.OnMap { x = 0, y = 0 }, side = Side.Player1, direction = Just Direction.East, fuel = Nothing, supplies = supplies }

                board : GameBoard.GameBoard
                board =
                    { map = { width = 5, height = 3, baseTile = Terrain.GrassPlain, features = [] }, units = [ unit ], depots = [] }

                exhausted : Unit.Unit
                exhausted =
                    { unit | supplies = { supplies | current = 1 } }

                traced : Maybe Movement.Option
                traced =
                    Movement.trace rules board unit (Movement.start { x = 0, y = 0 }) { x = 0, y = 1 }
                        |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 1, y = 1 })

                fieldGun : Unit.Unit
                fieldGun =
                    { exhausted | kind = UnitKind.FieldGun }

                vehicle : Unit.Unit
                vehicle =
                    { unit | kind = UnitKind.Tank, fuel = Just { current = 2, maximum = 64 }, supplies = { supplies | current = 0, movementPerTile = 0 } }

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "upkeep is reserved before walking" (Movement.tileLimit exhausted == Just 0 && List.isEmpty (Movement.options [] rules board exhausted))
                , test "field guns also need supplies after upkeep" (List.isEmpty (Movement.options [] rules board fieldGun))
                , test "tracing reserves upkeep only once" (traced |> Maybe.map (\path -> List.length path.path == 3) |> Maybe.withDefault False)
                , test "extending a trace cannot overspend supplies" (traced |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 2, y = 1 }) |> (==) Nothing)
                , test "backtracking refunds movement supplies" (traced |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 0, y = 1 }) |> Maybe.andThen (\path -> Movement.trace rules board unit path { x = 0, y = 2 }) |> Maybe.map (\path -> List.length path.path == 3) |> Maybe.withDefault False)
                , test "vehicles use fuel rather than supplies for movement" (Movement.tileLimit vehicle == Just 2 && not (List.isEmpty (Movement.options [] rules board vehicle)))
                , test "empty supplies do not underflow the walking limit" (Movement.tileLimit { unit | supplies = { supplies | current = 0 } } == Just 0)
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
                            List.concatMap (check rules) cases ++ traceChecks rules ++ reservationChecks rules ++ fuelChecks rules ++ supplyChecks rules ++ transportChecks rules
                    )
                )
        , update = \msg model -> never msg
        , subscriptions = \_ -> Sub.none
        }


transportChecks : List Movement.Rule -> List String
transportChecks rules =
    case ( UnitId.parse "1", UnitId.parse "4", UnitId.parse "2" ) of
        ( Ok passengerId, Ok truckId, Ok otherId ) ->
            let
                passenger : Unit.Unit
                passenger =
                    { id = passengerId
                    , side = Side.Player1
                    , kind = UnitKind.Infantry
                    , direction = Just Direction.East
                    , hitPoints = { current = 16, maximum = 16 }
                    , supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }
                    , fuel = Nothing
                    , cargoCapacity = 0
                    , location = Unit.OnMap { x = 0, y = 0 }
                    }

                truck : Unit.Unit
                truck =
                    { passenger | id = truckId, kind = UnitKind.SupplyTruck, cargoCapacity = 2, direction = Nothing, location = Unit.OnMap { x = 1, y = 0 }, fuel = Just { current = 64, maximum = 64 } }

                board : GameBoard.GameBoard
                board =
                    { map = { width = 4, height = 3, baseTile = Terrain.GrassPlain, features = [] }
                    , depots = []
                    , units = [ passenger, truck ]
                    }

                aboard : Unit.Unit
                aboard =
                    { passenger | location = Unit.Aboard truckId }

                fullBoard : GameBoard.GameBoard
                fullBoard =
                    { board | units = [ passenger, truck, aboard, { aboard | id = otherId } ] }

                rideBoard : GameBoard.GameBoard
                rideBoard =
                    { board | units = [ aboard, truck ] }

                canReach : GameBoard.GameBoard -> Unit.Unit -> Coordinate -> Bool
                canReach current unit destination =
                    Movement.options [] rules current unit |> List.any (\option -> option.destination == destination)

                unload : Maybe Movement.Option
                unload =
                    Movement.preview rules rideBoard aboard (Movement.start { x = 1, y = 0 }) { x = 2, y = 0 }

                extendingUnload : Maybe Movement.Option
                extendingUnload =
                    unload |> Maybe.andThen (\path -> Movement.trace rules rideBoard aboard path { x = 3, y = 0 })

                expect : String -> Bool -> List String
                expect name valid =
                    if valid then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ expect "infantry can board" (canReach board passenger { x = 1, y = 0 })
                , expect "truck can collect infantry" (canReach board truck { x = 0, y = 0 })
                , expect "field guns can board" (canReach board { passenger | kind = UnitKind.FieldGun } { x = 1, y = 0 })
                , expect "tanks cannot board" (not (canReach board { passenger | kind = UnitKind.Tank } { x = 1, y = 0 }))
                , expect "full trucks reject boarding" (not (canReach fullBoard passenger { x = 1, y = 0 }))
                , expect "unload offers adjacent squares" (canReach rideBoard aboard { x = 2, y = 0 })
                , expect "unload does not offer distant squares" (not (canReach rideBoard aboard { x = 3, y = 0 }))
                , expect "traced unload cannot extend beyond one tile" (extendingUnload == Nothing)
                ]

        _ ->
            [ "invalid transport fixture IDs" ]
