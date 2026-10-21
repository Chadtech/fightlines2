module Game.View.TerrainTile exposing
    ( clockClass
    , definitions
    , onMap
    , styles
    , toSvg
    )

import Api.Enum.Direction as Direction exposing (Direction)
import Api.Enum.MapTheme as MapTheme exposing (MapTheme)
import Api.Enum.Terrain as Terrain exposing (Terrain)
import Game.Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.Shoreline as Shoreline
    exposing
        ( Bank(..)
        , Corner(..)
        , Transition(..)
        )
import Game.View.Cliff as Cliff
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria


groundFadeHtmlId : String
groundFadeHtmlId =
    "fightlines-beach-ground-fade"


groundMaskHtmlId : String
groundMaskHtmlId =
    "fightlines-beach-ground-mask"


beachSliceHtmlId : String
beachSliceHtmlId =
    "fightlines-beach-corner-slice"


beachCornerSteps : Int
beachCornerSteps =
    24


{-| Shared definitions are mounted once in the shell, including for inspector SVGs.
-}
definitions : Html msg
definitions =
    let
        sliceHalfWidth : Float
        sliceHalfWidth =
            16 * tan (pi / (4 * toFloat beachCornerSteps)) + 0.002

        slicePoints : String
        slicePoints =
            "0,0 16,-" ++ String.fromFloat sliceHalfWidth ++ " 16," ++ String.fromFloat sliceHalfWidth
    in
    Svg.svg
        [ SA.width "0"
        , SA.height "0"
        , Aria.hidden True
        , A.css
            [ S.absolute
            ]
        ]
        [ Svg.defs
            []
            [ Svg.clipPath
                [ SA.id beachSliceHtmlId
                , SA.clipPathUnits "userSpaceOnUse"
                ]
                [ Svg.polygon
                    [ SA.points slicePoints ]
                    []
                ]
            , Svg.linearGradient
                [ SA.id groundFadeHtmlId
                , SA.x1 "0"
                , SA.y1 "0"
                , SA.x2 "0"
                , SA.y2 "4"
                , SA.gradientUnits "userSpaceOnUse"
                ]
                [ Svg.stop
                    [ SA.offset "0"
                    , SA.stopColor "white"
                    ]
                    []
                , Svg.stop
                    [ SA.offset "1"
                    , SA.stopColor "white"
                    , SA.stopOpacity "0"
                    ]
                    []
                ]
            , Svg.mask
                [ SA.id groundMaskHtmlId
                , SA.maskUnits "userSpaceOnUse"
                , SA.x "0"
                , SA.y "0"
                , SA.width "16"
                , SA.height "16"
                ]
                [ Svg.rect
                    [ SA.width "16"
                    , SA.height "4"
                    , SA.fill ("url(#" ++ groundFadeHtmlId ++ ")")
                    ]
                    []
                ]
            ]
        ]
        |> Svg.toUnstyled
        |> H.fromUnstyled


{-| One inherited clock keeps newly painted tiles and inspection portraits in phase.
-}
clockClass : String
clockClass =
    "fightlines-water-clock"


