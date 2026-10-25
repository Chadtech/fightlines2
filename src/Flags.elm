module Flags exposing
    ( Flags
    , decoder
    )

import Json.Decode as Decode
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Random


type alias Flags =
    { isProduction : Bool
    , operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , seed : Random.Seed
    }


decoder : Decode.Decoder Flags
decoder =
    Decode.map4 Flags
        (Decode.field "isProduction" Decode.bool)
        (Decode.field "operatingSystem" OperatingSystem.decoder)
        (Decode.field "localStorage" LocalStorage.decoder)
        (Decode.field "seed" (Decode.map Random.initialSeed Decode.int))
