module Game.View.UnitSprite exposing
    ( Appearance
    , appearance
    , portraitFooting
    , portraitToSvg
    , portraitWidth
    , toSvg
    )

import Api.Enum.Entrenchment as Entrenchment exposing (Entrenchment)
import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.SpriteFacing as SpriteFacingEnum exposing (SpriteFacing)
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Game.Unit exposing (Unit)
import Html.Styled.Lazy as Lazy
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Sprite as Sprite


{-| Visual inputs shared by gameplay portraits and formation calibration.
No identity, position, resources, or combat rules are needed to draw a unit.
-}
type alias Appearance =
    { kind : UnitKind
    , playerNumber : PlayerNumber
    , spriteFacing : SpriteFacing
    , entrenchment : Entrenchment
    }


appearance : Unit -> Appearance
appearance unit =
    { kind = unit.kind
    , playerNumber = unit.playerNumber
    , spriteFacing = unit.spriteFacing
    , entrenchment = unit.entrenchment
    }



-- Map sprites keep compact cells; field-gun portraits use their elongated master.


portraitWidth : Appearance -> Float
portraitWidth unit =
    case unit.kind of
        Kind.FieldGun ->
            40

        _ ->
            16


{-| Contact points in portrait view-box units, excluding transparent bottom padding.
They track the exported sprite's boots, tracks, wheels, or gun carriage.
-}
portraitFooting : Appearance -> Float
portraitFooting unit =
    case unit.kind of
        Kind.Infantry ->
            15.1875

        Kind.FieldGun ->
            15.1

        _ ->
            14.9375


portraitToSvg : Appearance -> Svg msg
portraitToSvg unit =
    if unit.entrenchment == Entrenchment.Entrenched then
        Lazy.lazy2 entrenchedView unit.playerNumber (unit.spriteFacing == SpriteFacingEnum.Left)

    else
        Lazy.lazy3 portraitView unit.kind unit.playerNumber (unit.spriteFacing == SpriteFacingEnum.Left)


portraitView : UnitKind -> PlayerNumber -> Bool -> Svg msg
portraitView kind playerNumber facingLeft =
    case kind of
        Kind.FieldGun ->
            let
                team : String
                team =
                    case playerNumber of
                        PlayerNumber.Player1 ->
                            "red"

                        PlayerNumber.Player2 ->
                            "blue"

                sideProfile : String
                sideProfile =
                    if facingLeft then
                        "translate(40 0) scale(-1 1)"

                    else
                        ""
            in
            Svg.image
                [ SA.xlinkHref ("/assets/field-gun-portraits-anime-v1/" ++ team ++ ".png")
                , SA.width "40"
                , SA.height "16"
                , SA.preserveAspectRatio "xMidYMid meet"
                , SA.transform sideProfile
                , SA.css
                    [ Css.property "image-rendering" "auto"
                    ]
                ]
                []

        _ ->
            Lazy.lazy4 spriteView 0 kind playerNumber facingLeft


toSvg : Int -> Unit -> Svg msg
toSvg column unit =
    if unit.entrenchment == Entrenchment.Entrenched then
        Lazy.lazy2 entrenchedView unit.playerNumber (unit.spriteFacing == SpriteFacingEnum.Left)

    else
        Lazy.lazy4 spriteView column unit.kind unit.playerNumber (unit.spriteFacing == SpriteFacingEnum.Left)


spriteView : Int -> UnitKind -> PlayerNumber -> Bool -> Svg msg
spriteView column kind playerNumber facingLeft =
    let
        row : Int
        row =
            (case kind of
                Kind.Infantry ->
                    0

                Kind.Tank ->
                    3

                Kind.Truck ->
                    6

                Kind.FieldGun ->
                    9
            )
                + (case playerNumber of
                    PlayerNumber.Player1 ->
                        0

                    PlayerNumber.Player2 ->
                        1
                  )

        sideProfile : String
        sideProfile =
            if facingLeft then
                "translate(16 0) scale(-1 1)"

            else
                ""
    in
    Svg.g
        [ SA.transform sideProfile
        , SA.css
            [ Css.property "image-rendering" "auto"
            ]
        ]
        [ Sprite.toSvg
            { path = "/assets/units_illustrated-v4.png"
            , sheetWidth = 64
            , sheetHeight = 192
            , column = column
            , row = row
            }
        ]


entrenchedView : PlayerNumber -> Bool -> Svg msg
entrenchedView playerNumber facingLeft =
    let
        team : String
        team =
            case playerNumber of
                PlayerNumber.Player1 ->
                    "red"

                PlayerNumber.Player2 ->
                    "blue"

        sideProfile : String
        sideProfile =
            if facingLeft then
                "translate(16 0) scale(-1 1)"

            else
                ""
    in
    Svg.image
        [ SA.xlinkHref ("/assets/infantry-entrenched-v1/" ++ team ++ ".png")
        , SA.width "16"
        , SA.height "16"
        , SA.transform sideProfile
        ]
        []
