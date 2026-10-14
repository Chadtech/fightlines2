module Depot exposing
    ( Depot
    , description
    , image
    , label
    , resourceLabel
    , selection
    , stockDescription
    , supplies
    )

import Api.Enum.DepotKind as DepotKind exposing (DepotKind)
import Api.Object
import Api.Object.Depot as DepotApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Supply


type alias Depot =
    { kind : DepotKind
    , position : Coordinate
    , stock : Maybe Supply.Stock
    }


selection : SelectionSet Depot Api.Object.Depot
selection =
    SS.succeed Depot
        |> SS.with DepotApi.kind
        |> SS.with (DepotApi.position Coordinate.selection)
        |> SS.with (DepotApi.stock Supply.stockSelection)


supplies : Depot -> Bool
supplies depot =
    depot.kind == DepotKind.Supply


resourceLabel : Depot -> String
resourceLabel depot =
    case depot.kind of
        DepotKind.Supply ->
            "supplies"

        DepotKind.Fuel ->
            "fuel"


label : Depot -> String
label depot =
    case depot.kind of
        DepotKind.Supply ->
            "supply depot"

        DepotKind.Fuel ->
            "fuel depot"


image : Depot -> String
image depot =
    case depot.kind of
        DepotKind.Supply ->
            "/assets/supply-depot-illustrated-v1.png"

        DepotKind.Fuel ->
            "/assets/fuel-depot-illustrated-v4.png"


description : Depot -> String
description depot =
    case depot.kind of
        DepotKind.Supply ->
            "a neutral supply source for either player. replenishes units on its square or one cardinally adjacent square at the end of the turn, before upkeep."

        DepotKind.Fuel ->
            "a neutral fuel source for either player. refills living tanks and trucks on its square or one cardinally adjacent square at the end of the turn, before upkeep."


stockDescription : Depot -> String
stockDescription depot =
    case depot.kind of
        DepotKind.Supply ->
            "finite stock, shared by both players. delivery and loading crates draw from these supplies."

        DepotKind.Fuel ->
            "finite stock, shared by both players. refills vehicle tanks up to capacity while fuel remains."
