module Fightlines.View.About exposing
    ( Section(..)
    , all
    , dialog
    , htmlId
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)
import View.Prose as Prose



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Section
    = Intro
    | Inspiration
    | Pacifism



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


all : List Section
all =
    [ Intro
    , Inspiration
    , Pacifism
    ]


htmlId : String
htmlId =
    "about-fightlines-dialog"


sectionTitle : Section -> String
sectionTitle section =
    case section of
        Intro ->
            "intro"

        Inspiration ->
            "inspiration"

        Pacifism ->
            "pacifism"


{-| Fill in each section here. Blank lines separate paragraphs.
-}
sectionText : Section -> List String
sectionText section =
    case section of
        Intro ->
            [ """Hi. Thanks for playing my game. My name is Chad ("Chadtech" online). I am a programmer and father of three. I made this game for free
and I don't have a patreon or any way for you to give me money.""" ]

        Inspiration ->
            [ """Growing up, I played a lot of war video games. While they were a lot of fun, only as I got older and became
more well read in history, did I notice discrepancies between the way wars are depicted in video games and the reality of war.
It really got my gears turning on what a video game would be like if it was realistic."""
            , """In actual wars, cities typically are not captured, they get destroyed. It's not like the enemy flag
goes down and yours goes up. If your enemy had a city, and was extracting food and supplies and production from it, you
can't just take the city and then you are the person extracting food and supplies and production from it. Capturing the
city generally means destroying it. The things that made the city productive, the peace that made people comfortable and
capable to do useful productivity things, the physical stuff that made life and work possible; those are all destroyed
when capturing a city. So in a realistic game, it should only be capable of destroying enemy capacity, not obtaining it.
Foes should gradually cripple each other, as they gradually destroy each other's cities.
"""
            , """In actual wars, most of the personelle are not on the frontlines. Quite a lot of them are just locating
equipment, people, and supplies, to where they need to be. If all you did was deliver troops to the frontlines, they would
lose catastrophically without a continuous pipeline of food and ammunition. I felt a realistic game should require
attention to that pipeline, and a loss of that pipeline to the enemy should be catastrophic and as dangerous as the
fighting forces themselves being destroyed. It should be a risky ordeal to get forces to where they need to be."""
            ]

        Pacifism ->
            [ """This is a war game, I don't feel any issues with enjoying war games, but it is interesting how much war and violence is embraced
in the abstract and in entertainment, despite the fact that it's really really bad. Isn't that weird? I find this an
interesting fact about society, and I also find the morality of war and violence interesting, so I am just going to take
this opportunity here, on this obscure part of this website, to share my thoughts.

War is really bad. I don't mean just regrettably bad, as if it was just a difficult struggle, or it was bad but also unfortunately necessary.
I mean it's just bad. A very large majority of all the decisions to take part in a war, even in defense, have been really dumb. In some extreme
circumstances, violence can be justified, like in self defense or the defense of others, or maybe to protect your home or business.
Do wars resemble those cases of self defense? Not at all. Most wars were easily avoidable. Most of the time the horrors of war were
not justified by the cause or the aims of the war. Most of the time, it would be better of either side just gave up and surrendered immediately.""" ]


{-| Add your photo under public/assets/ and set this to Just "/assets/your-photo.jpg".
Nothing keeps the portrait hidden until a photo is ready.
-}
aboutPhotoSource : Maybe String
aboutPhotoSource =
    Nothing



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


dialog : { onClose : msg } -> Dialog msg
dialog events =
    let
        photo : Html msg
        photo =
            case aboutPhotoSource of
                Nothing ->
                    H.text ""

                Just source ->
                    H.img
                        [ A.src source
                        , A.alt "the creator of fightlines"
                        , A.css
                            [ S.block
                            , S.wFull
                            , S.maxW64
                            , S.hAuto
                            , S.outdent
                            ]
                        ]
                        []
    in
    Dialog.make htmlId
        "about fightlines"
        events.onClose
        [ H.div
            [ Aria.label "about fightlines text"
            , A.tabindex 0
            , A.css
                [ S.col
                , S.g4
                , S.p3
                , S.bgNightwood3
                , S.indentStrong
                , S.maxHViewportInsetRem 11
                , S.overflowAuto
                , S.focusVisible [ S.outlineYellow5 ]
                ]
            ]
            (photo :: List.map sectionView all)
        , Button.secondary "close" events.onClose
            |> Button.toHtml
        ]
        |> Dialog.article
        |> Dialog.withCloseButton


sectionView : Section -> Html msg
sectionView section =
    let
        header : Html msg
        header =
            H.h2
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text (sectionTitle section) ]
    in
    H.section
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        (header :: List.concatMap Prose.paragraphs (sectionText section))
