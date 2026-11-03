module View.Tabs exposing
    ( Tabs
    , new
    , panel
    , toHtml
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import NonEmptyList exposing (NonEmpty)
import Style as S
import View.Aria as Aria



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
    Tabs config



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


toHtml : Tabs value msg -> Html msg
toHtml ((Tabs config) as tabs) =
    H.nav
        [ A.attribute "role" "tablist"
        , Aria.label config.label
        , A.attribute "aria-orientation" "vertical"
        , A.css
            [ S.col
            , S.g2
            ]
        ]
        (config.options
            |> NonEmptyList.toList
            |> List.map (tabButton tabs)
        )


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

        navigationDecoder : Decode.Decoder ( msg, Bool )
        navigationDecoder =
            Decode.field "key" Decode.string
                |> Decode.andThen decodeNavigation

        decodeNavigation : String -> Decode.Decoder ( msg, Bool )
        decodeNavigation key =
            case key of
                "ArrowDown" ->
                    Decode.succeed ( config.onNavigate (nextTab option.value values), True )

                "ArrowUp" ->
                    Decode.succeed ( config.onNavigate (nextTab option.value (NonEmptyList.reverse values)), True )

                "Home" ->
                    Decode.succeed ( config.onNavigate (NonEmptyList.head values), True )

                "End" ->
                    Decode.succeed ( config.onNavigate (NonEmptyList.last values), True )

                _ ->
                    Decode.fail "not a tab navigation key"
    in
    H.button
        [ A.type_ "button"
        , A.id (config.htmlId option.value)
        , A.tabindex tabIndex
        , A.attribute "role" "tab"
        , A.attribute "aria-selected" selectedText
        , A.attribute "aria-controls" (panelHtmlId (config.htmlId option.value))
        , Ev.onClick (config.onClick option.value)
        , Ev.preventDefaultOn "keydown" navigationDecoder
        , A.css
            [ S.wFull
            , S.p3
            , S.textLeft
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
