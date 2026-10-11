module GameBoard exposing
    ( GameBoard
    , Msg(..)
    , RotationSelection
    , UnloadRoute
    , setUnits
    , toHtml
    )

import AnimationFrame exposing (Frame)
import Api.Enum.Direction exposing (Direction)
import Api.Enum.UnitKind as Kind
import Coordinate exposing (Coordinate)
import Css
import Css.Global
import Depot exposing (Depot)
import Direction
import Html.Attributes as HA
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Json.Decode as Decode
import ListUtil
import Map exposing (Map)
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
import View.RotationChoices as RotationChoices
import View.TerrainTile as TerrainTile
import View.UnitCargo as UnitCargo
import View.UnitFacing as UnitFacing
import View.UnitSprite as UnitSprite



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias GameBoard =
    { map : Map
    , depots : List Depot
    , units : List Unit
    }


{-| An unload preview always connects the truck to one adjacent tile.
-}
type alias UnloadRoute =
    { origin : Coordinate
    , direction : Direction
    }


type alias RotationSelection =
    { unitId : UnitId
    , position : Coordinate
    , direction : Direction
    }


type Msg
    = RotationChoicesMsg RotationChoices.Msg
    | ClickedUnit UnitId { detail : Int }
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



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setUnits : List Unit -> GameBoard -> GameBoard
setUnits units board =
    { board | units = units }


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



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


toHtml :
    { frame : Frame
    , rotation : Maybe RotationSelection
    , visibleTiles : List Coordinate
    , choosingDestination : Bool
    , reachable : List Coordinate
    , paths : List (List Coordinate)
    , orderedUnits : List UnitId
    , unloads : List UnloadRoute
    , previewPath : List Coordinate
    , moving : List { unitId : UnitId, position : Point }
    , selected : Maybe Coordinate
    }
    -> GameBoard
    -> Html Msg
