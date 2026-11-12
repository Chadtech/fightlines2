module DevPanel exposing
    ( Error(..)
    , Model
    , Msg(..)
    , Tab(..)
    , dialog
    , htmlId
    , init
    , tabHtmlId
    )

import AppVersion
import Features exposing (Feature)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import NonEmptyList
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)
import View.Tabs as Tabs



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { selectedTab : Tab
    }


type Tab
    = ErrorsTab
    | FeaturesTab


type Error
    = Error
        { title : String
        , details : String
        }


type Msg
    = Canceled
    | TabClicked Tab
    | TabNavigationPressed Tab
    | TestErrorButtonClicked
    | FeatureCheckboxChanged Feature Bool


htmlId : String
htmlId =
    "dev-panel"


errorsTabHtmlId : String
errorsTabHtmlId =
    "dev-panel-errors-tab"


errorsPanelHtmlId : String
errorsPanelHtmlId =
    errorsTabHtmlId ++ "-panel"



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
dialog : List Error -> Features.Model -> Model -> Dialog Msg
dialog errors features model =
    Dialog.make htmlId
        "dev panel"
        Canceled
        [ H.p
            []
            [ H.text ("frontend version " ++ AppVersion.current ++ " · released " ++ AppVersion.releasedAt) ]
        , H.div
            [ A.css
                [ S.grid
                , S.gridColumns "7rem minmax(0, 1fr)"
                , S.g3
                , S.h75Viewport
                , S.flex1
                , S.minH0
                , S.belowWidth 480
                    [ S.gridColumns "5rem minmax(0, 1fr)" ]
                ]
            ]
            [ tabs errors model.selectedTab
            , tabContent errors features model.selectedTab
            ]
        , H.div
            [ A.css
                [ S.row
                , S.shrink0
                ]
            ]
            [ Button.primary "done" Canceled
                |> Button.toHtml
            ]
        ]
        |> Dialog.workspace


tabs : List Error -> Tab -> Html Msg
tabs errors selectedTab =
    Tabs.new
        { label = "dev panel sections"
        , selected = selectedTab
        , options =
            NonEmptyList.fromCons
                { value = ErrorsTab
                , label = "errors (" ++ String.fromInt (List.length errors) ++ ")"
                }
                [ { value = FeaturesTab
                  , label = "features"
                  }
                ]
        , htmlId = tabHtmlId
        , onClick = TabClicked
        , onNavigate = TabNavigationPressed
        }
        |> Tabs.toHtml


tabHtmlId : Tab -> String
tabHtmlId tab =
    case tab of
        ErrorsTab ->
            errorsTabHtmlId

        FeaturesTab ->
            "dev-panel-features-tab"


panelHtmlId : Tab -> String
panelHtmlId tab =
    tabHtmlId tab ++ "-panel"


tabContent : List Error -> Features.Model -> Tab -> Html Msg
tabContent errors features tab =
    case tab of
        ErrorsTab ->
            errorsView errors

        FeaturesTab ->
            featuresView features


featuresView : Features.Model -> Html Msg
featuresView features =
    H.section
        [ A.id (panelHtmlId FeaturesTab)
        , A.attribute "role" "tabpanel"
        , Aria.labelledBy (tabHtmlId FeaturesTab)
        , A.css
            [ S.col
            , S.g3
            , S.minW0
            , S.overflowAuto
            ]
        ]
        [ H.p
            []
            [ H.text "features saved on this device" ]
        , H.div
            [ A.css
                [ S.col
                , S.g3
                ]
            ]
            (List.map (featureCheckbox features) Features.all)
        ]


featureCheckbox : Features.Model -> Feature -> Html Msg
featureCheckbox features feature =
    Checkbox.new
        { label = Features.label feature
        , checked = Features.enabled feature features
        , onCheck = FeatureCheckboxChanged feature
        }
        |> Checkbox.toHtml [ H.text (Features.label feature) ]


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
