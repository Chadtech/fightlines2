module Fightlines.Page.LobbyPage exposing
    ( Flags
    , Location(..)
    , Model
    , Msg
    , currentLocation
    , init
    , listeners
    , load
    , setShared
    , subscriptions
    , update
    , view
    )

import Api.Enum.Controller
    exposing
        ( Controller(..)
        )
import Api.Enum.PlayerNumber
    exposing
        ( PlayerNumber(..)
        )
import Api.Mutation
import Api.Object
import Api.Object.PlayerView as PlayerView
import Api.Object.Snapshot as Snapshot
import Api.Query
import Api.Scalar
    exposing
        ( MapId
        )
import ApiRequest
    exposing
        ( Response
        )
import EditableMap exposing (NamedMap)
import Effect as E
    exposing
        ( Eff
        )
import Fightlines.Route as Route
import Fightlines.Shared as Shared
import Fightlines.View.MapChoice as MapChoice
import Game.MapId as MapId
import Game.PlayerNumber as PlayerNumber
import Game.View.MapPreview as MapPreview
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Json.Decode as Decode
import LobbyId
    exposing
        ( LobbyId
        )
import Ports.Js.From as FromJs
import Ports.Js.To as ToJs
import Style as S
import Time
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Select as Select
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { lobby : Snapshot
    , mapPreviews : List NamedMap
    }


type alias Snapshot =
    { id : LobbyId
    , name : String
    , mapType : MapId
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    }


type alias Player =
    { name : String
    , isHost : Bool
    , controller : Controller
    , isYou : Bool
    , playerNumber : PlayerNumber
    }


type alias Model =
    { shared : Shared.Model
    , id : LobbyId
    , name : String
    , mapType : MapId
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    , mapPreviews : List NamedMap
    , screen : Screen
    , requestStatus : RequestStatus
    , refreshing : Bool
    , pollRevision : PollRevision
    , error : Maybe String
    , actionError : Maybe String
    , copyStatus : CopyStatus
    }


type Location
    = LobbySetup
    | MapLibrary


type Screen
    = Setup
    | Library LibraryState


type alias LibraryState =
    { preview : MapId
    , search : String
    }


{-| Polls belong to the lobby settings revision at which they were requested.
A settings change invalidates older responses without blocking the controls.
-}
type PollRevision
    = PollRevision Int


{-| A pending side choice carries its displayed value, so failed requests
restore the authoritative selection.
-}
type RequestStatus
    = Idle
    | SavingSettings
    | SavingMap
    | ChoosingSide PlayerNumber


type CopyStatus
    = CopyIdle
    | Copying
    | Copied
    | CopyFailed


type alias CopyResult =
    { url : String
    , success : Bool
    }


type Msg
    = SideInputChanged PlayerNumber
    | ControllerInputChanged Controller
    | ChooseMapButtonClicked
    | BackToLobbyButtonClicked
    | MapPreviewClicked MapId
    | MapSearchInputChanged String
    | UseMapButtonClicked
    | MapResponseReceived (Response Snapshot)
    | StartButtonClicked
    | RetryButtonClicked
    | CopyLinkButtonClicked
    | CopyLinkResultReceived CopyResult
    | CopyFeedbackElapsed
    | PollTimerElapsed Time.Posix
    | LobbyResponseReceived PollRevision (Response Snapshot)
    | ActionResponseReceived (Response Snapshot)



----------------------------------------------------------------
-- SHARED STATE --
----------------------------------------------------------------


