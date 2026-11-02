module View.Prose exposing (paragraphs)

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S


{-| Source line wrapping becomes spaces; blank lines separate paragraphs.
-}
paragraphs : String -> List (Html msg)
paragraphs source =
    let
        paragraph : String -> Html msg
        paragraph content =
            H.p
                [ A.css
                    [ S.wrapAnywhere
                    ]
                ]
                [ H.text content ]
    in
    source
        |> String.replace "\u{000D}\n" "\n"
        |> String.split "\n\n"
        |> List.map (String.words >> String.join " ")
        |> List.filter (not << String.isEmpty)
        |> List.map paragraph
