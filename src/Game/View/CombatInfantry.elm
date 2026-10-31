module Game.View.CombatInfantry exposing
    ( Loadout(..)
    , endsAt
    , frameAt
    , impactsStartAt
    , loadoutFor
    , preload
    , toSvg
    )

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Game.View.CombatAttack as CombatAttack
import Game.View.UnitSprite as UnitSprite exposing (Appearance)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
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


burstDurationMs : Float
burstDurationMs =
    1920


{-| Small-arms hits begin midway through sustained fire rather than after it.
The theater adds the same short contact buffer used by other weapons.
-}
impactsStartAt : CombatAttack.Attack -> Int -> Float
impactsStartAt attack figures =
    case attack of
        CombatAttack.Attacking timing ->
            if figures > 0 then
                timing.startsAt + burstDurationMs / 2

            else
                0

        CombatAttack.NotAttacking ->
            0


endsAt : CombatAttack.Attack -> Int -> Float
endsAt attack figures =
    case attack of
        CombatAttack.Attacking timing ->
            if figures > 0 then
                timing.startsAt + burstDurationMs

            else
                0

        CombatAttack.NotAttacking ->
            0


{-| Short flashes use individual phases and cadences, including repeated poses.
The shared presentation clock freezes these frames during pauses and map peeks.
-}
frameAt : { elapsed : Float, figureIndex : Int } -> CombatAttack.Attack -> Int
frameAt clock attack =
    case attack of
        CombatAttack.NotAttacking ->
            0

        CombatAttack.Attacking timing ->
            let
                age : Float
                age =
                    clock.elapsed - timing.startsAt

                offsetMs : Int
                offsetMs =
                    modBy 7 (clock.figureIndex * 3) * 20

                cadenceMs : Int
                cadenceMs =
                    if clock.figureIndex == 0 then
                        90

                    else
                        160 + modBy 3 clock.figureIndex * 20

                figureAgeMs : Int
                figureAgeMs =
                    floor age - offsetMs

                flashing : Bool
                flashing =
                    (age < burstDurationMs)
                        && (figureAgeMs >= 0)
                        && (modBy cadenceMs figureAgeMs < 40)
            in
            if flashing then
                1

            else
                0


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


spritePath : Pose -> String -> Int -> String
spritePath pose team frame =
    let
        suffix : String
        suffix =
            if frame == 1 then
                "-firing"

            else
                ""
    in
    "/assets/combat-infantry-v1/" ++ poseName pose ++ "-" ++ team ++ suffix ++ ".png"


preload : Html msg
preload =
    let
        posePaths : Pose -> List String
        posePaths pose =
            [ spritePath pose "red" 0
            , spritePath pose "red" 1
            , spritePath pose "blue" 0
            , spritePath pose "blue" 1
            ]

        image : String -> Html msg
        image path =
            H.node "link"
                [ A.rel "preload"
                , A.attribute "as" "image"
                , A.href path
                ]
                []
    in
    H.div
        [ A.hidden True ]
        (List.concatMap posePaths [ MachineGunTeam, Standing, Kneeling, Prone ]
            |> List.map image
        )


type alias Drawing =
    { width : Int
    , height : Int
    , padding : Int
    }


drawingFor : Pose -> PlayerNumber -> Drawing
drawingFor pose player =
    case pose of
        Standing ->
            { width = 627, height = 627, padding = 96 }

        Kneeling ->
            { width = 512, height = 458, padding = 96 }

        Prone ->
            { width = 512, height = 131, padding = 96 }

        MachineGunTeam ->
            case player of
                PlayerNumber.Player1 ->
                    { width = 512, height = 278, padding = 128 }

                PlayerNumber.Player2 ->
                    { width = 512, height = 277, padding = 128 }


toSvg : { elapsed : Float, figureIndex : Int } -> CombatAttack.Attack -> Appearance -> Svg msg
toSvg clock attack unit =
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
            poseAt clock.figureIndex

        frame : Int
        frame =
            frameAt clock attack

        drawing : Drawing
        drawing =
            drawingFor pose unit.playerNumber

        standingViewBox : String
        standingViewBox =
            case unit.playerNumber of
                PlayerNumber.Player1 ->
                    "139 59 452 508"

                PlayerNumber.Player2 ->
                    "154 83 456 515"

        viewBox : String
        viewBox =
            if pose == Standing then
                standingViewBox

            else
                "0 0 512 486"

        imageY : Int
        imageY =
            if pose == Standing then
                0

            else
                486 - drawing.height

        artwork : Int -> Svg msg
        artwork index =
            let
                width : Int
                width =
                    if index == 1 then
                        drawing.width + drawing.padding

                    else
                        drawing.width
            in
            -- Retain the idle canvas scale and footing. Only the flash extends
            -- beyond its right edge, so swapping frames cannot shrink the figure.
            Svg.svg
                [ SA.width "16"
                , SA.height (String.fromFloat (UnitSprite.portraitFooting unit))
                , SA.viewBox viewBox
                , SA.preserveAspectRatio "xMidYMax meet"
                , SA.overflow "visible"
                ]
                [ Svg.image
                    [ SA.xlinkHref (spritePath pose team index)
                    , SA.y (String.fromInt imageY)
                    , SA.width (String.fromInt width)
                    , SA.height (String.fromInt drawing.height)
                    ]
                    []
                ]
    in
    Svg.g
        [ SA.transform facing
        , A.attribute "data-infantry-pose" (poseName pose)
        , A.attribute "data-infantry-frame" (String.fromInt frame)
        ]
        [ Svg.g
            [ A.css
                [ S.reducedMotion
                    [ S.displayNone ]
                ]
            ]
            [ artwork frame ]
        , Svg.g
            [ A.css
                [ S.displayNone
                , S.reducedMotion
                    [ Css.display Css.inline ]
                ]
            ]
            [ artwork 0 ]
        ]
