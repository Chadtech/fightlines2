module Page.Home exposing
    ( Model
    , Msg
    , init
    , setShared
    , styles
    , update
    , view
    )

import Effect as E exposing (Eff)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Random
import Route
import Shared
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Msg
    = PlayButtonClicked
    | SceneCycleCompleted BackgroundScene


type alias Model =
    { shared : Shared.Model
    , snow : ScenePosition
    , desert : ScenePosition
    , logistics : ScenePosition
    }


type BackgroundScene
    = Snow
    | Desert
    | Logistics


type alias ScenePosition =
    { centerXPercent : Int
    , centerYPercent : Int
    , rotationDegrees : Int
    }


type alias SceneArtwork =
    { source : String
    , delaySeconds : Int
    , width : String
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Model
init shared =
    let
        ( snow, snowSeed ) =
            Random.step scenePositionGenerator shared.seed

        ( desert, desertSeed ) =
            Random.step scenePositionGenerator snowSeed

        ( logistics, nextSeed ) =
            Random.step scenePositionGenerator desertSeed
    in
    { shared = Shared.setSeed nextSeed shared
    , snow = snow
    , desert = desert
    , logistics = logistics
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


scenePositionGenerator : Random.Generator ScenePosition
scenePositionGenerator =
    Random.map3 ScenePosition
        (Random.int 64 78)
        (Random.int 42 58)
        (Random.int -12 12)


repositionScene : BackgroundScene -> Model -> Model
repositionScene scene model =
    let
        ( position, nextSeed ) =
            Random.step scenePositionGenerator model.shared.seed

        advanced : Model
        advanced =
            { model | shared = Shared.setSeed nextSeed model.shared }
    in
    case scene of
        Snow ->
            { advanced | snow = position }

        Desert ->
            { advanced | desert = position }

        Logistics ->
            { advanced | logistics = position }


scenePosition : Model -> BackgroundScene -> ScenePosition
scenePosition model scene =
    case scene of
        Snow ->
            model.snow

        Desert ->
            model.desert

        Logistics ->
            model.logistics


sceneArtwork : BackgroundScene -> SceneArtwork
sceneArtwork scene =
    case scene of
        Snow ->
            { source = "/assets/home-battlefield-snow-v1.png"
            , delaySeconds = 4
            , width = "clamp(42rem, 78vw, 86rem)"
            }

        Desert ->
            { source = "/assets/home-battlefield-desert-v1.png"
            , delaySeconds = 22
            , width = "clamp(42rem, 78vw, 86rem)"
            }

        Logistics ->
            { source = "/assets/home-battlefield-logistics-v1.png"
            , delaySeconds = 40
            , width = "clamp(34rem, 62vw, 68rem)"
            }



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        PlayButtonClicked ->
            ( model, E.navigate Route.NewLobby )

        SceneCycleCompleted scene ->
            repositionScene scene model
                |> E.withOut



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.flex1
            , S.relative
            , S.isolate
            , S.col
            , S.itemsCenter
            , S.justifyCenter
            , S.g8
            , S.py8
            ]
        ]
        [ battlefieldBackground model
        , portrait
        , H.div
            [ A.css
                [ S.relative
                , S.wFull
                , S.maxW160
                , S.col
                , S.g3
                ]
            ]
            [ H.h1
                []
                [ H.img
                    [ A.src "/assets/fightlines-logo-v1.png"
                    , A.alt "fightlines"
                    , A.width 2146
                    , A.height 732
                    , A.css
                        [ S.block
                        , S.wFull
                        , S.hAuto
                        , S.animation "fightlines-home-logo-enter 900ms ease-out both"
                        , S.reducedMotion
                            [ S.animationNone
                            ]
                        ]
                    ]
                    []
                ]
            , H.p
                [ A.css
                    [ S.textAlignCenter
                    , S.textGray4
                    , S.animation "fightlines-home-fade-enter 900ms ease-out 2700ms both"
                    , S.reducedMotion
                        [ S.animationNone
                        ]
                    ]
                ]
                [ H.text "a turn based strategy game based on logistics, supply, and transportation" ]
            ]
        , H.nav
            [ Aria.label "main navigation"
            , A.css
                [ S.relative
                , S.wFull
                , S.maxW96
                ]
            ]
            [ [ Button.primary "play" PlayButtonClicked
                    |> Button.fullWidth
                    |> Button.toHtml
              ]
                |> Card.toHtml Card.simple
            ]
        , quotation
        ]
    ]


