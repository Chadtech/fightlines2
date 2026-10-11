module UnitId exposing
    ( UnitId
    , parse
    , selection
    , toString
    )

import Api.Object exposing (Unit)
import Api.Object.Unit as UnitApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type UnitId
    = UnitId String


parse : String -> Result String UnitId
parse value =
    if String.isEmpty value then
        Err "unit id is empty"

    else
        Ok (UnitId value)


toString : UnitId -> String
toString (UnitId value) =
    value


selection : SelectionSet UnitId Unit
selection =
    UnitApi.id |> SS.mapOrFail parse
