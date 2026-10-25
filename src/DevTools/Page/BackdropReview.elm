module DevTools.Page.BackdropReview exposing
    ( Flags
    , Model
    , Msg
    , init
    , load
    , setShared
    , update
    , view
    )

import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.SpriteFacing as SpriteFacing exposing (SpriteFacing)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Api.Object
import Api.Object.CombatBackdrop as BackdropApi
import Api.Object.CombatBackdropCatalog as BackdropCatalogApi
import Api.Query
import ApiRequest
import DevTools.Shared as Shared
import Effect as E exposing (Eff)
import Game.BackdropCalibration as Calibration
    exposing
        ( Calibration
        , Entry
        , Key
        )
import Game.UnitKind as UnitKindLabel
import Game.View.CombatTheater as CombatTheater
import Game.View.UnitSprite exposing (Appearance)
import Graphql.Http
import Graphql.SelectionSet as SS
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Random
import Style as S
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Range as Range
import View.Select as Select



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Backdrop =
    { path : String
    , label : String
    }


type alias BackdropCatalog =
    { first : Backdrop
    , rest : List Backdrop
    }


type alias Model =
    { shared : Shared.Model
    , backdropCalibrations : List Entry
    , backdrops : List Backdrop
    , left : Scene
    , right : Scene
    , drafts : List Entry
    , saveStatus : SaveStatus
    , copySource : String
    , copyDestination : String
    , copyStatus : CopyStatus
    }


type alias Scene =
    { backdrop : String
    , kind : UnitKind
    , player : PlayerNumber
    , facing : SpriteFacing
    , hitPoints : Int
    }


type Side
    = Left
    | Right


type Parameter
    = FrontFooting
    | RowSpacing
    | UnitSize
    | RearScale


type SaveStatus
    = Idle
    | Saving PendingSave
    | SaveFailed Key String


type CopyStatus
    = CopyReady
    | Copying PendingCopy
    | CopyDone String Int
    | CopyFailed String


type RequestId
    = RequestId Int


type alias PendingSave =
    { requestId : RequestId
    , entry : Entry
    }


type alias PendingCopy =
    { requestId : RequestId
    , source : String
    , destination : String
    , drafts : List Entry
    }


type Msg
    = CopySourceChanged String
    | CopyDestinationChanged String
    | CopyClicked
    | CopyResponseReceived RequestId (ApiRequest.Response (List Entry))
    | ParameterChanged Side Parameter Float
    | SaveClicked Side
    | SaveResponseReceived RequestId (ApiRequest.Response Entry)
    | BackdropChanged Side String
    | KindChanged Side UnitKind
    | PlayerChanged Side PlayerNumber
    | FacingChanged Side SpriteFacing
    | HitPointsChanged Side Int



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { backdropCalibrations : List Entry
    , backdrops : BackdropCatalog
    }


load : Graphql.Http.Request Flags
load =
    SS.succeed Flags
        |> SS.with Calibration.catalogSelection
        |> SS.with
            (Api.Query.combatBackdrops
                (SS.succeed BackdropCatalog
                    |> SS.with (BackdropCatalogApi.first backdropSelection)
                    |> SS.with (BackdropCatalogApi.rest backdropSelection)
                )
            )
        |> ApiRequest.queryRequest


backdropSelection : SS.SelectionSet Backdrop Api.Object.CombatBackdrop
backdropSelection =
    SS.succeed Backdrop
        |> SS.with BackdropApi.path
        |> SS.with BackdropApi.label


init : Shared.Model -> Flags -> Model
init shared flags =
    let
        leftBackdrop : String
        leftBackdrop =
            initialBackdrop "road" flags.backdrops

        rightBackdrop : String
        rightBackdrop =
            initialBackdrop "snowy-road" flags.backdrops
    in
    { shared = shared
    , backdropCalibrations = flags.backdropCalibrations
    , backdrops = flags.backdrops.first :: flags.backdrops.rest
    , copySource = initialCopySource leftBackdrop flags.backdropCalibrations
    , copyDestination = rightBackdrop
    , copyStatus = CopyReady
    , drafts = []
    , saveStatus = Idle
    , left =
        { backdrop = leftBackdrop
        , kind = UnitKind.Tank
        , player = PlayerNumber.Player1
        , facing = SpriteFacing.Right
        , hitPoints = 16
        }
    , right =
        { backdrop = rightBackdrop
        , kind = UnitKind.Tank
        , player = PlayerNumber.Player2
        , facing = SpriteFacing.Left
        , hitPoints = 16
        }
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }


