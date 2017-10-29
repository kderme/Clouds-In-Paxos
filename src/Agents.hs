module Agents where

import Message

import           Data.Binary
import           Data.Typeable
import Control.Concurrent (threadDelay)
import Control.Distributed.Process
import Control.Monad (replicateM,replicateM_,void,unless)
import Data.Maybe (fromJust)

master :: Int -> Int -> Process ()
master a p = do
  say "Hello, I`m the master"
  selfPid <- getSelfPid
  lsAcceptors <- replicateM a $ spawnLocal $ acceptor selfPid
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

type AcceptState = (Time,Time,Maybe Command)

acceptor :: ProcessId -> Process ()
acceptor masterPid = do
  say "Hello, I`m an acceptor"
  acceptWithState masterPid (0, 0, Nothing)

acceptWithState :: ProcessId -> AcceptState -> Process ()
acceptWithState masterPid s@(tMax,tStore,mcmd) = do
  selfPid <- getSelfPid
  let
    prep :: Prepare -> Process ()
    prep m@(Prepare t pid) = do
      say $ "Got " ++  show m
      if t > tMax
      then do
        sayAndSend pid $ Promise tStore mcmd selfPid
        say $ "Setting Tmax = " ++ show t
        acceptWithState masterPid (t, tStore, mcmd)
      else
        acceptWithState masterPid s
    prop :: Propose -> Process ()
    prop m@(Propose t cmd pid) = do
      say $ "Got " ++  show m
      if t == tMax
      then do
        say $ "Setting Tstore = " ++ show t
        say $ "Setting cmd = " ++ show cmd
        sayAndSend pid $ Proposal True
        acceptWithState masterPid (t, t, Just cmd)
        else
          acceptWithState masterPid s
    exec :: Execute -> Process ()
    exec m@(Execute cmd) = do
      say $ "Got " ++ show m
      send masterPid $ Executed cmd

  say "Waiting..."
  receiveWait [match prep, match prop, match exec]

type PromiseState = (Time, Maybe Command, [ProcessId], Int)

proposer :: [ProcessId] -> Int -> Process ()
proposer ls majority = do
  say $ "Hello, I`m a proposer. majority = " ++ show majority
  selfPid <- getSelfPid
  let cmd = selfPid
      time = 1
      prep = Prepare time selfPid
      prepareLoop t = do
        broadcast ls prep
        reached <- waitPromise ls selfPid majority t cmd
        unless reached $ prepareLoop $ t + 1
  prepareLoop time

waitPromise :: [ProcessId] -> ProcessId -> Int -> Time -> Command -> Process Bool
waitPromise ls selfPid majority myTime myCmd = go (0, Nothing, [], 0)
  where
    go :: PromiseState -> Process Bool
    go (time, mcmd, promLs, promCount) = do
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
          else go (newTime,newMcmd,newPromLs,newPromCount)
      say "Waiting promise ..."
      receiveWait [match timeOut, match prom]


waitSuccess :: [ProcessId] -> ProcessId -> Int -> Time -> Command -> Process Bool
waitSuccess ls selfPid majority myTime cmd = go 0
  where
    go :: Int -> Process Bool
    go succCount = do
      timerPid <- setTimer 20000000 selfPid
      let
        success :: Proposal -> Process Bool
        success _ = do
          let newSuccCount = succCount + 1
          say $ "Got success " ++ show newSuccCount
          if newSuccCount >= majority
          then do
            kill timerPid "Got success majority. Kill the timer!"
            broadcast ls $ Execute cmd
            return True
          else go newSuccCount
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
