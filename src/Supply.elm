module Supply exposing
    ( GroundCrate
    , Rules
    , Stock
    , crateSelection
    , rulesSelection
    , stockSelection
    )

import Api.Object
import Api.Object.GroundSupplyCrate as CrateApi
import Api.Object.SupplyRules as RulesApi
import Api.Object.SupplyStock as StockApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Stock =
    { current : Int
    , maximum : Int
    }


type alias GroundCrate =
    { position : Coordinate
    , stock : Stock
    }


type alias Rules =
    { depotCapacity : Int
    , crateCapacity : Int
    }


stockSelection : SelectionSet Stock Api.Object.SupplyStock
stockSelection =
    SS.succeed Stock
        |> SS.with StockApi.current
        |> SS.with StockApi.maximum


crateSelection : SelectionSet GroundCrate Api.Object.GroundSupplyCrate
crateSelection =
    SS.succeed GroundCrate
        |> SS.with (CrateApi.position Coordinate.selection)
        |> SS.with (CrateApi.stock stockSelection)


rulesSelection : SelectionSet Rules Api.Object.SupplyRules
rulesSelection =
    SS.succeed Rules
        |> SS.with RulesApi.depotCapacity
        |> SS.with RulesApi.crateCapacity