currentLocation : Model -> Location
currentLocation model =
    case model.screen of
        Setup ->
            LobbySetup

        Library _ ->
            MapLibrary


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Location -> Shared.Model -> Flags -> ( Model, Eff Msg )
init location shared flags =
    let
        lobby : Snapshot
        lobby =
            flags.lobby

        canOpenLibrary : Bool
        canOpenLibrary =
            (location == MapLibrary) && lobby.isHost && (lobby.gameUrl == Nothing)

        mustReturnToLobby : Bool
        mustReturnToLobby =
            (location == MapLibrary) && not canOpenLibrary && (lobby.gameUrl == Nothing)

        screen : Screen
        screen =
            if canOpenLibrary then
                Library
                    { preview = lobby.mapType
                    , search = ""
                    }

            else
                Setup

        routeCorrection : Eff Msg
        routeCorrection =
            if mustReturnToLobby then
                Route.pushUrl (Route.Lobby lobby.id)

            else
                E.none

        model : Model
        model =
            { shared = shared
            , id = lobby.id
            , name = lobby.name
            , mapType = lobby.mapType
            , screen = screen
            , mapPreviews = flags.mapPreviews
            , players = lobby.players
            , isHost = lobby.isHost
            , isMember = lobby.isMember
            , gameUrl = lobby.gameUrl
            , requestStatus = Idle
            , refreshing = False
            , pollRevision = PollRevision 0
            , error = Nothing
            , actionError = Nothing
            , copyStatus = CopyIdle
            }
    in
    ( model
    , E.batch
        [ gameNavigation
            { isMember = lobby.isMember
            , gameUrl = lobby.gameUrl
            }
            lobby.id
        , routeCorrection
        ]
    )


load : LobbyId -> Graphql.Http.Request Flags
load id =
    SS.succeed Flags
        |> SS.with (Api.Query.lobby { id = LobbyId.toString id } snapshotSelection)
        |> SS.with (Api.Query.mapPreviews EditableMap.namedSelection)
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setRequestStatus : RequestStatus -> Model -> Model
setRequestStatus requestStatus model =
    { model | requestStatus = requestStatus }


setActionError : Maybe String -> Model -> Model
setActionError actionError model =
    { model | actionError = actionError }


setRefreshing : Bool -> Model -> Model
setRefreshing refreshing model =
    { model | refreshing = refreshing }


setError : Maybe String -> Model -> Model
setError error model =
    { model | error = error }


setCopyStatus : CopyStatus -> Model -> Model
setCopyStatus copyStatus model =
    { model | copyStatus = copyStatus }


start : LobbyId -> Graphql.Http.Request Snapshot
start id =
    Api.Mutation.startGame { id = LobbyId.toString id } snapshotSelection
        |> ApiRequest.mutationRequest


saveMap : LobbyId -> MapId -> Graphql.Http.Request Snapshot
saveMap id mapType =
    Api.Mutation.setLobbyMap
        { id = LobbyId.toString id
        , mapType = mapType
        }
        snapshotSelection
        |> ApiRequest.mutationRequest


snapshotSelection : SelectionSet Snapshot Api.Object.Snapshot
snapshotSelection =
    SS.succeed Snapshot
        |> SS.with (Snapshot.id |> SS.mapOrFail LobbyId.parse)
        |> SS.with Snapshot.name
        |> SS.with Snapshot.mapType
        |> SS.with
            (Snapshot.players
                (SS.succeed Player
                    |> SS.with PlayerView.name
                    |> SS.with PlayerView.isHost
                    |> SS.with PlayerView.controller
                    |> SS.with PlayerView.isYou
                    |> SS.with PlayerView.playerNumber
                )
            )
        |> SS.with Snapshot.isHost
        |> SS.with Snapshot.isMember
        |> SS.with Snapshot.gameUrl


isMap : MapId -> NamedMap -> Bool
isMap mapType map =
    map.mapType == mapType


mapDimensions : NamedMap -> String
mapDimensions map =
    String.fromInt map.definition.width
        ++ " × "
        ++ String.fromInt map.definition.height


hasJoinedHuman : Model -> Bool
hasJoinedHuman model =
    let
        isJoinedHuman : Player -> Bool
        isJoinedHuman player =
            not player.isHost && (player.controller == Human)
    in
    List.any isJoinedHuman model.players


canChooseMap : Model -> Bool
canChooseMap model =
    not (isBusy model) && model.isHost && (model.gameUrl == Nothing)


