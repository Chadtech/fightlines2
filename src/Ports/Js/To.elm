port module Ports.Js.To exposing
    ( Msg(..)
    , toCmd
    )

import Common.Ports.Js.Encode as Common
import Json.Encode as Je


type Msg
    = CopyLink { url : String }
    | OpenDialog { htmlId : String }
    | SetLocalStorage { key : String, value : Je.Value }


toCmd : Msg -> Cmd msg
toCmd msg =
    toJs (encode msg)


encode : Msg -> Je.Value
encode msg =
    case msg of
        SetLocalStorage entry ->
            Common.setLocalStorage entry

        OpenDialog dialog ->
            Common.openDialog dialog

        CopyLink { url } ->
            Common.message "copyLink"
                [ ( "url", Je.string url )
                ]


port toJs : Je.Value -> Cmd msg
