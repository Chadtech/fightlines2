module LocalStorage exposing
    ( LocalStorage
    , decoder
    , get
    , test
    )

import Dict exposing (Dict)
import Json.Decode as JD exposing (Decoder)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type LocalStorage
    = LocalStorage (Dict String JD.Value)



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


decoder : Decoder LocalStorage
decoder =
    JD.keyValuePairs JD.value
        |> JD.map (Dict.fromList >> LocalStorage)


get : LocalStorage -> String -> Decoder a -> Result JD.Error (Maybe a)
get (LocalStorage storage) key valueDecoder =
    case Dict.get key storage of
        Just json ->
            JD.decodeValue valueDecoder json
                |> Result.map Just

        Nothing ->
            Ok Nothing


test : LocalStorage
test =
    LocalStorage Dict.empty