startGameBlockedReason : Model -> Maybe String
startGameBlockedReason model =
    if model.gameUrl /= Nothing then
        Just "this game has started. joining is closed."

    else if not model.isHost then
        Just "waiting for the host to start the game…"

    else if List.length model.players < 2 then
        Just "waiting for another player"

    else if List.length model.players /= 2 then
        Just "this game requires exactly two players"

    else if isBusy model then
        Just "waiting for the current request to finish…"

    else if model.refreshing then
        Just "updating lobby…"

    else
        Nothing


isBusy : Model -> Bool
isBusy model =
    model.requestStatus /= Idle


beginSettingsChange : Model -> Model
beginSettingsChange model =
    let
        nextRevision : PollRevision -> PollRevision
        nextRevision (PollRevision revision) =
            PollRevision (revision + 1)
    in
    { model | pollRevision = nextRevision model.pollRevision }
        |> setRequestStatus SavingSettings
        |> setActionError Nothing
        |> setRefreshing False


refresh : Model -> ( Model, Eff Msg )
refresh model =
    if model.refreshing || isBusy model then
        ( model, E.none )

    else
        ( model
            |> setRefreshing True
        , E.request (LobbyResponseReceived model.pollRevision)
            (Api.Query.lobby
                { id = LobbyId.toString model.id
                }
                snapshotSelection
                |> ApiRequest.queryRequest
            )
        )


receive : Snapshot -> Model -> ( Model, Eff Msg )
receive snapshot model =
    ( { model | id = snapshot.id, name = snapshot.name, mapType = snapshot.mapType, players = snapshot.players, isHost = snapshot.isHost, isMember = snapshot.isMember, gameUrl = snapshot.gameUrl }
        |> setError Nothing
    , gameNavigation
        { isMember = snapshot.isMember
        , gameUrl = snapshot.gameUrl
        }
        snapshot.id
    )


gameNavigation :
    { isMember : Bool
    , gameUrl : Maybe String
    }
    -> LobbyId
    -> Eff msg
gameNavigation args lobbyId =
    if args.isMember && args.gameUrl /= Nothing then
        Route.pushUrl (Route.Game lobbyId)

    else
        E.none


