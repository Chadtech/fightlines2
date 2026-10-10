module View.GameBoard exposing (Msg(..), toHtml)

import AnimationFrame exposing (Frame)
import Api.Enum.Terrain as Terrain
import Coordinate exposing (Coordinate)
import Css
import Css.Global
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
import Point exposing (Point)
import Style as S
import Svg
    exposing
        ( Svg
        )
import Svg.Attributes as SA
import Svg.Events as Ev
import Svg.Styled as StyledSvg
import Unit exposing (Unit)
import UnitId
    exposing
        ( UnitId
        )
import View.UnitFacing as UnitFacing
import View.UnitSprite as UnitSprite


type Msg
    = ClickedUnit UnitId { detail : Int }
    | PressedEnterOnUnit UnitId
    | PressedSpaceOnUnit UnitId
    | MouseOverUnit UnitId
    | ClickedDepot Coordinate { detail : Int }
    | PressedEnterOnDepot Coordinate
    | PressedSpaceOnDepot Coordinate
    | MouseOverDepot Coordinate
    | ClickedTile Coordinate { detail : Int }
    | PressedEnterOnTile Coordinate
    | PressedSpaceOnTile Coordinate
    | MouseOverTile Coordinate


at : Coordinate -> List (Svg msg) -> Svg msg
at position children =
    Svg.g
        [ SA.transform ("translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")")
        ]
        children


onKeyDown : { pressedEnter : msg, pressedSpace : msg } -> Svg.Attribute msg
onKeyDown messages =
    Ev.preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    case key of
                        "Enter" ->
                            Decode.succeed ( messages.pressedEnter, True )

                        " " ->
                            Decode.succeed ( messages.pressedSpace, True )

                        _ ->
                            Decode.fail "not Enter or Space"
                )
        )


onClickWithDetail : ({ detail : Int } -> msg) -> Svg.Attribute msg
onClickWithDetail toMsg =
    Ev.on "click"
        (Decode.field "detail" Decode.int
            |> Decode.map (\detail -> toMsg { detail = detail })
        )


toHtml :
    { frame : Frame
    , reachable : List Coordinate
    , paths : List (List Coordinate)
    , previewPath : List Coordinate
    , moving : Maybe { unitId : UnitId, position : Point }
    , selected : Maybe Coordinate
    }
    -> GameBoard
    -> Html Msg
