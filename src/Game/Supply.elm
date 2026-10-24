module Game.Supply exposing
    ( CargoStock
    , GroundCrate
    , Rules
    , Stock
    , cargoImage
    , cargoLabel
    , cargoPlural
    , cargoSelection
    , crateSelection
    , resourceLabel
    , rulesSelection
    , stockSelection
    )

import Api.Enum.ResourceKind as Kind exposing (ResourceKind)
import Api.Object
import Api.Object.CargoStock as CargoApi
import Api.Object.GroundSupplyCrate as CrateApi
import Api.Object.ResourceStock as StockApi
import Api.Object.SupplyRules as RulesApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Stock =
    { current : Int
    , maximum : Int
    }


type alias CargoStock =
    { kind : ResourceKind
    , current : Int
    , maximum : Int
    }


type alias GroundCrate =
    { position : Coordinate
    , stock : CargoStock
    }


type alias Rules =
    { depotCapacity : Int
    , crateCapacity : Int
    }


stockSelection : SelectionSet Stock Api.Object.ResourceStock
stockSelection =
    SS.succeed Stock
        |> SS.with StockApi.current
        |> SS.with StockApi.maximum


crateSelection : SelectionSet GroundCrate Api.Object.GroundSupplyCrate
crateSelection =
    SS.succeed GroundCrate
        |> SS.with (CrateApi.position Coordinate.selection)
        |> SS.with (CrateApi.stock cargoSelection)


rulesSelection : SelectionSet Rules Api.Object.SupplyRules
rulesSelection =
    SS.succeed Rules
        |> SS.with RulesApi.depotCapacity
        |> SS.with RulesApi.crateCapacity


cargoSelection : SelectionSet CargoStock Api.Object.CargoStock
cargoSelection =
    SS.succeed CargoStock
        |> SS.with CargoApi.kind
        |> SS.with CargoApi.current
        |> SS.with CargoApi.maximum


cargoLabel : ResourceKind -> String
cargoLabel kind =
    case kind of
        Kind.Supply ->
            "supply crate"

        Kind.Fuel ->
            "fuel drums"


cargoPlural : ResourceKind -> String
cargoPlural kind =
    case kind of
        Kind.Supply ->
            "supply crates"

        Kind.Fuel ->
            "fuel drums"


resourceLabel : ResourceKind -> String
resourceLabel kind =
    case kind of
        Kind.Supply ->
            "supplies"

        Kind.Fuel ->
            "fuel"


cargoImage : ResourceKind -> String
cargoImage kind =
    case kind of
        Kind.Supply ->
            "/assets/supply-crate-illustrated-v1.png"

        Kind.Fuel ->
            "/assets/fuel-drums-illustrated-v1.png"
