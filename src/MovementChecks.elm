port module MovementChecks exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.Direction as Direction
import Api.Enum.MapTheme as MapTheme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.Terrain as Terrain
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import Json.Decode as D
import Map exposing (Map)
import Movement
import Platform
import TerrainFeature
import Unit
import Unit.Fuel exposing (Fuel)
import Unit.Location as Location
import Unit.Supplies exposing (Supplies)
import UnitId
import Util.List as ListUtil


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
                fuel : Maybe Fuel
                fuel =
                    case fixture.kind of
                        UnitKind.Tank ->
                            Just { current = 64, maximum = 64 }

                        UnitKind.Truck ->
                            Just { current = 64, maximum = 64 }

                        _ ->
                            Nothing

                unit : Unit.Unit
                unit =
                    { destroyed = False
                    , combatRules = { range = 1, shape = AmbushShape.Line, damage = 4, readinessCost = 2, shotCost = 2 }
                    , cargoCapacity = 0
                    , id = id
                    , kind = fixture.kind
                    , location = Location.OnMap fixture.origin
                    , playerNumber = PlayerNumber.Player1
                    , spriteFacing = SpriteFacing.Right
                    , direction = Just Direction.East
                    , resources =
                        Just
                            { supplyCargo = []
                            , hitPoints =
                                { current = 16
                                , maximum = 16
                                }
                            , supplies =
                                { current = 64
                                , maximum = 64
                                , upkeepPerTurn = 1
                                , roughTerrainSurcharge =
                                    if fixture.kind == UnitKind.Infantry then
                                        1

                                    else
                                        0
                                , movementPerTile =
                                    case fixture.kind of
                                        UnitKind.Infantry ->
                                            3

                                        UnitKind.FieldGun ->
                                            1

                                        _ ->
                                            0
                                }
                            , fuel = fuel
                            }
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

                map : Map
                map =
                    { width = rows |> List.head |> Maybe.map String.length |> Maybe.withDefault 0, height = List.length rows, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = features }

                units : List Unit.Unit
                units =
                    unit :: (List.map (\position -> { unit | location = Location.OnMap position, playerNumber = PlayerNumber.Player2, spriteFacing = SpriteFacing.Left }) fixture.occupied ++ List.map (\position -> { unit | location = Location.OnMap position }) fixture.allies)

                options : List Movement.Option
                options =
                    Movement.options [] rules map units unit

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
                            features
                                |> ListUtil.find (\feature -> feature.position == position)
                                |> Maybe.andThen
                                    (\feature ->
                                        rules
                                            |> ListUtil.find (\rule -> rule.kind == fixture.kind)
                                            |> Maybe.andThen
                                                (\rule ->
                                                    rule.terrainCosts
                                                        |> ListUtil.find (\entry -> entry.terrain == feature.terrain)
                                                        |> Maybe.map .cost
                                                )
                                    )
                                |> Maybe.withDefault 1000
                    in
                    (List.head option.path == Just fixture.origin)
                        && ((List.reverse option.path |> List.head) == Just option.destination)
                        && List.all
                            (\( a, b ) ->
                                abs (a.x - b.x) + abs (a.y - b.y) == 1
                            )
                            steps
                        && not (List.member option.destination (fixture.allies ++ fixture.occupied))
                        && (List.sum (List.map entryCost (List.drop 1 option.path)) == option.cost)
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
                    { destroyed = False
                    , combatRules =
                        { range = 1
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , id = id
                    , kind = UnitKind.Infantry
                    , location = Location.OnMap origin
                    , playerNumber = PlayerNumber.Player1
                    , spriteFacing = SpriteFacing.Right
                    , direction = Just Direction.East
                    , resources =
                        Just
                            { supplyCargo = []
                            , hitPoints =
                                { current = 16
                                , maximum = 16
                                }
                            , supplies =
                                { current = 64
                                , maximum = 64
                                , upkeepPerTurn = 1
                                , roughTerrainSurcharge = 0
                                , movementPerTile = 1
                                }
                            , fuel = Nothing
                            }
                    }

                map : Map
                map =
                    { width = 4, height = 4, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [] }

                units : List Unit.Unit
                units =
                    [ unit ]

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
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path down)
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path right)

                traceFrom : Coordinate -> Maybe Movement.Option
                traceFrom destination =
                    traced |> Maybe.andThen (\path -> Movement.trace rules map units unit path destination)

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
                        |> Maybe.andThen (\path -> Movement.preview rules map units unit path up)
                        |> Maybe.map (\path -> path.cost == 2 && path.path == [ origin, up ])
                        |> Maybe.withDefault False
                    )
                , test "preview preserves the traced route when it fits"
                    (traced |> Maybe.andThen (\path -> Movement.preview rules map units unit path right) |> (==) traced)
                , test "preview still rejects destinations beyond the full budget"
                    (traced |> Maybe.andThen (\path -> Movement.preview rules map units unit path { x = 3, y = 3 }) |> (==) Nothing)
                , test "skipped cells extend the existing prefix"
                    (Movement.trace rules map units unit (Movement.start origin) { x = 0, y = 2 }
                        |> Maybe.map (\path -> path.path == [ origin, down, { x = 0, y = 2 } ] && path.cost == 4)
                        |> Maybe.withDefault False
                    )
                , test "enemy cells allow a route preview but resolution may stop it"
                    (Movement.trace rules map [ unit, { unit | location = Location.OnMap down, playerNumber = PlayerNumber.Player2, spriteFacing = SpriteFacing.Left } ] unit (Movement.start origin) down /= Nothing)
                , test "allied squares can be traced through but cannot be destinations"
                    (let
                        alliedUnits : List Unit.Unit
                        alliedUnits =
                            [ unit, { unit | location = Location.OnMap down } ]
                     in
                     Movement.trace rules map alliedUnits unit (Movement.start origin) down
                        |> Maybe.andThen
                            (\path ->
                                if Movement.canStop [] alliedUnits unit path then
                                    Nothing

                                else
                                    Movement.trace rules map alliedUnits unit path { x = 0, y = 2 }
                            )
                        |> Maybe.map (\path -> path.path == [ origin, down, { x = 0, y = 2 } ] && path.cost == 4 && Movement.canStop [] alliedUnits unit path)
                        |> Maybe.withDefault False
                    )
                , test "terrain mobility is refunded on backtracking"
                    (let
                        roughMap : Map
                        roughMap =
                            { width = 4, height = 4, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [ { position = down, terrain = Terrain.Hills } ] }
                     in
                     Movement.trace rules roughMap units unit (Movement.start origin) down
                        |> Maybe.andThen
                            (\path ->
                                if path.cost == 2 then
                                    Movement.trace rules roughMap units unit path origin

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
                    { destroyed = False
                    , combatRules =
                        { range = 1
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , id = id
                    , kind = UnitKind.Infantry
                    , location =
                        Location.OnMap
                            { x = 0
                            , y = 0
                            }
                    , playerNumber = PlayerNumber.Player1
                    , spriteFacing = SpriteFacing.Right
                    , direction = Just Direction.East
                    , resources =
                        Just
                            { supplyCargo = []
                            , hitPoints =
                                { current = 16
                                , maximum = 16
                                }
                            , supplies =
                                { current = 64
                                , maximum = 64
                                , upkeepPerTurn = 1
                                , roughTerrainSurcharge = 0
                                , movementPerTile = 1
                                }
                            , fuel = Nothing
                            }
                    }

                map : Map
                map =
                    { width = 3, height = 1, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [] }

                units : List Unit.Unit
                units =
                    [ unit ]

                reserved : Coordinate
                reserved =
                    { x = 1, y = 0 }

                beyond : Coordinate
                beyond =
                    { x = 2, y = 0 }

                options : List Movement.Option
                options =
                    Movement.options [ reserved ] rules map units unit

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
                    (Movement.trace rules map units unit (Movement.start { x = 0, y = 0 }) reserved
                        |> Maybe.map (Movement.canStop [ reserved ] units unit >> not)
                        |> Maybe.withDefault False
                    )
                , test "routes can pass through reserved destinations"
                    (List.any (\option -> option.destination == beyond && option.path == [ { x = 0, y = 0 }, reserved, beyond ]) options)
                , test "releasing a reservation restores its movement choice"
                    (Movement.options [] rules map units unit
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
                    { destroyed = False
                    , combatRules =
                        { range = 1
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , id = id
                    , kind = UnitKind.Tank
                    , location =
                        Location.OnMap
                            { x = 0
                            , y = 0
                            }
                    , playerNumber = PlayerNumber.Player1
                    , spriteFacing = SpriteFacing.Right
                    , direction = Just Direction.East
                    , resources =
                        Just
                            { supplyCargo = []
                            , hitPoints =
                                { current = 16
                                , maximum = 16
                                }
                            , supplies =
                                { current = 64
                                , maximum = 64
                                , upkeepPerTurn = 1
                                , roughTerrainSurcharge = 0
                                , movementPerTile = 0
                                }
                            , fuel =
                                Just
                                    { current = 2
                                    , maximum = 64
                                    }
                            }
                    }

                map : Map
                map =
                    { width = 5, height = 3, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [ { position = { x = 1, y = 0 }, terrain = Terrain.Forest } ] }

                units : List Unit.Unit
                units =
                    [ unit ]

                reachable : List Movement.Option
                reachable =
                    Movement.options [] rules map units unit

                emptyUnit : Unit.Unit
                emptyUnit =
                    { unit | resources = Maybe.map (\resources -> { resources | fuel = Just { current = 0, maximum = 64 } }) unit.resources }

                traced : Maybe Movement.Option
                traced =
                    Movement.trace rules map units unit (Movement.start { x = 0, y = 0 }) { x = 0, y = 1 }
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 1, y = 1 })

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "empty vehicles have no movement choices" (List.isEmpty (Movement.options [] rules map units emptyUnit))
                , test "fuel bounds every returned path" (List.all (\option -> List.length option.path <= 3) reachable)
                , test "short expensive routes remain reachable when cheaper detours exceed fuel"
                    (List.any (\option -> option.destination == { x = 2, y = 0 } && option.cost == 8 && List.length option.path == 3) reachable)
                , test "tracing spends remaining fuel across extensions"
                    (traced |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 2, y = 1 }) |> (==) Nothing)
                , test "backtracking refunds fuel for later extensions"
                    (traced
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 0, y = 1 })
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 0, y = 2 })
                        |> Maybe.map (\path -> List.length path.path == 3)
                        |> Maybe.withDefault False
                    )
                , test "fuel-limited previews reroute to an affordable path"
                    (traced |> Maybe.andThen (\path -> Movement.preview rules map units unit path { x = 1, y = 0 }) |> Maybe.map (\path -> List.length path.path == 2) |> Maybe.withDefault False)
                , test "full fuel does not override the movement budget"
                    (Movement.options [] rules map units { unit | resources = Maybe.map (\resources -> { resources | fuel = Just { current = 64, maximum = 64 } }) unit.resources } |> List.all (\option -> option.cost <= 12))
                ]


