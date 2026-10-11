module Board exposing (Board)

import Depot exposing (Depot)
import Map exposing (Map)
import Unit exposing (Unit)


{-| Shared domain data for movement, turn calculations, and the game page.
-}
type alias Board =
    { map : Map
    , depots : List Depot
    , units : List Unit
    }
