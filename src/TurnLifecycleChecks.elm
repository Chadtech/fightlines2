port module TurnLifecycleChecks exposing (main)

import GamePage.Selection
    exposing
        ( Inspection(..)
        , Selection(..)
        , UnitInteraction(..)
        )
import Movement
import PlannedOrder
import Platform
import TurnLifecycle exposing (Phase(..))
import TurnPlayback
import UnitId


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
    case UnitId.parse "1" of
        Err _ ->
            [ "could not construct lifecycle fixture ID" ]

        Ok unitId ->
            let
                drafts : List PlannedOrder.PlannedOrder
                drafts =
                    [ { unitId = unitId, action = PlannedOrder.Hold { x = 1, y = 1 } } ]

                selection : Selection
                selection =
                    UnitSelection
                        { id = unitId
                        , interaction = ChoosingMove { preview = Movement.start { x = 1, y = 1 }, options = [] }
                        }

                inspectedTile : Selection
                inspectedTile =
                    Inspecting (TileInspection { x = 2, y = 3 })

                choosingMove : Phase
                choosingMove =
                    Planning { orders = drafts, selection = Just selection }

                pending : Phase
                pending =
                    Submitting { turnNumber = 1, orders = drafts, inspection = Just (UnitInspection unitId) }

                confirmed : Phase
                confirmed =
                    TurnLifecycle.observeSubmission True pending

                frames : List TurnPlayback.Frame
                frames =
                    [ { units = [], visibleTiles = [] }
                    , { units = [], visibleTiles = [ { x = 1, y = 1 } ] }
                    ]

                playing : Phase
                playing =
                    TurnLifecycle.startTurn False frames

                alreadySubmittedPlayback : Phase
                alreadySubmittedPlayback =
                    TurnLifecycle.startTurn True frames
            in
            List.concat
                [ expect "starting submission must lock editing and retain the inspected unit"
                    (TurnLifecycle.startSubmission 1 choosingMove == pending)
                , expect "starting submission again must not alter any locked phase"
                    (TurnLifecycle.startSubmission 2 pending
                        == pending
                        && TurnLifecycle.startSubmission 2 confirmed
                        == confirmed
                        && TurnLifecycle.startSubmission 2 playing
                        == playing
                    )
                , expect "inspection can change or clear during every locked phase"
                    (TurnLifecycle.selection (TurnLifecycle.setSelection (Just inspectedTile) pending)
                        == Just inspectedTile
                        && TurnLifecycle.selection (TurnLifecycle.setSelection (Just inspectedTile) confirmed)
                        == Just inspectedTile
                        && TurnLifecycle.selection (TurnLifecycle.setSelection (Just inspectedTile) playing)
                        == Just inspectedTile
                        && TurnLifecycle.selection (TurnLifecycle.setSelection Nothing pending)
                        == Nothing
                        && TurnLifecycle.selection (TurnLifecycle.setSelection Nothing confirmed)
                        == Nothing
                        && TurnLifecycle.selection (TurnLifecycle.setSelection Nothing playing)
                        == Nothing
                    )
                , expect "a failed submission must preserve inspection changed while the request was pending"
                    (TurnLifecycle.selection (TurnLifecycle.finishSubmission 1 (TurnLifecycle.setSelection (Just inspectedTile) pending)) == Just inspectedTile)
                , expect "poll confirmation must preserve inspection changed while submitting"
                    (TurnLifecycle.selection (TurnLifecycle.observeSubmission True (TurnLifecycle.setSelection (Just inspectedTile) pending)) == Just inspectedTile)
                , expect "playback completion must preserve inspection chosen during animation"
                    (Maybe.map (.phase >> TurnLifecycle.selection) (TurnLifecycle.tick 1000 (TurnLifecycle.setSelection (Just inspectedTile) playing))
                        == Just (Just inspectedTile)
                        && Maybe.map (.phase >> TurnLifecycle.selection) (TurnLifecycle.tick 1000 (TurnLifecycle.setSelection (Just inspectedTile) alreadySubmittedPlayback))
                        == Just (Just inspectedTile)
                    )
                , expect "a new turn must start without carrying selection from the previous turn"
                    (TurnLifecycle.selection (TurnLifecycle.startTurn False frames)
                        == Nothing
                        && TurnLifecycle.selection (TurnLifecycle.startTurn True [])
                        == Nothing
                    )
                , expect "editing an order must preserve the active planning interaction"
                    (TurnLifecycle.setOrders [] choosingMove == Planning { orders = [], selection = Just selection })
                , expect "submission confirmed by polling must discard editable interactions"
                    (TurnLifecycle.observeSubmission True choosingMove == WaitingForOpponent { orders = drafts, inspection = Just (UnitInspection unitId) })
                , expect "unsubmitted polling must preserve the active planning interaction"
                    (TurnLifecycle.observeSubmission False choosingMove == choosingMove)
                , expect "locked phases must reject attempts to open an editable interaction"
                    (TurnLifecycle.setSelection (Just selection) pending
                        == pending
                        && TurnLifecycle.setSelection (Just selection) confirmed
                        == confirmed
                        && TurnLifecycle.setSelection (Just selection) playing
                        == playing
                    )
                , expect "submission failure must recover drafts as inspection without reopening a command or preview"
                    (TurnLifecycle.selection (TurnLifecycle.finishSubmission 1 pending) == Just (Inspecting (UnitInspection unitId)))
                , expect "playback without a selected object must finish with no selection"
                    (Maybe.map (.phase >> TurnLifecycle.selection) (TurnLifecycle.tick 1000 playing) == Just Nothing)
                , expect "submission failure must restore the exact drafts"
                    (TurnLifecycle.finishSubmission 1 pending == Planning { orders = drafts, selection = Just (Inspecting (UnitInspection unitId)) })
                , expect "an older request must not finish a newer submission"
                    (TurnLifecycle.finishSubmission 0 pending == pending)
                , expect "poll confirmation must lock drafts before the submit request finishes"
                    (confirmed == WaitingForOpponent { orders = drafts, inspection = Just (UnitInspection unitId) })
                , expect "late failure must not unlock a turn already confirmed by polling"
                    (TurnLifecycle.finishSubmission 1 confirmed == confirmed)
                , expect "an unsubmitted poll must not regress waiting or pending submission"
                    (TurnLifecycle.observeSubmission False confirmed == confirmed && TurnLifecycle.observeSubmission False pending == pending)
                , expect "order edits are allowed only during planning"
                    (TurnLifecycle.setOrders [] (Planning { orders = drafts, selection = Nothing }) == Planning { orders = [], selection = Nothing } && TurnLifecycle.setOrders [] pending == pending && TurnLifecycle.setOrders [] confirmed == confirmed)
                , expect "polling remains available in planning and waiting, but not submitting or playback"
                    (TurnLifecycle.canPoll (Planning { orders = drafts, selection = Nothing }) && TurnLifecycle.canPoll confirmed && not (TurnLifecycle.canPoll pending) && not (TurnLifecycle.canPoll playing))
                , expect "late submission completion must not interrupt playback or restore old drafts"
                    (TurnLifecycle.finishSubmission 1 playing == playing && TurnLifecycle.orders playing == [])
                , expect "same-turn submission flags must not interrupt playback"
                    (TurnLifecycle.playback (TurnLifecycle.observeSubmission True playing) == TurnLifecycle.playback playing)
                , expect "playback completion must open a fresh planning turn and use the final frame"
                    (TurnLifecycle.tick 1000 playing == Just { phase = Planning { orders = [], selection = Nothing }, frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "playback completion must retain submission of a turn submitted elsewhere"
                    (TurnLifecycle.tick 1000 alreadySubmittedPlayback == Just { phase = WaitingForOpponent { orders = [], inspection = Nothing }, frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "submission observed during playback must lock the completed turn"
                    (TurnLifecycle.tick 1000 (TurnLifecycle.observeSubmission True playing) == Just { phase = WaitingForOpponent { orders = [], inspection = Nothing }, frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "turns without playback must enter planning or waiting immediately"
                    (TurnLifecycle.startTurn False [] == Planning { orders = [], selection = Nothing } && TurnLifecycle.startTurn True [] == WaitingForOpponent { orders = [], inspection = Nothing })
                , expect "stray animation messages must not advance a planning or waiting turn"
                    (TurnLifecycle.tick 1000 (Planning { orders = drafts, selection = Nothing }) == Nothing && TurnLifecycle.tick 1000 confirmed == Nothing)
                ]


expect : String -> Bool -> List String
expect message condition =
    if condition then
        []

    else
        [ message ]