inviteUrl : Model -> String
inviteUrl model =
    model.shared.origin ++ Route.toString (Route.Lobby model.id)



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        SideInputChanged playerNumber ->
            let
                canChooseSide : Bool
                canChooseSide =
                    not (isBusy model)
                        && model.isMember
                        && (model.gameUrl == Nothing)
                        && List.any .isYou model.players

                isSelectedSide : Player -> Bool
                isSelectedSide player =
                    player.isYou && (player.playerNumber == playerNumber)

                alreadySelected : Bool
                alreadySelected =
                    List.any isSelectedSide model.players
            in
            if not canChooseSide || alreadySelected then
                ( model, E.none )

            else
                let
                    updatedModel : Model
                    updatedModel =
                        beginSettingsChange model
                in
                ( updatedModel
                    |> setRequestStatus (ChoosingSide playerNumber)
                , Api.Mutation.setLobbySide
                    { id = LobbyId.toString model.id
                    , playerNumber = playerNumber
                    }
                    snapshotSelection
                    |> ApiRequest.mutationRequest
                    |> E.request ActionResponseReceived
                )

        ControllerInputChanged controller ->
            let
                canChangeController : Bool
                canChangeController =
                    not (isBusy model)
                        && model.isHost
                        && (model.gameUrl == Nothing)
                        && not (hasJoinedHuman model)
            in
            if not canChangeController then
                ( model, E.none )

            else
                ( beginSettingsChange model
                , Api.Mutation.setLobbyController
                    { id = LobbyId.toString model.id
                    , controller = controller
                    }
                    snapshotSelection
                    |> ApiRequest.mutationRequest
                    |> E.request ActionResponseReceived
                )

        ChooseMapButtonClicked ->
            if not (canChooseMap model) then
                ( model, E.none )

            else
                ( model, Route.pushUrl (Route.LobbyMaps model.id) )

        BackToLobbyButtonClicked ->
            ( model, Route.pushUrl (Route.Lobby model.id) )

        MapSearchInputChanged search ->
            case model.screen of
                Library library ->
                    ( { model | screen = Library { library | search = search } }
                    , E.none
                    )

                Setup ->
                    ( model, E.none )

        MapPreviewClicked mapType ->
            case model.screen of
                Library library ->
                    if List.any (isMap mapType) model.mapPreviews then
                        ( { model
                            | screen =
                                Library
                                    { library
                                        | preview = mapType
                                    }
                          }
                        , E.none
                        )

                    else
                        ( model, E.none )

                Setup ->
                    ( model, E.none )

        UseMapButtonClicked ->
            case model.screen of
                Library library ->
                    if not (canChooseMap model) then
                        ( model, E.none )

                    else
                        let
                            updatedModel : Model
                            updatedModel =
                                beginSettingsChange model
                        in
                        ( updatedModel
                            |> setRequestStatus SavingMap
                        , E.request MapResponseReceived (saveMap model.id library.preview)
                        )

                Setup ->
                    ( model, E.none )

        MapResponseReceived result ->
            if model.requestStatus /= SavingMap then
                ( model, E.none )

            else
                case result of
                    Ok snapshot ->
                        let
                            returnToLobby : Eff Msg
                            returnToLobby =
                                if snapshot.gameUrl == Nothing then
                                    Route.pushUrl (Route.Lobby model.id)

                                else
                                    E.none
                        in
                        (model
                            |> setRequestStatus Idle
                            |> setActionError Nothing
                        )
                            |> receive snapshot
                            |> E.and returnToLobby

                    Err error ->
                        ( model
                            |> setRequestStatus Idle
                            |> setActionError (Just (ApiRequest.errorMessage error))
                        , E.none
                        )

        StartButtonClicked ->
            if startGameBlockedReason model /= Nothing then
                ( model, E.none )

            else
                ( model
                    |> setRequestStatus SavingSettings
                    |> setActionError Nothing
                , E.request ActionResponseReceived (start model.id)
                )

        RetryButtonClicked ->
            refresh model

        CopyLinkButtonClicked ->
            if model.copyStatus == Copying || model.copyStatus == Copied then
                ( model, E.none )

            else
                ( model
                    |> setCopyStatus Copying
                , E.toJs (ToJs.CopyLink { url = inviteUrl model })
                )

        CopyLinkResultReceived result ->
            if result.url /= inviteUrl model || model.copyStatus /= Copying then
                ( model, E.none )

            else if result.success then
                ( model
                    |> setCopyStatus Copied
                , E.after 2000 CopyFeedbackElapsed
                )

            else
                ( model
                    |> setCopyStatus CopyFailed
                , E.none
                )

        CopyFeedbackElapsed ->
            ( model
                |> setCopyStatus CopyIdle
            , E.none
            )

        PollTimerElapsed _ ->
            refresh model

        LobbyResponseReceived pollRevision result ->
            if pollRevision /= model.pollRevision then
                ( model, E.none )

            else
                case result of
                    Ok snapshot ->
                        (model
                            |> setRefreshing False
                        )
                            |> receive snapshot

                    Err error ->
                        (model
                            |> setRefreshing False
                            |> setError (Just (ApiRequest.errorMessage error))
                        )
                            |> E.withOut

        ActionResponseReceived result ->
            case result of
                Ok snapshot ->
                    (model
                        |> setRequestStatus Idle
                        |> setActionError Nothing
                    )
                        |> receive snapshot

                Err error ->
                    ( model
                        |> setRequestStatus Idle
                        |> setActionError (Just (ApiRequest.errorMessage error))
                    , E.none
                    )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    case model.screen of
        Setup ->
            lobbyView model

        Library library ->
            [ libraryView model library ]


