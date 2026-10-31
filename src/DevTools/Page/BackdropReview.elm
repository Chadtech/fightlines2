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
        , CopyScope(..)
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
import NonEmptyList exposing (NonEmpty)
import Random
import Style as S
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Checkbox as Checkbox
import View.Range as Range
import View.Select as Select



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Backdrop =
    { path : String
    , label : String
    }


type alias Model =
    { shared : Shared.Model
    , backdropCalibrations : List Entry
    , backdrops : NonEmpty Backdrop
    , backdrop : String
    , kind : UnitKind
    , player : PlayerNumber
    , facing : SpriteFacing
    , hitPoints : Int
    , entrenchment : Entrenchment.Entrenchment
    , drafts : List Entry
    , saveStatus : SaveStatus
    , copySource : String
    , copyDestination : String
    , copyScope : Maybe CopyScope
    , copyStatus : CopyStatus
    }


type Parameter
    = FrontFooting
    | RowSpacing
    | UnitSize
    | RearScale
    | TrenchFooting
    | TrenchSize
    | SecondTrenchFooting
    | SecondTrenchSize


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
    , scope : CopyScope
    }


type Msg
    = CopySourceChanged String
    | CopyDestinationChanged String
    | CopyUnitChanged (Maybe UnitKind)
    | CopyAllUnitsChanged Bool
    | CopyClicked
    | CopyResponseReceived RequestId (ApiRequest.Response (List Entry))
    | ParameterChanged Parameter Float
    | SaveClicked
    | SaveResponseReceived RequestId (ApiRequest.Response Entry)
    | BackdropChanged String
    | KindChanged UnitKind
    | PlayerChanged PlayerNumber
    | FacingLeftChanged Bool
    | HitPointsChanged Int
    | EntrenchmentChanged Entrenchment.Entrenchment



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { backdropCalibrations : List Entry
    , backdrops : NonEmpty Backdrop
    }


