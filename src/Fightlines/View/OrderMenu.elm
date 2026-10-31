module Fightlines.View.OrderMenu exposing
    ( Msg(..)
    , keyCommands
    , optionHtmlId
    , toHtml
    )

import Css
import Game.Camera as Camera exposing (Camera)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot exposing (Depot)
import Game.Map as Map exposing (Map)
import Game.Unit as Unit exposing (Unit)
import Game.UnitOrder as Order exposing (MenuOption(..), Order)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Html.Styled.Lazy as Lazy
import Json.Decode as Decode exposing (Decoder)
import KeyCmd exposing (KeyCmd)
import Point exposing (Point)
import Style as S
import View.Aria as Aria
import View.InfoMarker as InfoMarker


type Msg
    = MenuPressed
    | InfoClicked
    | CancelClicked
    | OrderFocused MenuOption
    | OrderPicked Order
    | ArrowedUpOrderMenu MenuOption
    | ArrowedDownOrderMenu MenuOption


keyCommands : Map -> List Depot -> Unit -> KeyCmd Msg
keyCommands map depots unit =
    let
        orderKey : Order -> KeyCmd Msg
        orderKey order =
            KeyCmd.fromKeys [ Order.shortcut order ] (OrderPicked order)
    in
    Order.available depots unit
        |> List.filter (Order.canUse map depots unit)
        |> List.map orderKey
        |> KeyCmd.batch


toHtml : List Depot -> Map -> Camera -> Coordinate -> Unit -> Html Msg
toHtml depots map camera position unit =
    Lazy.lazy6 ordersView depots map camera.offset camera.zoom position unit


ordersView :
    List Depot
    -> Map
    -> Point
    -> Float
    -> Coordinate
    -> Unit
    -> Html Msg
ordersView depots map offset zoom position unit =
    let
        camera : Camera
        camera =
            { offset = offset, zoom = zoom }

        opensLeft : Bool
        opensLeft =
            position.x >= map.width // 2

        horizontalEdge : Int
        horizontalEdge =
            if opensLeft then
                position.x

            else
                position.x + 1

        menuAnchor : { x : String, y : String }
        menuAnchor =
            Camera.anchor camera
                { x = toFloat horizontalEdge / toFloat map.width - 0.5
                , y = (toFloat position.y + 0.5 - toFloat map.height / 2) / toFloat map.width
                }

        horizontalOffset : String
        horizontalOffset =
            if opensLeft then
                "calc(-100% - 0.25rem)"

            else
                "0.25rem"

        translation : String
        translation =
            "translate("
                ++ constrainedOffset "100cqw" menuAnchor.x horizontalOffset
                ++ ", "
                ++ constrainedOffset "100cqh" menuAnchor.y "-3rem"
                ++ ")"

        constrainedOffset : String -> String -> String -> String
        constrainedOffset viewportSize origin preferred =
            -- Transform percentages measure the menu itself, including wrapped content.
            "clamp(calc(0.5rem - "
                ++ origin
                ++ "), "
                ++ preferred
                ++ ", calc("
                ++ viewportSize
                ++ " - "
                ++ origin
                ++ " - 100% - 0.5rem))"

        orders : List Order
        orders =
            Order.available depots unit
    in
    H.section
        [ Aria.label "unit orders"
        , Ev.stopPropagationOn "mousedown" (Decode.succeed ( MenuPressed, True ))
        , A.css
            [ S.absolute
            , S.leftValue menuAnchor.x
            , S.topValue menuAnchor.y
            , S.z4
            , S.w52
            , S.maxWContainerInset4
            , S.maxHContainerInset4
            , S.overflowAuto
            , S.transformOriginTopLeft
            , S.transform translation
            , S.bgGray1
            , S.textGray4
            , S.outdent
            , S.shadowMenu
            , S.p1
            , S.defaultCursor
            , S.col
            , S.g1
            ]
        ]
        [ H.div
            [ A.css
                [ S.row
                , S.itemsCenter
                , S.justifySpaceBetween
                , S.bgGray3
                , S.shrink0
                , S.textGray0
                , S.p2
                ]
            ]
            [ H.h3
                [ A.css
                    [ S.textGray0 ]
                ]
                [ H.text "orders" ]
            , H.div
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.g1
                    ]
                ]
                [ infoButton
                , closeButton
                ]
            ]
        , H.div
            [ Aria.role Aria.Group
            , Aria.label "choose an order"
            , A.css
                [ S.col
                , S.shrink0
                ]
            ]
            (List.map (orderButton map depots unit) orders)
        , cancelRow
        ]


infoButton : Html Msg
infoButton =
    H.button
        [ A.type_ "button"
        , Aria.label "about orders"
        , A.title "about orders"
        , A.attribute "aria-haspopup" "dialog"
        , Ev.onClick InfoClicked
        , A.css
            [ S.batch headerButtonStyles
            , S.bgTransparent
            , S.textGray0
            , S.hover
                [ S.textGray1 ]
            ]
        ]
        [ InfoMarker.toHtml ]


