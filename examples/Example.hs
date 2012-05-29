{-# LANGUAGE PackageImports, OverloadedStrings #-}
module Example where

import Data.Text as T

import Network.Xmpp
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad
import Control.Monad.IO.Class

philonous :: JID
philonous = read "uart14@species64739.dyndns.org"

attXmpp :: STM a -> XmppThread a
attXmpp = liftIO . atomically

autoAccept :: XmppThread ()
autoAccept = forever $ do
  st <- pullPresence
  case st of
    Presence from _ idq (Just Subscribe) _ _ _ _  ->
      sendS . SPresence $
           Presence Nothing from idq (Just Subscribed) Nothing Nothing Nothing []
    _ -> return ()

mirror :: XmppThread ()
mirror = forever $ do
  st <- pullMessage
  case st of
    Message (Just from) _ idq tp subject (Just bd) thr _ ->
      sendS . SMessage $
        Message Nothing from idq tp subject
          (Just $ "you wrote: " `T.append` bd) thr []
    _ -> return ()


main :: IO ()
main = do
  sessionConnect "localhost" "species64739.dyndns.org" "bot" Nothing $ do
--      singleThreaded $ xmppStartTLS exampleParams
      singleThreaded $ xmppSASL "pwd"
      xmppThreadedBind (Just "botsi")
--      singleThreaded $ xmppBind (Just "botsi")
      singleThreaded $ xmppSession
      forkXmpp autoAccept
      forkXmpp mirror
      sendS . SPresence $ Presence Nothing Nothing Nothing Nothing
                (Just Available) Nothing Nothing []
      sendS . SMessage $ Message Nothing philonous Nothing Nothing Nothing
        (Just "bla") Nothing []
      liftIO  . forever $ threadDelay 1000000
      return ()
  return ()

