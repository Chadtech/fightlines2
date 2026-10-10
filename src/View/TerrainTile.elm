module View.TerrainTile exposing (toSvg)

import Api.Enum.MapTheme as MapTheme exposing (MapTheme)
import Api.Enum.Terrain as Terrain exposing (Terrain)
import Html.Styled.Attributes as A
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA


type alias Appearance =
    { groundPath : String
    , groundFilter : String
    , featureFilter : String
    }


appearance : MapTheme -> Appearance
appearance theme =
    case theme of
        MapTheme.GreenForest ->
            { groundPath = "/assets/terrain-grass-illustrated-v2.png"
            , groundFilter = "none"
            , featureFilter = "none"
            }

        MapTheme.Desert ->
            { groundPath = "/assets/terrain-desert.svg"
            , groundFilter = "none"
            , featureFilter = "sepia(0.8) saturate(0.65) brightness(1.15)"
            }

        MapTheme.Snow ->
            { groundPath = "/assets/terrain-grass-illustrated-v2.png"
            , groundFilter = "grayscale(1) brightness(2.6)"
            , featureFilter = "saturate(0.15) brightness(1.8)"
            }


image : { path : String, filter : String } -> Svg msg
image config =
    Svg.image
        [ SA.width "16"
        , SA.height "16"
        , SA.xlinkHref config.path
        , A.style "filter" config.filter
        , SA.pointerEvents "none"
        ]
        []


{-| Themes change artwork only; terrain remains the source of game rules.
-}
toSvg : { theme : MapTheme, terrain : Terrain } -> Svg msg
toSvg config =
    let
        art : Appearance
        art =
            appearance config.theme

        featurePath : Maybe String
        featurePath =
            case config.terrain of
                Terrain.GrassPlain ->
                    Nothing

                Terrain.Hills ->
                    Just "/assets/terrain-hills-illustrated-v3.png"

                Terrain.Forest ->
                    Just "/assets/terrain-forest-illustrated-v3.png"

        featureImages : List (Svg msg)
        featureImages =
            featurePath
                |> Maybe.map (\path -> [ image { path = path, filter = art.featureFilter } ])
                |> Maybe.withDefault []

        groundImage : Svg msg
        groundImage =
            image { path = art.groundPath, filter = art.groundFilter }

        images : List (Svg msg)
        images =
            groundImage :: featureImages
    in
    Svg.g
        []
        images