initialBackdrop : String -> BackdropCatalog -> String
initialBackdrop preferred catalog =
    let
        preferredPath : String
        preferredPath =
            "/assets/combat-backdrops-anime-v1/" ++ preferred ++ ".png"

        available : Backdrop -> Bool
        available backdrop =
            backdrop.path == preferredPath
    in
    if List.any available (catalog.first :: catalog.rest) then
        preferredPath

    else
        catalog.first.path


backdropOptions : Model -> List { value : String, label : String }
backdropOptions model =
    let
        option : Backdrop -> { value : String, label : String }
        option backdrop =
            { value = backdrop.path
            , label = backdrop.label
            }
    in
    List.map option model.backdrops


sceneAt : Side -> Model -> Scene
sceneAt side model =
    case side of
        Left ->
            model.left

        Right ->
            model.right


sideName : Side -> String
sideName side =
    case side of
        Left ->
            "left"

        Right ->
            "right"


sceneKey : Scene -> Key
sceneKey config =
    { backdrop = config.backdrop
    , unitKind = config.kind
    }


draftCalibration : Key -> Model -> Calibration
draftCalibration key model =
    Calibration.find key (model.drafts ++ model.backdropCalibrations)
        |> Maybe.withDefault Calibration.suggested


changeCalibration : Key -> Parameter -> Float -> Model -> Model
changeCalibration key parameter value model =
    let
        current : Calibration
        current =
            draftCalibration key model

        next : Calibration
        next =
            case parameter of
                FrontFooting ->
                    { current
                        | frontFooting = clamp 55 98 (toFloat (round value))
                    }

                RowSpacing ->
                    { current
                        | rowSpacing = clamp 0 26 (toFloat (round value))
                    }

                UnitSize ->
                    { current
                        | unitSize = clamp 12 40 (toFloat (round value))
                    }

                RearScale ->
                    { current
                        | rearScale = clamp 35 100 (toFloat (round value))
                    }
    in
    { model
        | drafts =
            Calibration.replace
                { backdrop = key.backdrop
                , unitKind = key.unitKind
                , calibration = next
                }
                model.drafts
    }


mapScene : Side -> (Scene -> Scene) -> Model -> Model
mapScene side transform model =
    case side of
        Left ->
            { model
                | left = transform model.left
            }

        Right ->
            { model
                | right = transform model.right
            }


initialCopySource : String -> List Entry -> String
initialCopySource fallback catalog =
    catalog
        |> List.head
        |> Maybe.map .backdrop
        |> Maybe.withDefault fallback


writing : Model -> Bool
writing model =
    case ( model.saveStatus, model.copyStatus ) of
        ( Saving _, _ ) ->
            True

        ( _, Copying _ ) ->
            True

        _ ->
            False


canCopy : Model -> Bool
canCopy model =
    let
        savedSource : Entry -> Bool
        savedSource entry =
            entry.backdrop == model.copySource
    in
    not (writing model)
        && (model.copySource /= model.copyDestination)
        && List.any savedSource model.backdropCalibrations


backdropLabel : String -> String
backdropLabel path =
    path
        |> String.split "/"
        |> List.reverse
        |> List.head
        |> Maybe.withDefault path
        |> String.replace ".png" ""
        |> String.replace "-" " "


{-| IDs consume the shared seed so responses from a previous visit cannot
complete an unrelated request after returning to this page.
-}
nextRequest :
    Shared.Model
    ->
        { requestId : RequestId
        , shared : Shared.Model
        }
nextRequest shared =
    let
        ( value, seed ) =
            Random.step (Random.int 0 2147483647) shared.seed
    in
    { requestId = RequestId value
    , shared = Shared.setSeed seed shared
    }


