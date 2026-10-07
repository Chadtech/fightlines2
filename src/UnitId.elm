module UnitId exposing
    ( UnitId
    , parse
    , toString
    )


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