libraryView : Model -> LibraryState -> Html Msg
libraryView model library =
    let
        search : String
        search =
            String.trim library.search |> String.toLower

        matchesSearch : NamedMap -> Bool
        matchesSearch map =
            String.contains search
                (String.toLower (MapId.label map.mapType ++ " " ++ map.definition.description))

        matchingMaps : List NamedMap
        matchingMaps =
            List.filter matchesSearch model.mapPreviews

        choices : List (Html Msg)
        choices =
            if List.isEmpty matchingMaps then
                [ H.p
                    [ Aria.role Aria.Status
                    , A.css
                        [ S.p2
                        ]
                    ]
                    [ H.text "no maps match your search."
                    ]
                ]

            else
                List.map choice matchingMaps

        choice : NamedMap -> Html Msg
        choice map =
            MapChoice.toHtml
                { map = map
                , selected = map.mapType == library.preview
                , onSelect = MapPreviewClicked map.mapType
                }

        preview : Html Msg
        preview =
            case List.filter (isMap library.preview) model.mapPreviews |> List.head of
                Just map ->
                    mapDetailsView map

                Nothing ->
                    H.p
                        [ Aria.role Aria.Alert
                        ]
                        [ H.text "this map preview is unavailable. choose another map."
                        ]

        saveFeedback : Maybe String
        saveFeedback =
            if model.requestStatus == SavingMap then
                Just "saving…"

            else
                Nothing

        actionError : Html Msg
        actionError =
            case model.actionError of
                Just error ->
                    H.p
                        [ Aria.role Aria.Alert
                        ]
                        [ H.text error
                        ]

                Nothing ->
                    H.text ""

        pollError : Html Msg
        pollError =
            case model.error of
                Just error ->
                    H.div
                        [ A.css
                            [ S.col
                            , S.g2
                            ]
                        ]
                        [ H.p
                            [ Aria.role Aria.Status
                            ]
                            [ H.text error
                            ]
                        , Button.secondary "retry" RetryButtonClicked
                            |> Button.toHtml
                        ]

                Nothing ->
                    H.text ""
    in
    Card.toHtml
        (Card.simple
            |> Card.withHeader
                (CardHeader.simple "choose map"
                    |> CardHeader.withCaption model.name
                )
        )
        [ H.div
            [ A.css
                [ S.row
                , S.itemsStart
                , S.g4
                , S.belowWidth 720
                    [ S.col
                    ]
                ]
            ]
            [ H.div
                [ A.css
                    [ S.w72
                    , S.maxWFull
                    , S.shrink0
                    , S.col
                    , S.g3
                    , S.belowWidth 720
                        [ S.wFull
                        ]
                    ]
                ]
                [ H.label
                    [ A.css
                        [ S.col
                        , S.g1
                        ]
                    ]
                    [ H.text "search maps"
                    , TextField.simple library.search MapSearchInputChanged
                        |> TextField.toHtml
                    ]
                , H.div
                    [ A.css
                        [ S.col
                        , S.bgNightwood3
                        , S.indentStrong
                        , S.p2px
                        , S.maxHViewportInsetRem 16
                        , S.overflowAuto
                        ]
                    ]
                    choices
                ]
            , H.div
                [ A.css
                    [ S.flex1
                    , S.minW0
                    , S.wFull
                    ]
                ]
                [ preview
                ]
            ]
        , pollError
        , actionError
        , H.div
            [ A.css
                [ S.row
                , S.itemsCenter
                , S.flexWrap
                , S.g3
                , S.pt3
                ]
            ]
            [ H.fieldset
                [ A.disabled (isBusy model || not model.isHost || (model.gameUrl /= Nothing))
                , A.css
                    [ S.border0
                    ]
                ]
                [ Button.primary "use this map" UseMapButtonClicked
                    |> Button.withFeedback saveFeedback
                    |> Button.toHtml
                ]
            , Button.secondary "back to lobby" BackToLobbyButtonClicked
                |> Button.toHtml
            ]
        ]