resetCopyFeedback : CopyStatus -> CopyStatus
resetCopyFeedback status =
    case status of
        Copying _ ->
            status

        _ ->
            CopyReady



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        CopySourceChanged path ->
            { model
                | copySource = path
                , copyStatus = resetCopyFeedback model.copyStatus
            }
                |> E.withOut

        CopyDestinationChanged path ->
            { model
                | copyDestination = path
                , copyStatus = resetCopyFeedback model.copyStatus
            }
                |> E.withOut

        CopyClicked ->
            if not (canCopy model) then
                model
                    |> E.withOut

            else
                let
                    request :
                        { requestId : RequestId
                        , shared : Shared.Model
                        }
                    request =
                        nextRequest model.shared

                    pending : PendingCopy
                    pending =
                        { requestId = request.requestId
                        , source = model.copySource
                        , destination = model.copyDestination
                        , drafts = model.drafts
                        }
                in
                ( { model
                    | copyStatus = Copying pending
                    , shared = request.shared
                  }
                , E.request (CopyResponseReceived pending.requestId)
                    (Calibration.copy
                        { source = pending.source
                        , destination = pending.destination
                        }
                    )
                )

        CopyResponseReceived requestId result ->
            case model.copyStatus of
                Copying pending ->
                    if pending.requestId /= requestId then
                        model
                            |> E.withOut

                    else
                        case result of
                            Ok entries ->
                                let
                                    keepDraft : Entry -> Bool
                                    keepDraft draft =
                                        let
                                            key : Key
                                            key =
                                                { backdrop = draft.backdrop
                                                , unitKind = draft.unitKind
                                                }

                                            wasReplaced : Bool
                                            wasReplaced =
                                                (Calibration.find key entries /= Nothing)
                                                    && (Calibration.find key pending.drafts == Just draft.calibration)
                                        in
                                        not wasReplaced
                                in
                                ( { model
                                    | backdropCalibrations =
                                        List.foldl Calibration.replace model.backdropCalibrations entries
                                    , drafts = List.filter keepDraft model.drafts
                                    , copyStatus = CopyDone pending.destination (List.length entries)
                                    , saveStatus = Idle
                                  }
                                , E.none
                                )

                            Err error ->
                                { model
                                    | copyStatus = CopyFailed (ApiRequest.errorMessage error)
                                }
                                    |> E.withOut

                _ ->
                    model
                        |> E.withOut

        ParameterChanged side parameter value ->
            changeCalibration (sceneKey (sceneAt side model)) parameter value model
                |> E.withOut

        SaveClicked side ->
            case ( model.saveStatus, model.copyStatus ) of
                ( Saving _, _ ) ->
                    model
                        |> E.withOut

                ( _, Copying _ ) ->
                    model
                        |> E.withOut

                _ ->
                    let
                        entry : Entry
                        entry =
                            { backdrop = (sceneAt side model).backdrop
                            , unitKind = (sceneAt side model).kind
                            , calibration = draftCalibration (sceneKey (sceneAt side model)) model
                            }

                        request :
                            { requestId : RequestId
                            , shared : Shared.Model
                            }
                        request =
                            nextRequest model.shared
                    in
                    ( { model
                        | saveStatus =
                            Saving
                                { requestId = request.requestId
                                , entry = entry
                                }
                        , shared = request.shared
                      }
                    , E.request (SaveResponseReceived request.requestId) (Calibration.save entry)
                    )

        SaveResponseReceived requestId response ->
            case model.saveStatus of
                Saving pending ->
                    if pending.requestId /= requestId then
                        model
                            |> E.withOut

                    else
                        case response of
                            Ok entry ->
                                ( { model
                                    | backdropCalibrations = Calibration.replace entry model.backdropCalibrations
                                    , saveStatus = Idle
                                  }
                                , E.none
                                )

                            Err error ->
                                { model
                                    | saveStatus =
                                        SaveFailed
                                            { backdrop = pending.entry.backdrop
                                            , unitKind = pending.entry.unitKind
                                            }
                                            (ApiRequest.errorMessage error)
                                }
                                    |> E.withOut

                _ ->
                    model
                        |> E.withOut

        BackdropChanged side path ->
            mapScene side
                (\config ->
                    { config
                        | backdrop = path
                    }
                )
                model
                |> E.withOut

        KindChanged side kind ->
            mapScene side
                (\config ->
                    { config
                        | kind = kind
                    }
                )
                model
                |> E.withOut

        PlayerChanged side player ->
            mapScene side
                (\config ->
                    { config
                        | player = player
                    }
                )
                model
                |> E.withOut

        FacingChanged side facing ->
            mapScene side
                (\config ->
                    { config
                        | facing = facing
                    }
                )
                model
                |> E.withOut

        HitPointsChanged side hitPoints ->
            mapScene side
                (\config ->
                    { config
                        | hitPoints = hitPoints
                    }
                )
                model
                |> E.withOut



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.col
            , S.g3
            , S.wFull
            , S.maxW256
            , S.mAuto
            ]
        ]
        [ copyControls model
        , H.div
            [ A.css
                [ S.grid
                , S.gridCols1
                , S.md
                    [ S.gridCols2
                    ]
                , S.g3
                ]
            ]
            [ scenePanel Left model model.left
            , scenePanel Right model model.right
            ]
        ]
    ]


scenePanel : Side -> Model -> Scene -> Html Msg
scenePanel side model config =
    let
        card : Card.Card
        card =
            Card.simple
                |> Card.withHeader (CardHeader.simple (sideName side ++ " scene"))
    in
    Card.toHtml card
        [ previewSelectors side model config
        , sceneView model config
        , calibrationControls side model (sceneKey config)
        , H.details
            []
            [ H.summary
                []
                [ H.text "more preview options"
                ]
            , controls side config
            ]
        ]


