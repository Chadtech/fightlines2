module DevTools.Flags exposing
    ( Flags
    , decoder
    )

import Json.Decode as Decode
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Random
import ScreenSize exposing (ScreenSize)
import Time


type alias Flags =
    { now : Time.Posix
    , screenSize : ScreenSize
    , operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , seed : Random.Seed
    }


decoder : Decode.Decoder Flags
decoder =
    Decode.map5
        Flags
        (Decode.field "now" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "screenSize" ScreenSize.decoder)
        (Decode.field "operatingSystem" OperatingSystem.decoder)
        (Decode.field "localStorage" LocalStorage.decoder)
        (Decode.field "seed" (Decode.map Random.initialSeed Decode.int))
