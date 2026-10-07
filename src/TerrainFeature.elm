module TerrainFeature exposing (TerrainFeature)

import Api.Enum.Terrain exposing (Terrain)
import Coordinate exposing (Coordinate)


type alias TerrainFeature =
    { position : Coordinate
    , terrain : Terrain
    }