closeButton : Html Msg
closeButton =
    H.button
        [ A.type_ "button"
        , Aria.label "close order menu"
        , A.title "close order menu"
        , Ev.onClick CancelClicked
        , A.css
            [ S.batch headerButtonStyles
            , S.bgGray1
            , S.textGray4
            , S.outdentStrong
            , S.hover
                [ S.bgGray2
                , S.textGray5
                ]
            , S.active
                [ S.indentStrong ]
            ]
        ]
        [ H.span
            [ Aria.hidden True ]
            [ H.text "×" ]
        ]


headerButtonStyles : List Css.Style
headerButtonStyles =
    [ S.row
    , S.itemsCenter
    , S.justifyCenter
    , S.shrink0
    , S.w6
    , S.h6
    , S.p0
    , S.borderTransparent
    , S.pointerCursor
    , S.focusVisible
        [ S.outlineCurrent ]
    ]


orderHtmlId : Order -> String
orderHtmlId order =
    "unit-order-"
        ++ Order.assetName order
        ++ "-"
        ++ String.replace " " "-" (Order.label order)


optionHtmlId : MenuOption -> String
optionHtmlId option =
    case option of
        OrderOption order ->
            orderHtmlId order

        CancelOption ->
            "unit-order-cancel"


cancelRow : Html Msg
cancelRow =
    H.button
        [ A.id (optionHtmlId CancelOption)
        , A.type_ "button"
        , Ev.onClick CancelClicked
        , Ev.onFocus (OrderFocused CancelOption)
        , Ev.custom "keydown" (navigationDecoder CancelOption)
        , A.attribute "aria-keyshortcuts" "Escape"
        , A.css orderRowStyles
        ]
        [ H.span
            [ Aria.hidden True
            , A.css
                [ S.shrink0
                , S.w7p5
                , S.h7p5
                ]
            ]
            []
        , H.text "cancel (esc)"
        ]


orderButton : Map -> List Depot -> Unit -> Order -> Html Msg
orderButton map depots unit order =
    let
        implemented : Bool
        implemented =
            Order.canUse map depots unit order

        title : String
        title =
            if implemented then
                Order.label order

            else if order == Order.Sabotage then
                "requires infantry already on an operational depot and enough supplies for upkeep"

            else if order == Order.DigIn then
                "requires stationary, unentrenched infantry away from roads, depots, fortresses, and building wreckage, with "
                    ++ String.fromInt unit.combatRules.digInCost
                    ++ " supplies plus upkeep"

            else if order == Order.IndirectFire then
                "not enough supplies for readiness and one shell"

            else if order == Order.StandGround then
                "not enough supplies to stand ground"

            else if order == Order.Ambush then
                "not enough supplies to maintain ambush readiness"

            else if order == Order.AttackMove then
                "not enough supplies to move and fire"

            else
                "not available yet"

        styles : List Css.Style
        styles =
            if implemented then
                orderRowStyles

            else
                orderRowStyles ++ [ S.opacity 0.45, S.notAllowedCursor ]
    in
    H.button
        [ A.id (orderHtmlId order)
        , A.type_ "button"
        , A.disabled (not implemented)
        , A.title title
        , Ev.onClick (OrderPicked order)
        , Ev.onFocus (OrderFocused (OrderOption order))
        , Ev.custom "keydown" (navigationDecoder (OrderOption order))
        , A.attribute "aria-keyshortcuts" (Order.shortcut order)
        , A.css styles
        ]
        [ orderIcon order
        , H.text (Order.label order ++ " (" ++ Order.shortcut order ++ ")")
        ]


navigationDecoder : MenuOption -> Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
navigationDecoder current =
    let
        fromKey : String -> Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
        fromKey key =
            let
                stopAll : Msg -> Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
                stopAll msg =
                    Decode.succeed
                        { message = msg
                        , stopPropagation = True
                        , preventDefault = True
                        }
            in
            case key of
                "ArrowDown" ->
                    stopAll <| ArrowedDownOrderMenu current

                "ArrowRight" ->
                    stopAll <| ArrowedDownOrderMenu current

                "ArrowLeft" ->
                    stopAll <| ArrowedUpOrderMenu current

                "ArrowUp" ->
                    stopAll <| ArrowedUpOrderMenu current

                _ ->
                    Decode.fail "not order navigation"
    in
    Decode.field "key" Decode.string
        |> Decode.andThen fromKey


orderRowStyles : List Css.Style
orderRowStyles =
    [ S.row
    , S.shrink0
    , S.itemsCenter
    , S.g2
    , S.p2
    , S.wFull
    , S.textLeft
    , S.borderTransparent
    , S.bgGray1
    , S.textGray5
    , S.pointerCursor
    , S.hover
        [ S.outdent
        , S.bgGray2
        , S.textYellow5
        ]
    , S.focusVisible
        [ S.outdent
        , S.textYellow5
        , S.outlineYellow5
        , S.outlineOffsetNeg3
        ]
    , S.active
        [ S.indent
        ]
    ]


orderIcon : Order -> Html msg
orderIcon order =
    H.img
        [ A.src ("/assets/orders-anime-v1/" ++ Order.assetName order ++ ".png")
        , A.alt ""
        , A.css
            [ S.shrink0
            , S.w7p5
            , S.h7p5
            , S.objectContain
            , S.imageRenderingAuto
            ]
        ]
        []
