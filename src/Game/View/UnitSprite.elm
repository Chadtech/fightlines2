module Game.View.UnitSprite exposing
    ( portraitToSvg
    , portraitWidth
    , toSvg
    )

import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.SpriteFacing as SpriteFacingEnum
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Game.Unit as Unit exposing (Unit)
import Html.Styled.Lazy as Lazy
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Sprite as Sprite



-- Map sprites keep compact cells; field-gun portraits use their elongated master.


portraitWidth : Unit -> Float
portraitWidth unit =
    case unit.kind of
        Kind.FieldGun ->
            40

        _ ->
            16


portraitToSvg : Unit -> Svg msg
portraitToSvg unit =
    if unit.entrenchment == Entrenchment.Entrenched then
        Lazy.lazy2 entrenchedView unit.playerNumber (facesLeft unit)

    else
        Lazy.lazy3 portraitView unit.kind unit.playerNumber (facesLeft unit)


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
        Lazy.lazy2 entrenchedView unit.playerNumber (facesLeft unit)

    else
        Lazy.lazy4 spriteView column unit.kind unit.playerNumber (facesLeft unit)


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


facesLeft : Unit -> Bool
facesLeft unit =
    unit.spriteFacing == SpriteFacingEnum.Left


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
