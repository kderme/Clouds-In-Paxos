module Main where

import Message
import Agents

import System.Environment
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process
import Control.Distributed.Process.Node

main :: IO ()
main = do
  [neg,a,p] <- getArgs
  Right t <- createTransport "127.0.0.1" "10501" defaultTCPParameters
  node <- newLocalNode t initRemoteTable
  _ <- runProcess node $ master (read neg) (read a) (read p)
  return ()