toHtml config model =
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
            let
                baseAttributes : List (Svg.Attribute Msg)
                baseAttributes =
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , SA.stroke S.nightwood2Str
                    , SA.strokeOpacity "0.22"
                    , SA.strokeWidth "0.25"
                    , Ev.onMouseOver (MouseOverTile position)
                    , onClickWithDetail (ClickedTile position)
                    ]

                movementAttributes : List (Svg.Attribute Msg)
                movementAttributes =
                    if List.member position config.reachable then
                        [ HA.attribute "tabindex" "0"
                        , HA.attribute "role" "button"
                        , HA.attribute "aria-label" ("move to (" ++ String.fromInt position.x ++ ", " ++ String.fromInt position.y ++ ")")
                        , onKeyDown
                            { pressedEnter = PressedEnterOnTile position
                            , pressedSpace = PressedSpaceOnTile position
                            }
                        ]

                    else
                        []
            in
            at position
                [ Svg.rect
                    (baseAttributes ++ movementAttributes)
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
                    , Ev.onMouseOver (MouseOverDepot depot.position)
                    , onClickWithDetail (ClickedDepot depot.position)
                    , onKeyDown
                        { pressedEnter = PressedEnterOnDepot depot.position
                        , pressedSpace = PressedSpaceOnDepot depot.position
                        }
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
                transform : String
                transform =
                    case config.moving of
                        Just moving ->
                            if moving.unitId == unit.id then
                                "translate(" ++ String.fromFloat (moving.position.x * 16) ++ " " ++ String.fromFloat (moving.position.y * 16) ++ ")"

                            else
                                "translate(" ++ String.fromInt (unit.position.x * 16) ++ " " ++ String.fromInt (unit.position.y * 16) ++ ")"

                        Nothing ->
                            "translate(" ++ String.fromInt (unit.position.x * 16) ++ " " ++ String.fromInt (unit.position.y * 16) ++ ")"
            in
            Svg.g
                [ SA.transform transform
                ]
                [ UnitSprite.toSvg (AnimationFrame.unitColumn config.frame unit.id) unit
                    |> StyledSvg.toUnstyled
                , UnitFacing.toSvg (config.selected == Just unit.position) unit
                    |> StyledSvg.toUnstyled
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , HA.attribute "role" "button"
                    , HA.attribute "aria-label" (Unit.label unit)
                    , Ev.onMouseOver (MouseOverUnit unit.id)
                    , onClickWithDetail (ClickedUnit unit.id)
                    , onKeyDown
                        { pressedEnter = PressedEnterOnUnit unit.id
                        , pressedSpace = PressedSpaceOnUnit unit.id
                        }
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

        reachableTile : Coordinate -> Svg Msg
        reachableTile position =
            at position
                [ Svg.rect
                    [ SA.x "1"
                    , SA.y "1"
                    , SA.width "14"
                    , SA.height "14"
                    , SA.fill S.yellow5Str
                    , SA.fillOpacity "0.12"
                    , SA.stroke S.yellow5Str
                    , SA.strokeOpacity "0.65"
                    , SA.strokeWidth "0.5"
                    ]
                    []
                ]

        pathPoint : Coordinate -> String
        pathPoint position =
            String.fromInt (position.x * 16 + 8)
                ++ ","
                ++ String.fromInt (position.y * 16 + 8)

        pathPoints : List Coordinate -> String
        pathPoints path =
            path
                |> List.map pathPoint
                |> String.join " "

        destinationMarker : Coordinate -> Svg Msg
        destinationMarker position =
            at position
                [ Svg.circle
                    [ SA.cx "8"
                    , SA.cy "8"
                    , SA.r "2"
                    , SA.fill S.yellow5Str
                    ]
                    []
                ]

        plannedPath : List Coordinate -> List (Svg Msg)
        plannedPath path =
            let
                route : List (Svg Msg)
                route =
                    [ Svg.polyline
                        [ SA.points (pathPoints path)
                        , SA.fill "none"
                        , SA.stroke S.yellow5Str
                        , SA.strokeWidth "1.25"
                        , SA.strokeDasharray "2 1"
                        ]
                        []
                    ]

                destination : List (Svg Msg)
                destination =
                    path
                        |> List.reverse
                        |> List.head
                        |> Maybe.map destinationMarker
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []
            in
            route ++ destination

        previewPath : List Coordinate -> List (Svg Msg)
        previewPath path =
            if List.length path > 1 then
                [ Svg.polyline
                    [ SA.points (pathPoints path)
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "1.5"
                    ]
                    []
                ]

            else
                []

        movementOverlay : Svg Msg
        movementOverlay =
            let
                reachableTiles : List (Svg Msg)
                reachableTiles =
                    List.map reachableTile config.reachable

                plannedPaths : List (Svg Msg)
                plannedPaths =
                    List.concatMap plannedPath config.paths

                preview : List (Svg Msg)
                preview =
                    previewPath config.previewPath
            in
            Svg.g
                [ SA.pointerEvents "none"
                , HA.attribute "aria-hidden" "true"
                ]
                (reachableTiles ++ plannedPaths ++ preview)

        selectionMarker : Coordinate -> Svg Msg
        selectionMarker position =
            at position
                [ Svg.rect
                    [ SA.x "0.75"
                    , SA.y "0.75"
                    , SA.width "14.5"
                    , SA.height "14.5"
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeOpacity "0.8"
                    , SA.strokeWidth "0.5"
                    , SA.pointerEvents "none"
                    , HA.attribute "aria-hidden" "true"
                    ]
                    []
                ]

        selection : List (Svg Msg)
        selection =
            config.selected
                |> Maybe.map selectionMarker
                |> Maybe.map List.singleton
                |> Maybe.withDefault []
    in
    H.div
        [ A.css
            [ S.wFull
            , Css.Global.descendants
                [ Css.Global.selector "rect[role=button]"
                    [ Css.outline Css.none
                    , Css.pseudoClass "focus-visible"
                        [ Css.property "outline" ("0.5px solid " ++ S.yellow5Str)
                        , Css.property "outline-offset" "-1px"
                        , Css.property "border-radius" "0"
                        ]
                    ]
                ]
            ]
        ]
        [ UnitFacing.styles
        , Svg.svg
            [ SA.viewBox ("0 0 " ++ String.fromInt (model.map.width * 16) ++ " " ++ String.fromInt (model.map.height * 16))
            , SA.width "100%"
            , HA.attribute "role" "group"
            , HA.attribute "aria-label" "supply point battlefield"
            ]
            (terrain :: movementOverlay :: (List.map tileTarget positions ++ List.map depotView model.depots ++ List.map unitView model.units ++ selection))
            |> H.fromUnstyled
        ]
