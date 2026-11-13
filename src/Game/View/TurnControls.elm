module Game.View.TurnControls exposing
    ( Activity(..)
    , Msg(..)
    , SurrenderState(..)
    , headerSubmit
    , headerSurrender
    , htmlId
    , panel
    , replayPanel
    , submit
    , surrender
    , surrenderButtonHtmlId
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
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
            , S.maxH40Viewport
            , S.overflowAuto
            , S.shrink0
            , S.maxWFull
            , S.wFitContent
            , S.row
            , S.flexWrap
            , S.itemsCenter
            , S.when (kind == LiveControls)
                [ S.maxWContainerRem 45
                , S.g2
                , S.columnGap1p5
                , S.compactViewport
                    [ S.maxWFull
                    , S.wFull
                    , S.grid
                    , S.gridColumns "minmax(0, 1fr) minmax(0, 1fr)"
                    , S.g2
                    , S.p2
                    , S.shortLandscape
                        [ S.gridColumns "repeat(3, minmax(0, 1fr))"
                        , S.belowWidth 639
                            [ S.gridColumns "repeat(2, minmax(0, 1fr))"
                            ]
                        ]
                    ]
                ]
            , S.when (kind == ReplayControls)
                [ S.columnGap6 ]
            ]
        ]
        children


submitButton : Activity -> String -> Button.Button Msg
submitButton activity label =
    case activity of
        Planning ->
            Button.primary label SubmitClicked
                |> Button.attention

        Ready ->
            Button.primary label SubmitClicked
                |> Button.attention

        Waiting ->
            Button.disabled label
                |> Button.highlighted

        _ ->
            Button.disabled label


headerSubmit : Activity -> String -> Html Msg
headerSubmit activity label =
    submitButton activity label
        |> Button.small
        |> Button.toHtml


headerSurrender : SurrenderState -> Html Msg
headerSurrender state =
    surrenderButton Button.danger state
        |> Button.small
        |> Button.toHtml


submit : Activity -> String -> Html Msg
submit activity label =
    let
        button : Html Msg
        button =
            submitButton activity label
                |> Button.fullWidth
                |> Button.toHtml

        loading : List (Html Msg)
        loading =
            if activity == Waiting then
                [ LoadingBar.toHtml True ]

            else
                []
    in
    H.div
        [ A.css
            [ S.col
            , S.g1
            , S.shrink0
            , S.w32
            , S.compactViewport
                [ S.wFull
                , S.minW0
                ]
            ]
        ]
        (button :: loading)


surrenderButton :
    (String -> Msg -> Button.Button Msg)
    -> SurrenderState
    -> Button.Button Msg
surrenderButton availableButton state =
    let
        button : Button.Button Msg
        button =
            case state of
                SurrenderAvailable ->
                    availableButton "surrender" SurrenderClicked

                SurrenderUnavailable ->
                    Button.disabled "surrender"

                SurrenderPending ->
                    Button.disabled "surrendering…"
    in
    button
        |> Button.withHtmlId surrenderButtonHtmlId
        |> Button.opensDialog


surrender : SurrenderState -> Html Msg
surrender state =
    surrenderButton Button.secondary state
        |> Button.toHtml
