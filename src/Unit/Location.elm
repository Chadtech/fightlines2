module Unit.Location exposing
    ( Location(..)
    , selection
    )

import Api.Object.Aboard as AboardApi
import Api.Object.OnMap as OnMapApi
import Api.Union
import Api.Union.UnitLocation as LocationApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import UnitId exposing (UnitId)


{-| Board occupancy and transport are mutually exclusive. Aboard units derive
physical position from their carrier, without storing a duplicate coordinate.
Dismounting is a local planning projection; it permits follow-up actions but
records that unloading has already consumed part of the turn.
-}
type Location
    = OnMap Coordinate
    | Aboard UnitId
    | Dismounting Coordinate


selection : SelectionSet Location Api.Union.UnitLocation
selection =
    LocationApi.fragments
        { onOnMap =
            SS.map OnMap
                (OnMapApi.position Coordinate.selection)
        , onAboard =
            AboardApi.carrierId
                |> SS.mapOrFail UnitId.parse
                |> SS.map Aboard
        }
