module Error exposing (Error(..))

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Json.Decode as JD
import UnitId exposing (UnitId)


type Error
    = LocalStorageDecodeFailed { key : String, error : JD.Error }
    | UnitOwnerNotFound { unitId : UnitId, playerNumber : PlayerNumber }
