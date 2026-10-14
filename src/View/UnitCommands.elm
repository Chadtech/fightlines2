module View.UnitCommands exposing
    ( Msg(..)
    , optionHtmlId
    , toHtml
    )

import Camera exposing (Camera)
import Coordinate exposing (Coordinate)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Map exposing (Map)
import Style as S
import Unit exposing (Unit)
import UnitCommand as Command exposing (Command, MenuOption(..))
import View.Aria as Aria
import View.InfoMarker as InfoMarker


type Msg
    = MenuPressed
    | InfoClicked
    | CancelClicked
    | CommandFocused MenuOption
    | CommandPicked Command
    | ArrowedUpCommandMenu MenuOption
    | ArrowedDownCommandMenu MenuOption


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
            "clamp(calc(0.5rem - " ++ origin ++ "), " ++ preferred ++ ", calc(" ++ viewportSize ++ " - " ++ origin ++ " - 100% - 0.5rem))"

        commands : List Command
        commands =
            Command.available unit
    in
    H.section
        [ Aria.label "unit commands"
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
                []
                [ H.text "commands" ]
            , infoButton
            ]
        , H.div
            [ Aria.role Aria.Group
            , Aria.label "choose a command"
            , A.css
                [ S.col
                , S.shrink0
                ]
            ]
            (List.map (commandButton unit) commands)
        , cancelRow
        ]


infoButton : Html Msg
infoButton =
    H.button
        [ A.type_ "button"
        , Aria.label "about commands"
        , A.title "about commands"
        , A.attribute "aria-haspopup" "dialog"
        , Ev.onClick InfoClicked
        , A.css
            [ S.p1
            , S.pointerCursor
            , S.textGray0
            , S.hover
                [ S.textGray5 ]
            , S.focusVisible
                [ S.outlineCurrent
                ]
            ]
        ]
        [ InfoMarker.toHtml ]


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
            [ Aria.hidden True
            , A.css
                [ S.shrink0
                , S.w7p5
                , S.h7p5
                ]
            ]
            []
        , H.text "cancel"
        ]


commandButton : Unit -> Command -> Html Msg
commandButton unit command =
    let
        implemented : Bool
        implemented =
            Command.canUse unit command

        title : String
        title =
            if implemented then
                Command.label command

            else if command == Command.IndirectFire then
                "not enough supplies for readiness and one shell"

            else if command == Command.StandGround then
                "not enough supplies to stand ground"

            else if command == Command.Ambush then
                "not enough supplies to maintain ambush readiness"

            else if command == Command.AttackMove then
                "not enough supplies to move and fire"

            else
                "not available yet"

        styles : List Css.Style
        styles =
            if implemented then
                commandRowStyles

            else
                commandRowStyles ++ [ S.opacity 0.45, S.notAllowedCursor ]
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


commandIcon : Command -> Html msg
commandIcon command =
    H.img
        [ A.src ("/assets/commands-anime-v1/" ++ Command.assetName command ++ ".png")
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
