module Game.Inspection exposing (Inspection(..))

import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.UnitId as UnitId exposing (UnitId)


type Inspection
    = UnitInspection UnitId
    | TileInspection Coordinate