mapDetailsView : NamedMap -> Html Msg
mapDetailsView map =
    H.section
        [ Aria.label "map details"
        , A.css
            [ S.grid
            , S.gridColumns "minmax(0, 1.2fr) minmax(0, 1fr)"
            , S.itemsStart
            , S.g4
            , S.belowWidth 1100
                [ S.gridCols1
                ]
            ]
        ]
        [ H.div
            [ A.css
                [ S.wFull
                , S.bgNightwood2
                , S.indentStrong
                , S.p3
                ]
            ]
            [ H.div
                [ A.css
                    [ S.wFull
                    , S.aspectRatio
                        { width = map.definition.width
                        , height = map.definition.height
                        }
                    ]
                ]
                [ MapPreview.toHtml map
                ]
            ]
        , H.div
            [ A.css
                [ S.col
                , S.g3
                , S.minW0
                ]
            ]
            [ H.h2
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text (MapId.label map.mapType)
                ]
            , H.p
                [ A.css
                    [ S.textGray4
                    ]
                ]
                [ H.text (mapDimensions map)
                ]
            , H.p
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.flexWrap
                    , S.g2
                    , S.textGray4
                    ]
                ]
                [ H.text "starting forces:"
                , H.span
                    [ A.css
                        [ S.textRed1
                        ]
                    ]
                    [ H.text "player 1 (red)"
                    ]
                , H.span
                    [ A.css
                        [ S.textBlue1
                        ]
                    ]
                    [ H.text "player 2 (blue)"
                    ]
                ]
            , H.p
                [ A.css
                    [ S.borderT
                    , S.borderGray2
                    , S.pt3
                    , S.textGray5
                    ]
                ]
                [ H.text map.definition.description
                ]
            ]
        ]


lobbyView : Model -> List (Html Msg)
lobbyView model =
    [ H.div
        [ A.css
            [ S.row
            , S.itemsStart
            , S.g4
            , S.wFull
            , S.belowWidth 720
                [ S.col
                ]
            ]
        ]
        [ H.div
            [ A.css
                [ S.widthPct 44
                , S.minW0
                , S.belowWidth 720
                    [ S.wFull
                    ]
                ]
            ]
            [ settingsView model
            ]
        , H.div
            [ A.css
                [ S.flex1
                , S.minW0
                , S.belowWidth 720
                    [ S.wFull
                    ]
                ]
            ]
            [ playersView model
            ]
        ]
    ]


settingsView : Model -> Html Msg
settingsView model =
    let
        notice : String
        notice =
            [ model.error
            , model.actionError
            ]
                |> List.filterMap identity
                |> String.join " "
                |> String.trim

        errorNotice : Html Msg
        errorNotice =
            if String.isEmpty notice then
                H.text ""

            else
                H.p
                    [ Aria.role Aria.Status
                    ]
                    [ H.text notice
                    ]

        retryControl : Html Msg
        retryControl =
            case model.error of
                Just _ ->
                    H.fieldset
                        [ A.disabled (isBusy model || model.refreshing)
                        , A.css
                            [ S.border0
                            ]
                        ]
                        [ Button.secondary "retry" RetryButtonClicked
                            |> Button.toHtml
                        ]

                Nothing ->
                    H.text ""
    in
    [ mapView model
    , inviteView model
    , startControlsView model
    , errorNotice
    , retryControl
    ]
        |> Card.toHtml
            (Card.simple
                |> Card.withHeader
                    (CardHeader.simple model.name
                        |> CardHeader.withCaption "game lobby"
                    )
            )


