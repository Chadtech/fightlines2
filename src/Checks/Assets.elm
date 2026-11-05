port module Checks.Assets exposing (main)

import Api.Enum.MapTheme as MapTheme
import Game.Assets as Assets
import Platform


port catalogs : List { theme : String, paths : List String } -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init =
            \_ ->
                ( ()
                , [ MapTheme.GreenForest, MapTheme.Desert, MapTheme.Snow ]
                    |> List.map (\theme -> { theme = MapTheme.toString theme, paths = Assets.imagePaths theme })
                    |> catalogs
                )
        , update = \message _ -> never message
        , subscriptions = \_ -> Sub.none
        }
