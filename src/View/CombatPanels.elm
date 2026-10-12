module View.CombatPanels exposing (Msg(..), styles, toHtml)

import Api.Enum.SpriteFacing as SpriteFacing
import CombatHealth exposing (CombatHealth)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
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
import View.CombatEffects as CombatEffects
import View.UnitSprite as UnitSprite


type Msg
    = ContinueClicked
    | SeeMapPressed
    | SeeMapReleased


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
            .fightlines-combat-panels { animation: fightlines-combat-pop 200ms ease-out both; }
            .fightlines-combat-focus *:not(.fightlines-combat-shine),
            .fightlines-combat-focus *::before,
            .fightlines-combat-focus *::after { animation-play-state: paused !important; }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-combat-panels { animation: none; }
                .fightlines-combat-health-fill { width: var(--combat-health-end) !important; }
            }
        """
        ]


toHtml : Panel -> Html Msg
toHtml panel =
    let
        attacker : Unit
        attacker =
            panel.exchange.attacker

        target : Unit
        target =
            panel.exchange.target

        card : Card.Card
        card =
            Card.simple |> Card.withHeader (CardHeader.simple "ambush")

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
        , Aria.label "ambush"
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
        [ H.div
            [ Aria.hidden True
            , A.css
                [ S.absolute
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.bgNightwood2
                , Css.opacity (Css.num shadeOpacity)
                ]
            ]
            []
        , H.div
            [ A.class "fightlines-combat-card"
            , A.css
                [ S.relative
                , S.wFull
                , S.textGray5
                , Css.maxWidth (Css.rem 44)
                , Css.opacity (Css.num cardOpacity)
                , Css.maxHeight (Css.calc (Css.vh 100) (Css.minus (Css.rem 1.5)))
                , S.overflowAuto
                ]
            ]
            [ H.div
                [ A.class "fightlines-combat-panels"
                ]
                [ Card.toHtml card
                    [ H.div
                        [ A.css
                            [ S.grid
                            , S.g3
                            , Css.property "grid-template-columns" "minmax(0, 1fr) minmax(0, 1fr)"
                            ]
                        ]
                        [ portrait panel.elapsed panel.exchange.attackerHealth { attacker | spriteFacing = SpriteFacing.Right }
                        , portrait panel.elapsed panel.exchange.targetHealth { target | spriteFacing = SpriteFacing.Left }
                        ]
                    , H.div
                        [ A.css
                            [ S.row
                            , S.g3
                            , S.justifySpaceBetween
                            ]
                        ]
                        [ H.div
                            [ Ev.onMouseDown SeeMapPressed
                            , Ev.onMouseUp SeeMapReleased
                            , Ev.onMouseLeave SeeMapReleased
                            ]
                            [ Button.secondary "see map" SeeMapReleased |> Button.toHtml
                            ]
                        , H.div
                            [ Ev.preventDefaultOn "keydown" (HtmlEvent.enter ( SeeMapReleased, True ))
                            , Ev.stopPropagationOn "keyup" (HtmlEvent.enter ( ContinueClicked, True ))
                            ]
                            [ Button.primary "continue" ContinueClicked |> Button.toHtml
                            ]
                        ]
                    ]
                ]
            ]
        ]


portrait : Float -> CombatHealth -> Unit -> Html Msg
portrait elapsed health unit =
    let
        explosion : List (Html Msg)
        explosion =
            if health.after.current < health.before.current && elapsed >= 200 && elapsed < 560 then
                [ Svg.svg
                    [ SA.viewBox "-12 -12 24 24"
                    , Aria.label "unit hit"
                    , SA.css
                        [ S.absolute
                        , S.top0
                        , S.left0
                        , S.wFull
                        , S.hFull
                        ]
                    ]
                    [ CombatEffects.explosion |> Svg.fromUnstyled
                    ]
                ]

            else
                []

        sprite : Html Msg
        sprite =
            Svg.svg
                [ SA.viewBox "0 0 16 16"
                , Aria.role Aria.Image
                , Aria.label (Unit.label unit)
                , SA.css
                    [ S.block
                    , S.wFull
                    , Css.property "aspect-ratio" "1"
                    , Css.maxHeight (Css.vh 40)
                    ]
                ]
                [ UnitSprite.toSvg 0 unit
                ]

        content : List (Html Msg)
        content =
            sprite :: explosion
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            , S.minW0
            ]
        ]
        [ H.div
            [ A.css
                [ S.relative
                , S.bgNightwood3
                , S.indentStrong
                ]
            ]
            content
        , healthBar elapsed health
        ]


healthBar : Float -> CombatHealth -> Html Msg
healthBar elapsed health =
    let
        progress : Float
        progress =
            clamp 0 1 ((elapsed - 560) / 500)

        current : Float
        current =
            toFloat health.before.current + toFloat (health.after.current - health.before.current) * progress

        percent : Float
        percent =
            100 * current / toFloat health.after.maximum

        endPercent : Float
        endPercent =
            if elapsed < 560 then
                100 * toFloat health.before.current / toFloat health.before.maximum

            else
                100 * toFloat health.after.current / toFloat health.after.maximum

        color : Css.Style
        color =
            if percent < 25 then
                S.bgRed1

            else if percent <= 75 then
                S.bgYellow4

            else
                S.bgGreen1
    in
    H.div
        [ Aria.role Aria.Meter
        , Aria.label "hit points"
        , Aria.valueMin 0
        , Aria.valueMax health.after.maximum
        , Aria.valueNow (round current)
        , A.css
            [ S.col
            , S.g1
            ]
        ]
        [ H.p []
            [ H.text (String.fromInt (round current) ++ " / " ++ String.fromInt health.after.maximum)
            ]
        , H.div
            [ A.css
                [ S.bgNightwood3
                , S.h3
                , S.overflowHidden
                ]
            ]
            [ H.div
                [ A.class "fightlines-combat-health-fill"
                , A.css
                    [ color
                    , S.hFull
                    , Css.width (Css.pct percent)
                    , Css.property "--combat-health-end" (String.fromFloat endPercent ++ "%")
                    ]
                ]
                []
            ]
        ]
