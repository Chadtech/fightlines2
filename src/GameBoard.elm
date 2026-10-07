module GameBoard exposing (GameBoard)

import Depot exposing (Depot)
import Map exposing (Map)
import Unit exposing (Unit)


type alias GameBoard =
    { map : Map
    , depots : List Depot
    , units : List Unit
    }
