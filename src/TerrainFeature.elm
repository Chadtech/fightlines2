module TerrainFeature exposing
    ( TerrainFeature
    , selection
    )

import Api.Enum.Terrain exposing (Terrain)
import Api.Object
import Api.Object.TerrainFeature as FeatureApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias TerrainFeature =
    { position : Coordinate
    , terrain : Terrain
    }


selection : SelectionSet TerrainFeature Api.Object.TerrainFeature
selection =
    SS.succeed TerrainFeature
        |> SS.with (FeatureApi.position Coordinate.selection)
        |> SS.with FeatureApi.terrain
