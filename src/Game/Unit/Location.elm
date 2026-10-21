module Game.Unit.Location exposing
    ( Location(..)
    , dismounting
    , selection
    )

import Api.Object.Aboard as AboardApi
import Api.Object.OnMap as OnMapApi
import Api.Union
import Api.Union.UnitLocation as LocationApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.SelectionSet as SS exposing (SelectionSet)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Board occupancy and transport are mutually exclusive. Aboard units derive
physical position from their carrier, without storing a duplicate coordinate.
Dismounting is a local planning projection; it permits follow-up actions but
records that unloading has already consumed part of the turn.
-}
type Location
    = OnMap Coordinate
    | Aboard UnitId
    | Dismounting Coordinate



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Construct a local planning location at the chosen unloading square.
-}
dismounting : Coordinate -> Location
dismounting position =
    Dismounting position


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
