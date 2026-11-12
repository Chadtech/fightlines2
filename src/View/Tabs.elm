module View.Tabs exposing
    ( Tabs
    , helpButtonHtmlId
    , horizontal
    , new
    , panel
    , toHeader
    , toHtml
    , withAccessibleLabel
    , withHelp
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import NonEmptyList exposing (NonEmpty)
import Style as S
import Util.List as ListUtil
import View.Aria as Aria
import View.InfoMarker as InfoMarker



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Tabs value msg
    = Tabs
        { label : String
        , selected : value
        , options : NonEmpty (Option value)
        , htmlId : value -> String
        , onClick : value -> msg
        , onNavigate : value -> msg
        , orientation : Orientation
        , accessibleLabel : Option value -> String
        , help : List (Help value msg)
        }


type alias Help value msg =
    { tab : value
    , label : String
    , onClick : msg
    }


type Orientation
    = Vertical
    | Horizontal


type alias KeyEvent msg =
    { message : msg
    , stopPropagation : Bool
    , preventDefault : Bool
    }


type alias Option value =
    { value : value
    , label : String
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


nextTab : value -> NonEmpty value -> value
nextTab current options =
    let
        first : value
        first =
            NonEmptyList.head options

        afterCurrent : List value -> value
        afterCurrent remaining =
            case remaining of
                [] ->
                    first

                value :: rest ->
                    if value == current then
                        List.head rest |> Maybe.withDefault first

                    else
                        afterCurrent rest
    in
    afterCurrent (NonEmptyList.toList options)


panelHtmlId : String -> String
panelHtmlId tabHtmlId =
    tabHtmlId ++ "-panel"



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Vertical tabs with caller-owned selection and focus effects. Options must
contain the selected value and have distinct values and HTML IDs. Keyboard
navigation emits its own event so the caller can move focus to the selected tab.
-}
new :
    { label : String
    , selected : value
    , options : NonEmpty (Option value)
    , htmlId : value -> String
    , onClick : value -> msg
    , onNavigate : value -> msg
    }
    -> Tabs value msg
new config =
    Tabs
        { label = config.label
        , selected = config.selected
        , options = config.options
        , htmlId = config.htmlId
        , onClick = config.onClick
        , onNavigate = config.onNavigate
        , orientation = Vertical
        , accessibleLabel = .label
        , help = []
        }


horizontal : Tabs value msg -> Tabs value msg
horizontal (Tabs config) =
    Tabs { config | orientation = Horizontal }


withAccessibleLabel :
    value
    -> String
    -> Tabs value msg
    -> Tabs value msg
withAccessibleLabel value label (Tabs config) =
    let
        accessibleLabel : Option value -> String
        accessibleLabel option =
            if option.value == value then
                label

            else
                config.accessibleLabel option
    in
    Tabs { config | accessibleLabel = accessibleLabel }


helpButtonHtmlId : String -> String
helpButtonHtmlId tabHtmlId =
    tabHtmlId ++ "-help"


{-| Add a separate help button beside a tab label, within the same visual area.
The help button remains available regardless of which tab is selected.
-}
withHelp : Help value msg -> Tabs value msg -> Tabs value msg
withHelp help (Tabs config) =
    Tabs { config | help = help :: config.help }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


{-| Inset horizontal tabs on the panel's own surface.
-}
toHeader : Tabs value msg -> Html msg
toHeader tabs =
    H.div
        [ A.css
            [ S.shrink0
            , S.p2
            ]
        ]
        [ toHtml tabs
        ]


toHtml : Tabs value msg -> Html msg
toHtml ((Tabs config) as tabs) =
    let
        orientation : String
        orientation =
            case config.orientation of
                Vertical ->
                    "vertical"

                Horizontal ->
                    "horizontal"

        layout : Css.Style
        layout =
            case config.orientation of
                Vertical ->
                    S.col

                Horizontal ->
                    S.row
    in
    H.nav
        [ A.attribute "role" "tablist"
        , Aria.label config.label
        , A.attribute "aria-orientation" orientation
        , A.css
            [ layout
            , S.minW0
            , S.g2
            ]
        ]
        (config.options
            |> NonEmptyList.toList
            |> List.map (tabView tabs)
        )


tabView : Tabs value msg -> Option value -> Html msg
tabView ((Tabs config) as tabs) option =
    let
        belongsToTab : Help value msg -> Bool
        belongsToTab help =
            help.tab == option.value

        selected : Bool
        selected =
            config.selected == option.value

        group : List (Html msg) -> Html msg
        group content =
            H.div
                [ A.attribute "role" "presentation"
                , A.css
                    [ S.row
                    , S.itemsStretch
                    , S.minW0
                    , S.flex1
                    , S.when selected S.bgYellow2
                    ]
                ]
                content
    in
    case ListUtil.find belongsToTab config.help of
        Nothing ->
            case config.orientation of
                Vertical ->
                    tabButton tabs option

                Horizontal ->
                    group [ tabButton tabs option ]

        Just help ->
            group
                [ tabButton tabs option
                , helpButton (config.htmlId option.value) selected help
                ]


helpButton : String -> Bool -> Help value msg -> Html msg
helpButton tabHtmlId selected help =
    let
        activation : Decode.Decoder (KeyEvent msg)
        activation =
            Decode.field "key" Decode.string
                |> Decode.andThen activate

        activate : String -> Decode.Decoder (KeyEvent msg)
        activate key =
            if (key == "Enter") || (key == " ") then
                Decode.succeed
                    { message = help.onClick
                    , stopPropagation = True
                    , preventDefault = True
                    }

            else
                Decode.fail "not a help activation key"
    in
    H.button
        [ A.type_ "button"
        , A.id (helpButtonHtmlId tabHtmlId)
        , Aria.label help.label
        , A.attribute "aria-haspopup" "dialog"
        , Ev.onClick help.onClick
        , Ev.custom "keydown" activation
        , A.css
            [ S.row
            , S.itemsCenter
            , S.justifyCenter
            , S.shrink0
            , S.w11
            , S.minH11
            , S.p0
            , S.border0
            , S.bgTransparent
            , S.textGray4
            , S.pointerCursor
            , S.hover
                [ S.bgGray2
                , S.textGray5
                ]
            , S.when selected
                (S.batch
                    [ S.textYellow5
                    , S.hover
                        [ S.bgYellow2
                        , S.textYellow6
                        ]
                    ]
                )
            ]
        ]
        [ InfoMarker.toHtml ]


tabButton : Tabs value msg -> Option value -> Html msg
tabButton (Tabs config) option =
    let
        isSelected : Bool
        isSelected =
            config.selected == option.value

        selectedText : String
        selectedText =
            if isSelected then
                "true"

            else
                "false"

        tabIndex : Int
        tabIndex =
            if isSelected then
                0

            else
                -1

        values : NonEmpty value
        values =
            NonEmptyList.map .value config.options

        navigationDecoder : Decode.Decoder msg
        navigationDecoder =
            Decode.field "key" Decode.string
                |> Decode.andThen decodeNavigation

        navigate :
            Orientation
            -> NonEmpty value
            -> Decode.Decoder msg
        navigate orientation options =
            if config.orientation == orientation then
                Decode.succeed
                    (config.onNavigate (nextTab option.value options))

            else
                Decode.fail "not this tab orientation"

        navigationEvent : Decode.Decoder (KeyEvent msg)
        navigationEvent =
            Decode.map handledNavigation navigationDecoder

        handledNavigation : msg -> KeyEvent msg
        handledNavigation message =
            { message = message
            , stopPropagation = True
            , preventDefault = True
            }

        decodeNavigation : String -> Decode.Decoder msg
        decodeNavigation key =
            case key of
                "ArrowDown" ->
                    navigate Vertical values

                "ArrowUp" ->
                    navigate Vertical (NonEmptyList.reverse values)

                "ArrowRight" ->
                    navigate Horizontal values

                "ArrowLeft" ->
                    navigate Horizontal (NonEmptyList.reverse values)

                "Enter" ->
                    Decode.succeed (config.onNavigate option.value)

                " " ->
                    Decode.succeed (config.onNavigate option.value)

                "Home" ->
                    Decode.succeed
                        (config.onNavigate (NonEmptyList.head values))

                "End" ->
                    Decode.succeed
                        (config.onNavigate (NonEmptyList.last values))

                _ ->
                    Decode.fail "not a tab navigation key"
    in
    H.button
        [ A.type_ "button"
        , A.id (config.htmlId option.value)
        , A.tabindex tabIndex
        , A.attribute "role" "tab"
        , Aria.label (config.accessibleLabel option)
        , A.attribute "aria-selected" selectedText
        , A.attribute "aria-controls" (panelHtmlId (config.htmlId option.value))
        , Ev.onClick (config.onClick option.value)
        , Ev.custom "keydown" navigationEvent
        , A.css
            [ S.wFull
            , S.minW0
            , S.p3
            , S.textLeft
            , S.when (config.orientation == Horizontal)
                (S.batch
                    [ S.p2
                    , S.textAlignCenter
                    , S.flex1
                    ]
                )
            , S.pointerCursor
            , S.bgTransparent
            , S.textGray4
            , S.border0
            , S.hover
                [ S.bgGray2
                , S.textGray5
                ]
            , S.when isSelected
                (S.batch
                    [ S.bgYellow2
                    , S.textYellow5
                    , S.hover
                        [ S.bgYellow2
                        , S.textYellow5
                        ]
                    ]
                )
            ]
        ]
        [ H.text option.label
        ]


{-| Keep inactive content mounted but hidden, linking each panel to its tab.
The caller owns content spacing and layout.
-}
panel : Tabs value msg -> value -> List (Html msg) -> Html msg
panel (Tabs config) value content =
    let
        isHidden : Bool
        isHidden =
            config.selected /= value
    in
    H.section
        [ A.id (panelHtmlId (config.htmlId value))
        , A.attribute "role" "tabpanel"
        , Aria.labelledBy (config.htmlId value)
        , A.hidden isHidden
        , A.css
            [ S.minW0
            , S.when isHidden S.displayNone
            ]
        ]
        content
