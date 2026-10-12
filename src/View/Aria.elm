module View.Aria exposing
    ( Role(..)
    , hidden
    , label
    , labelledBy
    , role
    , svgHidden
    , svgLabel
    , svgRole
    , valueMax
    , valueMin
    , valueNow
    )

import Html.Attributes as UnstyledAttributes
import Html.Styled exposing (Attribute)
import Html.Styled.Attributes as A
import Svg


{-| Roles used by the interface. Attributes work with styled HTML and SVG;
use the `svgRole`, `svgLabel`, and `svgHidden` helpers for unstyled SVG.
-}
type Role
    = Alert
    | Button
    | Group
    | Image
    | List
    | Meter
    | Status


role : Role -> Attribute msg
role value =
    A.fromUnstyled (svgRole value)


roleText : Role -> String
roleText value =
    case value of
        Alert ->
            "alert"

        Button ->
            "button"

        Group ->
            "group"

        Image ->
            "img"

        List ->
            "list"

        Meter ->
            "meter"

        Status ->
            "status"


label : String -> Attribute msg
label value =
    A.fromUnstyled (svgLabel value)


labelledBy : String -> Attribute msg
labelledBy =
    A.attribute "aria-labelledby"


hidden : Bool -> Attribute msg
hidden isHidden =
    A.fromUnstyled (svgHidden isHidden)


svgRole : Role -> Svg.Attribute msg
svgRole value =
    UnstyledAttributes.attribute "role" (roleText value)


svgLabel : String -> Svg.Attribute msg
svgLabel =
    UnstyledAttributes.attribute "aria-label"


svgHidden : Bool -> Svg.Attribute msg
svgHidden isHidden =
    let
        value : String
        value =
            if isHidden then
                "true"

            else
                "false"
    in
    UnstyledAttributes.attribute "aria-hidden" value


valueMin : Int -> Attribute msg
valueMin value =
    A.attribute "aria-valuemin" (String.fromInt value)


valueMax : Int -> Attribute msg
valueMax value =
    A.attribute "aria-valuemax" (String.fromInt value)


valueNow : Int -> Attribute msg
valueNow value =
    A.attribute "aria-valuenow" (String.fromInt value)
