port module PointerGestureChecks exposing (main)

import GamePage.BattlefieldNavigation as Navigation
import Platform
import PointerGesture


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    let
        pressed : PointerGesture.PointerGesture
        pressed =
            PointerGesture.press { start = { x = 10, y = 20 }, origin = { x = 100, y = 200 } }

        belowThreshold : { gesture : PointerGesture.PointerGesture, offset : Maybe { x : Float, y : Float } }
        belowThreshold =
            PointerGesture.move { x = 13, y = 24 } pressed

        panning : { gesture : PointerGesture.PointerGesture, offset : Maybe { x : Float, y : Float } }
        panning =
            PointerGesture.move { x = 16, y = 20 } pressed

        returned : { gesture : PointerGesture.PointerGesture, offset : Maybe { x : Float, y : Float } }
        returned =
            PointerGesture.move { x = 10, y = 20 } panning.gesture

        released : PointerGesture.PointerGesture
        released =
            PointerGesture.finish panning.gesture

        routePressed : Navigation.Model
        routePressed =
            Navigation.init |> Navigation.press { x = 10, y = 20 }

        routeDragged : Navigation.Model
        routeDragged =
            routePressed |> Navigation.update (Navigation.MouseMoved { x = 50, y = 20 } 1)

        routeReleased : Navigation.Model
        routeReleased =
            routeDragged |> Navigation.update (Navigation.MouseReleased { x = 50, y = 20 })

        nextPress : PointerGesture.PointerGesture
        nextPress =
            PointerGesture.press { start = { x = 0, y = 0 }, origin = { x = 106, y = 200 } }
    in
    List.concat
        [ expect "route dragging keeps the camera fixed and suppresses its follow-up click"
            (Navigation.camera routeDragged == Navigation.camera routePressed && Navigation.camera routeReleased == Navigation.camera routePressed && Navigation.suppressesClick routeReleased && not (Navigation.active routeReleased))
        , expect "an ordinary press is active and permits clicks"
            (PointerGesture.active pressed && not (PointerGesture.suppressesClick pressed))
        , expect "movement below six pixels must not pan or suppress a click"
            (belowThreshold.gesture == pressed && belowThreshold.offset == Nothing)
        , expect "six pixels must start panning relative to the camera origin"
            (PointerGesture.active panning.gesture && PointerGesture.suppressesClick panning.gesture && panning.offset == Just { x = 106, y = 200 })
        , expect "a diagonal movement crossing six pixels must start panning"
            (PointerGesture.suppressesClick (PointerGesture.move { x = 15, y = 24 } pressed).gesture)
        , expect "returning to the press position must remain panning and suppress clicks"
            (PointerGesture.suppressesClick returned.gesture && returned.offset == Just { x = 100, y = 200 })
        , expect "release, lost buttons, visibility change, and zoom must stop panning but retain click suppression"
            (not (PointerGesture.active released) && PointerGesture.suppressesClick released && PointerGesture.finish released == released)
        , expect "ending an ordinary press must permit selection"
            (PointerGesture.finish belowThreshold.gesture == PointerGesture.idle)
        , expect "a release position crossing the threshold must still suppress the subsequent click"
            (PointerGesture.suppressesClick (PointerGesture.finish (PointerGesture.move { x = 16, y = 20 } pressed).gesture))
        , expect "a fresh press must clear previous click suppression"
            (PointerGesture.active nextPress && not (PointerGesture.suppressesClick nextPress))
        , expect "reset must stop the gesture and permit clicks"
            (not (PointerGesture.active PointerGesture.idle) && not (PointerGesture.suppressesClick PointerGesture.idle))
        , expect "movement without an active press must not change the camera or suppression"
            ((PointerGesture.move { x = 500, y = 500 } released).offset == Nothing && (PointerGesture.move { x = 500, y = 500 } released).gesture == released && (PointerGesture.move { x = 500, y = 500 } PointerGesture.idle).gesture == PointerGesture.idle)
        ]


expect : String -> Bool -> List String
expect label condition =
    if condition then
        []

    else
        [ label ]
