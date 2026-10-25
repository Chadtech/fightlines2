module Game.View.Battlefield exposing
    ( Args
    , DestinationArgs
    , DirectionArgs
    , DirectionPurpose(..)
    , IndirectTargetArgs
    , Interaction(..)
    , Msg(..)
    , OrdersView
    , PlaybackView
    , Presentation(..)
    , SavedOverlays
    , UnloadRoute
    , camera
    , htmlId
    , inspection
    , interaction
    , navigationControls
    , toSvg
    , viewportAttributes
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.SpriteFacing exposing (SpriteFacing)
import Api.Enum.UnitKind as UnitKind
import Css
import Css.Global
import Game.AnimationFrame as AnimationFrame
import Game.Camera as Camera exposing (Camera)
import Game.CombatRules exposing (CombatRules)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot as Depot exposing (Depot)
import Game.Direction as Direction
import Game.Map as Map exposing (Map)
import Game.Movement as Movement
import Game.PlannedOrder as PlannedOrder exposing (PlannedOrder)
import Game.PlaybackPresentation as PlaybackPresentation
import Game.RecordedOrder exposing (RecordedOrder)
import Game.Supply as Supply
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.View.Ambush as Ambush
import Game.View.CombatEffects as CombatEffects
import Game.View.DepotStock as DepotStock
import Game.View.MovementRoute as MovementRoute
import Game.View.ReplayOrders as ReplayOrders
import Game.View.RotationChoices as RotationChoices
import Game.View.SupplyCrate as SupplyCrate
import Game.View.TargetSight as TargetSight
import Game.View.TerrainTile as TerrainTile
import Game.View.UnitCargo as UnitCargo
import Game.View.UnitDeath as UnitDeath
import Game.View.UnitFacing as UnitFacing
import Game.View.UnitSprite as UnitSprite
import Game.View.UnitWarnings as UnitWarnings
import Html.Attributes as HA
import Html.Lazy as SvgLazy
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as HtmlEvents
import Json.Decode as Decode
import Point exposing (Point)
import Set exposing (Set)
import Size exposing (Size)
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as Ev
import Svg.Keyed as SvgKeyed
import Svg.Styled as StyledSvg
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import View.Aria as Aria
import View.Button as Button



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type TerrainAppearance
    = ClearTerrain
    | FoggedTerrain
    | DimmedTerrain
    | FoggedDimmedTerrain


type alias TerrainGroups =
    { clear : List Coordinate
    , fogged : List Coordinate
    , dimmed : List Coordinate
    , foggedDimmed : List Coordinate
    }


type alias UnloadRoute =
    { unitId : UnitId
    , origin : Coordinate
    , direction : Direction
    }


type Msg
    = PanLeftClicked
    | PanRightClicked
    | PanUpClicked
    | PanDownClicked
    | ZoomInClicked
    | ZoomOutClicked
    | ResetViewClicked
    | RotationChoicesMsg RotationChoices.Msg
    | ClickedUnit UnitId { detail : Int }
    | PressedEnterOnUnit UnitId
    | PressedSpaceOnUnit UnitId
    | MouseOverUnit UnitId
    | ClickedDepot Coordinate { detail : Int }
    | PressedEnterOnDepot Coordinate
    | PressedSpaceOnDepot Coordinate
    | MouseOverDepot Coordinate
    | ClickedDepotStock Coordinate { detail : Int }
    | PressedEnterOnDepotStock Coordinate
    | PressedSpaceOnDepotStock Coordinate
    | ClickedTile Coordinate { detail : Int }
    | PressedEnterOnTile Coordinate
    | PressedSpaceOnTile Coordinate
    | FocusedBoardUnit UnitId
    | FocusedBoardTile Coordinate
    | TargetPreviewLeft
    | MouseOverTile Coordinate
    | MousePressed Point
    | WheelScrolled Point Float
    | HomePressed


type alias WheelEvent =
    { pointer : Point
    , viewportSize : Point
    , delta : Float
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


inspection : OrdersView
inspection =
    { saved = emptySavedOverlays
    , interaction = Inspecting
    }


interaction : Presentation -> Interaction
interaction presentation =
    case presentation of
        Viewing view ->
            view.interaction

        Playing _ ->
            Inspecting

        Reviewing _ ->
            Inspecting



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


htmlId : String
htmlId =
    "battlefield-navigation"


emptySavedOverlays : SavedOverlays
emptySavedOverlays =
    { orders = []
    , unloadRoutes = []
    }


savedOverlays : Presentation -> SavedOverlays
savedOverlays presentation =
    case presentation of
        Viewing view ->
            view.saved

        Playing _ ->
            emptySavedOverlays

        Reviewing _ ->
            emptySavedOverlays


playback : Presentation -> Maybe TurnPlayback.Playback
playback presentation =
    case presentation of
        Viewing _ ->
            Nothing

        Playing view ->
            Just view.animation

        Reviewing review ->
            review.playback |> Maybe.map .animation


rotationSelection : Interaction -> Maybe DirectionArgs
rotationSelection boardInteraction =
    case boardInteraction of
        ChoosingDirection direction ->
            Just direction

        _ ->
            Nothing


isChoosingDestination : Interaction -> Bool
isChoosingDestination boardInteraction =
    case boardInteraction of
        ChoosingDestination _ ->
            True

        ChoosingIndirectTarget _ ->
            True

        _ ->
            False


reachableTiles : Map -> Interaction -> List Coordinate
reachableTiles map boardInteraction =
    case boardInteraction of
        ChoosingDestination destination ->
            List.map .destination destination.options

        ChoosingIndirectTarget target ->
            indirectTargets map target.origin target.range

        _ ->
            []


mousePressedDecoder : Decode.Decoder Msg
mousePressedDecoder =
    Decode.field "button" Decode.int
        |> Decode.andThen primaryMousePressed


primaryMousePressed : Int -> Decode.Decoder Msg
primaryMousePressed button =
    if button == 0 then
        Decode.map MousePressed Point.decoder

    else
        Decode.fail "only the primary button pans"


wheelScrolledDecoder : Decode.Decoder Msg
wheelScrolledDecoder =
    let
        wheelScrolled : WheelEvent -> Msg
        wheelScrolled event =
            WheelScrolled
                { x = event.pointer.x - event.viewportSize.x / 2
                , y = event.pointer.y - event.viewportSize.y / 2
                }
                event.delta
    in
    Decode.map3 WheelEvent
        Point.decoder
        viewportSizeDecoder
        wheelDeltaDecoder
        |> Decode.map wheelScrolled


viewportSizeDecoder : Decode.Decoder Point
viewportSizeDecoder =
    Decode.map2 Point
        (Decode.at [ "currentTarget", "clientWidth" ] Decode.float)
        (Decode.at [ "currentTarget", "clientHeight" ] Decode.float)


wheelDeltaDecoder : Decode.Decoder Float
wheelDeltaDecoder =
    Decode.map2 normalizeWheelDelta
        (Decode.field "deltaMode" Decode.int)
        (Decode.field "deltaY" Decode.float)


normalizeWheelDelta : Int -> Float -> Float
normalizeWheelDelta mode delta =
    case mode of
        1 ->
            delta * 16

        2 ->
            delta * 800

        _ ->
            delta


navigationKeyDecoder : Decode.Decoder Msg
navigationKeyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen navigationKeyPressed


navigationKeyPressed : String -> Decode.Decoder Msg
navigationKeyPressed key =
    if key == "Home" then
        Decode.succeed HomePressed

    else
        Decode.fail "not a navigation key"


preventDefault : msg -> ( msg, Bool )
preventDefault msg =
    ( msg, True )


plannedStationaryFacing : List PlannedOrder -> Unit -> Unit
plannedStationaryFacing orders unit =
    case ListUtil.find (\order -> order.unitId == unit.id) orders of
        Just order ->
            case order.action of
                PlannedOrder.Ambush facing ->
                    Unit.faceDirection (Just facing.direction) unit

                PlannedOrder.StandGround facing ->
                    Unit.faceDirection (Just facing.direction) unit

                _ ->
                    unit

        Nothing ->
            unit


isIndirectTargeting : Interaction -> Bool
isIndirectTargeting boardInteraction =
    case boardInteraction of
        ChoosingIndirectTarget _ ->
            True

        _ ->
            False



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


{-| Attributes for the page-owned navigation surface. Map these attributes to
page messages where the viewport is assembled.
-}
viewportAttributes :
    { dragging : Bool
    , interaction : Interaction
    }
    -> List (H.Attribute Msg)
viewportAttributes view =
    let
        cursorStyle : Css.Style
        cursorStyle =
            if view.dragging then
                S.grabbingCursor

            else if isIndirectTargeting view.interaction then
                S.crosshairCursor

            else
                S.grabCursor
    in
    [ A.id htmlId
    , A.attribute "tabindex" "0"
    , Aria.label "battlefield navigation"
    , A.css
        [ S.relative
        , S.flex1
        , S.minW0
        , S.minH0
        , S.hFull
        , S.row
        , S.itemsCenter
        , S.justifyCenter
        , S.overflowHidden
        , S.userSelectNone
        , S.containerSize
        , cursorStyle
        ]
    , HtmlEvents.on "mousedown" mousePressedDecoder
    , HtmlEvents.preventDefaultOn "wheel"
        (Decode.map preventDefault wheelScrolledDecoder)
    , HtmlEvents.preventDefaultOn "keydown"
        (Decode.map preventDefault navigationKeyDecoder)
    ]


{-| Apply to the board's camera container, leaving page overlays outside it.
-}
camera :
    { camera : Camera
    , transitioning : Bool
    }
    -> List (Html Msg)
    -> Html Msg
camera view =
    let
        cameraTransition : Css.Style
        cameraTransition =
            if view.transitioning then
                S.transformTransition PlaybackPresentation.cameraPanDurationMs

            else
                S.transformTransition 0
    in
    H.div
        [ A.css
            [ S.relative
            , S.widthValue Camera.boardWidth
            , S.shrink0
            , S.transform (Camera.transform view.camera)
            , cameraTransition
            , S.reducedMotion [ S.transformTransition 0 ]
            , Css.Global.descendants
                [ Css.Global.selector "rect"
                    [ S.outlineNone
                    , S.focusVisible
                        [ S.outlineYellow5HalfPixel
                        , S.outlineOffsetNeg1
                        , S.rounded0
                        ]
                    ]
                ]
            ]
        ]


navigationControls : Int -> Html Msg
navigationControls zoomPercent =
    H.section
        [ Aria.label "view controls"
        , A.css
            [ S.row
            , S.shrink0
            , S.minW0
            , S.maxWFull
            , S.flexWrap
            , S.itemsCenter
            , S.g3
            ]
        ]
        [ H.div
            [ Aria.role Aria.Group
            , Aria.label "pan map"
            , A.css
                [ S.grid
                , S.itemsCenter
                , S.justifyItemsCenter
                , S.g0p5
                ]
            ]
            [ panButton "↑" "pan up" PanUpClicked
            , H.div
                [ A.css
                    [ S.grid
                    , S.gridColumnsRem 3 1.625
                    , S.itemsCenter
                    , S.justifyItemsCenter
                    , S.g0p5
                    ]
                ]
                [ panButton "←" "pan left" PanLeftClicked
                , H.span
                    []
                    [ H.text "pan" ]
                , panButton "→" "pan right" PanRightClicked
                ]
            , panButton "↓" "pan down" PanDownClicked
            ]
        , H.div
            [ Aria.role Aria.Group
            , Aria.label "zoom map"
            , A.css
                [ S.grid
                , S.itemsCenter
                , S.justifyItemsCenter
                , S.g1
                ]
            ]
            [ H.div
                [ A.css
                    [ S.grid
                    , S.gridColumns "1.625rem 4ch 1.625rem"
                    , S.itemsCenter
                    , S.justifyItemsCenter
                    , S.g0p5
                    ]
                ]
                [ Button.secondary "−" ZoomOutClicked
                    |> Button.accessibleLabel "zoom out"
                    |> Button.square
                    |> Button.toHtml
                , H.span
                    []
                    [ H.text (String.fromInt zoomPercent ++ "%") ]
                , Button.secondary "+" ZoomInClicked
                    |> Button.accessibleLabel "zoom in"
                    |> Button.square
                    |> Button.toHtml
                ]
            , Button.secondary "reset view" ResetViewClicked
                |> Button.compact
                |> Button.fullWidth
                |> Button.toHtml
            ]
        ]


panButton : String -> String -> Msg -> Html Msg
panButton arrow label msg =
    Button.secondary arrow msg
        |> Button.accessibleLabel label
        |> Button.square
        |> Button.toHtml


at : Coordinate -> List (Svg msg) -> Svg msg
at position children =
    Svg.g
        [ SA.transform
            ("translate("
                ++ String.fromInt (position.x * 16)
                ++ " "
                ++ String.fromInt (position.y * 16)
                ++ ")"
            )
        ]
        children


savedCoverage : Size -> List Unit -> List PlannedOrder -> List (Svg Msg)
savedCoverage dimensions units orders =
    let
        saved : PlannedOrder -> Maybe (Svg Msg)
        saved order =
            case order.action of
                PlannedOrder.Ambush facing ->
                    ListUtil.find (\unit -> unit.id == order.unitId) units
                        |> Maybe.map (\unit -> Ambush.coverage dimensions facing.position facing.direction unit.combatRules)

                PlannedOrder.AttackMove attack ->
                    Just (RotationChoices.attackFacing attack.move.destination attack.direction)

                _ ->
                    Nothing
    in
    List.filterMap saved orders


{-| Resolved display inputs. This view cannot edit orders or issue requests.
-}
type alias Args =
    { map : Map
    , units : List Unit
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    , visibleTiles : List Coordinate
    , frame : AnimationFrame.Frame
    , selected : Maybe Coordinate
    , selectedUnitId : Maybe UnitId
    , facingUnits : List UnitId
    , presentation : Presentation
    }


type Presentation
    = Viewing OrdersView
    | Playing PlaybackView
    | Reviewing ReviewView


type alias ReviewView =
    { playback : Maybe PlaybackView
    , orders : List RecordedOrder
    }


type alias OrdersView =
    { saved : SavedOverlays
    , interaction : Interaction
    }


type alias SavedOverlays =
    { orders : List PlannedOrder
    , unloadRoutes : List UnloadRoute
    }


type alias PlaybackView =
    { animation : TurnPlayback.Playback
    , loss : Maybe TurnPlayback.Loss
    }


type Interaction
    = Inspecting
    | ChoosingDestination DestinationArgs
    | ChoosingIndirectTarget IndirectTargetArgs
    | ChoosingDirection DirectionArgs


type alias DestinationArgs =
    { options : List Movement.Option
    , action : String
    , purpose : MovementRoute.Purpose
    , path : List Coordinate
    }


type alias IndirectTargetArgs =
    { origin : Coordinate
    , range : Int
    , preview : Maybe Coordinate
    }


type alias DirectionArgs =
    { unitId : UnitId
    , position : Coordinate
    , direction : Direction
    , purpose : DirectionPurpose
    }


type DirectionPurpose
    = AmbushFacing CombatRules
    | StandGroundFacing
    | AttackMoveFacing (List Coordinate)


toSvg : Args -> Svg Msg
toSvg args =
    let
        boardInteraction : Interaction
        boardInteraction =
            interaction args.presentation

        saved : SavedOverlays
        saved =
            savedOverlays args.presentation

        animation : Maybe TurnPlayback.Playback
        animation =
            playback args.presentation

        rotationPreview : Maybe DirectionArgs
        rotationPreview =
            rotationSelection boardInteraction

        visiblePositions : Set Coordinate.Key
        visiblePositions =
            Set.fromList (List.map Coordinate.key args.visibleTiles)

        reachablePositions : Set Coordinate.Key
        reachablePositions =
            Set.fromList (List.map Coordinate.key (reachableTiles args.map boardInteraction))

        paths : List PlannedOrder
        paths =
            saved.orders

        orderedUnits : List UnitId
        orderedUnits =
            List.map .unitId paths

        unloads : List UnloadRoute
        unloads =
            saved.unloadRoutes

        movingPositions : List { unitId : UnitId, position : Point }
        movingPositions =
            TurnPlayback.movingPositions animation

        selected : Maybe Coordinate
        selected =
            args.selected

        terrain : Svg Msg
        terrain =
            interactionTerrain args.map args.visibleTiles selected boardInteraction

        terrainFilter : Coordinate -> String
        terrainFilter =
            boardTileFilter visiblePositions (isChoosingDestination boardInteraction) reachablePositions selected

        targetOutline : Coordinate -> Svg Msg
        targetOutline destination =
            at destination
                [ Svg.rect
                    [ SA.x "1"
                    , SA.y "1"
                    , SA.width "14"
                    , SA.height "14"
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "0.5"
                    , SA.strokeDasharray "1 1"
                    , SA.pointerEvents "none"
                    , Aria.svgHidden True
                    ]
                    []
                ]

        crateView : Supply.GroundCrate -> Svg Msg
        crateView crate =
            SvgLazy.lazy3 boardCrate
                (terrainFilter crate.position)
                (Set.member (Coordinate.key crate.position) visiblePositions)
                crate

        depotView : Depot -> Svg Msg
        depotView depot =
            SvgLazy.lazy2 boardDepot (terrainFilter depot.position) depot

        depotStockView : Depot -> Maybe (Svg Msg)
        depotStockView depot =
            let
                stockView : Supply.Stock -> Svg Msg
                stockView stock =
                    at depot.position
                        [ DepotStock.toSvg stock
                            |> StyledSvg.toUnstyled
                        , Svg.rect
                            [ SA.x "0.4"
                            , SA.y "12.4"
                            , SA.width "15.2"
                            , SA.height "3.4"
                            , SA.fill "transparent"
                            , SA.class "fightlines-depot-stock-target"
                            , HA.style "--depot-focus-color" S.yellow5Str
                            , HA.attribute "tabindex" "0"
                            , Aria.svgRole Aria.Button
                            , Aria.svgLabel (DepotStock.label depot stock)
                            , Ev.onMouseOver (MouseOverDepot depot.position)
                            , Ev.on "focus" (Decode.succeed (FocusedBoardTile depot.position))
                            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
                            , onClickWithDetail (ClickedDepotStock depot.position)
                            , onMapActivationKeyDown
                                { pressedEnter = PressedEnterOnDepotStock depot.position
                                , pressedSpace = PressedSpaceOnDepotStock depot.position
                                }
                            ]
                            [ Svg.title [] [ Svg.text (DepotStock.label depot stock) ]
                            ]
                        ]
            in
            Maybe.map stockView depot.stock

        previewedUnit : Unit -> Unit
        previewedUnit unit =
            case rotationPreview of
                Just rotation ->
                    if rotation.unitId == unit.id then
                        Unit.faceDirection (Just rotation.direction) unit

                    else
                        plannedStationaryFacing paths unit

                Nothing ->
                    plannedStationaryFacing paths unit

        unitTransform : Unit -> Coordinate -> String
        unitTransform unit position =
            case
                ListUtil.find
                    (\moving -> moving.unitId == unit.id)
                    movingPositions
            of
                Just moving ->
                    "translate("
                        ++ String.fromFloat (moving.position.x * 16)
                        ++ " "
                        ++ String.fromFloat (moving.position.y * 16)
                        ++ ")"

                Nothing ->
                    "translate("
                        ++ String.fromInt (position.x * 16)
                        ++ " "
                        ++ String.fromInt (position.y * 16)
                        ++ ")"

        facingView : Unit -> Maybe (Svg Msg)
        facingView unit =
            let
                facingClass : String
                facingClass =
                    if Maybe.map .unitId rotationPreview == Just unit.id then
                        "fightlines-rotation-preview"

                    else
                        ""

                markerAt : Coordinate -> Svg Msg
                markerAt position =
                    Svg.g
                        [ SA.transform (unitTransform unit position)
                        , SA.opacity (String.fromFloat (TurnPlayback.unitOpacity animation unit.id))
                        , SA.class facingClass
                        , SA.pointerEvents "none"
                        ]
                        [ UnitFacing.toSvg (selected == Just position) (previewedUnit unit)
                            |> StyledSvg.toUnstyled
                        ]

                showFacing : Bool
                showFacing =
                    List.member unit.id args.facingUnits && not (Unit.isDying unit)
            in
            if showFacing then
                Unit.mapPosition unit |> Maybe.map markerAt

            else
                Nothing

        facingOverlay : List (Svg Msg)
        facingOverlay =
            List.filterMap facingView args.units

        spotlightOverlay : List (Svg Msg)
        spotlightOverlay =
            animation
                |> Maybe.andThen TurnPlayback.spotlight
                |> Maybe.map (spotlightView >> List.singleton)
                |> Maybe.withDefault []

        spotlightView : List Coordinate -> Svg Msg
        spotlightView positions =
            if
                (animation
                    |> Maybe.andThen TurnPlayback.panels
                    |> Maybe.map .mapView
                )
                    == Just TurnPlayback.SeeingMap
            then
                CombatEffects.mapPeek args.map positions

            else
                CombatEffects.spotlight args.map positions

        lossSpotlight : TurnPlayback.Loss -> List (Svg Msg)
        lossSpotlight loss =
            [ UnitDeath.spotlight args.map args.units loss
                |> StyledSvg.toUnstyled
            ]

        lossOverlay : List (Svg Msg)
        lossOverlay =
            case args.presentation of
                Playing view ->
                    view.loss
                        |> Maybe.map lossSpotlight
                        |> Maybe.withDefault []

                Viewing _ ->
                    []

                Reviewing review ->
                    review.playback
                        |> Maybe.andThen .loss
                        |> Maybe.map lossSpotlight
                        |> Maybe.withDefault []

        unitView : Unit -> Coordinate -> Svg Msg
        unitView unit position =
            let
                aboardThisTruck : Unit -> Bool
                aboardThisTruck passenger =
                    Unit.carrierId passenger == Just unit.id

                passengerCount : Int
                passengerCount =
                    if unit.kind == UnitKind.Truck then
                        List.length (List.filter aboardThisTruck args.units)

                    else
                        0
            in
            Svg.g
                [ SA.opacity (String.fromFloat (TurnPlayback.unitOpacity animation unit.id)) ]
                [ SvgLazy.lazy6 boardUnit
                    unit
                    (previewedUnit unit).spriteFacing
                    (unitTransform unit position)
                    (List.member unit.id orderedUnits)
                    passengerCount
                    (AnimationFrame.unitColumn args.frame unit.id)
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

        unloadRoute : UnloadRoute -> Svg Msg
        unloadRoute route =
            let
                destination : Coordinate
                destination =
                    Direction.step route.origin route.direction

                isSelected : Bool
                isSelected =
                    args.selectedUnitId == Just route.unitId

                markerPoints : String
                markerPoints =
                    if isSelected then
                        "8,3 13,8 8,13 3,8"

                    else
                        "8,5 11,8 8,11 5,8"

                markerFill : String
                markerFill =
                    if isSelected then
                        S.yellow5Str

                    else
                        S.nightwood2Str

                markerStroke : String
                markerStroke =
                    if isSelected then
                        S.gray5Str

                    else
                        S.yellow5Str

                selectionOutline : List (Svg Msg)
                selectionOutline =
                    if isSelected then
                        [ Svg.rect
                            [ SA.x "1.5"
                            , SA.y "1.5"
                            , SA.width "13"
                            , SA.height "13"
                            , SA.fill "none"
                            , SA.stroke S.gray5Str
                            , SA.strokeWidth "1"
                            ]
                            []
                        ]

                    else
                        []

                marker : Svg Msg
                marker =
                    Svg.polygon
                        [ SA.points markerPoints
                        , SA.fill markerFill
                        , SA.stroke markerStroke
                        , SA.strokeWidth "1.25"
                        ]
                        []

                markerChildren : List (Svg Msg)
                markerChildren =
                    selectionOutline ++ [ marker ]
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
                , at destination markerChildren
                ]

        unloadOverlay : Svg Msg
        unloadOverlay =
            Svg.g
                [ SA.pointerEvents "none"
                , Aria.svgHidden True
                , HA.attribute "data-planned-unloads" (String.fromInt (List.length unloads))
                ]
                (List.map unloadRoute unloads)

        dimensions : Size
        dimensions =
            Map.toSize args.map

        facingCoverage : List (Svg Msg)
        facingCoverage =
            savedCoverage dimensions args.units paths ++ directionCoverage dimensions boardInteraction

        targetPreview : List (Svg Msg)
        targetPreview =
            case boardInteraction of
                ChoosingIndirectTarget target ->
                    target.preview
                        |> Maybe.map (\position -> [ at position [ TargetSight.toSvg TargetSight.Preview ] ])
                        |> Maybe.withDefault []

                _ ->
                    []

        indirectFireOverlay : Svg Msg
        indirectFireOverlay =
            let
                targetMarker : PlannedOrder -> Maybe ( String, Svg Msg )
                targetMarker order =
                    case order.action of
                        PlannedOrder.IndirectFire fire ->
                            let
                                sightState : TargetSight.State
                                sightState =
                                    if args.selectedUnitId == Just order.unitId then
                                        TargetSight.Saved

                                    else
                                        TargetSight.SavedInactive
                            in
                            Just
                                ( UnitId.toString order.unitId ++ ":" ++ String.fromInt fire.target.x ++ "," ++ String.fromInt fire.target.y
                                , at fire.target [ TargetSight.toSvg sightState ]
                                )

                        _ ->
                            Nothing
            in
            SvgKeyed.node "g"
                [ Aria.svgHidden True
                , SA.pointerEvents "none"
                ]
                (List.filterMap targetMarker paths)

        playbackImpacts : TurnPlayback.Playback -> Svg Msg
        playbackImpacts playing =
            CombatEffects.impacts (TurnPlayback.visibleIndirectImpacts playing ++ playing.current.sabotages) args.units (TurnPlayback.visibleShots playing)

        shotOverlay : Svg Msg
        shotOverlay =
            animation
                |> Maybe.map playbackImpacts
                |> Maybe.withDefault (Svg.text "")

        rotationOverlay : List (Svg Msg)
        rotationOverlay =
            case rotationPreview of
                Just rotation ->
                    [ directionChoices rotation.purpose args.map rotation.position rotation.direction
                        |> Svg.map RotationChoicesMsg
                    ]

                Nothing ->
                    []

        directionChoices : DirectionPurpose -> Map -> Coordinate -> Direction -> Svg RotationChoices.Msg
        directionChoices purpose =
            case purpose of
                AttackMoveFacing path ->
                    RotationChoices.attackToSvg path

                _ ->
                    RotationChoices.ambushToSvg

        selection : List (Svg Msg)
        selection =
            selected
                |> Maybe.map selectionMarker
                |> Maybe.map List.singleton
                |> Maybe.withDefault []

        recordedOrders : Svg Msg
        recordedOrders =
            case args.presentation of
                Reviewing review ->
                    ReplayOrders.toSvg args.selectedUnitId review.orders

                _ ->
                    Svg.text ""
    in
    Svg.svg
        [ SA.viewBox
            ("0 0 "
                ++ String.fromInt (args.map.width * 16)
                ++ " "
                ++ String.fromInt (args.map.height * 16)
            )
        , SA.width "100%"
        , HA.style "display" "block"
        , Aria.svgRole Aria.Group
        , Aria.svgLabel "battlefield"
        , Ev.on "mouseleave" (Decode.succeed TargetPreviewLeft)
        ]
        (List.concat
            [ [ terrain
              , interactionMovement args.map paths boardInteraction
              ]
            , [ interactionTileTargets args.map boardInteraction ]
            , List.map depotView args.depots
            , List.map crateView args.supplyCrates
            , List.concatMap (PlannedOrder.crateUnloads >> List.map (.destination >> targetOutline)) paths
            , List.filterMap
                (\unit ->
                    Unit.mapPosition unit
                        |> Maybe.map (unitView unit)
                )
                args.units
            , facingCoverage
            , [ unloadOverlay, shotOverlay ]
            , [ recordedOrders ]
            , selection
            , rotationOverlay
            , facingOverlay
            , List.filterMap depotStockView args.depots
            , [ indirectFireOverlay ]
            , targetPreview
            , spotlightOverlay
            , lossOverlay
            ]
        )


{-| Map.positions allocates coordinates each view; compare their components at lazy boundaries.
-}
boardTileTarget : String -> Bool -> Int -> Int -> Svg Msg
boardTileTarget destinationAction reachable x y =
    let
        position : Coordinate
        position =
            { x = x, y = y }

        baseAttributes : List (Svg.Attribute Msg)
        baseAttributes =
            [ SA.width "16"
            , SA.height "16"
            , SA.fill "transparent"
            , SA.stroke S.nightwood2Str
            , SA.strokeOpacity "0.22"
            , SA.strokeWidth "0.25"
            , Ev.onMouseOver (MouseOverTile position)
            , Ev.on "focus" (Decode.succeed (FocusedBoardTile position))
            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
            , onClickWithDetail (ClickedTile position)
            ]

        movementAttributes : List (Svg.Attribute Msg)
        movementAttributes =
            if reachable then
                [ HA.attribute "tabindex" "0"
                , Aria.svgRole Aria.Button
                , Aria.svgLabel
                    (destinationAction
                        ++ " ("
                        ++ String.fromInt position.x
                        ++ ", "
                        ++ String.fromInt position.y
                        ++ ")"
                    )
                , onMapActivationKeyDown
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


boardCrate : String -> Bool -> Supply.GroundCrate -> Svg Msg
boardCrate filter visible crate =
    let
        label : String
        label =
            if visible then
                Supply.cargoLabel crate.stock.kind

            else
                Supply.cargoLabel crate.stock.kind ++ " · last seen"
    in
    at crate.position
        [ Svg.g
            [ HA.style "filter" filter ]
            [ SupplyCrate.toSvg crate.stock.kind ]
        , Svg.rect
            [ SA.width "16"
            , SA.height "16"
            , SA.fill "transparent"
            , HA.attribute "tabindex" "0"
            , Aria.svgRole Aria.Button
            , Aria.svgLabel label
            , Ev.onMouseOver (MouseOverTile crate.position)
            , Ev.on "focus" (Decode.succeed (FocusedBoardTile crate.position))
            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
            , onClickWithDetail (ClickedTile crate.position)
            , onMapActivationKeyDown
                { pressedEnter = PressedEnterOnTile crate.position
                , pressedSpace = PressedSpaceOnTile crate.position
                }
            ]
            []
        ]


boardDepot : String -> Depot -> Svg Msg
boardDepot filter depot =
    at depot.position
        [ Svg.image
            [ SA.width "16"
            , SA.height "16"
            , SA.xlinkHref (Depot.image depot)
            , HA.style "filter" filter
            , HA.style "image-rendering" "auto"
            , SA.pointerEvents "none"
            , Aria.svgHidden True
            ]
            []
        , Svg.rect
            [ SA.width "16"
            , SA.height "16"
            , SA.fill "transparent"
            , HA.attribute "tabindex" "0"
            , Aria.svgRole Aria.Button
            , Aria.svgLabel (Depot.label depot)
            , Ev.onMouseOver (MouseOverDepot depot.position)
            , Ev.on "focus" (Decode.succeed (FocusedBoardTile depot.position))
            , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
            , onClickWithDetail (ClickedDepot depot.position)
            , onMapActivationKeyDown
                { pressedEnter = PressedEnterOnDepot depot.position
                , pressedSpace = PressedSpaceOnDepot depot.position
                }
            ]
            [ Svg.title
                []
                [ Svg.text (Depot.label depot)
                ]
            ]
        ]


boardUnit : Unit -> SpriteFacing -> String -> Bool -> Int -> Int -> Svg Msg
boardUnit unit facing transform ordered passengerCount column =
    let
        freightCount : Int
        freightCount =
            if unit.kind == UnitKind.Truck then
                Unit.freightCount unit

            else
                0

        cargoCount : Int
        cargoCount =
            passengerCount + freightCount

        freight : List Supply.CargoStock
        freight =
            unit.resources
                |> Maybe.map .supplyCargo
                |> Maybe.withDefault []

        cargoLabel : String
        cargoLabel =
            if cargoCount > 0 then
                Unit.label unit
                    ++ ", cargo: "
                    ++ String.fromInt cargoCount
                    ++ " / "
                    ++ String.fromInt unit.cargoCapacity
                    ++ ", passengers: "
                    ++ String.fromInt passengerCount
                    ++ ", freight: "
                    ++ String.fromInt freightCount

            else
                Unit.label unit

        warningLabel : String
        warningLabel =
            UnitWarnings.label unit

        accessibleLabel : String
        accessibleLabel =
            if String.isEmpty warningLabel then
                cargoLabel

            else
                cargoLabel ++ ", " ++ warningLabel

        spriteFilter : String
        spriteFilter =
            if ordered then
                "brightness(0.6)"

            else
                "none"

        artwork : List (Svg Msg)
        artwork =
            if Unit.isDying unit then
                [ UnitDeath.toSvg column unit
                    |> StyledSvg.toUnstyled
                ]

            else
                [ Svg.g
                    [ HA.style "filter" spriteFilter
                    ]
                    [ unit
                        |> Unit.setSpriteFacing facing
                        |> UnitSprite.toSvg
                            column
                        |> StyledSvg.toUnstyled
                    ]
                , UnitCargo.toSvg passengerCount
                    |> StyledSvg.toUnstyled
                , UnitCargo.freightToSvg freight
                    |> StyledSvg.toUnstyled
                , UnitWarnings.toSvg unit
                    |> StyledSvg.toUnstyled
                ]

        hitTarget : Svg Msg
        hitTarget =
            Svg.rect
                [ SA.width "16"
                , SA.height "16"
                , SA.fill "transparent"
                , HA.attribute "tabindex" "0"
                , Aria.svgRole Aria.Button
                , Aria.svgLabel accessibleLabel
                , Ev.onMouseOver (MouseOverUnit unit.id)
                , Ev.on "focus" (Decode.succeed (FocusedBoardUnit unit.id))
                , Ev.on "blur" (Decode.succeed TargetPreviewLeft)
                , onClickWithDetail (ClickedUnit unit.id)
                , onMapActivationKeyDown
                    { pressedEnter = PressedEnterOnUnit unit.id
                    , pressedSpace = PressedSpaceOnUnit unit.id
                    }
                ]
                [ Svg.title
                    []
                    [ Svg.text accessibleLabel
                    ]
                ]

        children : List (Svg Msg)
        children =
            artwork ++ [ hitTarget ]
    in
    Svg.g
        [ SA.transform transform
        ]
        children


boardTerrainTile : Map -> Bool -> Int -> Int -> Svg Msg
boardTerrainTile map visible x y =
    let
        position : Coordinate
        position =
            { x = x, y = y }

        fogAttributes : List (Svg.Attribute Msg)
        fogAttributes =
            if visible then
                []

            else
                [ HA.attribute "data-fog" "unseen"
                ]
    in
    Svg.g
        (SA.pointerEvents "none" :: fogAttributes)
        [ at position
            [ SvgLazy.lazy2 terrainArtwork map position
            ]
        ]


indirectTargets : Map -> Coordinate -> Int -> List Coordinate
indirectTargets map origin range =
    Map.positions map |> List.filter (Coordinate.inRange origin range)


boardTileFilter : Set Coordinate.Key -> Bool -> Set Coordinate.Key -> Maybe Coordinate -> Coordinate -> String
boardTileFilter visiblePositions choosingDestination reachablePositions selected position =
    boardTileAppearance visiblePositions choosingDestination reachablePositions selected position
        |> terrainAppearanceFilter


boardTileAppearance :
    Set Coordinate.Key
    -> Bool
    -> Set Coordinate.Key
    -> Maybe Coordinate
    -> Coordinate
    -> TerrainAppearance
boardTileAppearance visiblePositions choosingDestination reachablePositions selected position =
    let
        unavailable : Bool
        unavailable =
            choosingDestination
                && not (Set.member (Coordinate.key position) reachablePositions)
                && (selected /= Just position)
    in
    case ( Set.member (Coordinate.key position) visiblePositions, unavailable ) of
        ( True, False ) ->
            ClearTerrain

        ( False, False ) ->
            FoggedTerrain

        ( True, True ) ->
            DimmedTerrain

        ( False, True ) ->
            FoggedDimmedTerrain


terrainAppearanceFilter : TerrainAppearance -> String
terrainAppearanceFilter appearance =
    case appearance of
        ClearTerrain ->
            "none"

        FoggedTerrain ->
            "saturate(0.18) brightness(0.58)"

        DimmedTerrain ->
            "brightness(0.6)"

        FoggedDimmedTerrain ->
            "saturate(0.18) brightness(0.58) brightness(0.6)"


{-| Unwrap interaction and selection before lazy boundaries. The input records
may be freshly assembled by a page; their lists and coordinates remain persistent.
-}
interactionTerrain : Map -> List Coordinate -> Maybe Coordinate -> Interaction -> Svg Msg
interactionTerrain map visibleTiles selected boardInteraction =
    case boardInteraction of
        ChoosingDestination destination ->
            case selected of
                Just position ->
                    SvgLazy.lazy4 selectedMovementTerrain map visibleTiles destination.options position

                Nothing ->
                    SvgLazy.lazy3 unselectedMovementTerrain map visibleTiles destination.options

        ChoosingIndirectTarget target ->
            case selected of
                Just position ->
                    SvgLazy.lazy5 selectedIndirectTerrain map visibleTiles target.origin target.range position

                Nothing ->
                    SvgLazy.lazy4 unselectedIndirectTerrain map visibleTiles target.origin target.range

        _ ->
            SvgLazy.lazy2 inspectionTerrain map visibleTiles


inspectionTerrain : Map -> List Coordinate -> Svg Msg
inspectionTerrain map visibleTiles =
    terrainLayer map visibleTiles [] False Nothing


selectedMovementTerrain : Map -> List Coordinate -> List Movement.Option -> Coordinate -> Svg Msg
selectedMovementTerrain map visibleTiles options selected =
    terrainLayer map visibleTiles (List.map .destination options) True (Just selected)


unselectedMovementTerrain : Map -> List Coordinate -> List Movement.Option -> Svg Msg
unselectedMovementTerrain map visibleTiles options =
    terrainLayer map visibleTiles (List.map .destination options) True Nothing


selectedIndirectTerrain : Map -> List Coordinate -> Coordinate -> Int -> Coordinate -> Svg Msg
selectedIndirectTerrain map visibleTiles origin range selected =
    terrainLayer map visibleTiles (indirectTargets map origin range) True (Just selected)


unselectedIndirectTerrain : Map -> List Coordinate -> Coordinate -> Int -> Svg Msg
unselectedIndirectTerrain map visibleTiles origin range =
    terrainLayer map visibleTiles (indirectTargets map origin range) True Nothing


{-| Terrain stays inside its cell, so equal appearances can share one filter
without changing artwork order within a cell. Keep unit, depot, targeting and
selection layers separate from these terrain-only groups. Coordinate keys retain
unaffected tiles when visibility or destination availability changes.
-}
terrainLayer : Map -> List Coordinate -> List Coordinate -> Bool -> Maybe Coordinate -> Svg Msg
terrainLayer map visibleTiles reachable choosingDestination selected =
    let
        visiblePositions : Set Coordinate.Key
        visiblePositions =
            Set.fromList (List.map Coordinate.key visibleTiles)

        reachablePositions : Set Coordinate.Key
        reachablePositions =
            Set.fromList (List.map Coordinate.key reachable)

        groupTile : Coordinate -> TerrainGroups -> TerrainGroups
        groupTile position accumulated =
            case boardTileAppearance visiblePositions choosingDestination reachablePositions selected position of
                ClearTerrain ->
                    { accumulated | clear = position :: accumulated.clear }

                FoggedTerrain ->
                    { accumulated | fogged = position :: accumulated.fogged }

                DimmedTerrain ->
                    { accumulated | dimmed = position :: accumulated.dimmed }

                FoggedDimmedTerrain ->
                    { accumulated | foggedDimmed = position :: accumulated.foggedDimmed }

        groups : TerrainGroups
        groups =
            List.foldl groupTile
                { clear = []
                , fogged = []
                , dimmed = []
                , foggedDimmed = []
                }
                (Map.positions map)

        terrainGroup : TerrainAppearance -> List Coordinate -> Svg Msg
        terrainGroup appearance positions =
            let
                terrainTile : Coordinate -> ( String, Svg Msg )
                terrainTile position =
                    ( String.fromInt position.x ++ "," ++ String.fromInt position.y
                    , SvgLazy.lazy4 boardTerrainTile map (Set.member (Coordinate.key position) visiblePositions) position.x position.y
                    )
            in
            SvgKeyed.node "g"
                [ HA.style "filter" (terrainAppearanceFilter appearance) ]
                (List.map terrainTile (List.reverse positions))
    in
    Svg.g
        [ HA.style "image-rendering" "auto"
        ]
        [ terrainGroup ClearTerrain groups.clear
        , terrainGroup FoggedTerrain groups.fogged
        , terrainGroup DimmedTerrain groups.dimmed
        , terrainGroup FoggedDimmedTerrain groups.foggedDimmed
        ]


{-| Keep neighboring-terrain artwork separate from fog and destination treatment.
The map contains public terrain only; shoreline rendering does not reveal units.
-}
terrainArtwork : Map -> Coordinate -> Svg Msg
terrainArtwork map position =
    TerrainTile.onMap map position
        |> StyledSvg.toUnstyled


interactionTileTargets : Map -> Interaction -> Svg Msg
interactionTileTargets map boardInteraction =
    case boardInteraction of
        ChoosingDestination destination ->
            SvgLazy.lazy3 movementTileTargets map destination.options destination.action

        ChoosingIndirectTarget target ->
            SvgLazy.lazy3 indirectTileTargets map target.origin target.range

        _ ->
            SvgLazy.lazy inspectionTileTargets map


inspectionTileTargets : Map -> Svg Msg
inspectionTileTargets map =
    tileTargets map [] "inspect"


movementTileTargets : Map -> List Movement.Option -> String -> Svg Msg
movementTileTargets map options action =
    tileTargets map (List.map .destination options) action


indirectTileTargets : Map -> Coordinate -> Int -> Svg Msg
indirectTileTargets map origin range =
    tileTargets map (indirectTargets map origin range) "fire indirectly at"


tileTargets : Map -> List Coordinate -> String -> Svg Msg
tileTargets map reachable destinationAction =
    let
        reachablePositions : Set Coordinate.Key
        reachablePositions =
            Set.fromList (List.map Coordinate.key reachable)

        tileTarget : Coordinate -> Svg Msg
        tileTarget position =
            SvgLazy.lazy4 boardTileTarget destinationAction (Set.member (Coordinate.key position) reachablePositions) position.x position.y
    in
    Svg.g
        []
        (List.map tileTarget (Map.positions map))


interactionMovement : Map -> List PlannedOrder -> Interaction -> Svg Msg
interactionMovement map orders boardInteraction =
    case boardInteraction of
        ChoosingDestination destination ->
            SvgLazy.lazy4 destinationMovement destination.options orders destination.purpose destination.path

        ChoosingIndirectTarget target ->
            SvgLazy.lazy4 indirectMovement map target.origin target.range orders

        ChoosingDirection direction ->
            case direction.purpose of
                AttackMoveFacing path ->
                    SvgLazy.lazy3 attackDirectionMovement orders direction.direction path

                _ ->
                    SvgLazy.lazy savedMovement orders

        Inspecting ->
            SvgLazy.lazy savedMovement orders


destinationMovement : List Movement.Option -> List PlannedOrder -> MovementRoute.Purpose -> List Coordinate -> Svg Msg
destinationMovement options orders purpose path =
    movementLayer (List.map .destination options) orders (MovementRoute.preview purpose path)


indirectMovement : Map -> Coordinate -> Int -> List PlannedOrder -> Svg Msg
indirectMovement map origin range orders =
    movementLayer (indirectTargets map origin range) orders []


attackDirectionMovement : List PlannedOrder -> Direction -> List Coordinate -> Svg Msg
attackDirectionMovement orders direction path =
    movementLayer [] orders (MovementRoute.preview (MovementRoute.DirectedAttack direction) path)


savedMovement : List PlannedOrder -> Svg Msg
savedMovement orders =
    movementLayer [] orders []


directionCoverage : Size -> Interaction -> List (Svg Msg)
directionCoverage dimensions boardInteraction =
    case boardInteraction of
        ChoosingDirection direction ->
            case direction.purpose of
                AmbushFacing rules ->
                    [ Ambush.coverage dimensions direction.position direction.direction rules ]

                _ ->
                    []

        _ ->
            []


movementLayer : List Coordinate -> List PlannedOrder -> List (Svg Msg) -> Svg Msg
movementLayer reachable paths preview =
    let
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

        plannedPath : PlannedOrder -> List (Svg Msg)
        plannedPath order =
            let
                purpose : MovementRoute.Purpose
                purpose =
                    case order.action of
                        PlannedOrder.AttackMove attack ->
                            MovementRoute.DirectedAttack attack.direction

                        _ ->
                            MovementRoute.Travel
            in
            MovementRoute.planned purpose (PlannedOrder.path order)

        overlay : Svg Msg
        overlay =
            let
                reachableSquares : List (Svg Msg)
                reachableSquares =
                    List.map reachableTile reachable

                plannedPaths : List (Svg Msg)
                plannedPaths =
                    List.concatMap plannedPath paths
            in
            Svg.g
                [ SA.pointerEvents "none"
                , Aria.svgHidden True
                ]
                (reachableSquares ++ plannedPaths ++ preview)
    in
    overlay


{-| Enter and Space activate a focused board object. Reserve Meta/Ctrl chords
for shortcuts on every platform, including the window's submit command.
-}
onMapActivationKeyDown : { pressedEnter : msg, pressedSpace : msg } -> Svg.Attribute msg
onMapActivationKeyDown messages =
    let
        shortcutModifier : Decode.Decoder Bool
        shortcutModifier =
            Decode.map2 (||)
                (Decode.field "metaKey" Decode.bool)
                (Decode.field "ctrlKey" Decode.bool)

        activateWithoutShortcut : Bool -> Decode.Decoder ( msg, Bool )
        activateWithoutShortcut shortcutModifierPressed =
            if shortcutModifierPressed then
                Decode.fail "shortcut chords do not activate board objects"

            else
                Decode.oneOf
                    [ HtmlEvent.enter ( messages.pressedEnter, True )
                    , HtmlEvent.key " " ( messages.pressedSpace, True )
                    ]
    in
    Ev.preventDefaultOn "keydown"
        (shortcutModifier |> Decode.andThen activateWithoutShortcut)


onClickWithDetail : ({ detail : Int } -> msg) -> Svg.Attribute msg
onClickWithDetail toMsg =
    Ev.on "click"
        (Decode.field "detail" Decode.int
            |> Decode.map (\detail -> toMsg { detail = detail })
        )


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
            , Aria.svgHidden True
            ]
            []
        ]