battlefieldBackground : Model -> Html Msg
battlefieldBackground model =
    H.div
        [ Aria.hidden True
        , A.css
            [ S.fixed
            , S.inset0
            , S.overflowHidden
            , S.pointerEventsNone
            , S.reducedMotion
                [ S.displayNone
                ]
            ]
        ]
        [ backgroundScene model Snow
        , backgroundScene model Desert
        , backgroundScene model Logistics
        ]


backgroundScene : Model -> BackgroundScene -> Html Msg
backgroundScene model scene =
    let
        position : ScenePosition
        position =
            scenePosition model scene

        artwork : SceneArtwork
        artwork =
            sceneArtwork scene
    in
    H.div
        [ A.css
            [ S.absolute
            , S.leftValue (String.fromInt position.centerXPercent ++ "%")
            , S.topValue (String.fromInt position.centerYPercent ++ "%")
            , S.widthValue artwork.width
            , S.transform ("translate(-50%, -50%) rotate(" ++ String.fromInt position.rotationDegrees ++ "deg)")
            , S.mixBlendScreen
            , S.belowWidth 720
                [ S.widthValue "160vw"
                ]
            ]
        ]
        [ H.img
            [ A.src artwork.source
            , A.alt ""
            , Ev.on "animationiteration" (Decode.succeed (SceneCycleCompleted scene))
            , A.css
                [ S.block
                , S.wFull
                , S.hAuto
                , S.softEdgeMask
                , S.filter "grayscale(1) sepia(1) hue-rotate(48deg) saturate(2) brightness(0.55)"
                , S.opacity 0
                , S.animation
                    ("fightlines-home-battlefield-emerge 54s linear "
                        ++ String.fromInt artwork.delaySeconds
                        ++ "s infinite both"
                    )
                , S.reducedMotion
                    [ S.animationNone
                    ]
                ]
            ]
            []
        ]


portrait : Html msg
portrait =
    H.div
        [ Aria.hidden True
        , A.css
            [ S.fixed
            , S.inset0
            , S.pointerEventsNone
            , S.row
            , S.animation bradleyEntranceAnimation
            , S.reducedMotion
                [ S.animationNone
                ]
            ]
        ]
        [ H.div
            [ A.css
                [ S.hFull
                , S.maxWFull
                , S.bgNightwood2
                , S.imageMask bradleyPortraitSource
                ]
            ]
            [ H.img
                [ A.src bradleyPortraitSource
                , A.alt ""
                , A.css
                    [ S.block
                    , S.wAuto
                    , S.maxWFull
                    , S.hFull
                    , S.objectContain
                    , S.opacity 0.24
                    ]
                ]
                []
            ]
        ]


quotation : Html msg
quotation =
    H.blockquote
        [ A.css
            [ S.fixed
            , S.right8
            , S.topValue "50%"
            , S.transform "translateY(-50%)"
            , S.widthValue "calc((100vw - 40rem) / 2 - 3rem)"
            , S.maxW96
            , S.col
            , S.g3
            , S.textGray4
            , S.animation bradleyEntranceAnimation
            , S.reducedMotion
                [ S.animationNone
                ]
            , S.belowWidth 1200
                [ S.relative
                , S.right0
                , S.topValue "auto"
                , S.transform "none"
                , S.wFull
                , S.textAlignCenter
                ]
            ]
        ]
        [ H.p
            [ A.css
                [ S.fontSizeRem 1.5
                , S.belowWidth 720
                    [ S.fontSizeRem 1.25
                    ]
                ]
            ]
            [ H.text "“amateurs talk strategy."
            , H.br
                []
                []
            , H.text "professionals talk logistics.”"
            ]
        , H.footer
            [ A.css
                [ S.textGray3
                ]
            ]
            [ H.text "— general omar bradley" ]
        ]


bradleyPortraitSource : String
bradleyPortraitSource =
    "/assets/omar-bradley-cutout-v1.png"


bradleyEntranceAnimation : String
bradleyEntranceAnimation =
    "fightlines-home-fade-enter 1600ms ease-out 1000ms both"


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-home-logo-enter {
                from { opacity: 0; transform: translateY(-2rem); }
                to { opacity: 1; transform: translateY(0); }
            }

            @keyframes fightlines-home-fade-enter {
                from { opacity: 0; }
                to { opacity: 1; }
            }

            @keyframes fightlines-home-battlefield-emerge {
                0% {
                    opacity: 0;
                    transform: translate3d(-3%, 5%, 0) scale(0.94);
                    animation-timing-function: ease-out;
                }
                10% { opacity: 0.38; }
                18% {
                    opacity: 0.32;
                    animation-timing-function: ease-in;
                }
                30%, 100% {
                    opacity: 0;
                    transform: translate3d(4%, -5%, 0) scale(1.08);
                }
            }
        """
        ]
