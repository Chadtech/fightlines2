port module Fightlines.Checks.Home exposing (main)

import Browser
import Fightlines.Feedback as Feedback
import Fightlines.Page.Home as Home
import Graphql.Http
import LocalStorage
import OperatingSystem
import Random
import Shared
import Time


type Error
    = StartupPositionsNotReproduced
    | StartupSeedSuccessorNotReproduced
    | InitializationSeedNotAdvanced
    | ReturnVisitPositionsRepeated
    | ReturnVisitSeedNotAdvanced
    | RestoredPositionsNotReproduced
    | RestoredSeedSuccessorNotReproduced
    | BlankFeedbackAccepted
    | OversizedFeedbackAccepted
    | EmojiCharacterLimitIncorrect
    | DuplicateFeedbackSubmissionAllowed
    | PendingFeedbackTextChanged
    | FailedFeedbackTextLost
    | FeedbackRetryBlocked
    | FeedbackSuccessNotConfirmed
    | RejectedFeedbackTextLost
    | StaleFeedbackResponseAccepted


port results : List String -> Cmd msg


type Model
    = WaitingForClock
        { shared : Shared.Model
        , failures : List String
        }
    | Finished


type Msg
    = SharedMsg Shared.Msg
    | NavigationIgnored


main : Program () Model Msg
main =
    Browser.application
        { init =
            \_ url key ->
                let
                    initialTime : Time.Posix
                    initialTime =
                        Time.millisToPosix 1700000000000

                    shared : Shared.Model
                    shared =
                        Shared.init initialTime (Random.initialSeed 42) OperatingSystem.Unknown LocalStorage.test url key

                    clockFailures : List String
                    clockFailures =
                        if shared.now == initialTime then
                            []

                        else
                            [ "shared initialization must retain the supplied startup time" ]
                in
                ( WaitingForClock
                    { shared = shared
                    , failures = List.map errorToString (checks shared) ++ clockFailures
                    }
                , Cmd.none
                )
        , update = updateClock
        , subscriptions = clockSubscriptions
        , view = \_ -> { title = "home seed and shared clock checks", body = [] }
        , onUrlChange = \_ -> NavigationIgnored
        , onUrlRequest = \_ -> NavigationIgnored
        }


updateClock : Msg -> Model -> ( Model, Cmd Msg )
updateClock msg model =
    case ( msg, model ) of
        ( SharedMsg sharedMsg, WaitingForClock pending ) ->
            let
                ( shared, _ ) =
                    Shared.superUpdate sharedMsg pending.shared
            in
            if shared.now /= pending.shared.now then
                ( Finished, results pending.failures )

            else
                ( WaitingForClock { pending | shared = shared }, Cmd.none )

        _ ->
            ( model, Cmd.none )


clockSubscriptions : Model -> Sub Msg
clockSubscriptions model =
    case model of
        WaitingForClock _ ->
            Shared.subscriptions
                |> Sub.map SharedMsg

        Finished ->
            Sub.none


checks : Shared.Model -> List Error
checks shared =
    let
        first : Home.Model
        first =
            Home.init shared

        repeated : Home.Model
        repeated =
            Home.init shared

        nextVisit : Home.Model
        nextVisit =
            Home.init first.shared

        restored : Home.Model
        restored =
            first.shared
                |> Shared.setSeed shared.seed
                |> Home.init

        samePositions : Home.Model -> Home.Model -> Bool
        samePositions left right =
            (left.snow == right.snow)
                && (left.desert == right.desert)
                && (left.logistics == right.logistics)

        seedValues : Shared.Model -> List Int
        seedValues state =
            Random.step (Random.list 8 (Random.int 0 1000000)) state.seed
                |> Tuple.first
    in
    List.concat
        [ feedbackChecks
        , check StartupPositionsNotReproduced (samePositions first repeated)
        , check StartupSeedSuccessorNotReproduced (seedValues first.shared == seedValues repeated.shared)
        , check InitializationSeedNotAdvanced (seedValues shared /= seedValues first.shared)
        , check ReturnVisitPositionsRepeated (not (samePositions first nextVisit))
        , check ReturnVisitSeedNotAdvanced (seedValues first.shared /= seedValues nextVisit.shared)
        , check RestoredPositionsNotReproduced (samePositions first restored)
        , check RestoredSeedSuccessorNotReproduced (seedValues first.shared == seedValues restored.shared)
        ]