previewSelectors : Side -> Model -> Scene -> Html Msg
previewSelectors side model config =
    let
        prefix : String
        prefix =
            sideName side

        options :
            List
                { value : String
                , label : String
                }
        options =
            if List.any (\option -> option.value == config.backdrop) (backdropOptions model) then
                backdropOptions model

            else
                backdropOptions model
                    ++ [ { value = config.backdrop
                         , label = "custom backdrop"
                         }
                       ]

        kindOption :
            UnitKind
            ->
                { value : UnitKind
                , label : String
                }
        kindOption kind =
            { value = kind
            , label = UnitKindLabel.label kind
            }
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ field (prefix ++ "-backdrop")
            "backdrop"
            (Select.toHtml
                { htmlId = prefix ++ "-backdrop"
                , disabled = False
                , selected = config.backdrop
                , options = options
                , toValue = identity
                , decoder = Decode.string
                , onChange = BackdropChanged side
                }
            )
        , field (prefix ++ "-kind")
            "unit type"
            (Select.toHtml
                { htmlId = prefix ++ "-kind"
                , disabled = False
                , selected = config.kind
                , options = List.map kindOption UnitKind.list
                , toValue = UnitKind.toString
                , decoder = UnitKind.decoder
                , onChange = KindChanged side
                }
            )
        ]


sceneView : Model -> Scene -> Html Msg
sceneView model config =
    let
        appearance : Appearance
        appearance =
            { kind = config.kind
            , playerNumber = config.player
            , spriteFacing = config.facing
            , entrenchment = Entrenchment.Exposed
            }
    in
    CombatTheater.preview
        (Just (draftCalibration (sceneKey config) model))
        config.backdrop
        config.hitPoints
        appearance


controls : Side -> Scene -> Html Msg
controls side config =
    let
        prefix : String
        prefix =
            case side of
                Left ->
                    "left"

                Right ->
                    "right"

        playerOption :
            PlayerNumber
            ->
                { value : PlayerNumber
                , label : String
                }
        playerOption player =
            { value = player
            , label =
                case player of
                    PlayerNumber.Player1 ->
                        "red"

                    PlayerNumber.Player2 ->
                        "blue"
            }

        facingOption :
            SpriteFacing
            ->
                { value : SpriteFacing
                , label : String
                }
        facingOption facing =
            { value = facing
            , label = String.toLower (SpriteFacing.toString facing)
            }

        healthOption :
            Int
            ->
                { value : Int
                , label : String
                }
        healthOption hitPoints =
            { value = hitPoints
            , label = String.fromInt hitPoints
            }
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ field (prefix ++ "-player")
            "team"
            (Select.toHtml
                { htmlId = prefix ++ "-player"
                , disabled = False
                , selected = config.player
                , options = List.map playerOption PlayerNumber.list
                , toValue = PlayerNumber.toString
                , decoder = PlayerNumber.decoder
                , onChange = PlayerChanged side
                }
            )
        , field (prefix ++ "-facing")
            "facing"
            (Select.toHtml
                { htmlId = prefix ++ "-facing"
                , disabled = False
                , selected = config.facing
                , options = List.map facingOption SpriteFacing.list
                , toValue = SpriteFacing.toString
                , decoder = SpriteFacing.decoder
                , onChange = FacingChanged side
                }
            )
        , field (prefix ++ "-health")
            "hit points"
            (Select.toHtml
                { htmlId = prefix ++ "-health"
                , disabled = False
                , selected = config.hitPoints
                , options = List.map healthOption (List.range 0 16)
                , toValue = String.fromInt
                , decoder =
                    Decode.string
                        |> Decode.andThen decodeHitPoints
                , onChange = HitPointsChanged side
                }
            )
        , field (prefix ++ "-path")
            "custom backdrop path or url"
            (H.input
                [ A.id (prefix ++ "-path")
                , A.value config.backdrop
                , Ev.onInput (BackdropChanged side)
                , A.css
                    [ S.wFull
                    , S.minW0
                    , S.indentStrong
                    , S.bgNightwood3
                    , S.textGray5
                    , S.p2
                    ]
                ]
                []
            )
        ]


field : String -> String -> Html msg -> Html msg
field htmlId label control =
    H.div
        [ A.css
            [ S.col
            , S.g2
            , S.minW0
            ]
        ]
        [ H.label
            [ A.for htmlId
            ]
            [ H.text label
            ]
        , control
        ]


