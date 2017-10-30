{-# LANGUAGE RecordWildCards #-}
module Agents where

import Message

import           Data.Binary
import           Data.Typeable
import Control.Concurrent (threadDelay)
import Control.Distributed.Process
import Control.Monad (replicateM, replicateM_, unless, when)
import Data.Maybe (fromJust)

master :: Bool -> Int -> Int -> Process ()
master neg a p = do
  say "Hello, I`m the master"
  selfPid <- getSelfPid
  lsAcceptors <- replicateM a $ spawnLocal $ acceptor neg selfPid
  replicateM_ p $ spawnLocal $ proposer lsAcceptors (div a 2 + 1)
  cmds <- replicateM a waitExecuted
  say $ show cmds
  say "All Done"
  if all (\ cmd -> cmd == head cmds) cmds
  then say "SUCCESS!! All executed commands where the same"
  else say "OH NO!! Not all commands are the same"
  liftIO $ threadDelay 20000000
    where
      waitExecuted :: Process Command
      waitExecuted = do
        ex@(Executed cmd) <- expect
        say $ "Got " ++ show ex
        return cmd

data AcceptState = AcceptState {
    tMax   :: Time
  , tStore :: Time
  , mcmd   :: Maybe Command}

acceptor :: Bool -> ProcessId -> Process ()
acceptor sendNeg masterPid = do
  say "Hello, I`m an acceptor"
  go $ AcceptState 0 0 Nothing
  where
    go :: AcceptState -> Process ()
    go s@AcceptState{..} = do
      selfPid <- getSelfPid
      let
        prep :: Prepare -> Process ()
        prep m@(Prepare t pid) = do
          say $ "Got " ++  show m
          if t > tMax
          then do
            sayAndSend pid $ Promise tStore mcmd selfPid
            say $ "Setting Tmax = " ++ show t
            go $ AcceptState t tStore mcmd
          else do
            when sendNeg $ sayAndSend pid PromiseNotOk
            go s
        prop :: Propose -> Process ()
        prop m@(Propose t cmd pid) = do
          say $ "Got " ++  show m
          if t == tMax
          then do
            say $ "Setting Tstore = " ++ show t
            say $ "Setting cmd = " ++ show cmd
            sayAndSend pid $ Proposal True
            go $ AcceptState t t $ Just cmd
          else do
            when sendNeg $ sayAndSend pid $ Proposal False
            go s
        exec :: Execute -> Process ()
        exec m@(Execute cmd) = do
          say $ "Got " ++ show m
          send masterPid $ Executed cmd
          loop
        loop = loop
      say "Waiting..."
      receiveWait [match prep, match prop, match exec]


type PromiseState = (Time, Maybe Command, [ProcessId], Int, Int)

proposer :: [ProcessId] -> Int -> Process ()
proposer ls majority = do
  say $ "Hello, I`m a proposer. majority = " ++ show majority
  selfPid <- getSelfPid
  let cmd = selfPid
      time = 1
      prepareLoop t = do
        let prep = Prepare t selfPid
        broadcast ls prep
        reached <- waitPromise ls selfPid majority t cmd
        liftIO $ threadDelay 20000000
        unless reached $ prepareLoop $ t + 1
  prepareLoop time

waitPromise :: [ProcessId] -> ProcessId -> Int -> Time -> Command -> Process Bool
waitPromise ls selfPid majority myTime myCmd = go (0, Nothing, [], 0, 0)
  where
    go :: PromiseState -> Process Bool
    go (time, mcmd, promLs, promCount, promFailCount) = do
      timerPid <- setTimer 200000000 selfPid
      let
        prom :: PromiseOk -> Process Bool
        prom pr@(Promise prTime prMcmd prPid) = do
          say $ "Got " ++  show pr
          let newPromCount = promCount + 1
              newPromLs = prPid : promLs
              (newTime,newMcmd) = if prTime > time
              then (prTime,prMcmd)
              else (time,mcmd)
          if newPromCount >= majority
          then do
            kill timerPid "Got Promise majority. Kill the timer!"
            let cmd = if time > 0 then fromJust mcmd else myCmd
            broadcast newPromLs $ Propose myTime cmd selfPid
            waitSuccess ls selfPid majority myTime cmd
          else go (newTime,newMcmd,newPromLs,newPromCount, promFailCount)
        failProm :: PromiseNotOk -> Process Bool
        failProm pr = do
          say $ "Got " ++ show pr
          let newPromFailCount = promFailCount + 1
          if newPromFailCount >= majority
          then do
            kill timerPid "Got PromiseNotOk majority. Kill the timer!"
            return False
          else go (time, mcmd, promLs, promCount, newPromFailCount)

      say "Waiting promise ..."
      receiveWait [match timeOut, match prom, match failProm]


waitSuccess :: [ProcessId] -> ProcessId -> Int -> Time -> Command -> Process Bool
waitSuccess ls selfPid majority myTime cmd = go 0 0
  where
    go :: Int -> Int -> Process Bool
    go succCount failCount = do
      timerPid <- setTimer 20000000 selfPid
      let
        success :: Proposal -> Process Bool
        success pr@(Proposal True) = do
          let newSuccCount = succCount + 1
          say $ "Got " ++ show pr ++ " " ++ show newSuccCount
          if newSuccCount >= majority
          then do
            kill timerPid "Got success majority. Kill the timer!"
            broadcast ls $ Execute cmd
            return True
          else go newSuccCount failCount
        success (Proposal False) = do
          let newFailCount = failCount + 1
          say $ "Got " ++ show newFailCount
          if newFailCount >= majority
          then do
            kill timerPid "Got Fail majority. Kill the timer!"
            return False
          else go succCount newFailCount
      say "Waiting success ..."
      receiveWait [match timeOut, match success]

sayAndSend :: (Binary a,Typeable a,Show a) => ProcessId -> a -> Process ()
sayAndSend pid msg = do
  say $ "Sending " ++ show msg ++ " to " ++ show pid
  send pid msg

broadcast :: (Binary a,Typeable a,Show a) => [ProcessId] -> a -> Process ()
broadcast ls msg = do
  say $ "I broadcast " ++ show msg ++ " to " ++ show (length ls)
  mapM_ (`send` msg) ls

timeOut :: Expire -> Process Bool
timeOut _ = do
  say "Timeout"
  return False

setTimer :: Int -> ProcessId -> Process ProcessId
setTimer time pid =
  spawnLocal $ timer time pid

timer :: Int -> ProcessId -> Process ()
timer time pid = do
  liftIO $ threadDelay time
  sayAndSend pid Expire
