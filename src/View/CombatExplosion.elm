module View.CombatExplosion exposing
    ( durationMs
    , preload
    , spriteDisappearsAt
    , spriteOpacity
    , styles
    , toSvg
    )

import Api.Enum.SpriteFacing as SpriteFacing exposing (SpriteFacing)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria


durationMs : Float
durationMs =
    100


framePath : Int -> String
framePath index =
    "/assets/combat-impact-side-anime-v2/frame-" ++ String.fromInt index ++ ".png"


{-| Fetch every frame during the anticipation beat, before the fast strike.
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
            [ 10, 20, 50, 80, 90 ]
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
