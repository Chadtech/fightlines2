module ListUtil exposing (find)

{-| Return the first element that satisfies the predicate, stopping at the match.
Return `Nothing` when no element matches.
-}


find : (a -> Bool) -> List a -> Maybe a
find predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just first

            else
                find predicate rest
