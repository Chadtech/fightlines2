module Util.Maybe exposing (lazyFirst)

{-| Evaluate candidates in order, stopping at the first value.
-}


lazyFirst : List (() -> Maybe a) -> Maybe a
lazyFirst candidates =
    case candidates of
        first :: rest ->
            case first () of
                Just value ->
                    Just value

                Nothing ->
                    lazyFirst rest

        [] ->
            Nothing