inviteView : Model -> Html Msg
inviteView model =
    let
        copyFeedback : Maybe String
        copyFeedback =
            case model.copyStatus of
                Copied ->
                    Just "copied"

                _ ->
                    Nothing

        copyError : Html Msg
        copyError =
            case model.copyStatus of
                CopyFailed ->
                    H.p
                        [ Aria.role Aria.Alert
                        ]
                        [ H.text "could not copy. select the link and copy it manually."
                        ]

                _ ->
                    H.text ""
    in
    H.div
        [ A.css
            [ S.col
            , S.g1
            ]
        ]
        [ H.label
            [ A.for "invite-link"
            ]
            [ H.text "invite players"
            ]
        , H.div
            [ A.css
                [ S.row
                , S.g2
                , S.flexWrap
                ]
            ]
            [ H.input
                [ A.id "invite-link"
                , A.type_ "text"
                , A.value (inviteUrl model)
                , A.readonly True
                , A.css
                    [ S.flex1
                    , S.minW0
                    , S.minW40
                    , S.maxWFull
                    , S.p2
                    , S.indentStrong
                    , S.bgNightwood3
                    , S.textGray5
                    ]
                ]
                []
            , H.fieldset
                [ A.disabled (model.copyStatus == Copying || model.copyStatus == Copied)
                , A.css
                    [ S.border0
                    , S.shrink0
                    ]
                ]
                [ Button.secondary "copy link" CopyLinkButtonClicked
                    |> Button.withFeedback copyFeedback
                    |> Button.toHtml
                ]
            ]
        , copyError
        ]


mapView : Model -> Html Msg
mapView model =
    let
        chooseButton : Html Msg
        chooseButton =
            if model.isHost && (model.gameUrl == Nothing) then
                H.fieldset
                    [ A.disabled (isBusy model)
                    , A.css
                        [ S.border0
                        ]
                    ]
                    [ Button.secondary "choose map" ChooseMapButtonClicked
                        |> Button.toHtml
                    ]

            else
                H.text ""

        preview : Html Msg
        preview =
            case List.filter (isMap model.mapType) model.mapPreviews |> List.head of
                Just map ->
                    H.div
                        [ A.css
                            [ S.h64
                            , S.wFull
                            , S.bgNightwood2
                            , S.indentStrong
                            , S.p2
                            ]
                        ]
                        [ MapPreview.toHtml map
                        ]

                Nothing ->
                    H.text ""
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ H.p
            []
            [ H.text ("map: " ++ MapId.label model.mapType)
            ]
        , preview
        , chooseButton
        ]


controllerLabel : Controller -> String
controllerLabel controller =
    case controller of
        Human ->
            "human"

        Ai ->
            "ai"


startControlsView : Model -> Html Msg
startControlsView model =
    let
        blockedReason : Maybe String
        blockedReason =
            startGameBlockedReason model

        startControl : Button.Button Msg
        startControl =
            case blockedReason of
                Nothing ->
                    Button.primary "start game" StartButtonClicked

                Just reason ->
                    Button.disabled "start game"
                        |> Button.accessibleLabel ("start game: " ++ reason)

        startButton : Html Msg
        startButton =
            if model.isHost && (model.gameUrl == Nothing) then
                startControl
                    |> Button.toHtml

            else
                H.text ""

        status : Html Msg
        status =
            case blockedReason of
                Just reason ->
                    H.p
                        []
                        [ H.text reason
                        ]

                Nothing ->
                    H.text ""
    in
    H.div
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.flexWrap
            , S.g3
            ]
        ]
        [ startButton
        , status
        ]


playersView : Model -> Html Msg
playersView model =
    [ sideView model
    , H.p
        []
        [ H.text (String.fromInt (List.length model.players) ++ " / 2 players")
        ]
    , H.ul
        [ A.css
            [ S.col
            , S.g3
            , S.listNone
            ]
        ]
        (List.map (playerSlotView model) Api.Enum.PlayerNumber.list)
    ]
        |> Card.toHtml
            (Card.simple
                |> Card.withHeader (CardHeader.simple "players")
            )


sideLabel : PlayerNumber -> String
sideLabel playerNumber =
    let
        color : String
        color =
            case playerNumber of
                Player1 ->
                    "red"

                Player2 ->
                    "blue"
    in
    PlayerNumber.label playerNumber ++ " (" ++ color ++ ")"