feedbackChecks : List Error
feedbackChecks =
    let
        ( id, nextSeed ) =
            Random.step Feedback.requestId (Random.initialSeed 42)

        staleId : Feedback.RequestId
        staleId =
            Random.step Feedback.requestId nextSeed |> Tuple.first

        draft : Feedback.Draft
        draft =
            Feedback.edit "a suggestion\nwith details" Feedback.init

        pending : Maybe Feedback.Draft
        pending =
            Feedback.beginSubmission id draft

        failed : Maybe Feedback.Draft
        failed =
            Maybe.map (Feedback.receive id (Err (Graphql.Http.HttpError Graphql.Http.NetworkError))) pending

        accepted : Maybe Feedback.Draft
        accepted =
            Maybe.map (Feedback.receive id (Ok True)) pending
    in
    List.concat
        [ check BlankFeedbackAccepted
            (Feedback.beginSubmission id (Feedback.edit "  \n" Feedback.init) == Nothing)
        , check OversizedFeedbackAccepted
            (Feedback.beginSubmission id (Feedback.edit (String.repeat 5001 "x") Feedback.init) == Nothing)
        , check EmojiCharacterLimitIncorrect
            (Feedback.canSubmit (Feedback.edit (String.repeat 5000 "😀") Feedback.init))
        , check DuplicateFeedbackSubmissionAllowed
            (Maybe.andThen (Feedback.beginSubmission id) pending == Nothing)
        , check PendingFeedbackTextChanged
            (Maybe.map (Feedback.edit "changed" >> .text) pending == Just draft.text)
        , check FailedFeedbackTextLost
            (Maybe.map .text failed == Just draft.text)
        , check FeedbackRetryBlocked
            (Maybe.andThen (Feedback.beginSubmission id) failed /= Nothing)
        , check FeedbackSuccessNotConfirmed
            (accepted == Just { text = "", status = Feedback.Submitted })
        , check RejectedFeedbackTextLost
            (Maybe.map (Feedback.receive id (Ok False) >> .text) pending == Just draft.text)
        , check StaleFeedbackResponseAccepted
            ((Maybe.map (Feedback.receive staleId (Ok True)) pending == pending)
                && (Maybe.map (Feedback.receive staleId (Err (Graphql.Http.HttpError Graphql.Http.NetworkError))) pending == pending)
            )
        ]


check : Error -> Bool -> List Error
check error passed =
    if passed then
        []

    else
        [ error ]


errorToString : Error -> String
errorToString error =
    case error of
        StartupPositionsNotReproduced ->
            "the same startup seed reproduces all home positions"

        StartupSeedSuccessorNotReproduced ->
            "the same startup seed reproduces its successor"

        InitializationSeedNotAdvanced ->
            "initialization advances the shared seed"

        ReturnVisitPositionsRepeated ->
            "a return visit continues the shared random stream"

        ReturnVisitSeedNotAdvanced ->
            "a return visit advances the shared seed again"

        RestoredPositionsNotReproduced ->
            "restoring a seed reproduces its positions"

        RestoredSeedSuccessorNotReproduced ->
            "restoring a seed reproduces its successor"

        BlankFeedbackAccepted ->
            "blank feedback cannot be submitted"

        OversizedFeedbackAccepted ->
            "oversized feedback cannot be submitted"

        EmojiCharacterLimitIncorrect ->
            "the character limit counts emoji consistently with the server"

        DuplicateFeedbackSubmissionAllowed ->
            "a pending submission blocks duplicate sends"

        PendingFeedbackTextChanged ->
            "a pending submission preserves the submitted text"

        FailedFeedbackTextLost ->
            "failed submissions retain text for retry"

        FeedbackRetryBlocked ->
            "failed submissions can be retried"

        FeedbackSuccessNotConfirmed ->
            "accepted submissions clear the draft and confirm success"

        RejectedFeedbackTextLost ->
            "an unsuccessful server response keeps the draft"

        StaleFeedbackResponseAccepted ->
            "responses from an earlier submission cannot complete the current submission"
