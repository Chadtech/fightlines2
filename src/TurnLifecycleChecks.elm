port module TurnLifecycleChecks exposing (main)

import GamePage.EditingSelection exposing (EditingSelection(..), UnitInteraction(..))
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

                selection : EditingSelection
                selection =
                    EditingUnit
                        { id = unitId
                        , interaction = ChoosingMove { preview = Movement.start { x = 1, y = 1 }, options = [] }
                        }

                choosingMove : Phase
                choosingMove =
                    Planning { orders = drafts, editing = Just selection }

                pending : Phase
                pending =
                    Submitting { turnNumber = 1, orders = drafts }

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
                [ expect "editing an order must preserve the active planning interaction"
                    (TurnLifecycle.setOrders [] choosingMove == Planning { orders = [], editing = Just selection })
                , expect "submission confirmed by polling must discard editable interactions"
                    (TurnLifecycle.observeSubmission True choosingMove == WaitingForOpponent drafts)
                , expect "unsubmitted polling must preserve the active planning interaction"
                    (TurnLifecycle.observeSubmission False choosingMove == choosingMove)
                , expect "locked phases must reject attempts to open an editable interaction"
                    (TurnLifecycle.setEditing (Just selection) pending
                        == pending
                        && TurnLifecycle.setEditing (Just selection) confirmed
                        == confirmed
                        && TurnLifecycle.setEditing (Just selection) playing
                        == playing
                    )
                , expect "submission failure must recover drafts without reopening a command or preview"
                    (TurnLifecycle.editing (TurnLifecycle.finishSubmission 1 pending) == Nothing)
                , expect "playback completion must begin without an editable interaction"
                    (Maybe.map (.phase >> TurnLifecycle.editing) (TurnLifecycle.tick 1000 playing) == Just Nothing)
                , expect "submission failure must restore the exact drafts"
                    (TurnLifecycle.finishSubmission 1 pending == Planning { orders = drafts, editing = Nothing })
                , expect "an older request must not finish a newer submission"
                    (TurnLifecycle.finishSubmission 0 pending == pending)
                , expect "poll confirmation must lock drafts before the submit request finishes"
                    (confirmed == WaitingForOpponent drafts)
                , expect "late failure must not unlock a turn already confirmed by polling"
                    (TurnLifecycle.finishSubmission 1 confirmed == confirmed)
                , expect "an unsubmitted poll must not regress waiting or pending submission"
                    (TurnLifecycle.observeSubmission False confirmed == confirmed && TurnLifecycle.observeSubmission False pending == pending)
                , expect "order edits are allowed only during planning"
                    (TurnLifecycle.setOrders [] (Planning { orders = drafts, editing = Nothing }) == Planning { orders = [], editing = Nothing } && TurnLifecycle.setOrders [] pending == pending && TurnLifecycle.setOrders [] confirmed == confirmed)
                , expect "polling remains available in planning and waiting, but not submitting or playback"
                    (TurnLifecycle.canPoll (Planning { orders = drafts, editing = Nothing }) && TurnLifecycle.canPoll confirmed && not (TurnLifecycle.canPoll pending) && not (TurnLifecycle.canPoll playing))
                , expect "late submission completion must not interrupt playback or restore old drafts"
                    (TurnLifecycle.finishSubmission 1 playing == playing && TurnLifecycle.orders playing == [])
                , expect "same-turn submission flags must not interrupt playback"
                    (TurnLifecycle.playback (TurnLifecycle.observeSubmission True playing) == TurnLifecycle.playback playing)
                , expect "playback completion must open a fresh planning turn and use the final frame"
                    (TurnLifecycle.tick 1000 playing == Just { phase = Planning { orders = [], editing = Nothing }, frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "playback completion must retain submission of a turn submitted elsewhere"
                    (TurnLifecycle.tick 1000 alreadySubmittedPlayback == Just { phase = WaitingForOpponent [], frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "submission observed during playback must lock the completed turn"
                    (TurnLifecycle.tick 1000 (TurnLifecycle.observeSubmission True playing) == Just { phase = WaitingForOpponent [], frame = { units = [], visibleTiles = [ { x = 1, y = 1 } ] } })
                , expect "turns without playback must enter planning or waiting immediately"
                    (TurnLifecycle.startTurn False [] == Planning { orders = [], editing = Nothing } && TurnLifecycle.startTurn True [] == WaitingForOpponent [])
                , expect "stray animation messages must not advance a planning or waiting turn"
                    (TurnLifecycle.tick 1000 (Planning { orders = drafts, editing = Nothing }) == Nothing && TurnLifecycle.tick 1000 confirmed == Nothing)
                ]


expect : String -> Bool -> List String
expect message condition =
    if condition then
        []

    else
        [ message ]
