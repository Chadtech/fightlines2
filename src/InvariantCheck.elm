module InvariantCheck exposing
    ( InvariantCheck
    , andThen
    , error
    , happy
    , map
    , mapError
    , value
    , violated
    )

{-| The outcome of checking an internal assumption. Both alternatives retain a
usable value so a caller can continue while recording a violation separately.

An expected no-op satisfies the invariant. Use `violated` only when an assumption
has failed, supplying a value that is safe to continue with.

-}

----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type InvariantCheck error value
    = Satisfied value
    | Violated error value



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Continue with a value when the invariant holds, including expected no-ops.
-}
happy : value -> InvariantCheck error value
happy =
    Satisfied


{-| Continue with a safe value while retaining a violation for the caller to record.
-}
violated : error -> value -> InvariantCheck error value
violated =
    Violated


{-| Continue with the retained value even after a violation. If both operations
report a violation, retain the first one.
-}
andThen : (a -> InvariantCheck error b) -> InvariantCheck error a -> InvariantCheck error b
andThen next check =
    case check of
        Satisfied usable ->
            next usable

        Violated violation usable ->
            next usable
                |> value
                |> Violated violation


{-| Extract the usable value, whether or not the invariant was satisfied.
-}
value : InvariantCheck error value -> value
value check =
    case check of
        Satisfied usable ->
            usable

        Violated _ usable ->
            usable


{-| Extract a violation for the caller to record.
-}
error : InvariantCheck error value -> Maybe error
error check =
    case check of
        Satisfied _ ->
            Nothing

        Violated violation _ ->
            Just violation


{-| Transform the value in either alternative, preserving any violation.
-}
map : (a -> b) -> InvariantCheck error a -> InvariantCheck error b
map transform check =
    case check of
        Satisfied usable ->
            Satisfied (transform usable)

        Violated violation usable ->
            Violated violation (transform usable)


{-| Transform a violation without changing the usable value.
-}
mapError : (a -> b) -> InvariantCheck a value -> InvariantCheck b value
mapError transform check =
    case check of
        Satisfied usable ->
            Satisfied usable

        Violated violation usable ->
            Violated (transform violation) usable
