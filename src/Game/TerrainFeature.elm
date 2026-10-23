module Game.TerrainFeature exposing
    ( TerrainFeature
    , selection
    )

import Api.Object
import Api.Object.TerrainFeature as FeatureApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Terrain as Terrain exposing (Terrain)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias TerrainFeature =
    { position : Coordinate
    , terrain : Terrain
    }


selection : SelectionSet TerrainFeature Api.Object.TerrainFeature
selection =
    SS.succeed TerrainFeature
        |> SS.with (FeatureApi.position Coordinate.selection)
        |> SS.with (SS.map Terrain.fromApi FeatureApi.terrain)
