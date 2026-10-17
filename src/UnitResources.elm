module UnitResources exposing
    ( UnitResources
    , selection
    , setSupplies
    )

import Api.Object
import Api.Object.UnitResources as ResourcesApi
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Supply
import Unit.Fuel as Fuel exposing (Fuel)
import Unit.HitPoints as HitPoints exposing (HitPoints)
import Unit.Supplies as Supplies exposing (Supplies)


{-| Nothing at the unit level means all resources are concealed.
Within visible resources, fuel is absent only for units that do not use it.
-}
type alias UnitResources =
    { hitPoints : HitPoints
    , supplies : Supplies
    , fuel : Maybe Fuel
    , supplyCargo : List Supply.CargoStock
    }


selection : SelectionSet UnitResources Api.Object.UnitResources
selection =
    SS.succeed UnitResources
        |> SS.with (ResourcesApi.hitPoints HitPoints.selection)
        |> SS.with (ResourcesApi.supplies Supplies.selection)
        |> SS.with (ResourcesApi.fuel Fuel.selection)
        |> SS.with (ResourcesApi.supplyCargo Supply.cargoSelection)


setSupplies : Supplies -> UnitResources -> UnitResources
setSupplies supplies resources =
    { resources | supplies = supplies }
