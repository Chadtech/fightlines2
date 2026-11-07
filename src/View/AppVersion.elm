module View.AppVersion exposing (toHtml)

import AppVersion
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S


toHtml : Html msg
toHtml =
    H.span
        [ A.title ("version " ++ AppVersion.current ++ " released " ++ AppVersion.releasedAt)
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
            [ H.text (" · " ++ AppVersion.releasedAt) ]
        ]
