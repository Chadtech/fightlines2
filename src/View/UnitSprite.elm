module View.UnitSprite exposing (toSvg)

import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacingEnum
import Api.Enum.UnitKind as Kind
import Css
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import View.Sprite as Sprite



-- Board animation and static portraits share the same atlas and facing.


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
