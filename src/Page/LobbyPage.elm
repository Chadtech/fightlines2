module Page.LobbyPage exposing
    ( Flags
    , Model
    , Msg
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
import Api.Enum.MapType
    exposing
        ( MapType
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
import ApiRequest
    exposing
        ( Response
        )
import Effect as E
    exposing
        ( Eff
        )
import Game.MapType as MapType
import Game.PlayerNumber as PlayerNumber
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
import Route
import Shared
import Style as S
import Time
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Select as Select



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { id : LobbyId
    , name : String
    , mapType : MapType
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
    , mapType : MapType
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    , selectedMapType : MapType
    , requestStatus : RequestStatus
    , refreshing : Bool
    , pollRevision : PollRevision
    , error : Maybe String
    , actionError : Maybe String
    , copyStatus : CopyStatus
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
    | MapInputChanged MapType
    | MapResponseReceived (Response Flags)
    | StartButtonClicked
    | StartMapResponseReceived (Response Flags)
    | RetryButtonClicked
    | CopyLinkButtonClicked
    | CopyLinkResultReceived CopyResult
    | CopyFeedbackElapsed
    | PollTimerElapsed Time.Posix
    | LobbyResponseReceived PollRevision (Response Flags)
    | ActionResponseReceived (Response Flags)



----------------------------------------------------------------
-- SHARED STATE --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> ( Model, Eff Msg )
init shared flags =
    ( { shared = shared
      , id = flags.id
      , name = flags.name
      , mapType = flags.mapType
      , selectedMapType = flags.mapType
      , players = flags.players
      , isHost = flags.isHost
      , isMember = flags.isMember
      , gameUrl = flags.gameUrl
      , requestStatus = Idle
      , refreshing = False
      , pollRevision = PollRevision 0
      , error = Nothing
      , actionError = Nothing
      , copyStatus = CopyIdle
      }
    , gameNavigation
        { isMember = flags.isMember
        , gameUrl = flags.gameUrl
        }
        flags.id
    )


load : LobbyId -> Graphql.Http.Request Flags
load id =
    Api.Query.lobby { id = LobbyId.toString id } flagsSelection
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


start : LobbyId -> Graphql.Http.Request Flags
start id =
    Api.Mutation.startGame { id = LobbyId.toString id } flagsSelection
        |> ApiRequest.mutationRequest


saveMap : Model -> Graphql.Http.Request Flags
saveMap model =
    Api.Mutation.setLobbyMap
        { id = LobbyId.toString model.id
        , mapType = model.selectedMapType
        }
        flagsSelection
        |> ApiRequest.mutationRequest


flagsSelection : SelectionSet Flags Api.Object.Snapshot
flagsSelection =
    SS.succeed Flags
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
                ( { updatedModel | requestStatus = ChoosingSide playerNumber }
                , Api.Mutation.setLobbySide
                    { id = LobbyId.toString model.id
                    , playerNumber = playerNumber
                    }
                    flagsSelection
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
                    flagsSelection
                    |> ApiRequest.mutationRequest
                    |> E.request ActionResponseReceived
                )

        MapInputChanged mapType ->
            if isBusy model || not model.isHost || model.gameUrl /= Nothing then
                ( model, E.none )

            else
                let
                    updatedModel : Model
                    updatedModel =
                        beginSettingsChange { model | selectedMapType = mapType }
                in
                ( updatedModel
                , E.request MapResponseReceived (saveMap updatedModel)
                )

        MapResponseReceived result ->
            case result of
                Ok flags ->
                    { model
                        | requestStatus = Idle
                        , actionError = Nothing
                    }
                        |> receive flags

                Err error ->
                    ( { model
                        | requestStatus = Idle
                        , actionError = Just (ApiRequest.errorMessage error)
                      }
                    , E.none
                    )

        StartButtonClicked ->
            let
                canStart : Bool
                canStart =
                    not (isBusy model)
                        && not model.refreshing
                        && model.isHost
                        && model.gameUrl
                        == Nothing
                        && List.length model.players
                        == 2
            in
            if not canStart then
                ( model, E.none )

            else
                ( { model
                    | requestStatus = SavingSettings
                    , actionError = Nothing
                  }
                , E.request StartMapResponseReceived (saveMap model)
                )

        StartMapResponseReceived result ->
            case result of
                Ok flags ->
                    ( { model
                        | mapType = flags.mapType
                      }
                    , E.request ActionResponseReceived (start model.id)
                    )

                Err error ->
                    ( { model
                        | requestStatus = Idle
                        , actionError = Just (ApiRequest.errorMessage error)
                      }
                    , E.none
                    )

        RetryButtonClicked ->
            refresh model

        CopyLinkButtonClicked ->
            if model.copyStatus == Copying || model.copyStatus == Copied then
                ( model, E.none )

            else
                ( { model | copyStatus = Copying }
                , E.toJs (ToJs.CopyLink { url = inviteUrl model })
                )

        CopyLinkResultReceived result ->
            if result.url /= inviteUrl model || model.copyStatus /= Copying then
                ( model, E.none )

            else if result.success then
                ( { model | copyStatus = Copied }
                , E.after 2000 CopyFeedbackElapsed
                )

            else
                ( { model | copyStatus = CopyFailed }, E.none )

        CopyFeedbackElapsed ->
            ( { model | copyStatus = CopyIdle }, E.none )

        PollTimerElapsed _ ->
            refresh model

        LobbyResponseReceived pollRevision result ->
            if pollRevision /= model.pollRevision then
                ( model, E.none )

            else
                case result of
                    Ok flags ->
                        { model
                            | refreshing = False
                        }
                            |> receive flags

                    Err error ->
                        { model
                            | refreshing = False
                            , error = Just (ApiRequest.errorMessage error)
                        }
                            |> E.withOut

        ActionResponseReceived result ->
            case result of
                Ok flags ->
                    { model
                        | requestStatus = Idle
                        , actionError = Nothing
                    }
                        |> receive flags

                Err error ->
                    ( { model
                        | requestStatus = Idle
                        , actionError = Just (ApiRequest.errorMessage error)
                      }
                    , E.none
                    )


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
    { model
        | requestStatus = SavingSettings
        , actionError = Nothing
        , refreshing = False
        , pollRevision = nextRevision model.pollRevision
    }


refresh : Model -> ( Model, Eff Msg )
refresh model =
    if model.refreshing || isBusy model then
        ( model, E.none )

    else
        ( { model
            | refreshing = True
          }
        , E.request (LobbyResponseReceived model.pollRevision) (load model.id)
        )


receive : Flags -> Model -> ( Model, Eff Msg )
receive flags model =
    ( { model
        | id = flags.id
        , name = flags.name
        , mapType = flags.mapType
        , players = flags.players
        , isHost = flags.isHost
        , isMember = flags.isMember
        , gameUrl = flags.gameUrl
        , error = Nothing
      }
    , gameNavigation
        { isMember = flags.isMember
        , gameUrl = flags.gameUrl
        }
        flags.id
    )


gameNavigation : { isMember : Bool, gameUrl : Maybe String } -> LobbyId -> Eff msg
gameNavigation args lobbyId =
    if args.isMember && args.gameUrl /= Nothing then
        E.navigate (Route.Game lobbyId)

    else
        E.none



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


inviteUrl : Model -> String
inviteUrl model =
    model.shared.origin ++ Route.toString (Route.Lobby model.id)


view : Model -> List (Html Msg)
view model =
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
        [ A.css [ S.col, S.g1 ]
        ]
        [ H.label
            [ A.for "invite-link" ]
            [ H.text "invite players" ]
        , H.div
            [ A.css [ S.row, S.g2, S.flexWrap ] ]
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
                , A.css [ S.border0, S.shrink0 ]
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
        mapOption : MapType -> { value : MapType, label : String }
        mapOption mapType =
            { value = mapType
            , label = MapType.label mapType
            }
    in
    if model.isHost && model.gameUrl == Nothing then
        H.div
            [ A.css
                [ S.col
                , S.g1
                ]
            ]
            [ H.label
                [ A.for "map-type"
                ]
                [ H.text "map"
                ]
            , Select.toHtml
                { htmlId = "map-type"
                , disabled = isBusy model
                , selected = model.selectedMapType
                , options = List.map mapOption Api.Enum.MapType.list
                , toValue = Api.Enum.MapType.toString
                , decoder = Api.Enum.MapType.decoder
                , onChange = MapInputChanged
                }
            ]

    else
        H.p
            []
            [ H.text ("map: " ++ MapType.label model.mapType)
            ]


hasJoinedHuman : Model -> Bool
hasJoinedHuman model =
    let
        isJoinedHuman : Player -> Bool
        isJoinedHuman player =
            not player.isHost && (player.controller == Human)
    in
    List.any isJoinedHuman model.players


controllerLabel : Controller -> String
controllerLabel controller =
    case controller of
        Human ->
            "human"

        Ai ->
            "ai easy"

        AiMedium ->
            "ai medium"


startControlsView : Model -> Html Msg
startControlsView model =
    let
        startButton : Html Msg
        startButton =
            if model.isHost && (model.gameUrl == Nothing) then
                H.fieldset
                    [ A.disabled (isBusy model || model.refreshing || (List.length model.players /= 2))
                    , A.css
                        [ S.border0
                        ]
                    ]
                    [ Button.primary "start game" StartButtonClicked
                        |> Button.toHtml
                    ]

            else
                H.text ""

        status : Html Msg
        status =
            if model.gameUrl /= Nothing then
                H.p
                    []
                    [ H.text "this game has started. joining is closed."
                    ]

            else if not model.isHost then
                H.p
                    []
                    [ H.text "waiting for the host to start the game…"
                    ]

            else if List.length model.players < 2 then
                H.p
                    []
                    [ H.text "waiting for another player"
                    ]

            else
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
                , Select.toHtml
                    { htmlId = "your-side"
                    , disabled = isBusy model || (model.gameUrl /= Nothing)
                    , selected = selectedSide player
                    , options = List.map option Api.Enum.PlayerNumber.list
                    , toValue = Api.Enum.PlayerNumber.toString
                    , decoder = Api.Enum.PlayerNumber.decoder
                    , onChange = SideInputChanged
                    }
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
                Select.toHtml
                    { htmlId = controllerHtmlId
                    , disabled = isBusy model || hasJoinedHuman model
                    , selected = controller
                    , options = List.map option Api.Enum.Controller.list
                    , toValue = Api.Enum.Controller.toString
                    , decoder = Api.Enum.Controller.decoder
                    , onChange = ControllerInputChanged
                    }

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
