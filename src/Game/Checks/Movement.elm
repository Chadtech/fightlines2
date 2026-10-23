port module Game.Checks.Movement exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.DepotKind as DepotKind
import Api.Enum.Direction as Direction
import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.MapTheme as MapTheme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.Terrain as Terrain exposing (Terrain)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.Movement as Movement
import Game.TerrainFeature as TerrainFeature
import Game.Unit as Unit
import Game.Unit.Fuel exposing (Fuel)
import Game.Unit.Location as Location
import Game.Unit.Supplies exposing (Supplies)
import Game.UnitId as UnitId
import Game.UnitResources as UnitResources
import Json.Decode as D exposing (Decoder)
import Platform
import Set
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


coordinate : Decoder Coordinate
coordinate =
    D.map2 Coordinate (D.index 0 D.int) (D.index 1 D.int)


caseDecoder : Decoder Case
caseDecoder =
    D.map7 Case
        (D.field "name" D.string)
        (D.field "kind" UnitKind.decoder)
        (D.field "sketch" D.string)
        (D.field "origin" coordinate)
        (D.field "occupied" (D.list coordinate))
        (D.field "allies" (D.list coordinate))
        (D.field "expected" (D.list (D.list D.int)))


ruleDecoder : Decoder Movement.Rule
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
                            Just
                                { current = 64
                                , maximum = 64
                                , movementPerTile = 2
                                , movementPerCargoSlot = 0
                                }

                        UnitKind.Truck ->
                            Just
                                { current = 64
                                , maximum = 64
                                , movementPerTile = 1
                                , movementPerCargoSlot = 0
                                }

                        _ ->
                            Nothing

                unit : Unit.Unit
                unit =
                    { destroyed = False
                    , combatRules =
                        { range = 1
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , digInCost = 64
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , id = id
                    , kind = fixture.kind
                    , location = Location.OnMap fixture.origin
                    , playerNumber = PlayerNumber.Player1
                    , entrenchment = Entrenchment.Exposed
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

                                                else if symbol == '^' then
                                                    Terrain.Mountains

                                                else if symbol == '~' then
                                                    Terrain.Water

                                                else if symbol == ':' then
                                                    Terrain.Beach

                                                else
                                                    Terrain.Plain
                                            }
                                        )
                            )
                        |> List.concat

                map : Map
                map =
                    Map.fromFeatures { width = rows |> List.head |> Maybe.map String.length |> Maybe.withDefault 0, height = List.length rows, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = features }

                units : List Unit.Unit
                units =
                    unit
                        :: (List.map
                                (\position ->
                                    unit
                                        |> Unit.setOnMap position
                                        |> Unit.setPlayerNumber PlayerNumber.Player2
                                        |> Unit.setSpriteFacing SpriteFacing.Left
                                )
                                fixture.occupied
                                ++ List.map
                                    (\position ->
                                        unit
                                            |> Unit.setOnMap position
                                    )
                                    fixture.allies
                           )

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
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , digInCost = 64
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , id = id
                    , kind = UnitKind.Infantry
                    , location = Location.OnMap origin
                    , playerNumber = PlayerNumber.Player1
                    , entrenchment = Entrenchment.Exposed
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
                    Map.fromFeatures { width = 4, height = 4, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [] }

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
                    (Movement.trace rules
                        map
                        [ unit
                        , unit
                            |> Unit.setOnMap down
                            |> Unit.setPlayerNumber PlayerNumber.Player2
                            |> Unit.setSpriteFacing SpriteFacing.Left
                        ]
                        unit
                        (Movement.start origin)
                        down
                        /= Nothing
                    )
                , test "allied squares can be traced through but cannot be destinations"
                    (let
                        alliedUnits : List Unit.Unit
                        alliedUnits =
                            [ unit
                            , unit
                                |> Unit.setOnMap down
                            ]
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
                            Map.fromFeatures { width = 4, height = 4, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [ { position = down, terrain = Terrain.Hills } ] }
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
                ++ targetSearchChecks unit


{-| Compare exact paths, including ties, with the full reachability search.
The explicit cases exercise resource states that cannot be collapsed by position.
-}
targetSearchChecks : Unit.Unit -> List String
targetSearchChecks unit =
    let
        origin : Coordinate
        origin =
            { x = 0, y = 0 }

        destination : Coordinate
        destination =
            { x = 2, y = 0 }

        forest : Coordinate
        forest =
            { x = 1, y = 0 }

        map : Map
        map =
            Map.fromFeatures { width = 3, height = 2, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [ { position = forest, terrain = Terrain.Forest } ] }

        rule : Movement.Rule
        rule =
            { kind = unit.kind
            , budget = 12
            , terrainCosts =
                [ { terrain = Terrain.Plain, cost = 2 }
                , { terrain = Terrain.Forest, cost = 6 }
                , { terrain = Terrain.Hills, cost = 3 }
                , { terrain = Terrain.Mountains, cost = 0 }
                ]
            }

        expensiveRule : Movement.Rule
        expensiveRule =
            { rule | terrainCosts = List.map expensiveForest rule.terrainCosts }

        expensiveForest : Movement.TerrainCost -> Movement.TerrainCost
        expensiveForest entry =
            if entry.terrain == Terrain.Forest then
                { entry | cost = 8 }

            else
                entry

        -- The six-square target route settles before the four-square route,
        -- both at cost 8. Stopping at the first settled target is incorrect.
        lateShorterMap : Map
        lateShorterMap =
            Map.fromFeatures
                { width = 4
                , height = 3
                , baseTile = map.baseTile
                , theme = map.theme
                , features = List.indexedMap tieFeature [ 5, 5, 2, 1, 2, 2, 1, 5, 5, 1, 2, 1 ]
                }

        tieFeature : Int -> Int -> TerrainFeature.TerrainFeature
        tieFeature index cost =
            { position = { x = modBy 4 index, y = index // 4 }
            , terrain =
                case cost of
                    5 ->
                        Terrain.Forest

                    2 ->
                        Terrain.Hills

                    _ ->
                        Terrain.Plain
            }

        tieRule : Movement.Rule
        tieRule =
            { rule
                | terrainCosts =
                    [ { terrain = Terrain.Plain, cost = 1 }
                    , { terrain = Terrain.Hills, cost = 2 }
                    , { terrain = Terrain.Forest, cost = 5 }
                    ]
            }

        fuelLimited : Unit.Unit
        fuelLimited =
            unit
                |> Unit.setResources
                    (Maybe.map
                        (\resources ->
                            { resources
                                | fuel =
                                    Just
                                        { current = 4
                                        , maximum = 64
                                        , movementPerTile = 2
                                        , movementPerCargoSlot = 0
                                        }
                            }
                        )
                        unit.resources
                    )

        supplyLimited : Unit.Unit
        supplyLimited =
            unit
                |> Unit.setResources (Maybe.map limitedSupplies unit.resources)

        limitedSupplies : UnitResources.UnitResources -> UnitResources.UnitResources
        limitedSupplies resources =
            let
                supplies : Supplies
                supplies =
                    resources.supplies
            in
            { resources | supplies = { supplies | current = 5, roughTerrainSurcharge = 4 } }

        route : Movement.Rule -> Unit.Unit -> Coordinate -> Maybe Movement.Option
        route movementRule mover target =
            Movement.trace [ movementRule ] map [ mover ] mover (Movement.start origin) target

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]

        compareAll : Movement.Rule -> Unit.Unit -> Map -> List String
        compareAll movementRule mover board =
            let
                allRoutes : List Movement.Option
                allRoutes =
                    Movement.optionsAvoiding [ origin ] [ movementRule ] board [ mover ] mover

                compareTarget : Coordinate -> List String
                compareTarget target =
                    if target == origin then
                        []

                    else
                        expect ("target search differs from full search at " ++ String.fromInt target.x ++ "," ++ String.fromInt target.y)
                            (Movement.trace [ movementRule ] board [ mover ] mover (Movement.start origin) target
                                == ListUtil.find (\option -> option.destination == target) allRoutes
                            )
            in
            List.concatMap compareTarget (Map.positions board ++ [ { x = -1, y = 0 }, { x = board.width, y = 0 } ])

        withFeatures : List TerrainFeature.TerrainFeature -> Map
        withFeatures features =
            Map.fromFeatures
                { width = map.width
                , height = map.height
                , baseTile = map.baseTile
                , theme = map.theme
                , features = features
                }

        variedMaps : List Map
        variedMaps =
            [ map
            , withFeatures []
            , withFeatures [ { position = forest, terrain = Terrain.Mountains }, { position = { x = 1, y = 1 }, terrain = Terrain.Mountains } ]
            , withFeatures [ { position = forest, terrain = Terrain.Hills }, { position = destination, terrain = Terrain.Forest } ]
            ]

        compareMover : Unit.Unit -> List String
        compareMover mover =
            List.concatMap (compareAll rule mover) variedMaps
                ++ List.concatMap (compareAll expensiveRule mover) variedMaps
    in
    List.concat
        [ expect "equal movement cost prefers the shorter target route"
            (route rule unit destination |> Maybe.map .path |> (==) (Just [ origin, forest, destination ]))
        , expect "a cheaper weighted detour wins over the direct target route"
            (route expensiveRule unit destination |> Maybe.map (\option -> option.cost == 8 && List.length option.path == 5) |> Maybe.withDefault False)
        , expect "target search retains the expensive route when the cheaper detour exceeds fuel"
            (route expensiveRule fuelLimited destination |> Maybe.map (\option -> option.cost == 10 && option.path == [ origin, forest, destination ]) |> Maybe.withDefault False)
        , expect "target search retains the supply-affordable detour"
            (route rule supplyLimited destination |> Maybe.map (\option -> option.cost == 8 && List.length option.path == 5) |> Maybe.withDefault False)
        , expect "an equal cost and length tie keeps the established route"
            (route rule unit { x = 1, y = 1 } |> Maybe.map .path |> (==) (Just [ origin, { x = 0, y = 1 }, { x = 1, y = 1 } ]))
        , expect "a later settled target can win the equal-cost length tie"
            (Movement.trace [ tieRule ] lateShorterMap [ unit ] unit (Movement.start origin) { x = 3, y = 0 }
                |> Maybe.map (\option -> option.cost == 8 && option.path == [ origin, forest, destination, { x = 3, y = 0 } ])
                |> Maybe.withDefault False
            )
        , compareAll tieRule unit lateShorterMap
        , List.concatMap compareMover
            [ unit
            , fuelLimited
            , supplyLimited
            , unit
                |> Unit.setResources Nothing
            ]
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
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , digInCost = 64
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
                    , entrenchment = Entrenchment.Exposed
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
                    Map.fromFeatures { width = 3, height = 1, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [] }

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
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , digInCost = 64
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
                    , entrenchment = Entrenchment.Exposed
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
                                { current = 128
                                , maximum = 128
                                , upkeepPerTurn = 1
                                , roughTerrainSurcharge = 0
                                , movementPerTile = 0
                                }
                            , fuel =
                                Just
                                    { current = 14
                                    , maximum = 128
                                    , movementPerTile = 7
                                    , movementPerCargoSlot = 0
                                    }
                            }
                    }

                map : Map
                map =
                    Map.fromFeatures { width = 5, height = 3, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [ { position = { x = 1, y = 0 }, terrain = Terrain.Forest } ] }

                units : List Unit.Unit
                units =
                    [ unit ]

                reachable : List Movement.Option
                reachable =
                    Movement.options [] rules map units unit

                emptyUnit : Unit.Unit
                emptyUnit =
                    unit
                        |> Unit.setResources (Maybe.map (\resources -> { resources | fuel = Just { current = 0, maximum = 128, movementPerTile = 7, movementPerCargoSlot = 0 } }) unit.resources)

                traced : Maybe Movement.Option
                traced =
                    Movement.trace rules map units unit (Movement.start { x = 0, y = 0 }) { x = 0, y = 1 }
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 1, y = 1 })

                truck : Unit.Unit
                truck =
                    unit
                        |> Unit.setKind UnitKind.Truck
                        |> Unit.setCargoCapacity 2
                        |> Unit.setResources (Maybe.map (\resources -> { resources | fuel = Just { current = 12, maximum = 128, movementPerTile = 2, movementPerCargoSlot = 2 } }) unit.resources)

                passenger : Unit.Unit
                passenger =
                    unit
                        |> Unit.setLocation (Location.Aboard id)

                loadedTruck : Unit.Unit
                loadedTruck =
                    truck
                        |> Unit.setResources (Maybe.map (\resources -> { resources | supplyCargo = [ { kind = DepotKind.Supply, current = 256, maximum = 256 } ] }) truck.resources)

                fullCargo : List Unit.Unit
                fullCargo =
                    [ loadedTruck, passenger ]

                cargoTrace : Maybe Movement.Option
                cargoTrace =
                    Movement.trace rules map fullCargo loadedTruck (Movement.start { x = 0, y = 0 }) { x = 0, y = 1 }
                        |> Maybe.andThen (\path -> Movement.trace rules map fullCargo loadedTruck path { x = 1, y = 1 })

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "empty trucks spend two fuel per tile" (Movement.tileLimit [ truck ] truck == Just 6)
                , test "passengers add two fuel per tile" (Movement.tileLimit [ truck, passenger ] truck == Just 3)
                , test "freight adds two fuel per tile" (Movement.tileLimit [ loadedTruck ] loadedTruck == Just 3)
                , test "mixed full cargo spends six fuel per tile" (Movement.tileLimit fullCargo loadedTruck == Just 2)
                , test "loaded tracing accounts for fuel already spent" (cargoTrace |> Maybe.andThen (\path -> Movement.trace rules map fullCargo loadedTruck path { x = 2, y = 1 }) |> (==) Nothing)
                , test "empty vehicles have no movement choices" (List.isEmpty (Movement.options [] rules map units emptyUnit))
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
                    (Movement.options []
                        rules
                        map
                        units
                        (unit
                            |> Unit.setResources (Maybe.map (\resources -> { resources | fuel = Just { current = 128, maximum = 128, movementPerTile = 7, movementPerCargoSlot = 0 } }) unit.resources)
                        )
                        |> List.all (\option -> option.cost <= 12)
                    )
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
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , digInCost = 64
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
                    , entrenchment = Entrenchment.Exposed
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
                    Map.fromFeatures { width = 5, height = 3, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [] }

                units : List Unit.Unit
                units =
                    [ unit ]

                exhausted : Unit.Unit
                exhausted =
                    unit
                        |> Unit.setResources (Maybe.map (\resources -> { resources | supplies = { supplies | current = 1 } }) unit.resources)

                traced : Maybe Movement.Option
                traced =
                    Movement.trace rules map units unit (Movement.start { x = 0, y = 0 }) { x = 0, y = 1 }
                        |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 1, y = 1 })

                fieldGun : Unit.Unit
                fieldGun =
                    unit
                        |> Unit.setKind UnitKind.FieldGun
                        |> Unit.setResources (Maybe.map (\resources -> { resources | supplies = { supplies | current = 27, maximum = 196, upkeepPerTurn = 4, movementPerTile = 24 } }) unit.resources)

                suppliedFieldGun : Unit.Unit
                suppliedFieldGun =
                    fieldGun
                        |> Unit.setResources (Maybe.map (\resources -> { resources | supplies = { supplies | current = 28, maximum = 196, upkeepPerTurn = 4, movementPerTile = 24 } }) fieldGun.resources)

                vehicle : Unit.Unit
                vehicle =
                    unit
                        |> Unit.setKind UnitKind.Tank
                        |> Unit.setResources (Maybe.map (\resources -> { resources | fuel = Just { current = 2, maximum = 64, movementPerTile = 2, movementPerCargoSlot = 0 }, supplies = { supplies | current = 0, roughTerrainSurcharge = 0, movementPerTile = 0 } }) unit.resources)

                roughMap : Map
                roughMap =
                    { map | baseTile = Terrain.Forest }

                infantry : Unit.Unit
                infantry =
                    unit
                        |> Unit.setResources (Maybe.map (\resources -> { resources | supplies = { supplies | current = 8, movementPerTile = 3, roughTerrainSurcharge = 1 } }) unit.resources)

                roughTrace : Maybe Movement.Option
                roughTrace =
                    Movement.trace rules roughMap [ infantry ] infantry (Movement.start { x = 0, y = 0 }) { x = 1, y = 0 }

                terrainSupplyCostMatches : ( Terrain, Int ) -> Bool
                terrainSupplyCostMatches ( terrain, expected ) =
                    Movement.supplyCost
                        { map | baseTile = terrain }
                        { supplies | movementPerTile = 9, roughTerrainSurcharge = 4 }
                        [ { x = 0, y = 0 }, { x = 1, y = 0 } ]
                        == expected

                test : String -> Bool -> List String
                test name passed =
                    if passed then
                        []

                    else
                        [ name ]
            in
            List.concat
                [ test "upkeep is reserved before walking" (Movement.tileLimit units exhausted == Just 0 && List.isEmpty (Movement.options [] rules map units exhausted))
                , test "field guns also need supplies after upkeep" (List.isEmpty (Movement.options [] rules map units fieldGun))
                , test "field guns can move with exactly 28 supplies" (Movement.options [] rules map [ suppliedFieldGun ] suppliedFieldGun |> List.any (\option -> option.destination == { x = 1, y = 0 }))
                , test "tracing reserves upkeep only once" (traced |> Maybe.map (\path -> List.length path.path == 3) |> Maybe.withDefault False)
                , test "extending a trace cannot overspend supplies" (traced |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 2, y = 1 }) |> (==) Nothing)
                , test "backtracking refunds movement supplies" (traced |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 0, y = 1 }) |> Maybe.andThen (\path -> Movement.trace rules map units unit path { x = 0, y = 2 }) |> Maybe.map (\path -> List.length path.path == 3) |> Maybe.withDefault False)
                , test "vehicles use fuel rather than supplies for movement" (Movement.tileLimit units vehicle == Just 1 && not (List.isEmpty (Movement.options [] rules map units vehicle)))
                , test "empty supplies do not underflow the walking limit"
                    (Movement.tileLimit units
                        (unit
                            |> Unit.setResources (Maybe.map (\resources -> { resources | supplies = { supplies | current = 0 } }) unit.resources)
                        )
                        == Just 0
                    )
                , test "two forest squares retain infantry mobility"
                    (Movement.options []
                        rules
                        roughMap
                        [ unit ]
                        (infantry
                            |> Unit.setResources (Maybe.map (\resources -> { resources | supplies = { supplies | current = 9, movementPerTile = 3, roughTerrainSurcharge = 1 } }) infantry.resources)
                        )
                        |> List.any (\option -> option.destination == { x = 2, y = 0 } && option.cost == 4)
                    )
                , test "terrain supplies restrict otherwise reachable routes" (Movement.options [] rules roughMap [ infantry ] infantry |> List.all (\option -> List.length option.path <= 2))
                , test "terrain supply cost is paid on entered squares" (Movement.supplyCost roughMap { supplies | movementPerTile = 3, roughTerrainSurcharge = 1 } [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 2, y = 0 } ] == 8)
                , test "infantry movement supply costs match each passable terrain"
                    (List.all
                        terrainSupplyCostMatches
                        [ ( Terrain.Plain, 9 )
                        , ( Terrain.Beach, 9 )
                        , ( Terrain.Hills, 13 )
                        , ( Terrain.Forest, 13 )
                        , ( Terrain.Mountains, 13 )
                        ]
                    )
                , test "rough terrain trace extensions reserve upkeep" (roughTrace |> Maybe.andThen (\path -> Movement.trace rules roughMap [ infantry ] infantry path { x = 2, y = 0 }) |> (==) Nothing)
                ]


