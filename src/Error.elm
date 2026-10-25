module Error exposing (Error(..))

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Browser.Dom
import Game.OrderPlanning as OrderPlanning
import Game.UnitId as UnitId exposing (UnitId)
import Json.Decode as JD
import Ports.Js.From as FromJs


type Error
    = TestError
    | LocalStorageDecodeFailed { key : String, error : JD.Error }
    | UnitOwnerNotFound { unitId : UnitId, playerNumber : PlayerNumber }
    | FromJsFailed FromJs.Error
    | ElementFocusFailed Browser.Dom.Error
    | BattlefieldMeasurementFailed Browser.Dom.Error
    | OrderPlanningInvariantViolated OrderPlanning.InvariantViolation
