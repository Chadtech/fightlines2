port module DevTools.Ports.Js.To exposing
    ( Msg(..)
    , toCmd
    )

import Common.Ports.Js.Encode as Common
import Json.Encode as Je


type Msg
    = OpenDialog { htmlId : String }
    | GenerateMapThumbnail { htmlId : String, requestId : Int }
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

        GenerateMapThumbnail { htmlId, requestId } ->
            Common.message "generateMapThumbnail"
                [ ( "htmlId", Je.string htmlId )
                , ( "requestId", Je.int requestId )
                ]


port toJs : Je.Value -> Cmd msg
