module Error exposing (Error(..))

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Browser.Dom
import Deployment
import Game.OrderPlanning as OrderPlanning
import Game.TurnPlayback as TurnPlayback
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.Http
import Json.Decode as JD
import Ports.Js.From as FromJs


type Error
    = TestError
    | LocalStorageDecodeFailed { key : String, error : JD.Error }
    | UnitOwnerNotFound { unitId : UnitId, playerNumber : PlayerNumber }
    | FromJsFailed FromJs.Error
    | AudioFailed { operation : String, details : String }
    | DeploymentStatusFailed (Graphql.Http.Error Deployment.Status)
    | ElementFocusFailed Browser.Dom.Error
    | ElementScrollFailed Browser.Dom.Error
    | BattlefieldMeasurementFailed Browser.Dom.Error
    | OrderPlanningInvariantViolated OrderPlanning.InvariantViolation
    | PlanningErrorReportFailed String
    | TurnPlaybackInvariantViolated TurnPlayback.InvariantViolation
