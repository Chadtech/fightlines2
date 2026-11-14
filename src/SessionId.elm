module SessionId exposing
    ( SessionId
    , decoder
    , test
    , toString
    )

import Json.Decode as Decode exposing (Decoder)


type SessionId
    = SessionId String


decoder : Decoder SessionId
decoder =
    Decode.map SessionId Decode.string


test : SessionId
test =
    SessionId "00000000000000000000000000000001"


toString : SessionId -> String
toString (SessionId value) =
    value