toHtml config model =
    let
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

        terrainFilter : Coordinate -> String
        terrainFilter position =
            let
                visibilityFilters : List String
                visibilityFilters =
                    if List.member position config.visibleTiles then
                        []

                    else
                        [ "saturate(0.18) brightness(0.58)" ]

                unavailable : Bool
                unavailable =
                    config.choosingDestination
                        && not (List.member position config.reachable)
                        && config.selected
                        /= Just position

                destinationFilters : List String
                destinationFilters =
                    if unavailable then
                        [ "brightness(0.6)" ]

                    else
                        []

                filters : List String
                filters =
                    visibilityFilters ++ destinationFilters
            in
            if List.isEmpty filters then
                "none"

            else
                String.join " " filters

        depotView : Depot -> Svg Msg
        depotView depot =
            at depot.position
                [ Svg.image
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.xlinkHref "/assets/supply-depot-illustrated-v1.png"
                    , HA.style "filter" (terrainFilter depot.position)
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

        unitView : Unit -> Coordinate -> Svg Msg
        unitView unit position =
            let
                aboardThisTruck : Unit -> Bool
                aboardThisTruck passenger =
                    Unit.carrierId passenger == Just unit.id

                passengerCount : Int
                passengerCount =
                    if unit.kind == Kind.Truck then
                        List.length (List.filter aboardThisTruck model.units)

                    else
                        0

                accessibleLabel : String
                accessibleLabel =
                    if passengerCount > 0 then
                        Unit.label unit ++ ", cargo: " ++ String.fromInt passengerCount ++ " / " ++ String.fromInt unit.cargoCapacity

                    else
                        Unit.label unit

                spriteFilter : String
                spriteFilter =
                    if List.member unit.id config.orderedUnits then
                        "brightness(0.6)"

                    else
                        "none"

                previewUnit : Unit
                previewUnit =
                    case config.rotation of
                        Just rotation ->
                            if rotation.unitId == unit.id then
                                { unit | direction = Just rotation.direction }

                            else
                                unit

                        Nothing ->
                            unit

                facingClass : String
                facingClass =
                    if Maybe.map .unitId config.rotation == Just unit.id then
                        "fightlines-rotation-preview"

                    else
                        ""

                transform : String
                transform =
                    case ListUtil.find (\moving -> moving.unitId == unit.id) config.moving of
                        Just moving ->
                            "translate(" ++ String.fromFloat (moving.position.x * 16) ++ " " ++ String.fromFloat (moving.position.y * 16) ++ ")"

                        Nothing ->
                            "translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")"
            in
            Svg.g
                [ SA.transform transform
                , SA.class facingClass
                ]
                [ Svg.g
                    [ HA.style "filter" spriteFilter
                    ]
                    [ UnitSprite.toSvg (AnimationFrame.unitColumn config.frame unit.id) unit
                        |> StyledSvg.toUnstyled
                    ]
                , UnitFacing.toSvg (config.selected == Just position) previewUnit
                    |> StyledSvg.toUnstyled
                , UnitCargo.toSvg passengerCount
                    |> StyledSvg.toUnstyled
                , Svg.rect
                    [ SA.width "16"
                    , SA.height "16"
                    , SA.fill "transparent"
                    , HA.attribute "tabindex" "0"
                    , HA.attribute "role" "button"
                    , HA.attribute "aria-label" accessibleLabel
                    , Ev.onMouseOver (MouseOverUnit unit.id)
                    , onClickWithDetail (ClickedUnit unit.id)
                    , onKeyDown
                        { pressedEnter = PressedEnterOnUnit unit.id
                        , pressedSpace = PressedSpaceOnUnit unit.id
                        }
                    ]
                    [ Svg.title
                        []
                        [ Svg.text accessibleLabel
                        ]
                    ]
                ]

        positions : List Coordinate
        positions =
            List.range 0 (model.map.height - 1)
                |> List.concatMap
                    (\y -> List.range 0 (model.map.width - 1) |> List.map (\x -> { x = x, y = y }))

        terrainTile : Coordinate -> Svg Msg
        terrainTile position =
            let
                fogAttributes : List (Svg.Attribute Msg)
                fogAttributes =
                    if List.member position config.visibleTiles then
                        []

                    else
                        [ HA.attribute "data-fog" "unseen"
                        ]

                appearanceAttributes : List (Svg.Attribute Msg)
                appearanceAttributes =
                    [ HA.style "filter" (terrainFilter position)
                    , SA.pointerEvents "none"
                    ]
            in
            Svg.g
                (appearanceAttributes ++ fogAttributes)
                [ at position
                    [ TerrainTile.toSvg
                        { theme = model.map.theme
                        , terrain = Map.terrainAt model.map position
                        }
                        |> StyledSvg.toUnstyled
                    ]
                ]

        terrain : Svg Msg
        terrain =
            Svg.g
                [ HA.style "image-rendering" "auto"
                ]
                (List.map terrainTile positions)

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

        unloadRoute : UnloadRoute -> Svg Msg
        unloadRoute route =
            let
                destination : Coordinate
                destination =
                    Direction.step route.origin route.direction
            in
            Svg.g
                []
                [ Svg.polyline
                    [ SA.points (pathPoints [ route.origin, destination ])
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "1.25"
                    ]
                    []
                , at destination
                    [ Svg.polygon
                        [ SA.points "8,5 11,8 8,11 5,8"
                        , SA.fill S.nightwood2Str
                        , SA.stroke S.yellow5Str
                        , SA.strokeWidth "1.25"
                        ]
                        []
                    ]
                ]

        unloadOverlay : Svg Msg
        unloadOverlay =
            Svg.g
                [ SA.pointerEvents "none"
                , HA.attribute "aria-hidden" "true"
                , HA.attribute "data-planned-unloads" (String.fromInt (List.length config.unloads))
                ]
                (List.map unloadRoute config.unloads)

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

        rotationOverlay : List (Svg Msg)
        rotationOverlay =
            case config.rotation of
                Just rotation ->
                    [ RotationChoices.toSvg model.map rotation.position rotation.direction
                        |> Svg.map RotationChoicesMsg
                    ]

                Nothing ->
                    []

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
        [ Svg.svg
            [ SA.viewBox ("0 0 " ++ String.fromInt (model.map.width * 16) ++ " " ++ String.fromInt (model.map.height * 16))
            , SA.width "100%"
            , HA.attribute "role" "group"
            , HA.attribute "aria-label" "battlefield"
            ]
            (List.concat
                [ [ terrain, movementOverlay ]
                , List.map tileTarget positions
                , List.map depotView model.depots
                , List.filterMap (\unit -> Unit.boardPosition unit |> Maybe.map (unitView unit)) model.units
                , [ unloadOverlay ]
                , selection
                , rotationOverlay
                ]
            )
            |> H.fromUnstyled
        ]
