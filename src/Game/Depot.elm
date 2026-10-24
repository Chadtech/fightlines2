module Game.Depot exposing
    ( Depot
    , Hp
    , description
    , hpSelection
    , image
    , isDestroyed
    , label
    , resourceLabel
    , selection
    , stockDescription
    )

import Api.Enum.DepotKind as DepotKind exposing (DepotKind)
import Api.Object
import Api.Object.Depot as DepotApi
import Api.Object.DepotHp as HpApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Supply as Supply
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Depot =
    { kind : DepotKind
    , position : Coordinate
    , stock : Maybe Supply.Stock
    , hp : Hp
    }


type alias Hp =
    { current : Int
    , maximum : Int
    }


selection : SelectionSet Depot Api.Object.Depot
selection =
    SS.succeed Depot
        |> SS.with DepotApi.kind
        |> SS.with (DepotApi.position Coordinate.selection)
        |> SS.with (DepotApi.stock Supply.stockSelection)
        |> SS.with (DepotApi.hp hpSelection)


hpSelection : SelectionSet Hp Api.Object.DepotHp
hpSelection =
    SS.succeed Hp
        |> SS.with HpApi.current
        |> SS.with HpApi.maximum


isDestroyed : Depot -> Bool
isDestroyed depot =
    depot.hp.current == 0


resourceLabel : Depot -> String
resourceLabel depot =
    Supply.resourceLabel depot.kind


label : Depot -> String
label depot =
    if isDestroyed depot then
        "destroyed " ++ kindLabel depot

    else
        kindLabel depot


kindLabel : Depot -> String
kindLabel depot =
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
            "a neutral supply source for either player. replenishes units on its square or one cardinally adjacent square at the end of the turn, before upkeep. three shell hits or one turn of infantry sabotage destroy it and its stock."

        DepotKind.Fuel ->
            "a neutral fuel source for either player. refills living tanks and trucks on its square or one cardinally adjacent square at the end of the turn, before upkeep. one shell hit or one turn of infantry sabotage destroys it and its stock."


stockDescription : Depot -> String
stockDescription depot =
    case depot.kind of
        DepotKind.Supply ->
            "finite stock, shared by both players. delivery and loading crates draw from these supplies."

        DepotKind.Fuel ->
            "finite stock, shared by both players. vehicle refilling and loading fuel drums draw from this fuel."