styles : Html msg
styles =
    let
        frameKeyframe : Int -> String
        frameKeyframe index =
            let
                frame : Int
                frame =
                    modBy 32 index
            in
            String.fromFloat (toFloat index * 100 / 32)
                ++ "% { --fightlines-water-x: "
                ++ String.fromInt (-16 * modBy 8 frame)
                ++ "px; --fightlines-water-y: "
                ++ String.fromInt (-16 * (frame // 8))
                ++ "px; }"

        keyframes : String
        keyframes =
            List.range 0 32
                |> List.map frameKeyframe
                |> String.join "\n"
    in
    H.node "style"
        []
        [ H.text
            ("@keyframes fightlines-water-frames {"
                ++ keyframes
                ++ "} ."
                ++ clockClass
                ++ """ {
                    animation: fightlines-water-frames 1920ms steps(1, end) infinite;
                }
                .fightlines-water-clock:has(.fightlines-combat-focus, .fightlines-death-focus) {
                    animation-play-state: paused;
                }
                @media (prefers-reduced-motion: reduce) {
                    .fightlines-water-clock { animation: none; }
                }
                """
            )
        ]


waterView : Svg msg
waterView =
    Svg.svg
        [ SA.width "16"
        , SA.height "16"
        , SA.viewBox "0 0 16 16"
        , SA.overflow "hidden"
        , SA.pointerEvents "none"
        ]
        [ Svg.image
            [ SA.width "128"
            , SA.height "64"
            , SA.xlinkHref "/assets/terrain-water-illustrated-v1.png"
            , A.css
                [ S.transform "translate(var(--fightlines-water-x, 0px), var(--fightlines-water-y, 0px))"
                ]
            ]
            []
        ]


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
            { groundPath = "/assets/terrain-snow-plains-illustrated-v1.png"
            , groundFilter = "none"
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
    Lazy.lazy2 terrainView config.theme config.terrain


{-| Neighbor-aware artwork shared by live games, replays, authoring and inspection.
-}
onMap : Map -> Coordinate -> Svg msg
onMap map position =
    let
        shore : List (Svg msg)
        shore =
            Shoreline.at map position
                |> List.map (transitionView map.theme)

        artwork : List (Svg msg)
        artwork =
            toSvg { theme = map.theme, terrain = Map.terrainAt map position } :: shore
    in
    Svg.g
        [ SA.pointerEvents "none" ]
        artwork


transitionView : MapTheme -> Transition -> Svg msg
transitionView theme transition =
    let
        rotated : Int -> Svg msg -> Svg msg
        rotated degrees artwork =
            Svg.g
                [ SA.transform ("rotate(" ++ String.fromInt degrees ++ " 8 8)") ]
                [ artwork ]
    in
    case transition of
        BankEdge direction bank ->
            case bank of
                Cliff ->
                    Cliff.edge direction

                Sand ->
                    rotated (edgeRotation direction) beachEdgeView

        BankCorner corner bank ->
            case bank of
                Cliff ->
                    Cliff.corner corner

                Sand ->
                    rotated (cornerRotation corner) beachCornerView

        GroundEdge direction ->
            let
                art : Appearance
                art =
                    appearance theme

                ground : Svg msg
                ground =
                    Svg.g
                        [ SA.mask ("url(#" ++ groundMaskHtmlId ++ ")") ]
                        [ image { path = art.groundPath, filter = art.groundFilter } ]
            in
            rotated (edgeRotation direction) ground


beachEdgeView : Svg msg
beachEdgeView =
    image { path = "/assets/coast-illustrated-v1/beach-edge.png", filter = "none" }


{-| Bend the actual edge's sand/foam profile through a quarter turn. The first
and last slices sample its exact endpoints, matching the adjoining straight banks.
Small overlapping wedges avoid raster gaps; the enclosing SVG clips to the tile.
-}
beachCornerView : Svg msg
beachCornerView =
    let
        slice : Int -> Svg msg
        slice index =
            let
                progress : Float
                progress =
                    toFloat index / toFloat beachCornerSteps
            in
            Svg.g
                [ SA.transform ("rotate(" ++ String.fromFloat (90 * progress) ++ ")") ]
                [ Svg.g
                    [ SA.clipPath ("url(#" ++ beachSliceHtmlId ++ ")") ]
                    [ Svg.g
                        [ SA.transform ("matrix(0 1 1 0 0 " ++ String.fromFloat (-16 * progress) ++ ")") ]
                        [ beachEdgeView ]
                    ]
                ]
    in
    Svg.svg
        [ SA.width "16"
        , SA.height "16"
        , SA.viewBox "0 0 16 16"
        , SA.overflow "hidden"
        , SA.pointerEvents "none"
        ]
        (List.range 0 beachCornerSteps |> List.map slice)


edgeRotation : Direction -> Int
edgeRotation direction =
    case direction of
        Direction.North ->
            0

        Direction.East ->
            90

        Direction.South ->
            180

        Direction.West ->
            270


cornerRotation : Corner -> Int
cornerRotation corner =
    case corner of
        NorthWest ->
            0

        NorthEast ->
            90

        SouthEast ->
            180

        SouthWest ->
            270


terrainView : MapTheme -> Terrain -> Svg msg
terrainView theme terrain =
    let
        art : Appearance
        art =
            appearance theme

        featurePath : Maybe String
        featurePath =
            case terrain of
                Terrain.Plain ->
                    Nothing

                Terrain.Water ->
                    Nothing

                Terrain.Beach ->
                    Nothing

                Terrain.Hills ->
                    Just (hillPath theme)

                Terrain.Forest ->
                    Just "/assets/terrain-forest-illustrated-v3.png"

                Terrain.Mountains ->
                    Just (mountainPath theme)

        featureFilter : String
        featureFilter =
            case terrain of
                Terrain.Forest ->
                    art.featureFilter

                _ ->
                    "none"

        featureImages : List (Svg msg)
        featureImages =
            featurePath
                |> Maybe.map (\path -> [ image { path = path, filter = featureFilter } ])
                |> Maybe.withDefault []

        groundImage : Svg msg
        groundImage =
            case terrain of
                Terrain.Water ->
                    waterView

                Terrain.Beach ->
                    image { path = "/assets/coast-illustrated-v1/beach.png", filter = "none" }

                _ ->
                    image { path = art.groundPath, filter = art.groundFilter }

        images : List (Svg msg)
        images =
            groundImage :: featureImages
    in
    Svg.g
        []
        images


hillPath : MapTheme -> String
hillPath theme =
    case theme of
        MapTheme.GreenForest ->
            "/assets/terrain-hills-illustrated-v7.png"

        MapTheme.Snow ->
            "/assets/terrain-hills-snow-illustrated-v7.png"

        MapTheme.Desert ->
            "/assets/terrain-hills-desert-illustrated-v7.png"


mountainPath : MapTheme -> String
mountainPath theme =
    case theme of
        MapTheme.GreenForest ->
            "/assets/terrain-mountains-illustrated-v1.png"

        MapTheme.Snow ->
            "/assets/terrain-mountains-snow-illustrated-v1.png"

        MapTheme.Desert ->
            "/assets/terrain-mountains-desert-illustrated-v1.png"
