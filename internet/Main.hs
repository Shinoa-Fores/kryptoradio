{-# LANGUAGE OverloadedStrings, DeriveDataTypeable, RecordWildCards #-}
module Main where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM
import Control.Exception.Base (SomeException)
import Control.Monad (forever)
import Control.Monad.IO.Class (MonadIO, liftIO)
import qualified Data.ByteString.Char8 as B
import Data.Conduit
import Data.Conduit.Network
import qualified Data.String as S
import Data.Version
import System.Console.CmdArgs.Implicit
import System.IO
import Text.Printf

import Paths_kryptoradio_internet

defFrame :: Int
defFrame = 178

data Args = Args { host   :: String
                 , port   :: Int
                 , frame  :: Int
                 } deriving (Show, Data, Typeable)

synopsis =
  Args { host = "*" &= help "IP address to bind to (default: all)"
       , port = 3003 &= help "HTTP port to listen to (default: 3003)"
       , frame = defFrame &= help ("Frame size (default: " ++ show defFrame ++ ")")
       }
  &= program "kryptoradio-internet"
  &= summary ("Kryptoradio Internet Gateway " ++ showVersion version)
  &= help "Reads given number of bytes from standard input and writes them \
          \to all listeners. The default frame size equals to the PES packet \
          \payload size in DVB-T."

main :: IO ()
main = do
  Args{..} <- cmdArgs synopsis
  ch <- newBroadcastTChanIO
  hSetBuffering stdin NoBuffering
  forkIO $ forever $ do
    -- Read packets from standard input
    bs <- B.hGet stdin frame
    atomically $ writeTChan ch bs
  runTCPServer (serverSettings port $ S.fromString host) $ \appData -> do
    -- Write all data from a channel
    liftIO $ printf "%s connected\n" (show $ appSockAddr appData)
    source ch $$ catchC (appSink appData) (sayClose appData)

-- |Reports when the handle has been closed.
sayClose :: MonadIO m => AppData -> SomeException -> m ()
sayClose appData e = liftIO $ printf "%s disconnected (%s)\n"
                     (show $ appSockAddr appData) (show e)

-- |Reads given broadcast channel and writes the output to channel 
source :: TChan B.ByteString -> Source IO B.ByteString
source bChan = do
  chan <- liftIO $ atomically $ dupTChan bChan
  forever $ liftIO (atomically $ readTChan chan) >>= yield
