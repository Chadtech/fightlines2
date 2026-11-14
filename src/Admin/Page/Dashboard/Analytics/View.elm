module Admin.Page.Dashboard.Analytics.View exposing
    ( Msg(..)
    , resultsHtmlId
    , retryHtmlId
    , view
    )

import Admin.Page.Dashboard.Analytics as Analytics exposing (Analytics)
import Admin.Page.Dashboard.Analytics.LoadedResults as LoadedResults exposing (LoadedResults)
import Admin.Page.Dashboard.Analytics.Location as Location exposing (Location)
import Admin.Page.Dashboard.Analytics.Log as Log exposing (Log)
import Admin.Page.Dashboard.Analytics.LogId exposing (LogId)
import Admin.Page.Dashboard.Analytics.QueryResults exposing (QueryResults)
import Admin.Page.Dashboard.Analytics.Record as Record exposing (Record)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Keyed as Keyed
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Divider as Divider
import View.Select as Select



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Msg
    = PageButtonClicked Location
    | LogChanged LogId


type Controls
    = Ready
    | Busy



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Analytics -> Html Msg
view analytics =
    let
        status : List (Html Msg)
        status =
            case analytics of
                Analytics.Loading _ ->
                    [ H.p
                        [ Aria.role Aria.Status ]
                        [ H.text "loading analytics…" ]
                    ]

                Analytics.Failed failure ->
                    [ H.p
                        [ Aria.role Aria.Alert
                        , A.css [ S.textYellow5 ]
                        ]
                        [ H.text failure.error ]
                    , Button.secondary
                        "retry analytics"
                        (PageButtonClicked failure.location)
                        |> Button.withHtmlId retryHtmlId
                        |> Button.toHtml
                    ]

                _ ->
                    []

        content : List (Html Msg)
        content =
            case analytics of
                Analytics.NotLoaded ->
                    [ analyticsButton
                        Ready
                        "load analytics"
                        Location.latest
                    ]

                Analytics.Loaded loaded ->
                    analyticsContents Ready (Just loaded)

                Analytics.Loading pending ->
                    analyticsContents Busy pending.previous

                Analytics.Failed failure ->
                    analyticsContents Ready failure.previous

        cardContent : List (Html Msg)
        cardContent =
            content ++ status
    in
    Card.toHtml
        (Card.simple
            |> Card.withHeader (CardHeader.simple "player analytics")
        )
        cardContent


resultsHtmlId : String
resultsHtmlId =
    "admin-analytics-results"


retryHtmlId : String
retryHtmlId =
    "admin-analytics-retry"


analyticsContents :
    Controls
    -> Maybe LoadedResults
    -> List (Html Msg)
analyticsContents controls previous =
    case previous of
        Just analytics ->
            analyticsLogControls
                controls
                (LoadedResults.results analytics)
                :: analyticsResults analytics
                :: analyticsPagination controls analytics

        Nothing ->
            []


analyticsLogControls : Controls -> QueryResults -> Html Msg
analyticsLogControls controls results =
    let
        logSelectHtmlId : String
        logSelectHtmlId =
            "admin-analytics-log"

        logOption : Log -> { value : LogId, label : String }
        logOption log =
            { value = log.id
            , label = Log.label log
            }

        logPicker : List (Html Msg)
        logPicker =
            case results.selectedLog of
                Nothing ->
                    []

                Just selected ->
                    [ H.div
                        [ A.css
                            [ S.col
                            , S.g2
                            , S.minW0
                            , S.maxWFull
                            ]
                        ]
                        [ H.label
                            [ A.for logSelectHtmlId ]
                            [ H.text "log day and server" ]
                        , Select.new
                            { selected = selected
                            , options = List.map logOption results.logs
                            , onChange = LogChanged
                            }
                            |> Select.withHtmlId logSelectHtmlId
                            |> Select.disabled (controls == Busy)
                            |> Select.toHtml
                        ]
                    ]

        refresh : Html Msg
        refresh =
            analyticsButton controls "latest events" Location.latest

        content : List (Html Msg)
        content =
            logPicker ++ refreshControls

        refreshControls : List (Html Msg)
        refreshControls =
            [ refresh ]
    in
    H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.itemsEnd
            , S.g2
            ]
        ]
        content


analyticsResults : LoadedResults -> Html Msg
analyticsResults analytics =
    let
        results : QueryResults
        results =
            LoadedResults.results analytics

        notices : List (Html Msg)
        notices =
            if results.unreadable > 0 then
                [ H.p
                    []
                    [ H.text
                        ("unreadable events on this page · "
                            ++ String.fromInt results.unreadable
                        )
                    ]
                ]

            else if List.isEmpty results.records then
                [ H.p
                    []
                    [ H.text "no analytics events on this page." ]
                ]

            else
                []

        rows : List (Html Msg)
        rows =
            results.records
                |> List.map analyticsRow
                |> List.intersperse Divider.toHtml

        content : List (Html Msg)
        content =
            notices ++ rows
    in
    Keyed.node "div"
        [ A.id resultsHtmlId
        , A.tabindex -1
        , Aria.label "analytics events"
        , Aria.role Aria.Group
        , A.css [ S.focusVisible [ S.outlineYellow5 ] ]
        ]
        [ ( LoadedResults.key analytics
          , H.div
                [ A.css
                    [ S.col
                    , S.g3
                    ]
                ]
                content
          )
        ]


analyticsPagination :
    Controls
    -> LoadedResults
    -> List (Html Msg)
analyticsPagination controls analytics =
    let
        newer : List (Html Msg)
        newer =
            pageButton "newer events" (LoadedResults.newer analytics)

        older : List (Html Msg)
        older =
            pageButton "older events" (LoadedResults.older analytics)

        pageButton : String -> Maybe Location -> List (Html Msg)
        pageButton label location =
            case location of
                Just target ->
                    [ analyticsButton controls label target ]

                Nothing ->
                    []

        content : List (Html Msg)
        content =
            newer ++ older
    in
    if List.isEmpty content then
        []

    else
        [ H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g2
                ]
            ]
            content
        ]


analyticsButton :
    Controls
    -> String
    -> Location
    -> Html Msg
analyticsButton controls label location =
    case controls of
        Ready ->
            Button.secondary label (PageButtonClicked location)
                |> Button.toHtml

        Busy ->
            Button.disabled label
                |> Button.toHtml


analyticsRow : Record -> Html Msg
analyticsRow record =
    H.details
        [ A.css [ S.wrapAnywhere ] ]
        [ H.summary
            [ A.css
                [ S.pointerCursor
                , S.textGray5
                , S.focusVisible [ S.outlineYellow5 ]
                ]
            ]
            [ H.text (Record.title record)
            , H.span
                [ A.css [ S.textGray4 ] ]
                [ H.text (" · " ++ Record.receiptLabel record) ]
            ]
        , H.pre
            [ A.css
                [ S.p3
                , S.indentStrong
                , S.bgNightwood3
                , S.whitespacePreWrap
                , S.preserveTextCase
                ]
            ]
            [ H.text record.data ]
        ]
