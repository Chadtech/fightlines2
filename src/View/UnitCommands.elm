module View.UnitCommands exposing
    ( Msg(..)
    , State(..)
    , toHtml
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Map exposing (Map)
import Style as S
import Unit exposing (Unit)
import UnitCommand as Command exposing (Command)
import View.Button as Button


type State
    = Choosing
    | Confirming Command


type Msg
    = MenuPressed
    | CommandPicked Command
    | ConfirmClicked
    | CancelClicked


toHtml : State -> Map -> Float -> Unit -> Html Msg
toHtml state map zoom unit =
    let
        opensLeft : Bool
        opensLeft =
            unit.position.x >= map.width // 2

        horizontalEdge : Int
        horizontalEdge =
            if opensLeft then
                unit.position.x

            else
                unit.position.x + 1

        anchorX : Float
        anchorX =
            toFloat horizontalEdge / toFloat map.width * 100

        anchorY : Float
        anchorY =
            (toFloat unit.position.y + 0.5) / toFloat map.height * 100

        horizontalOffset : String
        horizontalOffset =
            if opensLeft then
                "calc(-100% - 0.5rem)"

            else
                "0.5rem"

        menuWidth : Css.Style
        menuWidth =
            case state of
                Confirming _ ->
                    Css.property "width" "max-content"

                _ ->
                    Css.width (Css.rem 13)

        translation : String
        translation =
            "translate(" ++ horizontalOffset ++ ", -50%)"
    in
    H.section
        [ A.attribute "aria-label" "unit command preview"
        , Ev.stopPropagationOn "mousedown" (Decode.succeed ( MenuPressed, True ))
        , A.css
            [ Css.position Css.absolute
            , Css.left (Css.pct anchorX)
            , Css.property "top" ("clamp(9rem, " ++ String.fromFloat anchorY ++ "%, calc(100% - 9rem))")
            , S.z4
            , menuWidth
            , S.transformOriginTopLeft
            , Css.property "transform" ("scale(" ++ String.fromFloat (1 / zoom) ++ ") " ++ translation)
            , S.bgGray1
            , S.textGray4
            , S.outdent
            , S.shadowMenu
            , S.p1
            , S.defaultCursor
            ]
        ]
        (case state of
            Choosing ->
                [ menuHeader "commands"
                , H.div
                    [ A.attribute "role" "group"
                    , A.attribute "aria-label" "unit commands"
                    , A.css
                        [ S.col
                        , S.py1
                        ]
                    ]
                    (List.map commandButton (Command.available unit.kind))
                , cancelFooter
                ]

            Confirming command ->
                [ menuHeader (Command.label command)
                , H.div
                    [ A.css
                        [ S.row
                        , S.g2
                        , S.p2
                        ]
                    ]
                    [ Button.primary "confirm" ConfirmClicked
                        |> Button.toHtml
                    , Button.secondary "cancel" CancelClicked
                        |> Button.toHtml
                    ]
                ]
        )


menuHeader : String -> Html msg
menuHeader title =
    H.div
        [ A.css
            [ S.bgGray3
            , S.textGray0
            , S.p2
            ]
        ]
        [ H.text title
        ]


commandButton : Command -> Html Msg
commandButton command =
    H.button
        [ A.type_ "button"
        , Ev.onClick (CommandPicked command)
        , A.css commandRowStyles
        ]
        [ commandIcon command
        , H.text (Command.label command)
        ]


cancelFooter : Html Msg
cancelFooter =
    H.div
        [ A.css
            [ Css.borderTop3 (Css.px 1) Css.solid (Css.hex S.gray0Str)
            , Css.paddingTop (Css.rem 0.25)
            ]
        ]
        [ H.button
            [ A.type_ "button"
            , Ev.onClick CancelClicked
            , A.css commandRowStyles
            ]
            [ H.span
                [ A.attribute "aria-hidden" "true"
                , A.css
                    [ Css.width (Css.px 30)
                    , Css.height (Css.px 30)
                    , S.row
                    , S.itemsCenter
                    , S.justifyCenter
                    , S.shrink0
                    ]
                ]
                [ H.text "×"
                ]
            , H.text "cancel"
            ]
        ]


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
