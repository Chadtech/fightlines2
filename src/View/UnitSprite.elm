module View.UnitSprite exposing
    ( portraitToSvg
    , portraitWidth
    , toSvg
    )

import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacingEnum
import Api.Enum.UnitKind as Kind
import Css
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
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
    case unit.kind of
        Kind.FieldGun ->
            let
                team : String
                team =
                    case unit.playerNumber of
                        PlayerNumber.Player1 ->
                            "red"

                        PlayerNumber.Player2 ->
                            "blue"

                sideProfile : String
                sideProfile =
                    if facesLeft unit then
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
            toSvg 0 unit


toSvg : Int -> Unit -> Svg msg
toSvg column unit =
    let
        row : Int
        row =
            (case unit.kind of
                Kind.Infantry ->
                    0

                Kind.Tank ->
                    3

                Kind.Truck ->
                    6

                Kind.FieldGun ->
                    9
            )
                + (case unit.playerNumber of
                    PlayerNumber.Player1 ->
                        0

                    PlayerNumber.Player2 ->
                        1
                  )

        sideProfile : String
        sideProfile =
            if facesLeft unit then
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
