module View.UnitCommands exposing
    ( Camera
    , MenuOption(..)
    , Msg(..)
    , enabledOptions
    , optionHtmlId
    , toHtml
    )

import Coordinate exposing (Coordinate)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Map exposing (Map)
import Point exposing (Point)
import Style as S
import Unit exposing (Unit)
import UnitCommand as Command exposing (Command)


type MenuOption
    = CommandOption Command
    | CancelOption


type Msg
    = MenuPressed
    | CancelClicked
    | CommandFocused MenuOption
    | CommandPicked Command
    | ArrowedUpCommandMenu MenuOption
    | ArrowedDownCommandMenu MenuOption


type alias Camera =
    { offset : Point
    , zoom : Float
    }


toHtml : Map -> Camera -> Coordinate -> Unit -> Html Msg
toHtml map camera position unit =
    let
        opensLeft : Bool
        opensLeft =
            position.x >= map.width // 2

        horizontalEdge : Int
        horizontalEdge =
            if opensLeft then
                position.x

            else
                position.x + 1

        anchorX : String
        anchorX =
            anchor "50cqw" camera.offset.x (toFloat horizontalEdge / toFloat map.width - 0.5)

        anchorY : String
        anchorY =
            anchor "50cqh" camera.offset.y ((toFloat position.y + 0.5 - toFloat map.height / 2) / toFloat map.width)

        anchor : String -> Float -> Float -> String
        anchor center offset fraction =
            -- Match BoardViewport's centered board width, then apply its camera.
            "calc(" ++ center ++ " + min(80cqw, 76vh) * " ++ String.fromFloat (fraction * camera.zoom) ++ " + " ++ String.fromFloat offset ++ "px)"

        horizontalOffset : String
        horizontalOffset =
            if opensLeft then
                "calc(-100% - 0.25rem)"

            else
                "0.25rem"

        translation : String
        translation =
            "translate("
                ++ constrainedOffset "100cqw" anchorX horizontalOffset
                ++ ", "
                ++ constrainedOffset "100cqh" anchorY "-3rem"
                ++ ")"

        constrainedOffset : String -> String -> String -> String
        constrainedOffset viewportSize origin preferred =
            -- Transform percentages measure the menu itself, including wrapped content.
            "clamp(calc(0.5rem - " ++ origin ++ "), " ++ preferred ++ ", calc(" ++ viewportSize ++ " - " ++ origin ++ " - 100% - 0.5rem))"

        commands : List Command
        commands =
            Command.available unit
    in
    H.section
        [ A.attribute "aria-label" "unit commands"
        , Ev.stopPropagationOn "mousedown" (Decode.succeed ( MenuPressed, True ))
        , A.css
            [ S.absolute
            , Css.property "left" anchorX
            , Css.property "top" anchorY
            , S.z4
            , Css.width (Css.rem 13)
            , Css.property "max-width" "calc(100cqw - 1rem)"
            , Css.property "max-height" "calc(100cqh - 1rem)"
            , S.overflowAuto
            , S.transformOriginTopLeft
            , Css.property "transform" translation
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
        [ H.h3
            [ A.css
                [ S.bgGray3
                , S.shrink0
                , S.textGray0
                , S.p2
                ]
            ]
            [ H.text "commands"
            ]
        , H.div
            [ A.attribute "role" "group"
            , A.attribute "aria-label" "choose a command"
            , A.css
                [ S.col
                , S.shrink0
                ]
            ]
            (List.map commandButton commands)
        , cancelRow
        ]


commandHtmlId : Command -> String
commandHtmlId command =
    "unit-command-" ++ Command.assetName command ++ "-" ++ String.replace " " "-" (Command.label command)


optionHtmlId : MenuOption -> String
optionHtmlId option =
    case option of
        CommandOption command ->
            commandHtmlId command

        CancelOption ->
            "unit-command-cancel"


enabledOptions : Unit -> List MenuOption
enabledOptions unit =
    let
        commands : List MenuOption
        commands =
            Command.available unit
                |> List.filter Command.isImplemented
                |> List.map CommandOption
    in
    commands ++ [ CancelOption ]


cancelRow : Html Msg
cancelRow =
    H.button
        [ A.id (optionHtmlId CancelOption)
        , A.type_ "button"
        , Ev.onClick CancelClicked
        , Ev.onFocus (CommandFocused CancelOption)
        , Ev.custom "keydown" (navigationDecoder CancelOption)
        , A.css commandRowStyles
        ]
        [ H.span
            [ A.attribute "aria-hidden" "true"
            , A.css
                [ S.shrink0
                , Css.width (Css.rem 1.875)
                , Css.height (Css.rem 1.875)
                ]
            ]
            []
        , H.text "cancel"
        ]


commandButton : Command -> Html Msg
commandButton command =
    let
        implemented : Bool
        implemented =
            Command.isImplemented command

        title : String
        title =
            if implemented then
                Command.label command

            else
                "not available yet"

        styles : List Css.Style
        styles =
            if implemented then
                commandRowStyles

            else
                commandRowStyles ++ [ Css.opacity (Css.num 0.45), Css.cursor Css.notAllowed ]
    in
    H.button
        [ A.id (commandHtmlId command)
        , A.type_ "button"
        , A.disabled (not implemented)
        , A.title title
        , Ev.onClick (CommandPicked command)
        , Ev.onFocus (CommandFocused (CommandOption command))
        , Ev.custom "keydown" (navigationDecoder (CommandOption command))
        , A.css styles
        ]
        [ commandIcon command
        , H.text (Command.label command)
        ]


navigationDecoder : MenuOption -> Decode.Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
navigationDecoder current =
    let
        fromKey : String -> Decode.Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
        fromKey key =
            case key of
                "ArrowDown" ->
                    Decode.succeed { message = ArrowedDownCommandMenu current, stopPropagation = True, preventDefault = True }

                "ArrowRight" ->
                    Decode.succeed { message = ArrowedDownCommandMenu current, stopPropagation = True, preventDefault = True }

                "ArrowLeft" ->
                    Decode.succeed { message = ArrowedUpCommandMenu current, stopPropagation = True, preventDefault = True }

                "ArrowUp" ->
                    Decode.succeed { message = ArrowedUpCommandMenu current, stopPropagation = True, preventDefault = True }

                _ ->
                    Decode.fail "not command navigation"
    in
    Decode.field "key" Decode.string |> Decode.andThen fromKey


commandRowStyles : List Css.Style
commandRowStyles =
    [ S.row
    , S.shrink0
    , S.itemsCenter
    , S.g2
    , S.p2
    , Css.width (Css.pct 100)
    , Css.textAlign Css.left_
    , Css.border3 (Css.px 1) Css.solid (Css.rgba 0 0 0 0)
    , S.bgGray1
    , S.textGray5
    , S.pointerCursor
    , Css.hover
        [ S.outdent
        , S.bgGray2
        , S.textYellow5
        ]
    , Css.pseudoClass "focus-visible"
        [ S.outdent
        , S.textYellow5
        , Css.outline3 (Css.px 1) Css.solid (Css.hex S.yellow5Str)
        , Css.outlineOffset (Css.px -3)
        ]
    , Css.active
        [ S.indent
        ]
    ]


commandIcon : Command -> Html msg
commandIcon command =
    H.img
        [ A.src ("/assets/commands-anime-v1/" ++ Command.assetName command ++ ".png")
        , A.alt ""
        , A.css
            [ S.shrink0
            , Css.width (Css.rem 1.875)
            , Css.height (Css.rem 1.875)
            , Css.property "object-fit" "contain"
            , Css.property "image-rendering" "auto"
            ]
        ]
        []