load : Graphql.Http.Request Flags
load =
    SS.succeed Flags
        |> SS.with Calibration.catalogSelection
        |> SS.with
            (Api.Query.combatBackdrops
                (SS.succeed NonEmptyList.fromCons
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
        backdrop : String
        backdrop =
            initialBackdrop "road" flags.backdrops
    in
    { shared = shared
    , backdropCalibrations = flags.backdropCalibrations
    , backdrops = flags.backdrops
    , copySource = initialCopySource backdrop flags.backdropCalibrations
    , copyDestination = initialBackdrop "snowy-road" flags.backdrops
    , copyScope = Nothing
    , copyStatus = CopyReady
    , drafts = []
    , saveStatus = Idle
    , backdrop = backdrop
    , kind = UnitKind.Tank
    , player = PlayerNumber.Player1
    , facing = SpriteFacing.Right
    , hitPoints = 16
    , entrenchment = Entrenchment.Exposed
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setDrafts : List Entry -> Model -> Model
setDrafts drafts model =
    { model | drafts = drafts }


setCopyStatus : CopyStatus -> Model -> Model
setCopyStatus copyStatus model =
    { model | copyStatus = copyStatus }


setCopyScope : Maybe CopyScope -> Model -> Model
setCopyScope copyScope model =
    { model
        | copyScope = copyScope
    }


setBackdropCalibrations : List Entry -> Model -> Model
setBackdropCalibrations backdropCalibrations model =
    { model | backdropCalibrations = backdropCalibrations }


setSaveStatus : SaveStatus -> Model -> Model
setSaveStatus saveStatus model =
    { model | saveStatus = saveStatus }


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }


initialBackdrop : String -> NonEmpty Backdrop -> String
initialBackdrop preferred catalog =
    let
        preferredPath : String
        preferredPath =
            "/assets/combat-backdrops-anime-v1/" ++ preferred ++ ".png"

        available : Backdrop -> Bool
        available backdrop =
            backdrop.path == preferredPath
    in
    if NonEmptyList.any available catalog then
        preferredPath

    else
        (NonEmptyList.head catalog).path


backdropOptions : Model -> List { value : String, label : String }
backdropOptions model =
    let
        option : Backdrop -> { value : String, label : String }
        option backdrop =
            { value = backdrop.path
            , label = backdrop.label
            }
    in
    NonEmptyList.map option model.backdrops
        |> NonEmptyList.toList


sceneHtmlId : String -> String
sceneHtmlId suffix =
    "backdrop-scene-" ++ suffix


selectedKey : Model -> Key
selectedKey model =
    { backdrop = model.backdrop
    , unitKind = model.kind
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

                TrenchSize ->
                    { current | trenchSize = clamp 10 45 (toFloat (round value)) }

                TrenchFooting ->
                    { current | trenchFooting = clamp 25 98 (toFloat (round value)) }

                SecondTrenchSize ->
                    { current | secondTrenchSize = clamp 10 45 (toFloat (round value)) }

                SecondTrenchFooting ->
                    { current | secondTrenchFooting = clamp 25 98 (toFloat (round value)) }

                RearScale ->
                    { current
                        | rearScale = clamp 35 100 (toFloat (round value))
                    }
    in
    model
        |> setDrafts
            (Calibration.replace
                { backdrop = key.backdrop
                , unitKind = key.unitKind
                , calibration = next
                }
                model.drafts
            )


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
            (entry.backdrop == model.copySource)
                && copyIncludes model.copyScope entry.unitKind
    in
    not (writing model)
        && (model.copySource /= model.copyDestination)
        && List.any savedSource model.backdropCalibrations


copyIncludes : Maybe CopyScope -> UnitKind -> Bool
copyIncludes scope kind =
    case scope of
        Just AllUnits ->
            True

        Just (OneUnit selectedKind) ->
            kind == selectedKind

        Nothing ->
            False


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
            ({ model | copySource = path }
                |> setCopyStatus (resetCopyFeedback model.copyStatus)
            )
                |> E.withOut

        CopyDestinationChanged path ->
            ({ model | copyDestination = path }
                |> setCopyStatus (resetCopyFeedback model.copyStatus)
            )
                |> E.withOut

        CopyUnitChanged kind ->
            model
                |> setCopyScope (Maybe.map OneUnit kind)
                |> setCopyStatus (resetCopyFeedback model.copyStatus)
                |> E.withOut

        CopyAllUnitsChanged checked ->
            let
                scope : Maybe CopyScope
                scope =
                    if checked then
                        Just AllUnits

                    else
                        Nothing
            in
            model
                |> setCopyScope scope
                |> setCopyStatus (resetCopyFeedback model.copyStatus)
                |> E.withOut

        CopyClicked ->
            case model.copyScope of
                Nothing ->
                    E.withOut model

                Just scope ->
                    if not (canCopy model) then
                        E.withOut model

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
                                , scope = scope
                                }
                        in
                        ( model
                            |> setCopyStatus (Copying pending)
                            |> setShared request.shared
                        , E.request (CopyResponseReceived pending.requestId)
                            (Calibration.copy
                                { source = pending.source
                                , destination = pending.destination
                                , scope = pending.scope
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
                                ( model
                                    |> setBackdropCalibrations (List.foldl Calibration.replace model.backdropCalibrations entries)
                                    |> setDrafts (List.filter keepDraft model.drafts)
                                    |> setCopyStatus (CopyDone pending.destination (List.length entries))
                                    |> setSaveStatus Idle
                                , E.none
                                )

                            Err error ->
                                (model
                                    |> setCopyStatus (CopyFailed (ApiRequest.errorMessage error))
                                )
                                    |> E.withOut

                _ ->
                    model
                        |> E.withOut

        ParameterChanged parameter value ->
            changeCalibration (selectedKey model) parameter value model
                |> E.withOut

        SaveClicked ->
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
                            { backdrop = model.backdrop
                            , unitKind = model.kind
                            , calibration = draftCalibration (selectedKey model) model
                            }

                        request :
                            { requestId : RequestId
                            , shared : Shared.Model
                            }
                        request =
                            nextRequest model.shared
                    in
                    ( model
                        |> setSaveStatus
                            (Saving
                                { requestId = request.requestId
                                , entry = entry
                                }
                            )
                        |> setShared request.shared
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
                                ( model
                                    |> setBackdropCalibrations (Calibration.replace entry model.backdropCalibrations)
                                    |> setSaveStatus Idle
                                , E.none
                                )

                            Err error ->
                                (model
                                    |> setSaveStatus
                                        (SaveFailed
                                            { backdrop = pending.entry.backdrop
                                            , unitKind = pending.entry.unitKind
                                            }
                                            (ApiRequest.errorMessage error)
                                        )
                                )
                                    |> E.withOut

                _ ->
                    model
                        |> E.withOut

        BackdropChanged path ->
            { model
                | backdrop = path
            }
                |> E.withOut

        KindChanged kind ->
            { model
                | kind = kind
            }
                |> E.withOut

        PlayerChanged player ->
            { model
                | player = player
            }
                |> E.withOut

        FacingLeftChanged checked ->
            let
                facing : SpriteFacing
                facing =
                    if checked then
                        SpriteFacing.Left

                    else
                        SpriteFacing.Right
            in
            { model
                | facing = facing
            }
                |> E.withOut

        EntrenchmentChanged entrenchment ->
            { model
                | entrenchment = entrenchment
            }
                |> E.withOut

        HitPointsChanged hitPoints ->
            { model
                | hitPoints = hitPoints
            }
                |> E.withOut



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.grid
            , S.gridCols1
            , S.md
                [ S.gridColumns "minmax(0, 3fr) minmax(0, 2fr)"
                ]
            , S.itemsStart
            , S.g3
            , S.wFull
            , S.maxW256
            , S.mAuto
            ]
        ]
        [ scenePanel model
        , copyControls model
        ]
    ]


scenePanel : Model -> Html Msg
scenePanel model =
    let
        card : Card.Card
        card =
            Card.simple
                |> Card.withHeader (CardHeader.simple "scene")
    in
    Card.toHtml card
        [ previewSelectors model
        , sceneView model
        , calibrationControls model
        , H.details
            []
            [ H.summary
                []
                [ H.text "more preview options"
                ]
            , controls model
            ]
        ]


previewSelectors : Model -> Html Msg
previewSelectors model =
    let
        options :
            List
                { value : String
                , label : String
                }
        options =
            if List.any (\option -> option.value == model.backdrop) (backdropOptions model) then
                backdropOptions model

            else
                backdropOptions model
                    ++ [ { value = model.backdrop
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

        entrenchmentControl : Html Msg
        entrenchmentControl =
            if model.kind == UnitKind.Infantry then
                field (sceneHtmlId "entrenchment")
                    "infantry position"
                    (Select.new
                        { selected = model.entrenchment
                        , options =
                            [ { value = Entrenchment.Exposed, label = "exposed infantry" }
                            , { value = Entrenchment.Entrenched, label = "entrenched infantry" }
                            ]
                        , onChange = EntrenchmentChanged
                        }
                        |> Select.withHtmlId (sceneHtmlId "entrenchment")
                        |> Select.toHtml
                    )

            else
                H.text ""
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ field (sceneHtmlId "backdrop")
            "backdrop"
            (Select.new
                { selected = model.backdrop
                , options = options
                , onChange = BackdropChanged
                }
                |> Select.withHtmlId (sceneHtmlId "backdrop")
                |> Select.toHtml
            )
        , field (sceneHtmlId "kind")
            "unit type"
            (Select.new
                { selected = model.kind
                , options = List.map kindOption UnitKind.list
                , onChange = KindChanged
                }
                |> Select.withHtmlId (sceneHtmlId "kind")
                |> Select.toHtml
            )
        , Checkbox.new
            { label = "face left"
            , checked = model.facing == SpriteFacing.Left
            , onCheck = FacingLeftChanged
            }
            |> Checkbox.toHtml [ H.text "face left" ]
        , entrenchmentControl
        ]


sceneView : Model -> Html Msg
sceneView model =
    let
        appearance : Appearance
        appearance =
            { kind = model.kind
            , playerNumber = model.player
            , spriteFacing = model.facing
            , entrenchment = model.entrenchment
            }
    in
    CombatTheater.preview
        (Just (draftCalibration (selectedKey model) model))
        model.backdrop
        model.hitPoints
        appearance


controls : Model -> Html Msg
controls model =
    let
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
        [ field (sceneHtmlId "player")
            "team"
            (Select.new
                { selected = model.player
                , options = List.map playerOption PlayerNumber.list
                , onChange = PlayerChanged
                }
                |> Select.withHtmlId (sceneHtmlId "player")
                |> Select.toHtml
            )
        , field (sceneHtmlId "health")
            "hit points"
            (Select.new
                { selected = model.hitPoints
                , options = List.map healthOption (List.range 0 16)
                , onChange = HitPointsChanged
                }
                |> Select.withHtmlId (sceneHtmlId "health")
                |> Select.toHtml
            )
        , field (sceneHtmlId "path")
            "custom backdrop path or url"
            (H.input
                [ A.id (sceneHtmlId "path")
                , A.value model.backdrop
                , Ev.onInput BackdropChanged
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


calibrationControls : Model -> Html Msg
calibrationControls model =
    let
        key : Key
        key =
            selectedKey model

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
                        TrenchSize ->
                            { suffix = "trench-size"
                            , label = "trench 1 size"
                            , value = settings.trenchSize
                            , minimum = 10
                            , maximum = 45
                            }

                        TrenchFooting ->
                            { suffix = "trench-footing"
                            , label = "trench 1 y position (from top)"
                            , value = settings.trenchFooting
                            , minimum = 25
                            , maximum = 98
                            }

                        FrontFooting ->
                            { suffix = "front"
                            , label = "front row position"
                            , value = settings.frontFooting
                            , minimum = 55
                            , maximum = 98
                            }

                        SecondTrenchSize ->
                            { suffix = "second-trench-size"
                            , label = "trench 2 size"
                            , value = settings.secondTrenchSize
                            , minimum = 10
                            , maximum = 45
                            }

                        SecondTrenchFooting ->
                            { suffix = "second-trench-footing"
                            , label = "trench 2 y position (from top)"
                            , value = settings.secondTrenchFooting
                            , minimum = 25
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
                { htmlId = sceneHtmlId range.suffix
                , label = range.label
                , value = range.value
                , minimum = range.minimum
                , maximum = range.maximum
                , onChange = ParameterChanged parameter
                }

        previewingTrenches : Bool
        previewingTrenches =
            (model.kind == UnitKind.Infantry) && (model.entrenchment == Entrenchment.Entrenched)

        parameters : List (Html Msg)
        parameters =
            if previewingTrenches then
                [ slider TrenchFooting
                , slider TrenchSize
                , slider SecondTrenchFooting
                , slider SecondTrenchSize
                , H.p
                    []
                    [ H.text "trench 1 is behind trench 2 in the direction the infantry face. smaller y values move a trench higher."
                    ]
                ]

            else
                [ slider FrontFooting
                , slider RowSpacing
                , slider UnitSize
                , slider RearScale
                ]

        actions : List (Html Msg)
        actions =
            [ saveButton
            , H.p
                [ A.attribute "role" "status" ]
                [ H.text status ]
            ]

        content : List (Html Msg)
        content =
            parameters ++ actions

        saving : Bool
        saving =
            writing model

        saveButton : Html Msg
        saveButton =
            if saving then
                Button.disabled "saving…"
                    |> Button.toHtml

            else
                Button.primary "save calibration" SaveClicked
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
        content


calibrationStatus : Key -> Calibration -> Model -> String
calibrationStatus key settings model =
    if Calibration.find key model.backdropCalibrations == Just settings then
        "saved · rebuild frontend to use in gameplay"

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

        allUnits : Bool
        allUnits =
            model.copyScope == Just AllUnits

        selectedKind : Maybe UnitKind
        selectedKind =
            case model.copyScope of
                Just (OneUnit kind) ->
                    Just kind

                _ ->
                    Nothing

        kindOption : UnitKind -> { value : Maybe UnitKind, label : String }
        kindOption kind =
            { value = Just kind
            , label = UnitKindLabel.label kind
            }

        buttonLabel : String
        buttonLabel =
            case model.copyScope of
                Just AllUnits ->
                    "copy and save all unit calibrations"

                Just (OneUnit kind) ->
                    "copy and save " ++ UnitKindLabel.label kind ++ " calibration"

                Nothing ->
                    "copy and save calibration"

        scopeDescription : String
        scopeDescription =
            case model.copyScope of
                Just AllUnits ->
                    "copies saved settings for all available unit types, replacing matching destination settings."

                Just (OneUnit kind) ->
                    if canCopy model || writing model then
                        "copies saved " ++ UnitKindLabel.label kind ++ " settings, replacing only that unit type at the destination."

                    else
                        "the source has no saved " ++ UnitKindLabel.label kind ++ " calibration."

                Nothing ->
                    "choose a unit type to copy."

        copyButton : Html Msg
        copyButton =
            if canCopy model then
                Button.primary buttonLabel CopyClicked
                    |> Button.toHtml

            else
                Button.disabled buttonLabel
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
                        scopeDescription

                Copying _ ->
                    "copying calibrations…"

                CopyDone destination count ->
                    let
                        unitLabel : String
                        unitLabel =
                            if count == 1 then
                                "unit calibration"

                            else
                                "unit calibrations"
                    in
                    "saved " ++ String.fromInt count ++ " " ++ unitLabel ++ " to " ++ backdropLabel destination

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
            (Select.new
                { selected = model.copySource
                , options = sources
                , onChange = CopySourceChanged
                }
                |> Select.withHtmlId "copy-source"
                |> Select.toHtml
            )
        , field "copy-destination"
            "to"
            (Select.new
                { selected = model.copyDestination
                , options = backdropOptions model
                , onChange = CopyDestinationChanged
                }
                |> Select.withHtmlId "copy-destination"
                |> Select.toHtml
            )
        , Checkbox.new
            { label = "all unit types"
            , checked = allUnits
            , onCheck = CopyAllUnitsChanged
            }
            |> Checkbox.disabled (writing model)
            |> Checkbox.toHtml [ H.text "all unit types" ]
        , field "copy-kind"
            "unit type"
            (Select.new
                { selected = selectedKind
                , options = { value = Nothing, label = "choose unit type" } :: List.map kindOption UnitKind.list
                , onChange = CopyUnitChanged
                }
                |> Select.withHtmlId "copy-kind"
                |> Select.disabled (allUnits || writing model)
                |> Select.toHtml
            )
        , copyButton
        , H.p
            [ A.attribute "role" "status"
            ]
            [ H.text status
            ]
        ]
