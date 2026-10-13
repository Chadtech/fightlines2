module Error exposing (Error(..))

import Json.Decode as JD


type Error
    = LocalStorageDecodeFailed { key : String, error : JD.Error }