decodeHitPoints : String -> Decode.Decoder Int
decodeHitPoints value =
    case String.toInt value of
        Just hitPoints ->
            if (hitPoints >= 0) && (hitPoints <= 16) then
                Decode.succeed hitPoints

            else
                Decode.fail "hit points must be between 0 and 16"

        Nothing ->
            Decode.fail "hit points must be an integer"


calibrationControls : Side -> Model -> Key -> Html Msg
calibrationControls side model key =
    let
        settings : Calibration
        settings =
            draftCalibration key model

        slider : Parameter -> Html Msg
        slider parameter =
            let
                range :
                    { suffix : String
                    , label : String
                    , value : Float
                    , minimum : Float
                    , maximum : Float
                    }
                range =
                    case parameter of
                        FrontFooting ->
                            { suffix = "front"
                            , label = "front row position"
                            , value = settings.frontFooting
                            , minimum = 55
                            , maximum = 98
                            }

                        RowSpacing ->
                            { suffix = "spacing"
                            , label = "distance between rows"
                            , value = settings.rowSpacing
                            , minimum = 0
                            , maximum = 26
                            }

                        UnitSize ->
                            { suffix = "size"
                            , label = "unit size"
                            , value = settings.unitSize
                            , minimum = 12
                            , maximum = 40
                            }

                        RearScale ->
                            { suffix = "rear-scale"
                            , label = "rear row size (% of front)"
                            , value = settings.rearScale
                            , minimum = 35
                            , maximum = 100
                            }
            in
            Range.toHtml
                { htmlId = sideName side ++ "-" ++ range.suffix
                , label = range.label
                , value = range.value
                , minimum = range.minimum
                , maximum = range.maximum
                , onChange = ParameterChanged side parameter
                }

        saving : Bool
        saving =
            writing model

        saveButton : Html Msg
        saveButton =
            if saving then
                Button.disabled "saving…"
                    |> Button.toHtml

            else
                Button.primary "save calibration" (SaveClicked side)
                    |> Button.toHtml

        status : String
        status =
            case model.saveStatus of
                SaveFailed failedKey error ->
                    if failedKey == key then
                        error

                    else
                        calibrationStatus key settings model

                _ ->
                    calibrationStatus key settings model
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ slider FrontFooting
        , slider RowSpacing
        , slider UnitSize
        , slider RearScale
        , saveButton
        , H.p
            [ A.attribute "role" "status"
            ]
            [ H.text status
            ]
        ]


calibrationStatus : Key -> Calibration -> Model -> String
calibrationStatus key settings model =
    if Calibration.find key model.backdropCalibrations == Just settings then
        "saved · used when opening gameplay"

    else
        "unsaved preview · save for this unit type and backdrop"


copyControls : Model -> Html Msg
copyControls model =
    let
        savedSource : { value : String, label : String } -> Bool
        savedSource option =
            List.any (\entry -> entry.backdrop == option.value) model.backdropCalibrations

        sources :
            List
                { value : String
                , label : String
                }
        sources =
            List.filter savedSource (backdropOptions model)

        copyButton : Html Msg
        copyButton =
            if canCopy model then
                Button.primary "copy and save all unit calibrations" CopyClicked
                    |> Button.toHtml

            else
                Button.disabled "copy and save all unit calibrations"
                    |> Button.toHtml

        status : String
        status =
            case model.copyStatus of
                CopyReady ->
                    if List.isEmpty sources then
                        "save a calibration before copying."

                    else if model.copySource == model.copyDestination then
                        "choose different source and destination backdrops."

                    else
                        "copies saved settings for all available unit types, replacing matching destination settings."

                Copying _ ->
                    "copying calibrations…"

                CopyDone destination count ->
                    "saved " ++ String.fromInt count ++ " unit calibrations to " ++ backdropLabel destination

                CopyFailed error ->
                    error

        card : Card.Card
        card =
            Card.simple
                |> Card.withHeader (CardHeader.simple "copy calibrations")
    in
    Card.toHtml card
        [ field "copy-source"
            "from"
            (Select.toHtml
                { htmlId = "copy-source"
                , disabled = False
                , selected = model.copySource
                , options = sources
                , toValue = identity
                , decoder = Decode.string
                , onChange = CopySourceChanged
                }
            )
        , field "copy-destination"
            "to"
            (Select.toHtml
                { htmlId = "copy-destination"
                , disabled = False
                , selected = model.copyDestination
                , options = backdropOptions model
                , toValue = identity
                , decoder = Decode.string
                , onChange = CopyDestinationChanged
                }
            )
        , copyButton
        , H.p
            [ A.attribute "role" "status"
            ]
            [ H.text status
            ]
        ]
