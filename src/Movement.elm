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
that terrain's cost. For example, infantry has a budget of 4 movement points;
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


options : List Rule -> GameBoard -> Unit -> List Option
options rules board unit =
    optionsAvoiding [] rules board unit
        |> List.filter (canStop board)


optionsAvoiding : List Coordinate -> List Rule -> GameBoard -> Unit -> List Option
optionsAvoiding blocked rules board unit =
    case List.filter (\rule -> rule.kind == unit.kind) rules |> List.head of
        Nothing ->
            []

        Just rule ->
            search rule
                board
                blocked
                unit.side
                [ { destination = unit.position, cost = 0, path = [ unit.position ] } ]
                (Dict.singleton (key unit.position) 0)
                []
                |> List.filter (\option -> option.destination /= unit.position)


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


{-| Search affordable routes. The dictionary keys are (column x, row y);
its integer values are the cheapest known accumulated costs, stored in half
movement points just like the rule budgets and terrain costs.
-}
search : Rule -> GameBoard -> List Coordinate -> Side -> List Option -> Dict ( Int, Int ) Int -> List Option -> List Option
search rule board blocked side frontier costs reached =
    case List.sortBy .cost frontier of
        [] ->
            List.reverse reached

        current :: remaining ->
            if Dict.get (key current.destination) costs /= Just current.cost then
                search rule board blocked side remaining costs reached

            else
                let
                    visit : Coordinate -> ( List Option, Dict ( Int, Int ) Int ) -> ( List Option, Dict ( Int, Int ) Int )
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

                                        alreadyReachedAtLowerOrEqualCost : Bool
                                        alreadyReachedAtLowerOrEqualCost =
                                            Dict.get (key position) best
                                                |> Maybe.map (\previous -> previous <= cost)
                                                |> Maybe.withDefault False
                                    in
                                    if impassableTerrain || exceedsBudget || alreadyReachedAtLowerOrEqualCost then
                                        ( pending, best )

                                    else
                                        ( { destination = position, cost = cost, path = current.path ++ [ position ] } :: pending
                                        , Dict.insert (key position) cost best
                                        )

                    ( next, nextCosts ) =
                        List.foldl visit ( remaining, costs ) (neighbors current.destination)
                in
                search rule board blocked side next nextCosts (current :: reached)


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

                    extendPath : Option -> Option
                    extendPath extension =
                        { destination = destination
                        , cost = current.cost + extension.cost
                        , path = current.path ++ List.drop 1 extension.path
                        }
                in
                -- Fill mouse-event gaps from the current tip, keeping every traced
                -- square. Never silently replace the prefix with a cheaper route.
                optionsAvoiding current.path [ remainingRule ] board { unit | position = current.destination }
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


canStop : GameBoard -> Option -> Bool
canStop board option =
    option.cost > 0 && not (List.any (\unit -> unit.position == option.destination) board.units)


preview : List Rule -> GameBoard -> Unit -> Option -> Coordinate -> Maybe Option
preview rules board unit current destination =
    case trace rules board unit current destination of
        Just path ->
            Just path

        Nothing ->
            trace rules board unit (start unit) destination
