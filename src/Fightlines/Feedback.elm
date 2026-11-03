module Fightlines.Feedback exposing
    ( Draft
    , RequestId
    , Status(..)
    , beginSubmission
    , canSubmit
    , edit
    , init
    , isSending
    , receive
    , request
    , requestId
    , tooLong
    )

import Api.Mutation
import ApiRequest
import Graphql.Http
import Random



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Draft =
    { text : String
    , status : Status
    }


type Status
    = Editing
    | Sending RequestId
    | Failed String
    | Submitted


type RequestId
    = RequestId Int



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


init : Draft
init =
    { text = ""
    , status = Editing
    }


requestId : Random.Generator RequestId
requestId =
    Random.map RequestId (Random.int 0 Random.maxInt)


isSending : Draft -> Bool
isSending draft =
    case draft.status of
        Sending _ ->
            True

        _ ->
            False


edit : String -> Draft -> Draft
edit text draft =
    case draft.status of
        Sending _ ->
            draft

        _ ->
            { text = text
            , status = Editing
            }


canSubmit : Draft -> Bool
canSubmit draft =
    not (isSending draft)
        && not (String.isEmpty (String.trim draft.text))
        && not (tooLong draft)


{-| Count Unicode characters consistently with the server, including emoji.
-}
tooLong : Draft -> Bool
tooLong draft =
    let
        countCharacter : Char -> Int -> Int
        countCharacter _ count =
            count + 1
    in
    String.foldl countCharacter 0 (String.trim draft.text) > 5000


beginSubmission : RequestId -> Draft -> Maybe Draft
beginSubmission id draft =
    if canSubmit draft then
        Just { draft | status = Sending id }

    else
        Nothing


request : Draft -> Graphql.Http.Request Bool
request draft =
    Api.Mutation.submitFeedback { text = draft.text }
        |> ApiRequest.mutationRequest


receive : RequestId -> ApiRequest.Response Bool -> Draft -> Draft
receive id response draft =
    case draft.status of
        Sending currentId ->
            if id /= currentId then
                draft

            else
                case response of
                    Ok True ->
                        { text = ""
                        , status = Submitted
                        }

                    Ok False ->
                        { draft | status = Failed "could not save your feedback. please try again." }

                    Err error ->
                        { draft | status = Failed (ApiRequest.errorMessage error) }

        _ ->
            draft
