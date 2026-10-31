module NonEmptyList exposing
    ( NonEmpty
    , all
    , any
    , append
    , cons
    , filter
    , foldl
    , foldr
    , fromCons
    , fromList
    , head
    , last
    , length
    , map
    , reverse
    , singleton
    , tail
    , toList
    )

{-| Lists with at least one element. Operations preserve non-emptiness where
possible; `tail` and `filter` return ordinary lists because they may be empty.
-}

----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type NonEmpty a
    = NonEmpty a (List a)



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Create a list containing one element.
-}
singleton : a -> NonEmpty a
singleton first =
    NonEmpty first []


{-| Create a non-empty list from its first element and remaining elements.
-}
fromCons : a -> List a -> NonEmpty a
fromCons =
    NonEmpty


{-| Convert an ordinary list, returning `Nothing` for an empty list.
-}
fromList : List a -> Maybe (NonEmpty a)
fromList list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            Just (NonEmpty first rest)


{-| Convert to an ordinary list without changing element order.
-}
toList : NonEmpty a -> List a
toList (NonEmpty first rest) =
    first :: rest


{-| Get the first element, which is always present.
-}
head : NonEmpty a -> a
head (NonEmpty first _) =
    first


{-| Get all elements after the first. The result may be empty.
-}
tail : NonEmpty a -> List a
tail (NonEmpty _ rest) =
    rest


{-| Get the last element, which is always present.
-}
last : NonEmpty a -> a
last (NonEmpty first rest) =
    List.foldl (\value _ -> value) first rest


{-| Count the elements. The result is always at least one.
-}
length : NonEmpty a -> Int
length (NonEmpty _ rest) =
    1 + List.length rest


{-| Add an element to the front.
-}
cons : a -> NonEmpty a -> NonEmpty a
cons first list =
    NonEmpty first (toList list)


{-| Append the second list after the first, preserving element order.
-}
append : NonEmpty a -> NonEmpty a -> NonEmpty a
append (NonEmpty first rest) list =
    NonEmpty first (rest ++ toList list)


{-| Transform each element, preserving non-emptiness and element order.
-}
map : (a -> b) -> NonEmpty a -> NonEmpty b
map transform (NonEmpty first rest) =
    NonEmpty (transform first) (List.map transform rest)


{-| Reverse the element order.
-}
reverse : NonEmpty a -> NonEmpty a
reverse (NonEmpty first rest) =
    List.foldl cons (singleton first) rest


{-| Fold from left to right, with the same argument order as `List.foldl`.
-}
foldl : (a -> b -> b) -> b -> NonEmpty a -> b
foldl step initial (NonEmpty first rest) =
    List.foldl step (step first initial) rest


{-| Fold from right to left, with the same argument order as `List.foldr`.
-}
foldr : (a -> b -> b) -> b -> NonEmpty a -> b
foldr step initial (NonEmpty first rest) =
    step first (List.foldr step initial rest)


{-| Keep matching elements. The result may be empty.
-}
filter : (a -> Bool) -> NonEmpty a -> List a
filter predicate list =
    List.filter predicate (toList list)


{-| Check whether at least one element matches.
-}
any : (a -> Bool) -> NonEmpty a -> Bool
any predicate (NonEmpty first rest) =
    predicate first || List.any predicate rest


{-| Check whether every element matches.
-}
all : (a -> Bool) -> NonEmpty a -> Bool
all predicate (NonEmpty first rest) =
    predicate first && List.all predicate rest
