module Game.UnloadCargo exposing
    ( UnloadCargo(..)
    , inspectionUnit
    , saveExit
    )

import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnloadingTruck as UnloadingTruck exposing (UnloadingTruck)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Crates use their original zero-based slot in the truck's supply cargo list.
Slots stay stable during planning; the server removes unloaded slots in descending order.
-}
type UnloadCargo
    = Passenger UnitId
    | Crate Int



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


inspectionUnit : UnloadingTruck -> UnloadCargo -> UnitId
inspectionUnit truck cargo =
    case cargo of
        Passenger id ->
            id

        Crate _ ->
            UnloadingTruck.unitId truck


saveExit : Coordinate -> UnloadCargo -> UnloadingTruck -> UnloadingTruck
saveExit destination cargo truck =
    case cargo of
        Passenger id ->
            UnloadingTruck.addPassengerExit { unitId = id, destination = destination } truck

        Crate index ->
            UnloadingTruck.addCrateExit { cargoIndex = index, destination = destination } truck
