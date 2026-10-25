module Subscriptions exposing (common)

import KeyCmd
    exposing
        ( KeyCmd
        )
import OperatingSystem
    exposing
        ( OperatingSystem
        )
import Ports.Js.From as FromJs



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


common :
    { operatingSystem : OperatingSystem
    , keyCommands : KeyCmd msg
    , listeners : List (FromJs.Listener msg)
    , onFromJsError : FromJs.Error -> msg
    }
    -> Sub msg
common args =
    Sub.batch
        [ FromJs.subscription
            { listeners = args.listeners
            , onError = args.onFromJsError
            }
        , KeyCmd.subscriptions
            args.operatingSystem
            [ args.keyCommands ]
        ]