supplyChecks : List Movement.Rule -> List String
supplyChecks rules =
    case UnitId.parse "1" of
        Err error ->
            [ error ]

        Ok id ->
            let
                supplies : Supplies
                supplies =
                    { current = 9, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 4 }

                unit : Unit.Unit
                unit =
                    { destroyed = False
                    , combatRules =
                        { range = 1
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , id = id
                    , kind = UnitKind.Infantry
                    , location =
                        Location.OnMap
                            { x = 0
                            , y = 0
                            }
                    , playerNumber = PlayerNumber.Player1
                    , spriteFacing = SpriteFacing.Right
                    , direction = Just Direction.East
                    , resources =
                        Just
                            { supplyCargo = []
                            , hitPoints =
                                { current = 16
                                , maximum = 16
                                }
                            , fuel = Nothing
                            , supplies = supplies
                            }
                    }

                map : Map
                map =
                    { width = 5, height = 3, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [] }

                units : List Unit.Unit
                units =
                    [ unit ]

                exhausted : Unit.Unit
                exhausted =
                    { unit | resources = Maybe.map (\resources -> { resources | supplies = { supplies | current = 1 } }) unit.resources }

                traced : Maybe Movement.Option
                traced =
                    Movement.trace rules map units unit (Movement.start { x = 0, y = 0 }) { x = 0, y = 1 }
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 1, y = 1 })

                fieldGun : Unit.Unit
                fieldGun =
                    { exhausted | kind = UnitKind.FieldGun }

                vehicle : Unit.Unit
                vehicle =
                    { unit | kind = UnitKind.Tank, resources = Maybe.map (\resources -> { resources | fuel = Just { current = 2, maximum = 64 }, supplies = { supplies | current = 0, roughTerrainSurcharge = 0, movementPerTile = 0 } }) unit.resources }

                roughMap : Map
                roughMap =
                    { map | baseTile = Terrain.Forest }

                infantry : Unit.Unit
                infantry =
                    { unit | resources = Maybe.map (\resources -> { resources | supplies = { supplies | current = 8, movementPerTile = 3, roughTerrainSurcharge = 1 } }) unit.resources }

                roughTrace : Maybe Movement.Option
                roughTrace =
                    Movement.trace rules roughMap [ infantry ] infantry (Movement.start { x = 0, y = 0 }) { x = 1, y = 0 }

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "upkeep is reserved before walking" (Movement.tileLimit exhausted == Just 0 && List.isEmpty (Movement.options [] rules map units exhausted))
                , test "field guns also need supplies after upkeep" (List.isEmpty (Movement.options [] rules map units fieldGun))
                , test "tracing reserves upkeep only once" (traced |> Maybe.map (\path -> List.length path.path == 3) |> Maybe.withDefault False)
                , test "extending a trace cannot overspend supplies" (traced |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 2, y = 1 }) |> (==) Nothing)
                , test "backtracking refunds movement supplies" (traced |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 0, y = 1 }) |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 0, y = 2 }) |> Maybe.map (\path -> List.length path.path == 3) |> Maybe.withDefault False)
                , test "vehicles use fuel rather than supplies for movement" (Movement.tileLimit vehicle == Just 2 && not (List.isEmpty (Movement.options [] rules map units vehicle)))
                , test "empty supplies do not underflow the walking limit" (Movement.tileLimit { unit | resources = Maybe.map (\resources -> { resources | supplies = { supplies | current = 0 } }) unit.resources } == Just 0)
                , test "two forest squares retain infantry mobility" (Movement.options [] rules roughMap [ unit ] { infantry | resources = Maybe.map (\resources -> { resources | supplies = { supplies | current = 9, movementPerTile = 3, roughTerrainSurcharge = 1 } }) infantry.resources } |> List.any (\option -> option.destination == { x = 2, y = 0 } && option.cost == 4))
                , test "terrain supplies restrict otherwise reachable routes" (Movement.options [] rules roughMap [ infantry ] infantry |> List.all (\option -> List.length option.path <= 2))
                , test "terrain supply cost is paid on entered squares" (Movement.supplyCost roughMap { supplies | movementPerTile = 3, roughTerrainSurcharge = 1 } [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 2, y = 0 } ] == 8)
                , test "rough terrain trace extensions reserve upkeep" (roughTrace |> Maybe.andThen (\path -> Movement.trace rules roughMap [ infantry ] infantry path { x = 2, y = 0 }) |> (==) Nothing)
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
                            List.concatMap
                                (check rules)
                                cases
                                ++ traceChecks rules
                                ++ reservationChecks rules
                                ++ fuelChecks rules
                                ++ supplyChecks rules
                                ++ transportChecks rules
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
                    , playerNumber = PlayerNumber.Player1
                    , spriteFacing = SpriteFacing.Right
                    , kind = UnitKind.Infantry
                    , direction = Just Direction.East
                    , destroyed = False
                    , combatRules =
                        { range = 1
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , location =
                        Location.OnMap
                            { x = 0
                            , y = 0
                            }
                    , resources =
                        Just
                            { supplyCargo = []
                            , hitPoints =
                                { current = 16
                                , maximum = 16
                                }
                            , supplies =
                                { current = 64
                                , maximum = 64
                                , upkeepPerTurn = 1
                                , roughTerrainSurcharge = 0
                                , movementPerTile = 1
                                }
                            , fuel = Nothing
                            }
                    }

                truck : Unit.Unit
                truck =
                    { passenger | id = truckId, kind = UnitKind.Truck, destroyed = False, combatRules = { range = 1, shape = AmbushShape.Line, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 2, direction = Nothing, location = Location.OnMap { x = 1, y = 0 }, resources = Maybe.map (\resources -> { resources | fuel = Just { current = 64, maximum = 64 } }) passenger.resources }

                map : Map
                map =
                    { width = 4, height = 3, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [] }

                units : List Unit.Unit
                units =
                    [ passenger, truck ]

                aboard : Unit.Unit
                aboard =
                    { passenger | location = Location.Aboard truckId }

                fullUnits : List Unit.Unit
                fullUnits =
                    [ passenger, truck, aboard, { aboard | id = otherId } ]

                rideUnits : List Unit.Unit
                rideUnits =
                    [ aboard, truck ]

                fuelEmptyTruck : Unit.Unit
                fuelEmptyTruck =
                    { truck | resources = Maybe.map (\resources -> { resources | fuel = Just { current = 0, maximum = 64 } }) truck.resources }

                strandedUnits : List Unit.Unit
                strandedUnits =
                    [ aboard, fuelEmptyTruck ]

                canReach : List Unit.Unit -> Unit.Unit -> Coordinate -> Bool
                canReach current unit destination =
                    Movement.options [] rules map current unit |> List.any (\option -> option.destination == destination)

                unload : Maybe Movement.Option
                unload =
                    Movement.preview rules map rideUnits aboard (Movement.start { x = 1, y = 0 }) { x = 2, y = 0 }

                extendingUnload : Maybe Movement.Option
                extendingUnload =
                    unload |> Maybe.andThen (\path -> Movement.trace rules map rideUnits aboard path { x = 3, y = 0 })

                expect : String -> Bool -> List String
                expect name valid =
                    if valid then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ expect "infantry can board" (canReach units passenger { x = 1, y = 0 })
                , expect "truck can collect infantry" (canReach units truck { x = 0, y = 0 })
                , expect "field guns can board" (canReach units { passenger | kind = UnitKind.FieldGun } { x = 1, y = 0 })
                , expect "tanks cannot board" (not (canReach units { passenger | kind = UnitKind.Tank } { x = 1, y = 0 }))
                , expect "full trucks reject boarding" (not (canReach fullUnits passenger { x = 1, y = 0 }))
                , expect "zero fuel still forbids truck movement" (List.isEmpty (Movement.options [] rules map strandedUnits fuelEmptyTruck))
                , expect "zero fuel truck passengers can unload beside the stationary truck" (canReach strandedUnits aboard { x = 2, y = 0 })
                , expect "stationary unloads still reject the occupied truck origin" (not (canReach strandedUnits aboard { x = 1, y = 0 }))
                , expect "stationary unloads still reject reserved exits" (not (List.any (\option -> option.destination == { x = 2, y = 0 }) (Movement.options [ { x = 2, y = 0 } ] rules map strandedUnits aboard)))
                , expect "stationary unloads still require passenger movement supplies" (not (canReach strandedUnits { aboard | resources = Maybe.map (\resources -> { resources | supplies = { current = 1, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 } }) aboard.resources } { x = 2, y = 0 }))
                , expect "unload offers adjacent squares" (canReach rideUnits aboard { x = 2, y = 0 })
                , expect "unload does not offer distant squares" (not (canReach rideUnits aboard { x = 3, y = 0 }))
                , expect "traced unload cannot extend beyond one tile" (extendingUnload == Nothing)
                ]

        _ ->
            [ "invalid transport fixture IDs" ]
