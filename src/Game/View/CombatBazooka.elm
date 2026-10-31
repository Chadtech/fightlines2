module Game.View.CombatBazooka exposing
    ( endsAt
    , frameAt
    , preload
    , toSvg
    )

import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Css
import Game.View.CombatAttack as CombatAttack
import Game.View.UnitSprite as UnitSprite exposing (Appearance)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA


{-| One launch and recovery, then hold the exact ready drawing. Figures share
the other theater weapons' stagger and the recorded participant's attack clock.
-}
endsAt : CombatAttack.Attack -> Int -> Float
endsAt attack figures =
    case attack of
        CombatAttack.Attacking timing ->
            if figures > 0 then
                timing.startsAt + toFloat (figures - 1) * CombatAttack.staggerMs + 800

            else
                0

        CombatAttack.NotAttacking ->
            0


frameAt : Float -> Int
frameAt age =
    [ 0, 140, 180, 260, 420, 610, 800 ]
        |> List.filter (\startsAt -> age >= startsAt)
        |> List.length


path : String -> String
path team =
    "/assets/bazooka-firing-v1/" ++ team ++ ".png"


preload : Html msg
preload =
    let
        image : String -> Html msg
        image team =
            H.node "link"
                [ A.rel "preload"
                , A.attribute "as" "image"
                , A.href (path team)
                ]
                []
    in
    H.div
        [ A.hidden True ]
        (List.map image [ "red", "blue" ])


toSvg : { elapsed : Float, figureIndex : Int } -> CombatAttack.Attack -> Appearance -> Svg msg
toSvg clock attack unit =
    let
        frame : Int
        frame =
            case attack of
                CombatAttack.NotAttacking ->
                    0

                CombatAttack.Attacking timing ->
                    frameAt (clock.elapsed - timing.startsAt - toFloat clock.figureIndex * CombatAttack.staggerMs)

        team : String
        team =
            case unit.playerNumber of
                PlayerNumber.Player1 ->
                    "red"

                PlayerNumber.Player2 ->
                    "blue"

        facing : String
        facing =
            case unit.spriteFacing of
                SpriteFacing.Left ->
                    "translate(16 0) scale(-1 1)"

                SpriteFacing.Right ->
                    ""

        drawing : Int -> Svg msg
        drawing index =
            Svg.svg
                -- The pair spans about 384px of each 640x512 cell. Its center
                -- is x=336; the registered boots meet y=460. Preserve the
                -- existing 16-unit pair width and calibrated ground contact.
                [ SA.x (String.fromFloat (8 - 336 / 24))
                , SA.y (String.fromFloat (UnitSprite.portraitFooting unit - 460 / 24))
                , SA.width (String.fromFloat (640 / 24))
                , SA.height (String.fromFloat (512 / 24))
                , SA.viewBox
                    (String.fromInt (modBy 4 index * 640)
                        ++ " "
                        ++ String.fromInt (index // 4 * 512)
                        ++ " 640 512"
                    )
                ]
                [ Svg.image
                    [ SA.xlinkHref (path team)
                    , SA.width "2560"
                    , SA.height "1024"
                    ]
                    []
                ]
    in
    Svg.g
        [ SA.transform facing
        , A.attribute "data-infantry-pose" "bazooka-team"
        , A.attribute "data-bazooka-frame" (String.fromInt frame)
        ]
        [ Svg.g
            [ A.css
                [ S.reducedMotion
                    [ S.displayNone ]
                ]
            ]
            [ drawing frame ]
        , Svg.g
            [ A.css
                [ S.displayNone
                , S.reducedMotion
                    [ Css.display Css.inline ]
                ]
            ]
            [ drawing 0 ]
        ]
