module View.AppVersion exposing (toHtml)

import AppVersion
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import LocalTime
import Style as S
import Time


toHtml : Time.Zone -> Html msg
toHtml zone =
    let
        releaseTime : String
        releaseTime =
            LocalTime.formatSeconds zone AppVersion.releasedAt
    in
    H.span
        [ A.title ("version " ++ AppVersion.current ++ " released " ++ releaseTime)
        , A.css
            [ S.textGray4
            , S.textShadowBlack
            , S.pointerEventsNone
            ]
        ]
        [ H.text ("v" ++ AppVersion.current)
        , H.span
            [ A.css
                [ S.compactViewport
                    [ S.displayNone
                    ]
                ]
            ]
            [ H.text (" · " ++ releaseTime) ]
        ]