sideView : Model -> Html Msg
sideView model =
    let
        ownPlayer : Maybe Player
        ownPlayer =
            List.filter .isYou model.players |> List.head

        selectedSide : Player -> PlayerNumber
        selectedSide player =
            case model.requestStatus of
                ChoosingSide playerNumber ->
                    playerNumber

                _ ->
                    player.playerNumber

        option : PlayerNumber -> { value : PlayerNumber, label : String }
        option playerNumber =
            { value = playerNumber
            , label = sideLabel playerNumber
            }
    in
    case ownPlayer of
        Just player ->
            H.div
                [ A.css
                    [ S.col
                    , S.g1
                    ]
                ]
                [ H.label
                    [ A.for "your-side"
                    ]
                    [ H.text "your side"
                    ]
                , Select.new
                    { selected = selectedSide player
                    , options = List.map option Api.Enum.PlayerNumber.list
                    , onChange = SideInputChanged
                    }
                    |> Select.withHtmlId "your-side"
                    |> Select.disabled (isBusy model || (model.gameUrl /= Nothing))
                    |> Select.toHtml
                , H.p
                    []
                    [ H.text "switching sides also moves the other player."
                    ]
                ]

        Nothing ->
            H.text ""


playerSlotView : Model -> PlayerNumber -> Html Msg
playerSlotView model playerNumber =
    let
        belongsToSlot : Player -> Bool
        belongsToSlot player =
            player.playerNumber == playerNumber

        occupant : Maybe Player
        occupant =
            model.players
                |> List.filter belongsToSlot
                |> List.head

        controller : Controller
        controller =
            occupant
                |> Maybe.map .controller
                |> Maybe.withDefault Human

        canConfigure : Bool
        canConfigure =
            model.isHost && (model.gameUrl == Nothing) && (Maybe.map .isHost occupant /= Just True)

        controllerHtmlId : String
        controllerHtmlId =
            "slot-controller-" ++ Api.Enum.PlayerNumber.toString playerNumber

        slotLabel : String
        slotLabel =
            sideLabel playerNumber

        label : Html Msg
        label =
            if canConfigure then
                H.label
                    [ A.for controllerHtmlId
                    ]
                    [ H.text slotLabel
                    ]

            else
                H.span
                    []
                    [ H.text slotLabel
                    ]

        occupantName : String
        occupantName =
            case occupant of
                Just player ->
                    let
                        role : String
                        role =
                            if player.isHost && player.isYou then
                                " (you, host)"

                            else if player.isHost then
                                " (host)"

                            else if player.isYou then
                                " (you)"

                            else
                                ""
                    in
                    player.name ++ role

                Nothing ->
                    "waiting for player"

        option : Controller -> { value : Controller, label : String }
        option choice =
            { value = choice
            , label = controllerLabel choice
            }

        control : Html Msg
        control =
            if canConfigure then
                Select.new
                    { selected = controller
                    , options = List.map option Api.Enum.Controller.list
                    , onChange = ControllerInputChanged
                    }
                    |> Select.withHtmlId controllerHtmlId
                    |> Select.disabled (isBusy model || hasJoinedHuman model)
                    |> Select.toHtml

            else
                H.span
                    []
                    [ H.text (controllerLabel controller)
                    ]

        controlTitle : String
        controlTitle =
            if canConfigure && hasJoinedHuman model then
                "a joined human cannot be replaced"

            else
                ""
    in
    H.li
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.g3
            , S.py2
            , S.when (playerNumber /= Player1)
                (S.batch
                    [ S.borderT
                    , S.borderGray2
                    , S.pt4
                    ]
                )
            ]
        ]
        [ H.div
            [ A.css
                [ S.col
                , S.g1
                , S.flex1
                , S.minW0
                , S.wrapAnywhere
                ]
            ]
            [ label
            , H.span
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text occupantName
                ]
            ]
        , H.div
            [ A.title controlTitle
            , A.css
                [ S.w32
                , S.shrink0
                ]
            ]
            [ control
            ]
        ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 2000 PollTimerElapsed


listeners : FromJs.Listener Msg
listeners =
    FromJs.data "copyLinkResult"
        (Decode.map2 CopyResult
            (Decode.field "url" Decode.string)
            (Decode.field "success" Decode.bool)
        )
        CopyLinkResultReceived
