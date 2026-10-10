module ResultUtil exposing (maybeResult)

{-| Move an optional result's error outside the `Maybe`, preserving absence.
-}


maybeResult : Maybe (Result error value) -> Result error (Maybe value)
maybeResult optionalResult =
    case optionalResult of
        Nothing ->
            Ok Nothing

        Just result ->
            Result.map Just result
