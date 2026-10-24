module EditableMap exposing
    ( Definition
    , DepotPlacement
    , NamedMap
    , UnitPlacement
    , map
    , name
    , namedSelection
    , reconnectRoads
    , saveMutation
    )

import Api.Enum.BuildingKind as BuildingKind exposing (BuildingKind)
import Api.Enum.Direction as Direction exposing (Direction)
import Api.Enum.MapTheme as MapTheme exposing (MapTheme)
import Api.Enum.MapType as MapType exposing (MapType)
import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Api.InputObject as Input
import Api.Mutation as Mutation
import Api.Object
import Api.Object.DepotPlacement as DepotApi
import Api.Object.MapDefinition as DefinitionApi
import Api.Object.NamedMap as NamedApi
import Api.Object.TerrainPlacement as TerrainApi
import Api.Object.UnitPlacement as UnitApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Direction as Direction
import Game.Map as Map exposing (Map)
import Game.Road as Road
import Game.Terrain as Terrain exposing (Terrain)
import Game.TerrainFeature as TerrainFeature exposing (TerrainFeature)
import Graphql.Operation exposing (RootMutation)
import Graphql.OptionalArgument as Optional
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias Definition =
    { description : String
    , width : Int
    , height : Int
    , theme : MapTheme
    , features : List TerrainFeature
    , depots : List DepotPlacement
    , units : List UnitPlacement
    }


type alias DepotPlacement =
    { position : Coordinate
    , kind : BuildingKind
    }


type alias UnitPlacement =
    { id : Int
    , position : Coordinate
    , playerNumber : PlayerNumber
    , kind : UnitKind
    , direction : Maybe Direction
    }


type alias NamedMap =
    { mapType : MapType
    , definition : Definition
    }


map : Definition -> Map
map definition =
    Map.fromFeatures
        { width = definition.width
        , height = definition.height
        , theme = definition.theme
        , baseTile = Terrain.Plain
        , features = definition.features
        }


{-| Update only road cells touched by terrain painting or their neighbors.
This belongs to authoring: saved maps already contain each explicit road shape.
-}
reconnectRoads : List Coordinate -> Definition -> Definition
reconnectRoads changed definition =
    let
        board : Map
        board =
            map definition

        affected : Coordinate -> Bool
        affected position =
            List.any (Coordinate.inRange position 1) changed

        roadNeighbor : Coordinate -> Direction -> Bool
        roadNeighbor position direction =
            let
                neighbor : Coordinate
                neighbor =
                    Direction.step position direction

                inBounds : Bool
                inBounds =
                    (neighbor.x >= 0) && (neighbor.y >= 0) && (neighbor.x < board.width) && (neighbor.y < board.height)
            in
            inBounds && Terrain.isRoad (Map.terrainAt board neighbor)

        reconnect : TerrainFeature -> TerrainFeature
        reconnect feature =
            if Terrain.isRoad feature.terrain && affected feature.position then
                { feature
                    | terrain =
                        Direction.all
                            |> List.filter (roadNeighbor feature.position)
                            |> Road.fromConnections
                            |> Terrain.Road
                }

            else
                feature
    in
    { definition | features = List.map reconnect definition.features }


namedSelection : SelectionSet NamedMap Api.Object.NamedMap
namedSelection =
    SS.succeed NamedMap
        |> SS.with NamedApi.mapType
        |> SS.with (NamedApi.definition definitionSelection)


definitionSelection : SelectionSet Definition Api.Object.MapDefinition
definitionSelection =
    SS.succeed Definition
        |> SS.with DefinitionApi.description
        |> SS.with DefinitionApi.width
        |> SS.with DefinitionApi.height
        |> SS.with DefinitionApi.theme
        |> SS.with (DefinitionApi.features terrainSelection)
        |> SS.with (DefinitionApi.depots depotSelection)
        |> SS.with (DefinitionApi.units unitSelection)


terrainSelection : SelectionSet TerrainFeature Api.Object.TerrainPlacement
terrainSelection =
    SS.succeed TerrainFeature
        |> SS.with (TerrainApi.position Coordinate.selection)
        |> SS.with (SS.map Terrain.fromApi TerrainApi.terrain)


depotSelection : SelectionSet DepotPlacement Api.Object.DepotPlacement
depotSelection =
    SS.succeed DepotPlacement
        |> SS.with (DepotApi.position Coordinate.selection)
        |> SS.with DepotApi.kind


unitSelection : SelectionSet UnitPlacement Api.Object.UnitPlacement
unitSelection =
    SS.succeed UnitPlacement
        |> SS.with UnitApi.id
        |> SS.with (UnitApi.position Coordinate.selection)
        |> SS.with UnitApi.playerNumber
        |> SS.with UnitApi.kind
        |> SS.with UnitApi.direction


saveMutation : MapType -> Definition -> SelectionSet () RootMutation
saveMutation mapType definition =
    Mutation.saveMap
        { mapType = mapType
        , definition = definitionInput definition
        }
        (SS.map (always ()) NamedApi.mapType)


positionInput : Coordinate -> Input.PositionInput
positionInput position =
    Input.buildPositionInput
        { x = position.x
        , y = position.y
        }


definitionInput : Definition -> Input.MapDefinitionInput
definitionInput definition =
    Input.buildMapDefinitionInput
        { description = definition.description
        , width = definition.width
        , height = definition.height
        , theme = definition.theme
        , features = List.map terrainInput definition.features
        , depots = List.map depotInput definition.depots
        , units = List.map unitInput definition.units
        }


terrainInput : TerrainFeature -> Input.TerrainPlacementInput
terrainInput feature =
    Input.buildTerrainPlacementInput
        { position = positionInput feature.position
        , terrain = Terrain.toApi feature.terrain
        }


depotInput : DepotPlacement -> Input.DepotPlacementInput
depotInput depot =
    Input.buildDepotPlacementInput
        { position = positionInput depot.position
        , kind = depot.kind
        }


unitInput : UnitPlacement -> Input.UnitPlacementInput
unitInput unit =
    Input.buildUnitPlacementInput
        { id = unit.id
        , position = positionInput unit.position
        , playerNumber = unit.playerNumber
        , kind = unit.kind
        }
        (\optionals ->
            { optionals
                | direction =
                    Maybe.map Optional.Present unit.direction
                        |> Maybe.withDefault Optional.Null
            }
        )


name : MapType -> String
name kind =
    MapType.toString kind
        |> String.replace "_" "-"
        |> String.toLower
