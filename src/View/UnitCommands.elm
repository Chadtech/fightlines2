module View.UnitCommands exposing
    ( Msg(..)
    , commandHtmlId
    , toHtml
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S
import Unit exposing (Unit)
import UnitCommand as Command exposing (Command)


type Msg
    = CommandPicked Command
    | ArrowedUpCommandMenu Command
    | ArrowedDownCommandMenu Command
    | CommandFocusCompleted


toHtml : Unit -> Html Msg
toHtml unit =
    let
        commands : List Command
        commands =
            Command.available unit
    in
    H.section
        [ A.attribute "aria-label" "unit commands"
        , A.css
            [ S.col
            , S.g1
            ]
        ]
        [ H.h3
            []
            [ H.text "commands"
            ]
        , H.div
            [ A.attribute "role" "group"
            , A.attribute "aria-label" "choose a command"
            , A.css
                [ S.col
                ]
            ]
            (List.map commandButton commands)
        , H.p
            [ A.css
                [ S.textGray4
                ]
            ]
            [ H.text "↑ ↓ choose · enter confirm"
            ]
        ]


commandHtmlId : Command -> String
commandHtmlId command =
    "unit-command-" ++ Command.assetName command ++ "-" ++ String.replace " " "-" (Command.label command)


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
        , Ev.custom "keydown" (navigationDecoder command)
        , A.css styles
        ]
        [ commandIcon command
        , H.text (Command.label command)
        ]


navigationDecoder : Command -> Decode.Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
navigationDecoder current =
    let
        fromKey : String -> Decode.Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
        fromKey key =
            case key of
                "ArrowDown" ->
                    Decode.succeed { message = ArrowedDownCommandMenu current, stopPropagation = True, preventDefault = True }

                "ArrowUp" ->
                    Decode.succeed { message = ArrowedUpCommandMenu current, stopPropagation = True, preventDefault = True }

                _ ->
                    Decode.fail "not command navigation"
    in
    Decode.field "key" Decode.string |> Decode.andThen fromKey


commandRowStyles : List Css.Style
commandRowStyles =
    [ S.row
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
        , A.width 30
        , A.height 30
        , A.css
            [ S.shrink0
            , Css.property "object-fit" "contain"
            , Css.property "image-rendering" "auto"
            ]
        ]
        []