lookupChecks : List String
lookupChecks =
    let
        test : String -> Bool -> List String
        test label passed =
            if passed then
                []

            else
                [ label ]

        features : List TerrainFeature.TerrainFeature
        features =
            [ { position = { x = 1, y = 0 }, terrain = Terrain.Forest }
            , { position = { x = 1, y = 0 }, terrain = Terrain.Hills }
            , { position = { x = 0, y = 1 }, terrain = Terrain.Mountains }
            , { position = { x = -1, y = 3 }, terrain = Terrain.Hills }
            ]

        map : Map
        map =
            Map.fromFeatures { width = 3, height = 4, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = features }

        positions : List Coordinate
        positions =
            { x = -1, y = 3 } :: { x = 9, y = 9 } :: Map.positions map

        originalTerrainAt : Coordinate -> Terrain.Terrain
        originalTerrainAt position =
            features
                |> ListUtil.find (\feature -> feature.position == position)
                |> Maybe.map .terrain
                |> Maybe.withDefault map.baseTile

        coordinates : List Coordinate
        coordinates =
            List.map .position features

        indexed : Set.Set Coordinate.Key
        indexed =
            Set.fromList (List.map Coordinate.key coordinates)

        sameMembership : Coordinate -> Bool
        sameMembership position =
            List.member position coordinates == Set.member (Coordinate.key position) indexed
    in
    List.concat
        [ test "indexed terrain preserves first duplicate, base terrain, coordinate order and outside-map lookups"
            (List.all (\position -> Map.terrainAt map position == originalTerrainAt position) positions)
        , test "coordinate membership preserves duplicate and absent positions"
            (List.all sameMembership positions)
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
                                ++ lookupChecks
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
                    , entrenchment = Entrenchment.Exposed
                    , spriteFacing = SpriteFacing.Right
                    , kind = UnitKind.Infantry
                    , direction = Just Direction.East
                    , destroyed = False
                    , combatRules =
                        { range = 1
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 4
                        , readinessCost = 2
                        , digInCost = 64
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
                    passenger
                        |> Unit.setId truckId
                        |> Unit.setKind UnitKind.Truck
                        |> Unit.setDestroyed False
                        |> Unit.setCombatRules
                            { range = 1
                            , indirectRange = 0
                            , shape = AmbushShape.Line
                            , damage = 4
                            , readinessCost = 2
                            , digInCost = 64
                            , shotCost = 2
                            }
                        |> Unit.setCargoCapacity 2
                        |> Unit.setDirection Nothing
                        |> Unit.setOnMap { x = 1, y = 0 }
                        |> Unit.setResources (Maybe.map (\resources -> { resources | fuel = Just { current = 64, maximum = 64, movementPerTile = 1, movementPerCargoSlot = 0 } }) passenger.resources)

                map : Map
                map =
                    Map.fromFeatures { width = 4, height = 3, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [] }

                units : List Unit.Unit
                units =
                    [ passenger, truck ]

                aboard : Unit.Unit
                aboard =
                    passenger
                        |> Unit.setLocation (Location.Aboard truckId)

                fullUnits : List Unit.Unit
                fullUnits =
                    [ passenger
                    , truck
                    , aboard
                    , aboard
                        |> Unit.setId otherId
                    ]

                rideUnits : List Unit.Unit
                rideUnits =
                    [ aboard, truck ]

                fuelEmptyTruck : Unit.Unit
                fuelEmptyTruck =
                    truck
                        |> Unit.setResources (Maybe.map (\resources -> { resources | fuel = Just { current = 0, maximum = 64, movementPerTile = 1, movementPerCargoSlot = 0 } }) truck.resources)

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
                , expect "field guns can board"
                    (canReach units
                        (passenger
                            |> Unit.setKind UnitKind.FieldGun
                        )
                        { x = 1, y = 0 }
                    )
                , expect "tanks cannot board"
                    (not
                        (canReach units
                            (passenger
                                |> Unit.setKind UnitKind.Tank
                            )
                            { x = 1, y = 0 }
                        )
                    )
                , expect "full trucks reject boarding" (not (canReach fullUnits passenger { x = 1, y = 0 }))
                , expect "zero fuel still forbids truck movement" (List.isEmpty (Movement.options [] rules map strandedUnits fuelEmptyTruck))
                , expect "zero fuel truck passengers can unload beside the stationary truck" (canReach strandedUnits aboard { x = 2, y = 0 })
                , expect "stationary unloads still reject the occupied truck origin" (not (canReach strandedUnits aboard { x = 1, y = 0 }))
                , expect "stationary unloads still reject reserved exits" (not (List.any (\option -> option.destination == { x = 2, y = 0 }) (Movement.options [ { x = 2, y = 0 } ] rules map strandedUnits aboard)))
                , expect "stationary unloads still require passenger movement supplies"
                    (not
                        (canReach strandedUnits
                            (aboard
                                |> Unit.setResources (Maybe.map (\resources -> { resources | supplies = { current = 1, maximum = 64, upkeepPerTurn = 1, roughTerrainSurcharge = 0, movementPerTile = 1 } }) aboard.resources)
                            )
                            { x = 2, y = 0 }
                        )
                    )
                , expect "unload offers adjacent squares" (canReach rideUnits aboard { x = 2, y = 0 })
                , expect "unload does not offer distant squares" (not (canReach rideUnits aboard { x = 3, y = 0 }))
                , expect "traced unload cannot extend beyond one tile" (extendingUnload == Nothing)
                ]

        _ ->
            [ "invalid transport fixture IDs" ]
