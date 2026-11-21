module AppVersion exposing
    ( current
    , releasedAt
    )

-- Generated from VERSION and VERSION_RELEASED_AT by tools/app-version.cjs. Do not edit manually.

import Time


current : String
current =
    "32"


releasedAt : Time.Posix
releasedAt =
    Time.millisToPosix 1795229718000
