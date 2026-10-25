port module DevTools.Ports.Js.To exposing
    ( Msg(..)
    , toCmd
    )

import Json.Encode as Je
import Ports.Js.Encode as Encode


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
            Encode.setLocalStorage entry

        OpenDialog dialog ->
            Encode.openDialog dialog

        GenerateMapThumbnail { htmlId, requestId } ->
            Encode.message "generateMapThumbnail"
                [ ( "htmlId", Je.string htmlId )
                , ( "requestId", Je.int requestId )
                ]


port toJs : Je.Value -> Cmd msg
