module Preference exposing (load)

import Error exposing (Error)
import Json.Decode as Decode exposing (Decoder)
import LocalStorage exposing (LocalStorage)



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Load a preference, using its default when absent or malformed.
Malformed values also retain their storage key and original decoder error.
-}
load :
    { key : String
    , decoder : Decoder value
    , defaultValue : value
    }
    -> LocalStorage
    -> ( value, Maybe Error )
load config storage =
    case LocalStorage.get storage config.key config.decoder of
        Ok saved ->
            ( Maybe.withDefault config.defaultValue saved, Nothing )

        Err decodeError ->
            ( config.defaultValue
            , Just (Error.LocalStorageDecodeFailed { key = config.key, error = decodeError })
            )
