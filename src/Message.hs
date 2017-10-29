{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}

module Message where

import           Data.Binary
import           GHC.Generics
import           Data.Typeable
import Control.Distributed.Process

type Count = Int

type Time = Int
type Command = ProcessId
type Success = Bool

data Prepare = Prepare Time ProcessId
    deriving (Show, Generic, Typeable, Binary)
data PromiseOk= Promise Time (Maybe Command) ProcessId
    deriving (Show, Generic, Typeable, Binary)
data PromiseNotOk = PromiseNotOk
    deriving (Show, Generic, Typeable, Binary)
data Propose = Propose Time Command ProcessId
    deriving (Show, Generic, Typeable, Binary)
newtype Proposal = Proposal Success
    deriving (Show, Generic, Typeable, Binary)
data Execute = Execute Command
    deriving (Show, Generic, Typeable, Binary)
data Executed = Executed Command
    deriving (Show, Generic, Typeable, Binary)
data Expire = Expire
  deriving (Show, Generic, Typeable, Binary)
