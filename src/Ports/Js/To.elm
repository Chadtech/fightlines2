port module Ports.Js.To exposing
    ( Msg(..)
    , toCmd
    )

import Audio
import Json.Encode as Je
import Ports.Js.Encode as Encode


type Msg
    = CopyLink { url : String }
    | GenerateMapThumbnail { htmlId : String, requestId : Int }
    | OpenDialog { htmlId : String }
    | Audio Audio.Event
    | SetLocalStorage { key : String, value : Je.Value }


toCmd : Msg -> Cmd msg
toCmd msg =
    toJs (encode msg)


encode : Msg -> Je.Value
encode msg =
    case msg of
        SetLocalStorage entry ->
            Encode.setLocalStorage entry

        OpenDialog dialog ->
            Encode.openDialog dialog

        Audio audio ->
            Encode.message "audio"
                [ ( "event", Audio.encodeEvent audio )
                ]

        GenerateMapThumbnail { htmlId, requestId } ->
            Encode.message "generateMapThumbnail"
                [ ( "htmlId", Je.string htmlId )
                , ( "requestId", Je.int requestId )
                ]

        CopyLink { url } ->
            Encode.message "copyLink"
                [ ( "url", Je.string url )
                ]


port toJs : Je.Value -> Cmd msg
