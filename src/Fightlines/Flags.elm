module Fightlines.Flags exposing
    ( Flags
    , decoder
    )

import Json.Decode as Decode exposing (Decoder)
import LocalStorage exposing (LocalStorage)
import LocalTime
import OperatingSystem exposing (OperatingSystem)
import Random
import ScreenSize exposing (ScreenSize)
import SessionId exposing (SessionId)
import Time


type alias Flags =
    { now : Time.Posix
    , timeZone : Time.Zone
    , isProduction : Bool
    , screenSize : ScreenSize
    , operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , seed : Random.Seed
    , sessionId : SessionId
    }


decoder : Decoder Flags
decoder =
    Decode.map8
        Flags
        (Decode.field "now" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "timeZone" LocalTime.decoder)
        (Decode.field "isProduction" Decode.bool)
        (Decode.field "screenSize" ScreenSize.decoder)
        (Decode.field "operatingSystem" OperatingSystem.decoder)
        (Decode.field "localStorage" LocalStorage.decoder)
        (Decode.field "seed" (Decode.map Random.initialSeed Decode.int))
        (Decode.field "sessionId" SessionId.decoder)
