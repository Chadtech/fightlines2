module Fightlines.View.About exposing
    ( Section(..)
    , all
    , dialog
    , htmlId
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Section
    = Intro
    | Pacifism



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


all : List Section
all =
    [ Intro
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

        Pacifism ->
            "pacifism"


{-| Fill in each section here. Blank lines separate paragraphs.
-}
sectionText : Section -> String
sectionText section =
    case section of
        Intro ->
            """Hi. Thanks for playing my game. My name is Chad (Chadtech online). I am a programmer and father of three. I made this game for free
    and I don't have a patreon or any way for you to give me money."""

        --Inspiration ->
        --    """From what I've gathered from reading history books on wars, real life wars are different from wars depicted in video games in several
        --    ways. For one, much of historical armies have comprised of extensive logistical support networks. If supplies can't get to the
        --    front line troops, they essentially lose. They lose combat readiness at least, if not worse fates like starvation.
        --
        --    Wars are also very destructive. Generally when a city is taken in a war, it is largely destroyed. Sometimes war games will
        --    include cities or factories as capturable by one play or another, and upon capture it simply flips sides. I think
        --    in real life, when a city has been captured, it was basically destroyed. And because it was destroyed, it lacks any productive
        --    capacity at all. It's just not possible to take or occupy an enemy city and expect business to continue on as usual. Commerce
        --    and productivity stop.
        --    """
        Pacifism ->
            """This is a war game, I don't feel any issues with enjoy war games, but it is interesting how much war and violence is embraced
            in the abstract and in entertainment, despite the fact that it's really really bad. It's not good to want war. We should be avoiding
            wars. I want to note that here in this obscure corner of this website, since it might not be obvious. The morality of war is an
            interesting topic in itself, along side the actual history of wars.

            So war is really bad. I don't mean just regrettably bad, as if it was just a difficult struggle, or it was bad but necessary.
            It's just bad. A very large majority of every decision to take part in a war, even in defense, has been really dumb. I am not
            an absolutist about war and violence. In some extreme circumstances, violence can be justified, like in self defense or the defense
            of others, or maybe to protect your home or business. Do wars resemble those cases of self defense? Not at all. Most wars were easily
            avoidable. Most of the time, it would be better of either side just gave up and surrendered immediately."""


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
        [ photo
        , H.div
            [ A.css
                [ S.col
                , S.g4
                ]
            ]
            (List.map sectionView all)
        , Button.secondary "close" events.onClose
            |> Button.toHtml
        ]
        |> Dialog.reference
        |> Dialog.withCloseButton


sectionView : Section -> Html msg
sectionView section =
    H.section
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        [ H.h2
            [ A.css
                [ S.textGray5
                ]
            ]
            [ H.text (sectionTitle section) ]
        , H.p
            [ A.css
                [ S.whitespacePreWrap
                , S.wrapAnywhere
                ]
            ]
            [ H.text (sectionText section) ]
        ]
