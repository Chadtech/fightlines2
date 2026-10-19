module Camera exposing
    ( Camera
    , Viewport
    , anchor
    , boardWidth
    , frame
    , transform
    )

import Map exposing (Map)
import Point exposing (Point)


type alias Camera =
    { offset : Point
    , zoom : Float
    }


{-| Keep the full container size for board scaling; the bottom controls obscure
part of that container without changing its coordinate system.
-}
type alias Viewport =
    { size : Point
    , bottomInset : Float
    }


{-| The initial whole-map overview, shared by the board and command anchors.
-}
boardWidth : String
boardWidth =
    "min(80cqw, 76cqh)"


anchor : Camera -> Point -> { x : String, y : String }
anchor camera fraction =
    let
        projected : { x : String, y : String }
        projected =
            displacement camera fraction
    in
    { x = "calc(50cqw + " ++ projected.x ++ ")"
    , y = "calc(50cqh + " ++ projected.y ++ ")"
    }


displacement : Camera -> Point -> { x : String, y : String }
displacement camera fraction =
    let
        axis : Float -> Float -> String
        axis boardFraction offset =
            "calc(" ++ boardWidth ++ " * " ++ String.fromFloat (boardFraction * camera.zoom) ++ " + " ++ String.fromFloat offset ++ "px)"
    in
    { x = axis fraction.x camera.offset.x
    , y = axis fraction.y camera.offset.y
    }


transform : Camera -> String
transform camera =
    let
        translation : { x : String, y : String }
        translation =
            displacement camera { x = 0, y = 0 }
    in
    "translate(" ++ translation.x ++ ", " ++ translation.y ++ ") scale(" ++ String.fromFloat camera.zoom ++ ")"


{-| Keep the view unless a subject tile is clipped. Reframe with one tile of
breathing room, reducing zoom only when the group cannot fit the viewport.
Viewport dimensions and offsets are in pixels; subject positions are in tiles.
-}
frame : Viewport -> Map -> List Point -> Camera -> Camera
frame viewport map positions camera =
    case positions of
        [] ->
            camera

        first :: rest ->
            let
                bounds : { left : Float, right : Float, top : Float, bottom : Float }
                bounds =
                    List.foldl
                        (\position current ->
                            { left = min current.left position.x
                            , right = max current.right position.x
                            , top = min current.top position.y
                            , bottom = max current.bottom position.y
                            }
                        )
                        { left = first.x, right = first.x, top = first.y, bottom = first.y }
                        rest

                width : Float
                width =
                    toFloat map.width

                boardPixels : Float
                boardPixels =
                    min (0.8 * viewport.size.x) (0.76 * viewport.size.y)

                visibleHeight : Float
                visibleHeight =
                    max 1 (viewport.size.y - viewport.bottomInset)

                tilePixels : Float
                tilePixels =
                    boardPixels * camera.zoom / width

                left : Float
                left =
                    (bounds.left - width / 2) * tilePixels + camera.offset.x

                right : Float
                right =
                    (bounds.right + 1 - width / 2) * tilePixels + camera.offset.x

                top : Float
                top =
                    (bounds.top - toFloat map.height / 2) * tilePixels + camera.offset.y

                bottom : Float
                bottom =
                    (bounds.bottom + 1 - toFloat map.height / 2) * tilePixels + camera.offset.y

                zoom : Float
                zoom =
                    min camera.zoom
                        (min
                            (viewport.size.x * width / (boardPixels * (bounds.right - bounds.left + 3)))
                            (visibleHeight * width / (boardPixels * (bounds.bottom - bounds.top + 3)))
                        )

                subjectsVisible : Bool
                subjectsVisible =
                    (left >= -viewport.size.x / 2)
                        && (right <= viewport.size.x / 2)
                        && (top >= -viewport.size.y / 2)
                        && (bottom <= viewport.size.y / 2 - viewport.bottomInset)
            in
            if subjectsVisible then
                camera

            else
                { zoom = zoom
                , offset =
                    { x = -(bounds.left + bounds.right + 1 - width) / 2 * boardPixels * zoom / width
                    , y = -(bounds.top + bounds.bottom + 1 - toFloat map.height) / 2 * boardPixels * zoom / width - viewport.bottomInset / 2
                    }
                }
