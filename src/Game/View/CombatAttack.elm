module Game.View.CombatAttack exposing
    ( Attack(..)
    , anticipationMs
    , endsAt
    , firingTimes
    , frameAt
    , preload
    , toSvg
    )

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Game.View.UnitSprite as UnitSprite exposing (Appearance)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA


{-| Only recorded firing participants receive an attack, including zero-damage shots.
The starting time belongs to the formation; each figure adds its own stagger.
-}
type Attack
    = NotAttacking
    | Attacking { startsAt : Float }


anticipationMs : Float
anticipationMs =
    1200


staggerMs : Float
staggerMs =
    90


durationMs : UnitKind -> Float
durationMs kind =
    case kind of
        Kind.Tank ->
            1050

        Kind.FieldGun ->
            840

        _ ->
            0


{-| Field-gun crews signal and brace before the muzzle flash.
-}
shotOffsetMs : UnitKind -> Float
shotOffsetMs kind =
    case kind of
        Kind.FieldGun ->
            320

        _ ->
            0


firingTimes : Attack -> UnitKind -> Int -> List Float
firingTimes attack kind figures =
    case attack of
        NotAttacking ->
            []

        Attacking timing ->
            if (figures > 0) && (durationMs kind > 0) then
                List.range 0 (figures - 1)
                    |> List.map (\index -> timing.startsAt + shotOffsetMs kind + toFloat index * staggerMs)

            else
                []


endsAt : Attack -> UnitKind -> Int -> Float
endsAt attack kind figures =
    firingTimes attack kind figures
        |> List.maximum
        |> Maybe.map ((+) (durationMs kind - shotOffsetMs kind))
        |> Maybe.withDefault 0


{-| The theater replaces the authoring previews' initial/final holds.
Fire and recover once, then hold the final drawn pose afterward.
-}
frameAt : UnitKind -> Float -> Int
frameAt kind age =
    let
        frameStarts : List Float
        frameStarts =
            case kind of
                Kind.Tank ->
                    [ 0, 30, 80, 160, 250, 370, 550, 790, 1050 ]

                Kind.FieldGun ->
                    [ 0, 220, 320, 390, 500, 660, 840 ]

                _ ->
                    []
    in
    if age < 0 then
        0

    else
        frameStarts
            |> List.filter (\startsAt -> age >= startsAt)
            |> List.length


tankPath : String -> String
tankPath team =
    "/assets/tank-firing-drawn-v6/" ++ team ++ ".png"


fieldGunPath : String -> String
fieldGunPath team =
    "/assets/field-gun-firing-drawn-v2/" ++ team ++ ".png"


teamName : PlayerNumber -> String
teamName player =
    case player of
        PlayerNumber.Player1 ->
            "red"

        PlayerNumber.Player2 ->
            "blue"


preload : Html msg
preload =
    let
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
        (List.map image [ tankPath "red", tankPath "blue", fieldGunPath "red", fieldGunPath "blue" ])


toSvg : { elapsed : Float, figureIndex : Int } -> Attack -> Appearance -> Svg msg
toSvg clock attack unit =
    case attack of
        Attacking timing ->
            let
                frame : Int
                frame =
                    frameAt unit.kind (clock.elapsed - timing.startsAt - toFloat clock.figureIndex * staggerMs)
            in
            case unit.kind of
                Kind.Tank ->
                    tankToSvg frame unit

                Kind.FieldGun ->
                    fieldGunToSvg frame unit

                _ ->
                    UnitSprite.portraitToSvg unit

        NotAttacking ->
            UnitSprite.portraitToSvg unit


type alias Atlas =
    { path : String
    , columns : Int
    , cellWidth : Int
    , cellHeight : Int
    , portraitWidth : Float
    , x : Float
    , y : Float
    , width : Float
    , height : Float
    }


tankToSvg : Int -> Appearance -> Svg msg
tankToSvg frame unit =
    -- The drawn cell's track anchor is (155.75,255.5). Match the original
    -- 16-unit portrait's center and footing, including ready/final holds.
    atlasToSvg
        { path = tankPath (teamName unit.playerNumber)
        , columns = 5
        , cellWidth = 448
        , cellHeight = 288
        , portraitWidth = 16
        , x = 8 - 155.75 / 16
        , y = UnitSprite.portraitFooting unit - 255.5 / 16
        , width = 28
        , height = 18
        }
        frame
        unit


fieldGunToSvg : Int -> Appearance -> Svg msg
fieldGunToSvg frame unit =
    let
        -- The runtime cell's wheel is at (496,260), radius 65px. Align its
        -- radius and ground contact to the static 40x16 portrait's wheel.
        scale : Float
        scale =
            3.75 / 65
    in
    atlasToSvg
        { path = fieldGunPath (teamName unit.playerNumber)
        , columns = 4
        , cellWidth = 1024
        , cellHeight = 368
        , portraitWidth = 40
        , x = 25.85 - 496 * scale
        , y = UnitSprite.portraitFooting unit - 325 * scale
        , width = 1024 * scale
        , height = 368 * scale
        }
        frame
        unit


atlasToSvg : Atlas -> Int -> Appearance -> Svg msg
atlasToSvg atlas frame unit =
    let
        facing : String
        facing =
            case unit.spriteFacing of
                SpriteFacing.Left ->
                    "translate(" ++ String.fromFloat atlas.portraitWidth ++ " 0) scale(-1 1)"

                SpriteFacing.Right ->
                    ""

        viewBox : String
        viewBox =
            String.fromInt (modBy atlas.columns frame * atlas.cellWidth)
                ++ " "
                ++ String.fromInt (frame // atlas.columns * atlas.cellHeight)
                ++ " "
                ++ String.fromInt atlas.cellWidth
                ++ " "
                ++ String.fromInt atlas.cellHeight
    in
    Svg.g
        [ A.attribute "data-attack-frame" (String.fromInt frame) ]
        [ Svg.g
            [ A.css
                [ S.reducedMotion
                    [ S.displayNone
                    ]
                ]
            , SA.transform facing
            ]
            [ Svg.svg
                [ SA.x (String.fromFloat atlas.x)
                , SA.y (String.fromFloat atlas.y)
                , SA.width (String.fromFloat atlas.width)
                , SA.height (String.fromFloat atlas.height)
                , SA.viewBox viewBox
                ]
                [ Svg.image
                    [ SA.xlinkHref atlas.path
                    , SA.width (String.fromInt (atlas.cellWidth * atlas.columns))
                    , SA.height (String.fromInt (atlas.cellHeight * 2))
                    ]
                    []
                ]
            ]
        , Svg.g
            [ A.css
                [ S.displayNone
                , S.reducedMotion
                    [ Css.display Css.inline
                    ]
                ]
            ]
            [ UnitSprite.portraitToSvg unit ]
        ]
