module View.GameBoard exposing (Msg(..), toHtml)

import AnimationFrame exposing (Frame)
import Api.Enum.Side as Side
    exposing
        ( Side
        )
import Api.Enum.Terrain as Terrain
import Api.Enum.UnitKind as UnitKind
    exposing
        ( UnitKind
        )
import Coordinate exposing (Coordinate)
import Depot exposing (Depot)
import GameBoard exposing (GameBoard)
import Html.Attributes as HA
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Json.Decode as Decode
import Map
import Style as S
import Svg
    exposing
        ( Svg
        )
import Svg.Attributes as SA
import Svg.Events as Ev
import Unit exposing (Unit)
import UnitId
    exposing
        ( UnitId
        )
import View.Sprite as Sprite


type Msg
    = UnitClicked UnitId
    | TileClicked Coordinate
    | UnitMouseClicked UnitId
    | TileMouseClicked Coordinate


at : Coordinate -> List (Svg msg) -> Svg msg
at position children =
    Svg.g
        [ SA.transform ("translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")")
        ]
        children


keyboardActivate : msg -> Svg.Attribute msg
keyboardActivate msg =
    Ev.preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Enter" || key == " " then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "not an activation key"
                )
        )


mouseActivate : msg -> msg -> Svg.Attribute msg
mouseActivate mouseMsg keyboardMsg =
    Ev.on "click"
        (Decode.field "detail" Decode.int
            |> Decode.map
                (\detail ->
                    if detail == 0 then
                        keyboardMsg

                    else
                        mouseMsg
                )
        )


toHtml :
    (Msg -> msg)
    ->
        { frame : Frame
        , selected : Maybe Coordinate
        }
    -> GameBoard
    -> Html msg
toHtml toMsg config model =
    let
        terrainView : Coordinate -> Svg Msg
        terrainView position =
            let
                path : Maybe String
                path =
                    case Map.terrainAt model.map position of
                        Terrain.GrassPlain ->
                            Nothing

                        Terrain.Hills ->
                            Just "/assets/terrain-hills-illustrated-v3.png"

                        Terrain.Forest ->
                            Just "/assets/terrain-forest-illustrated-v3.png"
            in
            path
                |> Maybe.map
                    (\imagePath ->
                        at position
                            [ Svg.image
                                [ SA.width "16"
                                , SA.height "16"
                                , SA.xlinkHref imagePath
                                , SA.pointerEvents "none"
                                ]
                                []
                            ]
                    )
                |> Maybe.withDefault (Svg.g [] [])

        tileTarget : Coordinate -> Svg Msg
        tileTarget position =
            at position
                [ Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , SA.stroke "#082208"
                    , SA.strokeOpacity "0.22"
                    , SA.strokeWidth "0.25"
                    , mouseActivate (TileMouseClicked position) (TileClicked position)
                    ]
                    []
                ]

        depotView : Depot -> Svg Msg
        depotView depot =
            at depot.position
                [ Svg.image
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.xlinkHref "/assets/supply-depot-illustrated-v1.png"
                    , HA.style "image-rendering" "auto"
                    , SA.pointerEvents "none"
                    , HA.attribute "aria-hidden" "true"
                    ]
                    []
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , HA.attribute "role" "button"
                    , HA.attribute "aria-label" "supply depot"
                    , mouseActivate (TileMouseClicked depot.position) (TileClicked depot.position)
                    , keyboardActivate (TileClicked depot.position)
                    ]
                    [ Svg.title
                        []
                        [ Svg.text "supply depot"
                        ]
                    ]
                ]

        unitView : Unit -> Svg Msg
        unitView unit =
            let
                row : Int
                row =
                    (case unit.kind of
                        UnitKind.Infantry ->
                            0

                        UnitKind.Tank ->
                            3

                        UnitKind.SupplyTruck ->
                            6

                        UnitKind.FieldGun ->
                            9
                    )
                        + (case unit.side of
                            Side.West ->
                                0

                            Side.East ->
                                1
                          )

                facing : String
                facing =
                    case unit.side of
                        Side.West ->
                            ""

                        Side.East ->
                            "translate(16 0) scale(-1 1)"
            in
            at unit.position
                [ Svg.g
                    [ SA.transform facing
                    , HA.style "image-rendering" "auto"
                    ]
                    [ Sprite.toSvg { path = "/assets/units_illustrated-v4.png", sheetWidth = 64, sheetHeight = 192, column = AnimationFrame.unitColumn config.frame unit.id, row = row }
                    ]
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , HA.attribute "role" "button"
                    , HA.attribute "aria-label" (Unit.label unit)
                    , mouseActivate (UnitMouseClicked unit.id) (UnitClicked unit.id)
                    , keyboardActivate (UnitClicked unit.id)
                    ]
                    [ Svg.title
                        []
                        [ Svg.text (Unit.label unit)
                        ]
                    ]
                ]

        positions : List Coordinate
        positions =
            List.range 0 (model.map.height - 1)
                |> List.concatMap
                    (\y -> List.range 0 (model.map.width - 1) |> List.map (\x -> { x = x, y = y }))

        terrain : Svg Msg
        terrain =
            Svg.g
                [ HA.style "image-rendering" "auto"
                ]
                (List.map
                    (\position ->
                        at position
                            [ Svg.image
                                [ SA.width "16"
                                , SA.height "16"
                                , SA.xlinkHref "/assets/terrain-grass-illustrated-v2.png"
                                , SA.pointerEvents "none"
                                ]
                                []
                            ]
                    )
                    positions
                    ++ List.map terrainView positions
                )

        selection : List (Svg Msg)
        selection =
            config.selected
                |> Maybe.map (\position -> at position [ Svg.g [ HA.style "image-rendering" "pixelated" ] [ Sprite.toSvg { path = "/assets/misc_sheet.png", sheetWidth = 16, sheetHeight = 464, column = 0, row = 2 } ] ])
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    H.div
        [ A.css
            [ S.wFull
            ]
        ]
        [ Svg.svg
            [ SA.viewBox ("0 0 " ++ String.fromInt (model.map.width * 16) ++ " " ++ String.fromInt (model.map.height * 16))
            , SA.width "100%"
            , HA.attribute "role" "group"
            , HA.attribute "aria-label" "supply point battlefield"
            ]
            (terrain :: (List.map tileTarget positions ++ List.map depotView model.depots ++ List.map unitView model.units ++ selection))
            |> H.fromUnstyled
        ]
        |> H.map toMsg
