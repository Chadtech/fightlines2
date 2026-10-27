module Game.BattlefieldSnapshot exposing (Player, Snapshot, selection)

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Object
import Api.Object.GamePlayerView as PlayerView
import Api.Object.GameSnapshot as SnapshotApi
import Api.Object.Scenario as Scenario
import Api.Scalar exposing (MapId)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot as Depot exposing (Depot)
import Game.Map as Map exposing (Map)
import Game.Supply as Supply
import Game.Unit as Unit exposing (Unit)
import Graphql.SelectionSet as SS exposing (SelectionSet)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| The viewer-projected battlefield, independent of live turn submission state.
-}
type alias Snapshot =
    { name : String
    , mapType : MapId
    , players : List Player
    , map : Map
    , units : List Unit
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    , visibleTiles : List Coordinate
    }


type alias Player =
    { name : String
    , playerNumber : PlayerNumber
    , isYou : Bool
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


selection : SelectionSet Snapshot Api.Object.GameSnapshot
selection =
    let
        playerSelection : SelectionSet Player Api.Object.GamePlayerView
        playerSelection =
            SS.succeed Player
                |> SS.with PlayerView.name
                |> SS.with PlayerView.playerNumber
                |> SS.with PlayerView.isYou
    in
    SS.succeed Snapshot
        |> SS.with SnapshotApi.name
        |> SS.with SnapshotApi.mapType
        |> SS.with (SnapshotApi.players playerSelection)
        |> SS.with (SnapshotApi.scenario (Scenario.map Map.selection))
        |> SS.with (SnapshotApi.scenario (Scenario.units Unit.selection))
        |> SS.with (SnapshotApi.scenario (Scenario.depots Depot.selection))
        |> SS.with (SnapshotApi.scenario (Scenario.supplyCrates Supply.crateSelection))
        |> SS.with (SnapshotApi.visibleTiles Coordinate.selection)
