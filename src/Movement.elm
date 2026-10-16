module Movement exposing
    ( Option
    , Rule
    , TerrainCost
    , canStop
    , options
    , optionsAvoiding
    , pointsLabel
    , preview
    , start
    , supplyCost
    , tileLimit
    , trace
    )

import Api.Enum.Terrain as Terrain exposing (Terrain)
import Api.Enum.UnitKind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import Dict exposing (Dict)
import Map exposing (Map)
import Unit exposing (Unit)
import Unit.Supplies exposing (Supplies)
import UnitResources exposing (UnitResources)
import Util.List as ListUtil


{-| The cost to enter a terrain square, as supplied by Rust's movement rules.
A movement point is a unit of the unit's travel budget: entering a square spends
that terrain's cost. For example, infantry has a budget of 2 movement points;
plain, hills, and forest each cost 1; mountains cost 2. Nonpositive entry costs
mean that terrain cannot be crossed.

The integers store twice the displayed value so half-point costs stay exact:
a plain cost of 1 is stored as 2, and a hill cost of 1.5 is stored as 3.

-}
type alias TerrainCost =
    { terrain : Terrain
    , cost : Int
    }


type alias Rule =
    { kind : UnitKind
    , budget : Int
    , terrainCosts : List TerrainCost
    }


type alias Option =
    { destination : Coordinate
    , cost : Int
    , path : List Coordinate
    }


type SearchGoal
    = AllDestinations
    | ToDestination Coordinate


