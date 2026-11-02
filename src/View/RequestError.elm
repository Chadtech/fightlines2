module View.RequestError exposing (toHtml, toast)

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader


{-| Shared presentation for failed HTTP actions. The page owns retry policy.
-}
toHtml :
    { title : String
    , message : String
    , guidance : String
    , retryEnabled : Bool
    , onRetry : msg
    , onDismiss : msg
    }
    -> Html msg
toHtml failure =
    let
        retry : Button.Button msg
        retry =
            if failure.retryEnabled then
                Button.secondary "try again" failure.onRetry

            else
                Button.disabled "try again"
    in
    H.div
        [ Aria.role Aria.Alert
        , Aria.label failure.title
        , A.css
            [ S.maxW96
            , S.wrapAnywhere
            ]
        ]
        [ [ H.p
                []
                [ H.text failure.message ]
          , H.p
                []
                [ H.text failure.guidance ]
          , H.div
                [ A.css
                    [ S.row
                    , S.g2
                    , S.flexWrap
                    ]
                ]
                [ Button.toHtml retry
                , Button.secondary "dismiss" failure.onDismiss
                    |> Button.toHtml
                ]
          ]
            |> Card.toHtml
                (Card.simple
                    |> Card.danger
                    |> Card.withHeader (CardHeader.simple failure.title)
                )
        ]


{-| Floating placement also works in a modal's native top layer.
-}
toast : Html msg -> Html msg
toast content =
    H.div
        [ A.css
            [ S.fixed
            , S.bottom4
            , S.left4
            , S.z4
            , S.maxWViewportInsetRem 2
            , S.maxH40Viewport
            , S.overflowAuto
            ]
        ]
        [ content ]
