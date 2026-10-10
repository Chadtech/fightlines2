module Movement exposing
    ( Option
    , Rule
    , TerrainCost
    , canStop
    , options
    , pointsLabel
    , preview
    , start
    , trace
    )

import Api.Enum.Side exposing (Side)
import Api.Enum.Terrain exposing (Terrain)
import Api.Enum.UnitKind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import Dict exposing (Dict)
import GameBoard exposing (GameBoard)
import Map
import Unit exposing (Unit)


{-| The cost to enter a terrain square, as supplied by Rust's movement rules.
A movement point is a unit of the unit's travel budget: entering a square spends
that terrain's cost. For example, infantry has a budget of 2 movement points;
grass costs 1, hills 1.5, and forest 2.

The integers store twice the displayed value so half-point costs stay exact:
a grass cost of 1 is stored as 2, and a hill cost of 1.5 is stored as 3.

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


pointsLabel : Int -> String
pointsLabel points =
    String.fromInt (points // 2)
        ++ (if modBy 2 points == 0 then
                ""

            else
                ".5"
           )


options : List Coordinate -> List Rule -> GameBoard -> Unit -> List Option
options reserved rules board unit =
    optionsAvoiding [] rules board unit
        |> List.filter (canStop reserved board)


optionsAvoiding : List Coordinate -> List Rule -> GameBoard -> Unit -> List Option
optionsAvoiding blocked rules board unit =
    case List.filter (\rule -> rule.kind == unit.kind) rules |> List.head of
        Nothing ->
            []

        Just rule ->
            search (Maybe.map .current unit.fuel)
                rule
                board
                blocked
                unit.side
                [ { destination = unit.position, cost = 0, path = [ unit.position ] } ]
                (Dict.singleton (searchKey (Maybe.map .current unit.fuel) (start unit)) 0)
                []
                |> List.filter (\option -> option.destination /= unit.position)
                |> List.foldl cheapestDestination Dict.empty
                |> Dict.values


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


searchKey : Maybe Int -> Option -> ( Int, Int, Int )
searchKey fuel option =
    ( option.destination.x
    , option.destination.y
    , fuel |> Maybe.map (\_ -> List.length option.path - 1) |> Maybe.withDefault 0
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


{-| Search affordable routes. Keys include column, row and fuel spent.
Units without fuel use zero for that third component. Retaining a cheapest
route for each fuel expenditure preserves short routes through expensive terrain.
Costs are stored in half movement points, independently of fuel.
-}
search : Maybe Int -> Rule -> GameBoard -> List Coordinate -> Side -> List Option -> Dict ( Int, Int, Int ) Int -> List Option -> List Option
search fuel rule board blocked side frontier costs reached =
    case List.sortBy .cost frontier of
        [] ->
            List.reverse reached

        current :: remaining ->
            if Dict.get (searchKey fuel current) costs /= Just current.cost then
                search fuel rule board blocked side remaining costs reached

            else
                let
                    visit : Coordinate -> ( List Option, Dict ( Int, Int, Int ) Int ) -> ( List Option, Dict ( Int, Int, Int ) Int )
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
                                position.x >= board.map.width

                            belowMap : Bool
                            belowMap =
                                position.y >= board.map.height

                            outsideMap : Bool
                            outsideMap =
                                leftOfMap || aboveMap || rightOfMap || belowMap

                            alreadyInPath : Bool
                            alreadyInPath =
                                List.member position blocked

                            enemyAtPosition : Unit -> Bool
                            enemyAtPosition unit =
                                unit.position == position && unit.side /= side

                            occupiedByEnemy : Bool
                            occupiedByEnemy =
                                List.any enemyAtPosition board.units
                        in
                        if outsideMap || alreadyInPath || occupiedByEnemy then
                            ( pending, best )

                        else
                            case rule.terrainCosts |> List.filter (\entry -> entry.terrain == Map.terrainAt board.map position) |> List.head of
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

                                        exceedsFuel : Bool
                                        exceedsFuel =
                                            fuel |> Maybe.map (\available -> List.length candidate.path - 1 > available) |> Maybe.withDefault False

                                        alreadyReachedAtLowerOrEqualCost : Bool
                                        alreadyReachedAtLowerOrEqualCost =
                                            Dict.get (searchKey fuel candidate) best
                                                |> Maybe.map (\previous -> previous <= cost)
                                                |> Maybe.withDefault False
                                    in
                                    if impassableTerrain || exceedsBudget || exceedsFuel || alreadyReachedAtLowerOrEqualCost then
                                        ( pending, best )

                                    else
                                        ( candidate :: pending
                                        , Dict.insert (searchKey fuel candidate) cost best
                                        )

                    ( next, nextCosts ) =
                        List.foldl visit ( remaining, costs ) (neighbors current.destination)
                in
                search fuel rule board blocked side next nextCosts (current :: reached)


start : Unit -> Option
start unit =
    { destination = unit.position
    , cost = 0
    , path = [ unit.position ]
    }


trace : List Rule -> GameBoard -> Unit -> Option -> Coordinate -> Maybe Option
trace rules board unit current destination =
    let
        rule : Maybe Rule
        rule =
            rules
                |> List.filter (\entry -> entry.kind == unit.kind)
                |> List.head

        costAt : Rule -> Coordinate -> Maybe Int
        costAt movementRule position =
            movementRule.terrainCosts
                |> List.filter (\entry -> entry.terrain == Map.terrainAt board.map position)
                |> List.head
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
                            | position = current.destination
                            , fuel = Maybe.map (\fuel -> { fuel | current = fuel.current - (List.length current.path - 1) }) unit.fuel
                        }

                    extendPath : Option -> Option
                    extendPath extension =
                        { destination = destination
                        , cost = current.cost + extension.cost
                        , path = current.path ++ List.drop 1 extension.path
                        }
                in
                -- Fill mouse-event gaps from the current tip, keeping every traced
                -- square. Never silently replace the prefix with a cheaper route.
                optionsAvoiding current.path [ remainingRule ] board remainingUnit
                    |> List.filter (\option -> option.destination == destination)
                    |> List.head
                    |> Maybe.map extendPath


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


canStop : List Coordinate -> GameBoard -> Option -> Bool
canStop reserved board option =
    option.cost
        > 0
        && not (List.member option.destination reserved)
        && not (List.any (\unit -> unit.position == option.destination) board.units)


preview : List Rule -> GameBoard -> Unit -> Option -> Coordinate -> Maybe Option
preview rules board unit current destination =
    case trace rules board unit current destination of
        Just path ->
            Just path

        Nothing ->
            trace rules board unit (start unit) destination
