module Game.View.CombatExplosion exposing
    ( casualtyAnimationAttribute
    , durationMs
    , mapToSvg
    , preload
    , spriteDisappearsAt
    , spriteOpacity
    , styles
    , toSvg
    )

import Api.Enum.SpriteFacing as SpriteFacing exposing (SpriteFacing)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria


durationMs : Float
durationMs =
    100


casualtyAnimationAttribute : String
casualtyAnimationAttribute =
    "data-casualty-animation"


framePath : Int -> String
framePath index =
    "/assets/combat-impact-side-anime-v2/frame-" ++ String.fromInt index ++ ".png"


{-| Fetch every frame at startup for both map casualties and theater strikes.
-}
preload : Html msg
preload =
    let
        frame : Int -> Html msg
        frame index =
            H.node "link"
                [ A.rel "preload"
                , A.attribute "as" "image"
                , A.href (framePath index)
                ]
                []
    in
    H.div
        [ A.hidden True
        ]
        (List.map frame (List.range 0 5))


spriteDisappearsAt : Float
spriteDisappearsAt =
    50


{-| Hide the casualty beneath the pressure blast before it blows apart.
-}
spriteOpacity : Float -> Float
spriteOpacity elapsed =
    1 - clamp 0 1 ((elapsed - 20) / (spriteDisappearsAt - 20))


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-map-explosion {
                0% { opacity: 1;
                }
                100% { opacity: 0;
                }
            }
            .fightlines-theater-explosion-still { display: none; }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-theater-explosion-frame { display: none; }
                .fightlines-theater-explosion-still { display: inline; }
            }
        """
        ]


{-| Use the theater clock so frame selection survives map peeks and long ticks.
The horizontal strike comes from the opponent's side and ignores pointer events.
-}
toSvg : SpriteFacing -> Float -> Svg msg
toSvg facing elapsed =
    let
        frame : Int
        frame =
            frameStarts
                |> List.drop 1
                |> List.filter (\startsAt -> elapsed >= startsAt)
                |> List.length

        image : String -> Int -> Svg msg
        image className index =
            let
                horizontalOffset : Float
                horizontalOffset =
                    if index == 0 then
                        -24 + 8 * clamp 0 1 (elapsed / 10)

                    else if index == 1 then
                        -20

                    else
                        -16
            in
            Svg.image
                [ SA.xlinkHref (framePath index)
                , SA.x (String.fromFloat horizontalOffset)
                , SA.y "-16"
                , SA.width "32"
                , SA.height "32"
                , SA.class className
                ]
                []

        incomingDirection : String
        incomingDirection =
            case facing of
                SpriteFacing.Left ->
                    ""

                SpriteFacing.Right ->
                    "scale(-1 1)"
    in
    Svg.g
        [ SA.pointerEvents "none"
        , SA.transform incomingDirection
        , Aria.hidden True
        , A.attribute "data-explosion-frame" (String.fromInt frame)
        ]
        [ image "fightlines-theater-explosion-frame" frame
        , image "fightlines-theater-explosion-still" 3
        ]


frameStarts : List Float
frameStarts =
    [ 0, 10, 20, 50, 80, 90 ]


{-| Play once when a map casualty appears, even while a loss dialog holds the
playback clock. Reuse the theater frames and timing, then leave the tile empty.
Completed frames return to their base opacity instead of retaining a stepped
animation sample, which can leave the final frames visible after they finish.
-}
mapToSvg : SpriteFacing -> Svg msg
mapToSvg facing =
    let
        frame : Float -> Float -> Svg msg
        frame startsAt endsAt =
            Svg.g
                [ A.attribute casualtyAnimationAttribute ""
                , A.css
                    [ S.opacity 0
                    , S.animation
                        ("fightlines-map-explosion "
                            ++ String.fromFloat (endsAt - startsAt)
                            ++ "ms steps(1, end) "
                            ++ String.fromFloat startsAt
                            ++ "ms"
                        )
                    , S.reducedMotion
                        [ S.displayNone
                        ]
                    ]
                ]
                [ toSvg facing startsAt
                ]

        frameEnds : List Float
        frameEnds =
            List.drop 1 frameStarts ++ [ durationMs ]

        frames : List (Svg msg)
        frames =
            List.map2 frame frameStarts frameEnds

        still : Svg msg
        still =
            Svg.g
                [ A.attribute casualtyAnimationAttribute ""
                , A.css
                    [ S.displayNone
                    , S.opacity 0
                    , S.animation
                        ("fightlines-map-explosion "
                            ++ String.fromFloat durationMs
                            ++ "ms steps(1, end)"
                        )
                    , S.reducedMotion
                        [ Css.display Css.inline
                        ]
                    ]
                ]
                [ toSvg facing 50
                ]

        content : List (Svg msg)
        content =
            frames ++ [ still ]
    in
    Svg.g
        [ SA.transform "translate(8 8) scale(0.75)"
        , SA.pointerEvents "none"
        , Aria.hidden True
        ]
        content
