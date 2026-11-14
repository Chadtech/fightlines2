module View.AppControls exposing (toHtml)

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import OperatingSystem exposing (OperatingSystem)
import ScreenSize
import Style as S
import View.AppVersion as AppVersion


toHtml : Maybe OperatingSystem -> List (Html msg) -> Html msg
toHtml operatingSystem controls =
    let
        content : List (Html msg)
        content =
            controls ++ [ AppVersion.toHtml ]

        mobileVisibility : S.Style
        mobileVisibility =
            case operatingSystem of
                Just platform ->
                    ScreenSize.mobileStyles platform [ S.displayNone ]

                Nothing ->
                    S.none
    in
    H.div
        [ A.css
            [ S.fixed
            , S.top1
            , S.left1
            , S.z4
            , S.row
            , S.itemsCenter
            , S.g1
            , S.pointerEventsNone
            , S.belowWidth 400
                [ S.top12 ]
            , mobileVisibility
            ]
        ]
        content
