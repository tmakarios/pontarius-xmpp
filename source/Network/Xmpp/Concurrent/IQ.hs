module Network.Xmpp.Concurrent.IQ where

import Control.Concurrent.STM
import Control.Concurrent (forkIO, threadDelay)
import Control.Monad
import Control.Monad.IO.Class
import Control.Monad.Trans.Reader

import Data.XML.Types
import qualified Data.Map as Map

import Network.Xmpp.Concurrent.Types
import Network.Xmpp.Concurrent.Monad
import Network.Xmpp.Types

-- | Sends an IQ, returns a 'TMVar' that will be filled with the first inbound
-- IQ with a matching ID that has type @result@ or @error@.
sendIQ :: Maybe Int -- ^ Timeout
       -> Maybe Jid -- ^ Recipient (to)
       -> IQRequestType  -- ^ IQ type (@Get@ or @Set@)
       -> Maybe LangTag  -- ^ Language tag of the payload (@Nothing@ for
                         -- default)
       -> Element -- ^ The IQ body (there has to be exactly one)
       -> Session
       -> IO (TMVar IQResponse)
sendIQ timeOut to tp lang body session = do -- TODO: Add timeout
    newId <- idGenerator session
    ref <- atomically $ do
        resRef <- newEmptyTMVar
        (byNS, byId) <- readTVar (iqHandlers . chans $ session)
        writeTVar (iqHandlers . chans $ session) (byNS, Map.insert newId resRef byId)
          -- TODO: Check for id collisions (shouldn't happen?)
        return resRef
    sendStanza  (IQRequestS $ IQRequest newId Nothing to lang tp body) (chans session)
    case timeOut of
        Nothing -> return ()
        Just t -> void . forkIO $ do
                  threadDelay t
                  doTimeOut (iqHandlers . chans $ session) newId ref
    return ref
  where
    doTimeOut handlers iqid var = atomically $ do
      p <- tryPutTMVar var IQResponseTimeout
      when p $ do
          (byNS, byId) <- readTVar (iqHandlers . chans $ session)
          writeTVar handlers (byNS, Map.delete iqid byId)
      return ()


-- | Like 'sendIQ', but waits for the answer IQ. Times out after 3 seconds
sendIQ' :: Maybe Jid
        -> IQRequestType
        -> Maybe LangTag
        -> Element
        -> Session
        -> IO IQResponse
sendIQ' to tp lang body session = do
    ref <- sendIQ (Just 3000000) to tp lang body session
    atomically $ takeTMVar ref


answerIQ :: IQRequestTicket
         -> Either StanzaError (Maybe Element)
         -> Session
         -> IO Bool
answerIQ (IQRequestTicket
              sentRef
              (IQRequest iqid from _to lang _tp bd))
           answer session = do
  let response = case answer of
        Left err  -> IQErrorS $ IQError iqid Nothing from lang err (Just bd)
        Right res -> IQResultS $ IQResult iqid Nothing from lang res
  atomically $ do
       sent <- readTVar sentRef
       case sent of
         False -> do
             writeTVar sentRef True

             writeTChan (outCh . chans $ session) response
             return True
         True -> return False
