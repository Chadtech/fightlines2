module Game.View.CombatInfantry exposing
    ( Loadout(..)
    , loadoutFor
    , toSvg
    )

import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Game.View.CombatAttack as CombatAttack
import Game.View.UnitSprite as UnitSprite exposing (Appearance)
import Html.Styled.Attributes as A
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA


type Loadout
    = SmallArms
    | Bazookas


{-| Only infantry actually firing at a tank switch to the anti-tank teams.
The theater supplies the recorded opponent, including reciprocal fire.
-}
loadoutFor : { kind : UnitKind, attack : CombatAttack.Attack, targetKind : Maybe UnitKind } -> Loadout
loadoutFor participant =
    case ( participant.kind, participant.attack, participant.targetKind ) of
        ( Kind.Infantry, CombatAttack.Attacking _, Just Kind.Tank ) ->
            Bazookas

        _ ->
            SmallArms


type Pose
    = MachineGunTeam
    | Standing
    | Kneeling
    | Prone
    | BazookaTeam


poseAt : Int -> Pose
poseAt index =
    case index of
        0 ->
            MachineGunTeam

        1 ->
            Standing

        2 ->
            Kneeling

        3 ->
            Kneeling

        _ ->
            Prone


poseName : Pose -> String
poseName pose =
    case pose of
        MachineGunTeam ->
            "machine-gun-team"

        Standing ->
            "standing"

        Kneeling ->
            "kneeling"

        Prone ->
            "prone"

        BazookaTeam ->
            "bazooka-team"


toSvg : Loadout -> Int -> Appearance -> Svg msg
toSvg loadout index unit =
    let
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

        pose : Pose
        pose =
            case loadout of
                SmallArms ->
                    poseAt index

                Bazookas ->
                    BazookaTeam

        path : String
        path =
            "/assets/combat-infantry-v1/" ++ poseName pose ++ "-" ++ team ++ ".png"

        standingViewBox : String
        standingViewBox =
            case unit.playerNumber of
                PlayerNumber.Player1 ->
                    "139 59 452 508"

                PlayerNumber.Player2 ->
                    "154 83 456 515"

        artwork : Svg msg
        artwork =
            case pose of
                Standing ->
                    -- Frame the visible figure in SVG, retaining the original PNG pixels and margins.
                    Svg.svg
                        [ SA.width "16"
                        , SA.height (String.fromFloat (UnitSprite.portraitFooting unit))
                        , SA.viewBox standingViewBox
                        , SA.preserveAspectRatio "xMidYMax meet"
                        , SA.overflow "visible"
                        ]
                        [ Svg.image
                            [ SA.xlinkHref path
                            , SA.width "627"
                            , SA.height "627"
                            ]
                            []
                        ]

                _ ->
                    Svg.image
                        [ SA.xlinkHref path
                        , SA.width "16"
                        , SA.height (String.fromFloat (UnitSprite.portraitFooting unit))
                        , SA.preserveAspectRatio "xMidYMax meet"
                        ]
                        []
    in
    Svg.g
        [ SA.transform facing
        , A.attribute "data-infantry-pose" (poseName pose)
        ]
        [ artwork ]
