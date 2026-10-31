module Game.UnitResources exposing
    ( UnitResources
    , selection
    , setFuel
    , setSupplies
    )

import Api.Object
import Api.Object.UnitResources as ResourcesApi
import Game.Supply as Supply
import Game.Unit.Fuel as Fuel exposing (Fuel)
import Game.Unit.HitPoints as HitPoints exposing (HitPoints)
import Game.Unit.Supplies as Supplies exposing (Supplies)
import Graphql.SelectionSet as SS exposing (SelectionSet)


{-| Nothing at the unit level means all resources are concealed.
Within visible resources, fuel is absent only for units that do not use it.
-}
type alias UnitResources =
    { hitPoints : HitPoints
    , supplies : Supplies
    , fuel : Maybe Fuel
    , supplyCargo : List Supply.CargoStock
    , exhaustionTurnsRemaining : Maybe Int
    }


selection : SelectionSet UnitResources Api.Object.UnitResources
selection =
    SS.succeed UnitResources
        |> SS.with (ResourcesApi.hitPoints HitPoints.selection)
        |> SS.with (ResourcesApi.supplies Supplies.selection)
        |> SS.with (ResourcesApi.fuel Fuel.selection)
        |> SS.with (ResourcesApi.supplyCargo Supply.cargoSelection)
        |> SS.with ResourcesApi.exhaustionTurnsRemaining


setSupplies : Supplies -> UnitResources -> UnitResources
setSupplies supplies resources =
    { resources | supplies = supplies }


setFuel : Maybe Fuel -> UnitResources -> UnitResources
setFuel fuel resources =
    { resources | fuel = fuel }
