module Fightlines.UserName exposing
    ( fromLocalStorage
    , remember
    )

import Effect as E exposing (Eff)
import Error exposing (Error)
import Json.Decode as JD
import Json.Encode as JE
import LocalStorage exposing (LocalStorage)
import Ports.Js.To as ToJs


fromLocalStorage : LocalStorage -> Result Error (Maybe String)
fromLocalStorage storage =
    LocalStorage.get storage key JD.string
        |> Result.mapError (\error -> Error.LocalStorageDecodeFailed { key = key, error = error })


remember : String -> Eff msg
remember name =
    E.toJs
        (ToJs.SetLocalStorage
            { key = key
            , value = JE.string (String.trim name)
            }
        )


key : String
key =
    "userName"
