port module HomeChecks exposing (main)

import Browser
import LocalStorage
import OperatingSystem
import Page.Home as Home
import Random
import Shared


port results : List String -> Cmd msg


main : Program () () ()
main =
    Browser.application
        { init =
            \_ url key ->
                ( ()
                , Shared.init (Random.initialSeed 42) OperatingSystem.Unknown LocalStorage.test url key
                    |> checks
                    |> results
                )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view = \_ -> { title = "home seed checks", body = [] }
        , onUrlChange = \_ -> ()
        , onUrlRequest = \_ -> ()
        }


checks : Shared.Model -> List String
checks shared =
    let
        first : Home.Model
        first =
            Home.init shared

        repeated : Home.Model
        repeated =
            Home.init shared

        nextVisit : Home.Model
        nextVisit =
            Home.init first.shared

        restored : Home.Model
        restored =
            first.shared
                |> Shared.setSeed shared.seed
                |> Home.init

        check : String -> Bool -> List String
        check label passed =
            if passed then
                []

            else
                [ label ]

        samePositions : Home.Model -> Home.Model -> Bool
        samePositions left right =
            (left.snow == right.snow)
                && (left.desert == right.desert)
                && (left.logistics == right.logistics)

        seedValues : Shared.Model -> List Int
        seedValues state =
            Random.step (Random.list 8 (Random.int 0 1000000)) state.seed
                |> Tuple.first
    in
    List.concat
        [ check "the same startup seed reproduces all home positions" (samePositions first repeated)
        , check "the same startup seed reproduces its successor" (seedValues first.shared == seedValues repeated.shared)
        , check "initialization advances the shared seed" (seedValues shared /= seedValues first.shared)
        , check "a return visit continues the shared random stream" (not (samePositions first nextVisit))
        , check "a return visit advances the shared seed again" (seedValues first.shared /= seedValues nextVisit.shared)
        , check "restoring a seed reproduces its positions" (samePositions first restored)
        , check "restoring a seed reproduces its successor" (seedValues first.shared == seedValues restored.shared)
        ]
