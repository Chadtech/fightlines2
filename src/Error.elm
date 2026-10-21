module Error exposing (Error(..))

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Browser.Dom
import Game.OrderPlanning as OrderPlanning
import Game.UnitId as UnitId exposing (UnitId)
import Json.Decode as JD


type Error
    = LocalStorageDecodeFailed { key : String, error : JD.Error }
    | UnitOwnerNotFound { unitId : UnitId, playerNumber : PlayerNumber }
    | BattlefieldMeasurementFailed Browser.Dom.Error
    | OrderPlanningInvariantViolated OrderPlanning.InvariantViolation
