module Game.View.TurnControls exposing
    ( Activity(..)
    , Msg(..)
    , SurrenderState(..)
    , feedback
    , htmlId
    , panel
    , playerRow
    , replayPanel
    , submit
    , surrender
    , surrenderButtonHtmlId
    )

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.LoadingBar as LoadingBar


type Activity
    = Planning
    | Ready
    | Locked
    | Submitting
    | Waiting
    | Playing


type Msg
    = SubmitClicked
    | SurrenderClicked


type SurrenderState
    = SurrenderAvailable
    | SurrenderUnavailable
    | SurrenderPending


htmlId : String
htmlId =
    "game-controls"


surrenderButtonHtmlId : String
surrenderButtonHtmlId =
    htmlId ++ "-surrender"


panel : List (Html msg) -> Html msg
panel =
    panelView LiveControls


replayPanel : List (Html msg) -> Html msg
replayPanel =
    panelView ReplayControls


type PanelKind
    = LiveControls
    | ReplayControls


panelView : PanelKind -> List (Html msg) -> Html msg
panelView kind children =
    H.section
        [ A.id htmlId
        , Aria.label "game controls"
        , A.css
            [ S.bgGray1
            , S.outdentTopRight
            , S.py2
            , S.px3
            , S.g3
            , S.columnGap6
            , S.shrink0
            , S.maxWFull
            , S.wFitContent
            , S.row
            , S.flexWrap
            , S.itemsCenter
            , S.when (kind == LiveControls)
                (S.compactViewport
                    [ S.wFull
                    , S.grid
                    , S.gridColumns "minmax(0, 1fr) minmax(0, 1fr)"
                    , S.g2
                    , S.p2
                    , S.shortLandscape
                        [ S.gridColumns "repeat(4, minmax(0, 1fr))"
                        , S.belowWidth 639
                            [ S.gridColumns "repeat(2, minmax(0, 1fr))"
                            ]
                        ]
                    ]
                )
            , S.when (kind == ReplayControls)
                (S.batch
                    [ S.maxH40Viewport
                    , S.overflowAuto
                    ]
                )
            ]
        ]
        children


submit : Activity -> String -> Html Msg
submit activity label =
    let
        button : Button.Button Msg
        button =
            case activity of
                Planning ->
                    Button.secondary label SubmitClicked

                Ready ->
                    Button.primary label SubmitClicked
                        |> Button.attention

                Waiting ->
                    Button.disabled label
                        |> Button.highlighted

                _ ->
                    Button.disabled label
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            , S.shrink0
            , S.w36
            , S.compactViewport
                [ S.wFull
                , S.minW0
                ]
            ]
        ]
        [ button
            |> Button.large
            |> Button.fullWidth
            |> Button.toHtml
        , LoadingBar.toHtml (activity == Waiting)
        ]


surrender : SurrenderState -> Html Msg
surrender state =
    let
        button : Button.Button Msg
        button =
            case state of
                SurrenderAvailable ->
                    Button.danger "surrender" SurrenderClicked

                SurrenderUnavailable ->
                    Button.disabled "surrender"

                SurrenderPending ->
                    Button.disabled "surrendering…"
    in
    button
        |> Button.withHtmlId surrenderButtonHtmlId
        |> Button.toHtml


feedback : List (Html msg) -> Html msg
feedback children =
    H.div
        [ A.css
            [ S.col
            , S.g1
            , S.minW0
            , S.maxWFull
            , S.w66
            , S.compactViewport
                [ S.wFull
                ]
            , S.wrapAnywhere
            ]
        ]
        children


playerRow : { name : String, playerNumber : PlayerNumber, status : String } -> Html msg
playerRow player =
    Lazy.lazy3 playerRowView player.name player.playerNumber player.status


playerRowView : String -> PlayerNumber -> String -> Html msg
playerRowView name playerNumber status =
    H.li
        [ A.css
            [ S.grid
            , S.gridColumns "minmax(0, 1fr) minmax(0, 14ch)"
            , S.g2
            , S.itemsCenter
            , S.minH6
            , S.compactViewport
                [ S.gridColumns "minmax(0, 1fr)"
                , S.g0
                , S.fontSizeRem 0.875
                ]
            ]
        ]
        [ H.div
            [ A.css
                [ S.row
                , S.itemsCenter
                , S.g2
                , S.minW0
                ]
            ]
            [ playerColor playerNumber
            , H.span
                [ A.title name
                , A.css
                    [ S.textEllipsis
                    ]
                ]
                [ H.text name ]
            ]
        , H.span
            [ A.css
                [ S.minW0
                ]
            ]
            [ H.text status
            ]
        ]


playerColor : PlayerNumber -> Html msg
playerColor playerNumber =
    let
        color : Css.Style
        color =
            case playerNumber of
                PlayerNumber.Player1 ->
                    S.bgRed1

                PlayerNumber.Player2 ->
                    S.bgBlue0

        label : String
        label =
            case playerNumber of
                PlayerNumber.Player1 ->
                    "player 1: red"

                PlayerNumber.Player2 ->
                    "player 2: blue"
    in
    H.span
        [ Aria.role Aria.Image
        , Aria.label label
        , A.css
            [ color
            , S.w2
            , S.h2
            , S.shrink0
            ]
        ]
        []
