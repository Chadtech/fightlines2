module ErrorHistory exposing
    ( Model
    , add
    , init
    )

{-| Session diagnostics, newest first.
-}


type alias Model error =
    { errors : List error
    }


init : Model error
init =
    { errors = []
    }


add : Maybe error -> Model error -> Model error
add maybeError model =
    case maybeError of
        Just error ->
            { model | errors = error :: model.errors }

        Nothing ->
            model
