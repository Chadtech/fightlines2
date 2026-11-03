module View.AppVersion exposing (toHtml)

import AppVersion
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S


toHtml : Html msg
toHtml =
    H.span
        [ A.title ("version " ++ AppVersion.current)
        , A.css
            [ S.fixed
            , S.top1
            , S.right1
            , S.z4
            , S.textGray4
            , S.textShadowBlack
            , S.pointerEventsNone
            , S.belowWidth 400
                [ S.top12 ]
            ]
        ]
        [ H.text ("v" ++ AppVersion.current) ]
