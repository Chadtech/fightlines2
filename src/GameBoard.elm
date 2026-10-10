module GameBoard exposing
    ( GameBoard
    , setUnits
    )

import Depot exposing (Depot)
import Map exposing (Map)
import Unit exposing (Unit)


type alias GameBoard =
    { map : Map
    , depots : List Depot
    , units : List Unit
    }


setUnits : List Unit -> GameBoard -> GameBoard
setUnits units board =
    { board | units = units }
