module Game.Depot exposing
    ( Depot
    , Hp
    , LoadingSource
    , description
    , hpSelection
    , image
    , isDestroyed
    , kindImage
    , kindLabel
    , label
    , loadingSource
    , resourceKind
    , selection
    , stockDescription
    )

import Api.Enum.BuildingKind as BuildingKind exposing (BuildingKind)
import Api.Enum.ResourceKind as ResourceKind exposing (ResourceKind)
import Api.Object
import Api.Object.Depot as DepotApi
import Api.Object.DepotHp as HpApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Supply as Supply
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Depot =
    { kind : BuildingKind
    , position : Coordinate
    , stock : Maybe Supply.Stock
    , hp : Hp
    }


type alias Hp =
    { current : Int
    , maximum : Int
    }


{-| A surviving resource building that can offer freight loading. Fortresses
have no resource identity and cannot enter this workflow.
-}
type alias LoadingSource =
    { kind : ResourceKind
    , stock : Maybe Supply.Stock
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


resourceKind : Depot -> Maybe ResourceKind
resourceKind depot =
    case depot.kind of
        BuildingKind.Supply ->
            Just ResourceKind.Supply

        BuildingKind.Fuel ->
            Just ResourceKind.Fuel

        BuildingKind.Fortress ->
            Nothing


loadingSource : Depot -> Maybe LoadingSource
loadingSource depot =
    let
        source : ResourceKind -> LoadingSource
        source kind =
            { kind = kind
            , stock = depot.stock
            }
    in
    if isDestroyed depot then
        Nothing

    else
        resourceKind depot
            |> Maybe.map source


label : Depot -> String
label depot =
    if isDestroyed depot then
        "destroyed " ++ kindLabel depot.kind

    else
        kindLabel depot.kind


kindLabel : BuildingKind -> String
kindLabel kind =
    case kind of
        BuildingKind.Supply ->
            "supply depot"

        BuildingKind.Fuel ->
            "fuel depot"

        BuildingKind.Fortress ->
            "fortress"


image : Depot -> String
image depot =
    if isDestroyed depot then
        "/assets/destroyed-depot-illustrated-v1.png"

    else
        kindImage depot.kind


kindImage : BuildingKind -> String
kindImage kind =
    case kind of
        BuildingKind.Supply ->
            "/assets/supply-depot-illustrated-v1.png"

        BuildingKind.Fuel ->
            "/assets/fuel-depot-illustrated-v4.png"

        BuildingKind.Fortress ->
            "/assets/fortress-illustrated-v2.png"


description : Depot -> String
description depot =
    case depot.kind of
        BuildingKind.Supply ->
            "a neutral supply source for either player. replenishes units on top of or next to the depot at the end of the turn, before upkeep. three shell hits or one turn of infantry sabotage destroy it and its stock."

        BuildingKind.Fuel ->
            "a neutral fuel source for either player. refills tanks and trucks on top of or next to the depot at the end of the turn, before upkeep. one shell hit or one turn of infantry sabotage destroys it and its stock."

        BuildingKind.Fortress ->
            "a neutral defensive position for either player. units occupying its square take 75% less damage from direct and indirect fire, with a minimum of one hp per hit. protection stacks with terrain and entrenchment while the fortress survives. eight shell hits or one turn of infantry sabotage destroy it and remove its protection. provides no supplies, fuel, or freight."


stockDescription : ResourceKind -> String
stockDescription kind =
    case kind of
        ResourceKind.Supply ->
            "finite stock, shared by both players. delivery and loading crates draw from these supplies."

        ResourceKind.Fuel ->
            "finite stock, shared by both players. vehicle refilling and loading fuel drums draw from this fuel."
