module Game.Building exposing
    ( Building
    , Hp
    , LoadingSource
    , description
    , destroyedImage
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
import Api.Object.Building as BuildingApi
import Api.Object.BuildingHp as HpApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Supply as Supply
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Building =
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


selection : SelectionSet Building Api.Object.Building
selection =
    SS.succeed Building
        |> SS.with BuildingApi.kind
        |> SS.with (BuildingApi.position Coordinate.selection)
        |> SS.with (BuildingApi.stock Supply.stockSelection)
        |> SS.with (BuildingApi.hp hpSelection)


hpSelection : SelectionSet Hp Api.Object.BuildingHp
hpSelection =
    SS.succeed Hp
        |> SS.with HpApi.current
        |> SS.with HpApi.maximum


isDestroyed : Building -> Bool
isDestroyed building =
    building.hp.current == 0


resourceKind : Building -> Maybe ResourceKind
resourceKind building =
    case building.kind of
        BuildingKind.Supply ->
            Just ResourceKind.Supply

        BuildingKind.Fuel ->
            Just ResourceKind.Fuel

        BuildingKind.Fortress ->
            Nothing


loadingSource : Building -> Maybe LoadingSource
loadingSource building =
    let
        source : ResourceKind -> LoadingSource
        source kind =
            { kind = kind
            , stock = building.stock
            }
    in
    if isDestroyed building then
        Nothing

    else
        resourceKind building
            |> Maybe.map source


label : Building -> String
label building =
    if isDestroyed building then
        "destroyed " ++ kindLabel building.kind

    else
        kindLabel building.kind


kindLabel : BuildingKind -> String
kindLabel kind =
    case kind of
        BuildingKind.Supply ->
            "supply depot"

        BuildingKind.Fuel ->
            "fuel depot"

        BuildingKind.Fortress ->
            "fortress"


image : Building -> String
image building =
    if isDestroyed building then
        destroyedImage

    else
        kindImage building.kind


kindImage : BuildingKind -> String
kindImage kind =
    case kind of
        BuildingKind.Supply ->
            "assets/supply-depot-illustrated-v1.png"

        BuildingKind.Fuel ->
            "assets/fuel-depot-illustrated-v4.png"

        BuildingKind.Fortress ->
            "assets/fortress-illustrated-v2.png"


description : Building -> String
description building =
    case building.kind of
        BuildingKind.Supply ->
            "a neutral supply source for either player. position units on or next to supply depots and they will be replenished from it at the end of the turn. trucks can load up supply crates from supply depots too."

        BuildingKind.Fuel ->
            "a neutral fuel source for either player. position units on or next to fuel depots and they will be replenished from it at the end of the turn. trucks can load up fuel drums from fuel depots too."

        BuildingKind.Fortress ->
            "a neutral defensive position for either player. units occupying its square take 75% less damage from direct and indirect fire."


stockDescription : ResourceKind -> String
stockDescription kind =
    case kind of
        ResourceKind.Supply ->
            "finite stock, shared by both players. delivery and loading crates draw from these supplies."

        ResourceKind.Fuel ->
            "finite stock, shared by both players. vehicle refilling and loading fuel drums draw from this fuel."


destroyedImage : String
destroyedImage =
    "assets/destroyed-depot-illustrated-v1.png"