pointsLabel : Int -> String
pointsLabel points =
    String.fromInt (points // 2)
        ++ (if modBy 2 points == 0 then
                ""

            else
                ".5"
           )


options : List Coordinate -> List Rule -> Map -> List Unit -> Unit -> List Option
options reserved rules map units unit =
    optionsAvoiding [] rules map units unit
        |> List.filter (canStop reserved units unit)


optionsAvoiding : List Coordinate -> List Rule -> Map -> List Unit -> Unit -> List Option
optionsAvoiding =
    affordableRoutes AllDestinations


affordableRoutes : SearchGoal -> List Coordinate -> List Rule -> Map -> List Unit -> Unit -> List Option
affordableRoutes goal blocked rules map units unit =
    case ( ListUtil.find (\rule -> rule.kind == unit.kind) rules, Unit.physicalPosition units unit ) of
        ( Just rule, Just origin ) ->
            search goal
                (tileLimit unit)
                unit
                rule
                map
                blocked
                [ start origin ]
                (Dict.singleton (searchKey (tileLimit unit) map unit (start origin)) 0)
                []
                |> List.filter (\option -> option.destination /= origin)
                |> List.foldl cheapestDestination Dict.empty
                |> Dict.values

        _ ->
            []


{-| Reserve upkeep once; only walking units spend supplies per tile.
Fuel and supplies bound tile count independently of terrain movement costs.
-}
tileLimit : Unit -> Maybe Int
tileLimit unit =
    let
        supplyLimit : Maybe Int
        supplyLimit =
            unit.resources |> Maybe.andThen (.supplies >> Unit.supplyMovementLimit)

        fuelLimit : Maybe Int
        fuelLimit =
            unit.resources |> Maybe.andThen .fuel |> Maybe.map (\fuel -> fuel.current // fuel.movementPerTile)
    in
    if Unit.carrierId unit /= Nothing then
        Just (min 1 (Maybe.withDefault 1 supplyLimit))

    else
        case ( fuelLimit, supplyLimit ) of
            ( Just fuel, Just supplies ) ->
                Just (min fuel supplies)

            ( Just fuel, Nothing ) ->
                Just fuel

            ( Nothing, supplies ) ->
                supplies


cheapestDestination : Option -> Dict ( Int, Int ) Option -> Dict ( Int, Int ) Option
cheapestDestination option best =
    case Dict.get (key option.destination) best of
        Just previous ->
            let
                previousIsBetter : Bool
                previousIsBetter =
                    previous.cost
                        < option.cost
                        || (previous.cost == option.cost && List.length previous.path <= List.length option.path)
            in
            if previousIsBetter then
                best

            else
                Dict.insert (key option.destination) option best

        Nothing ->
            Dict.insert (key option.destination) option best


searchKey : Maybe Int -> Map -> Unit -> Option -> ( ( Int, Int ), ( Int, Int ) )
searchKey limit map unit option =
    ( key option.destination
    , ( limit |> Maybe.map (\_ -> List.length option.path - 1) |> Maybe.withDefault 0
      , unit.resources |> Maybe.map (\resources -> supplyCost map resources.supplies option.path) |> Maybe.withDefault 0
      )
    )


key : Coordinate -> ( Int, Int )
key position =
    ( position.x, position.y )


neighbors : Coordinate -> List Coordinate
neighbors position =
    [ { x = position.x, y = position.y - 1 }
    , { x = position.x - 1, y = position.y }
    , { x = position.x + 1, y = position.y }
    , { x = position.x, y = position.y + 1 }
    ]


{-| Search affordable routes. Keys include position, tiles traveled, and supply expenditure.
Units without a resource movement limit use zero for the tile-count component.
Keeping costs for each path length and supply expenditure preserves affordable routes.
Costs are stored in half movement points, independently of fuel.
-}
search :
    SearchGoal
    -> Maybe Int
    -> Unit
    -> Rule
    -> Map
    -> List Coordinate
    -> List Option
    -> Dict ( ( Int, Int ), ( Int, Int ) ) Int
    -> List Option
    -> List Option
search goal limit unit rule map blocked frontier costs reached =
    case List.sortBy .cost frontier of
        [] ->
            List.reverse reached

        current :: remaining ->
            if Dict.get (searchKey limit map unit current) costs /= Just current.cost then
                search
                    goal
                    limit
                    unit
                    rule
                    map
                    blocked
                    remaining
                    costs
                    reached

            else if targetCostSettled goal reached current then
                List.reverse reached

            else
                let
                    -- The accumulator pairs pending routes with their best movement costs.
                    -- Dict keys are ((x, y), (tiles traveled, supplies spent)); keeping
                    -- resource usage separate preserves routes that remain affordable.
                    visit :
                        Coordinate
                        -> ( List Option, Dict ( ( Int, Int ), ( Int, Int ) ) Int )
                        -> ( List Option, Dict ( ( Int, Int ), ( Int, Int ) ) Int )
                    visit position ( pending, best ) =
                        let
                            leftOfMap : Bool
                            leftOfMap =
                                position.x < 0

                            aboveMap : Bool
                            aboveMap =
                                position.y < 0

                            rightOfMap : Bool
                            rightOfMap =
                                position.x >= map.width

                            belowMap : Bool
                            belowMap =
                                position.y >= map.height

                            outsideMap : Bool
                            outsideMap =
                                leftOfMap || aboveMap || rightOfMap || belowMap

                            alreadyInPath : Bool
                            alreadyInPath =
                                List.member position blocked
                        in
                        if outsideMap || alreadyInPath then
                            ( pending, best )

                        else
                            case
                                rule.terrainCosts
                                    |> ListUtil.find (\entry -> entry.terrain == Map.terrainAt map position)
                            of
                                Nothing ->
                                    ( pending, best )

                                Just entry ->
                                    let
                                        cost : Int
                                        cost =
                                            current.cost + entry.cost

                                        impassableTerrain : Bool
                                        impassableTerrain =
                                            entry.cost <= 0

                                        exceedsBudget : Bool
                                        exceedsBudget =
                                            cost > rule.budget

                                        candidate : Option
                                        candidate =
                                            { destination = position, cost = cost, path = current.path ++ [ position ] }

                                        exceedsSupplies : Bool
                                        exceedsSupplies =
                                            unit.resources
                                                |> Maybe.map
                                                    (\resources ->
                                                        supplyCost
                                                            map
                                                            resources.supplies
                                                            candidate.path
                                                            > max
                                                                0
                                                                (resources.supplies.current - resources.supplies.upkeepPerTurn)
                                                    )
                                                |> Maybe.withDefault False

                                        exceedsResources : Bool
                                        exceedsResources =
                                            (limit
                                                |> Maybe.map (\available -> List.length candidate.path - 1 > available)
                                                |> Maybe.withDefault False
                                            )
                                                || exceedsSupplies

                                        alreadyReachedAtLowerOrEqualCost : Bool
                                        alreadyReachedAtLowerOrEqualCost =
                                            Dict.get (searchKey limit map unit candidate) best
                                                |> Maybe.map (\previous -> previous <= cost)
                                                |> Maybe.withDefault False
                                    in
                                    if
                                        impassableTerrain
                                            || exceedsBudget
                                            || exceedsResources
                                            || alreadyReachedAtLowerOrEqualCost
                                    then
                                        ( pending, best )

                                    else
                                        ( candidate :: pending
                                        , Dict.insert (searchKey limit map unit candidate) cost best
                                        )

                    ( next, nextCosts ) =
                        List.foldl visit ( remaining, costs ) (neighbors current.destination)
                in
                search
                    goal
                    limit
                    unit
                    rule
                    map
                    blocked
                    next
                    nextCosts
                    (recordReached goal current reached)


{-| Positive entry costs make the frontier's movement cost a lower bound.
Finish the entire winning cost layer: another resource state may reach the
same destination at equal cost with fewer tiles. Keeping the existing stable
frontier order also preserves the first route when cost and length both tie.
-}
targetCostSettled : SearchGoal -> List Option -> Option -> Bool
targetCostSettled goal reached current =
    case ( goal, reached ) of
        ( ToDestination _, best :: _ ) ->
            current.cost > best.cost

        _ ->
            False


recordReached : SearchGoal -> Option -> List Option -> List Option
recordReached goal current reached =
    case goal of
        AllDestinations ->
            current :: reached

        ToDestination destination ->
            if current.destination == destination then
                current :: reached

            else
                reached


start : Coordinate -> Option
start position =
    { destination = position
    , cost = 0
    , path = [ position ]
    }


trace : List Rule -> Map -> List Unit -> Unit -> Option -> Coordinate -> Maybe Option
trace rules map units unit current destination =
    let
        rule : Maybe Rule
        rule =
            rules
                |> ListUtil.find (\entry -> entry.kind == unit.kind)

        costAt : Rule -> Coordinate -> Maybe Int
        costAt movementRule position =
            movementRule.terrainCosts
                |> ListUtil.find (\entry -> entry.terrain == Map.terrainAt map position)
                |> Maybe.map .cost

        prefix : List Coordinate
        prefix =
            takeThrough destination current.path
    in
    case rule of
        Nothing ->
            Nothing

        Just movementRule ->
            if List.member destination current.path then
                Just
                    { destination = destination
                    , cost = List.drop 1 prefix |> List.filterMap (costAt movementRule) |> List.sum
                    , path = prefix
                    }

            else
                let
                    remainingRule : Rule
                    remainingRule =
                        { movementRule | budget = movementRule.budget - current.cost }

                    remainingUnit : Unit
                    remainingUnit =
                        { unit
                            | resources = Maybe.map (remainingResources map current) unit.resources
                        }
                            |> Unit.setOnMap current.destination

                    extendPath : Option -> Option
                    extendPath extension =
                        { destination = destination
                        , cost = current.cost + extension.cost
                        , path = current.path ++ List.drop 1 extension.path
                        }
                in
                -- Fill mouse-event gaps from the current tip, keeping every traced
                -- square. Never silently replace the prefix with a cheaper route.
                affordableRoutes (ToDestination destination) current.path [ remainingRule ] map units remainingUnit
                    |> ListUtil.find (\option -> option.destination == destination)
                    |> Maybe.map extendPath
                    |> Maybe.andThen (withinTileLimit unit)


supplyCost : Map -> Supplies -> List Coordinate -> Int
supplyCost map supplies path =
    let
        entryCost : Coordinate -> Int
        entryCost position =
            case Map.terrainAt map position of
                Terrain.Plain ->
                    supplies.movementPerTile

                _ ->
                    supplies.movementPerTile + supplies.roughTerrainSurcharge
    in
    path
        |> List.drop 1
        |> List.map entryCost
        |> List.sum


remainingResources : Map -> Option -> UnitResources -> UnitResources
remainingResources map current resources =
    let
        tiles : Int
        tiles =
            List.length current.path - 1

        supplies : Supplies
        supplies =
            resources.supplies
    in
    { resources
        | supplies = { supplies | current = supplies.current - supplyCost map supplies current.path }
        , fuel = Maybe.map (\fuel -> { fuel | current = fuel.current - tiles * fuel.movementPerTile }) resources.fuel
    }


takeThrough : Coordinate -> List Coordinate -> List Coordinate
takeThrough destination path =
    case path of
        [] ->
            []

        position :: rest ->
            if position == destination then
                [ position ]

            else
                position :: takeThrough destination rest


canStop : List Coordinate -> List Unit -> Unit -> Option -> Bool
canStop reserved units mover option =
    let
        occupied : Bool
        occupied =
            List.any (\unit -> Unit.boardPosition unit == Just option.destination) units

        canLoad : Bool
        canLoad =
            Unit.loadingTarget units mover option.destination /= Nothing

        reservedDestination : Bool
        reservedDestination =
            List.member option.destination reserved
    in
    option.cost > 0 && not reservedDestination && (not occupied || canLoad)


preview : List Rule -> Map -> List Unit -> Unit -> Option -> Coordinate -> Maybe Option
preview rules map units unit current destination =
    case trace rules map units unit current destination of
        Just path ->
            Just path

        Nothing ->
            Unit.physicalPosition units unit
                |> Maybe.andThen (\origin -> trace rules map units unit (start origin) destination)


withinTileLimit : Unit -> Option -> Maybe Option
withinTileLimit unit option =
    let
        exceedsLimit : Bool
        exceedsLimit =
            tileLimit unit |> Maybe.map (\limit -> List.length option.path - 1 > limit) |> Maybe.withDefault False
    in
    if exceedsLimit then
        Nothing

    else
        Just option
