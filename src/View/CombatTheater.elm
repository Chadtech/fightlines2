module View.CombatTheater exposing (Msg(..), attackerOnLeft, backdropPath, readyToAutomaticallyClose, styles, toHtml)

import Api.Enum.CombatKind as CombatKind
import Api.Enum.MapTheme as MapTheme exposing (MapTheme)
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.Terrain as Terrain exposing (Terrain)
import CombatHealth exposing (CombatHealth)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Map exposing (Map)
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import TurnPlayback exposing (MapView(..), Panel)
import Unit exposing (Unit)
import Util.Html.Event as HtmlEvent
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Checkbox as Checkbox
import View.CombatExplosion as CombatExplosion
import View.CombatFormation as CombatFormation


type Msg
    = ContinueClicked
    | SeeMapPressed
    | SeeMapReleased
    | AutomaticallyCloseChanged Bool


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-combat-pop {
                0% { transform: scale(.65); opacity: 0; }
                70% { transform: scale(1.04); opacity: 1; }
                100% { transform: scale(1); opacity: 1; }
            }
            .fightlines-combat-focus *:not(.fightlines-combat-shine),
            .fightlines-combat-focus *::before,
            .fightlines-combat-focus *::after { animation-play-state: paused !important; }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-combat-figure { opacity: 1 !important; }
                .fightlines-combat-rumble { transform: none !important; }
            }
        """
        ]


{-| Preserve horizontal map order; for vertical encounters, north appears left.
-}
attackerOnLeft : Panel -> Bool
attackerOnLeft panel =
    case
        ( Unit.boardPosition panel.exchange.attacker
        , Unit.boardPosition panel.exchange.target
        )
    of
        ( Just attacker, Just target ) ->
            (attacker.x < target.x)
                || ((attacker.x == target.x) && (attacker.y <= target.y))

        _ ->
            True


{-| Let the final impact and its camera shake settle, then pause for half a second.
Keeping the map button held always keeps the encounter open.
-}
readyToAutomaticallyClose : Panel -> Bool
readyToAutomaticallyClose panel =
    let
        lastImpact : Float
        lastImpact =
            [ panel.exchange.attackerHealth, panel.exchange.targetHealth ]
                |> List.concatMap CombatFormation.impactStarts
                |> List.maximum
                |> Maybe.withDefault 1200

        animationEndsAt : Float
        animationEndsAt =
            lastImpact + impactContactDelayMs + rumbleDurationMs
    in
    panel.mapView == CardVisible && panel.elapsed >= animationEndsAt + automaticCloseDelayMs


impactContactDelayMs : Float
impactContactDelayMs =
    20


rumbleDurationMs : Float
rumbleDurationMs =
    160


automaticCloseDelayMs : Float
automaticCloseDelayMs =
    500


toHtml : { automaticallyClose : Bool } -> Map -> Panel -> Html Msg
toHtml config map panel =
    let
        attacker : Unit
        attacker =
            panel.exchange.attacker

        target : Unit
        target =
            panel.exchange.target

        portraits : List (Html Msg)
        portraits =
            if attackerOnLeft panel then
                [ portrait
                    map
                    panel
                    panel.exchange.attackerHealth
                    { attacker | spriteFacing = SpriteFacing.Right }
                , portrait
                    map
                    panel
                    panel.exchange.targetHealth
                    { target | spriteFacing = SpriteFacing.Left }
                ]

            else
                [ portrait
                    map
                    panel
                    panel.exchange.targetHealth
                    { target | spriteFacing = SpriteFacing.Right }
                , portrait
                    map
                    panel
                    panel.exchange.attackerHealth
                    { attacker | spriteFacing = SpriteFacing.Left }
                ]

        title : String
        title =
            case panel.exchange.kind of
                CombatKind.IndirectFire ->
                    "indirect fire"

                CombatKind.Ambush ->
                    "ambush"

                CombatKind.AttackMove ->
                    "attack move"

        card : Card.Card
        card =
            Card.simple
                |> Card.withHeader (CardHeader.simple title)

        cardOpacity : Float
        cardOpacity =
            case panel.mapView of
                CardVisible ->
                    1

                SeeingMap ->
                    0

        shadeOpacity : Float
        shadeOpacity =
            case panel.mapView of
                CardVisible ->
                    0.85

                SeeingMap ->
                    0
    in
    H.div
        [ A.attribute "data-combat-panels" ""
        , Aria.role Aria.Group
        , Aria.label title
        , A.css
            [ S.fixed
            , S.top0
            , S.bottom0
            , S.left0
            , S.right0
            , S.z4
            , S.col
            , S.itemsCenter
            , S.justifyCenter
            , S.p3
            ]
        ]
        [ CombatExplosion.styles
        , CombatExplosion.preload
        , H.div
            [ Aria.hidden True
            , A.css
                [ S.absolute
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.bgNightwood2
                , S.opacity shadeOpacity
                ]
            ]
            []
        , H.div
            [ A.css
                [ S.relative
                , S.wFull
                , S.textGray5
                , S.maxW256
                , S.opacity cardOpacity
                , S.maxHViewportInsetRem 1.5
                , S.overflowAuto
                ]
            ]
            [ H.div
                [ A.css
                    [ S.animation "fightlines-combat-pop 200ms ease-out both"
                    , S.reducedMotion
                        [ S.animationNone ]
                    ]
                ]
                [ Card.toHtml card
                    [ H.div
                        [ A.css
                            [ S.grid
                            , S.g3
                            , S.gridCols2
                            ]
                        ]
                        portraits
                    , H.div
                        [ A.css
                            [ S.row
                            , S.g3
                            , S.flexWrap
                            , S.itemsCenter
                            ]
                        ]
                        [ H.div
                            [ Ev.preventDefaultOn "keydown" (HtmlEvent.enter ( SeeMapReleased, True ))
                            , Ev.stopPropagationOn "keyup" (HtmlEvent.enter ( ContinueClicked, True ))
                            ]
                            [ Button.primary "continue" ContinueClicked |> Button.toHtml
                            ]
                        , H.div
                            [ Ev.onMouseDown SeeMapPressed
                            , Ev.onMouseUp SeeMapReleased
                            , Ev.onMouseLeave SeeMapReleased
                            ]
                            [ Button.secondary "see map" SeeMapReleased |> Button.toHtml
                            ]
                        , Checkbox.toHtml
                            { label = "automatically close"
                            , checked = config.automaticallyClose
                            , onCheck = AutomaticallyCloseChanged
                            }
                            [ H.text "automatically close" ]
                        ]
                    ]
                ]
            ]
        ]


backdropPath : MapTheme -> Terrain -> String
backdropPath theme terrain =
    let
        name : String
        name =
            case ( theme, terrain ) of
                ( MapTheme.GreenForest, Terrain.Forest ) ->
                    "forest"

                ( MapTheme.Snow, Terrain.Forest ) ->
                    "snowy-forest"

                ( MapTheme.Desert, Terrain.Forest ) ->
                    "desert-forest"

                ( MapTheme.GreenForest, Terrain.Hills ) ->
                    "hills"

                ( MapTheme.Snow, Terrain.Hills ) ->
                    "snowy-hills"

                ( MapTheme.Desert, Terrain.Hills ) ->
                    "desert-hills"

                ( MapTheme.GreenForest, Terrain.Mountains ) ->
                    "mountains"

                ( MapTheme.Snow, Terrain.Mountains ) ->
                    "snowy-mountains"

                ( MapTheme.Desert, Terrain.Mountains ) ->
                    "desert-mountains"

                ( MapTheme.GreenForest, Terrain.GrassPlain ) ->
                    "plains"

                ( MapTheme.Snow, Terrain.GrassPlain ) ->
                    "tundra-plains"

                ( MapTheme.Desert, Terrain.GrassPlain ) ->
                    "desert-plains"
    in
    "/assets/combat-backdrops-anime-v1/" ++ name ++ ".png"


{-| Both scenes share a camera kick at contact, then settle over 160ms.
Use the presentation clock instead of restarting a CSS animation on each render.
-}
rumbleTransform : Panel -> String
rumbleTransform panel =
    let
        contactStarts : List Float
        contactStarts =
            [ panel.exchange.attackerHealth, panel.exchange.targetHealth ]
                |> List.concatMap CombatFormation.impactStarts
                |> List.map ((+) impactContactDelayMs)
                |> List.filter (\startsAt -> startsAt <= panel.elapsed)

        transform : Float -> String
        transform startsAt =
            let
                age : Float
                age =
                    panel.elapsed - startsAt

                strength : Float
                strength =
                    (1 - clamp 0 1 (age / rumbleDurationMs)) ^ 2

                x : Float
                x =
                    2.4 * strength * cos (age * 0.15)

                y : Float
                y =
                    1.5 * strength * sin (age * 0.21)

                rotation : Float
                rotation =
                    0.7 * strength * cos (age * 0.12)
            in
            "translate("
                ++ String.fromFloat x
                ++ "px, "
                ++ String.fromFloat y
                ++ "px) rotate("
                ++ String.fromFloat rotation
                ++ "deg)"
    in
    contactStarts
        |> List.maximum
        |> Maybe.map transform
        |> Maybe.withDefault "none"


portrait : Map -> Panel -> CombatHealth -> Unit -> Html Msg
portrait map panel health unit =
    let
        terrain : Terrain
        terrain =
            Unit.boardPosition unit
                |> Maybe.map (Map.terrainAt map)
                |> Maybe.withDefault map.baseTile

        path : String
        path =
            backdropPath map.theme terrain

        background : Svg.Svg Msg
        background =
            Svg.image
                [ SA.xlinkHref path
                , SA.x "-4"
                , SA.y "-4"
                , SA.width "104"
                , SA.height "72"
                , SA.preserveAspectRatio "xMidYMid slice"
                , Aria.hidden True
                ]
                []

        figures : List (Svg.Svg Msg)
        figures =
            CombatFormation.toSvg panel.elapsed health unit

        content : List (Svg.Svg Msg)
        content =
            background :: figures

        description : String
        description =
            Unit.label unit
                ++ ": "
                ++ String.fromInt (CombatFormation.figureCount health.before.current)
                ++ " before combat, "
                ++ String.fromInt (CombatFormation.figureCount health.after.current)
                ++ " remaining"
    in
    Svg.svg
        [ SA.viewBox "0 0 96 64"
        , Aria.role Aria.Image
        , Aria.label description
        , A.attribute "data-combat-backdrop" path
        , SA.css
            [ S.block
            , S.wFull
            , S.minW0
            , S.bgNightwood3
            , S.indentStrong
            , S.aspectRatio { width = 3, height = 2 }
            ]
        ]
        [ Svg.g
            [ SA.class "fightlines-combat-rumble"
            , SA.css
                [ S.transform (rumbleTransform panel)
                , Css.property "transform-origin" "48px 32px"
                ]
            ]
            content
        ]
