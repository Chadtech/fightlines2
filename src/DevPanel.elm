module DevPanel exposing
    ( Error(..)
    , Model
    , Msg(..)
    , Tab(..)
    , dialog
    , htmlId
    , init
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { selectedTab : Tab
    }


type Tab
    = ErrorsTab


type Error
    = Error
        { title : String
        , details : String
        }


type Msg
    = Canceled
    | TabClicked Tab
    | TestErrorButtonClicked


htmlId : String
htmlId =
    "dev-panel"


errorsTabHtmlId : String
errorsTabHtmlId =
    "dev-panel-errors-tab"


errorsPanelHtmlId : String
errorsPanelHtmlId =
    "dev-panel-errors-panel"



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Model
init =
    { selectedTab = ErrorsTab }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


{-| Errors are presentation data supplied by the caller, independent of Shared.
-}
dialog : List Error -> Model -> Dialog Msg
dialog errors model =
    Dialog.make htmlId
        "dev panel"
        Canceled
        [ H.div
            [ A.css
                [ S.grid
                , S.gridColumns "7rem minmax(0, 1fr)"
                , S.g3
                , S.h75Viewport
                , S.minH0
                , S.belowWidth 480
                    [ S.gridColumns "5rem minmax(0, 1fr)" ]
                ]
            ]
            [ tabs errors model.selectedTab
            , tabContent errors model.selectedTab
            ]
        ]
        |> Dialog.workspace
        |> Dialog.withCloseButton


tabs : List Error -> Tab -> Html Msg
tabs errors selectedTab =
    H.nav
        [ A.attribute "role" "tablist"
        , A.attribute "aria-orientation" "vertical"
        , Aria.label "dev panel sections"
        ]
        [ H.button
            [ A.id errorsTabHtmlId
            , A.type_ "button"
            , A.attribute "role" "tab"
            , A.attribute "aria-selected" (selectedTabText selectedTab)
            , A.attribute "aria-controls" errorsPanelHtmlId
            , Ev.onClick (TabClicked ErrorsTab)
            , A.css
                [ S.row
                , S.itemsCenter
                , S.justifySpaceBetween
                , S.g2
                , S.wFull
                , S.p2
                , S.bgNightwood3
                , S.textYellow5
                , S.indentStrong
                ]
            ]
            [ H.text "errors"
            , H.span
                [ A.css
                    [ S.textGray4 ]
                ]
                [ H.text (String.fromInt (List.length errors)) ]
            ]
        ]


selectedTabText : Tab -> String
selectedTabText tab =
    case tab of
        ErrorsTab ->
            "true"


tabContent : List Error -> Tab -> Html Msg
tabContent errors tab =
    case tab of
        ErrorsTab ->
            errorsView errors


errorsView : List Error -> Html Msg
errorsView errors =
    let
        errorContent : List (Html Msg)
        errorContent =
            case errors of
                [] ->
                    [ H.li
                        []
                        [ H.text "no errors" ]
                    ]

                _ ->
                    List.map errorView errors
    in
    H.section
        [ A.id errorsPanelHtmlId
        , A.attribute "role" "tabpanel"
        , Aria.labelledBy errorsTabHtmlId
        , A.css
            [ S.col
            , S.g3
            , S.minW0
            , S.minH0
            ]
        ]
        [ H.div
            [ A.css
                [ S.row
                , S.itemsCenter
                , S.justifySpaceBetween
                , S.flexWrap
                , S.g2
                ]
            ]
            [ H.text "errors"
            , Button.secondary "test error" TestErrorButtonClicked
                |> Button.toHtml
            ]
        , H.p
            []
            [ H.text "newest first" ]
        , H.ul
            [ A.attribute "aria-live" "polite"
            , A.attribute "aria-relevant" "additions"
            , A.css
                [ S.bgNightwood3
                , S.indentStrong
                , S.p3
                , S.col
                , S.g3
                , S.listNone
                , S.flex1
                , S.minH0
                , S.overflowAuto
                ]
            ]
            errorContent
        ]


errorView : Error -> Html Msg
errorView (Error error) =
    H.li
        [ A.css
            [ S.col
            , S.g2
            , S.wrapAnywhere
            ]
        ]
        [ H.p
            [ A.css
                [ S.textGray5 ]
            ]
            [ H.text error.title ]
        , H.p
            [ A.css
                [ S.whitespacePreWrap ]
            ]
            [ H.text error.details ]
        ]
