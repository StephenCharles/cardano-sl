module Pos.Aeson.ClientTypes
       (
       ) where

import           Universum

import           Data.Aeson                   (ToJSON (..), object, (.=))
import           Data.Aeson.TH                (defaultOptions, deriveJSON, deriveToJSON)
import           Data.Version                 (showVersion)

import           Pos.Core.Types               (SoftwareVersion (..))
import           Pos.Util.BackupPhrase        (BackupPhrase)
import           Pos.Wallet.Web.ClientTypes   (Addr, ApiVersion (..), CAccount,
                                               CAccountId, CAccountInit, CAccountMeta,
                                               CAddress, CCoin, CHash, CId, CInitialized,
                                               CPaperVendWalletRedeem, CProfile,
                                               CPtxCondition, CTExMeta, CTx, CTxId,
                                               CTxMeta, CUpdateInfo, CWAddressMeta,
                                               CWallet, CWalletAssurance, CWalletInit,
                                               CWalletMeta, CWalletRedeem,
                                               ClientInfo (..), SyncProgress, Wal)
import           Pos.Wallet.Web.Error         (WalletError)
import           Pos.Wallet.Web.Sockets.Types (NotifyEvent)

deriveJSON defaultOptions ''CAccountId
deriveJSON defaultOptions ''CWAddressMeta
deriveJSON defaultOptions ''CWalletAssurance
deriveJSON defaultOptions ''CAccountMeta
deriveJSON defaultOptions ''CAccountInit
deriveJSON defaultOptions ''CWalletRedeem
deriveJSON defaultOptions ''CWalletMeta
deriveJSON defaultOptions ''CWalletInit
deriveJSON defaultOptions ''CPaperVendWalletRedeem
deriveJSON defaultOptions ''CTxMeta
deriveJSON defaultOptions ''CProfile
deriveJSON defaultOptions ''BackupPhrase
deriveJSON defaultOptions ''CId
deriveJSON defaultOptions ''Wal
deriveJSON defaultOptions ''Addr
deriveJSON defaultOptions ''CHash
deriveJSON defaultOptions ''CInitialized

deriveToJSON defaultOptions ''CCoin
deriveToJSON defaultOptions ''SyncProgress
deriveToJSON defaultOptions ''NotifyEvent
deriveToJSON defaultOptions ''WalletError
deriveToJSON defaultOptions ''CTxId
deriveToJSON defaultOptions ''CAddress
deriveToJSON defaultOptions ''CAccount
deriveToJSON defaultOptions ''CWallet
deriveToJSON defaultOptions ''CPtxCondition
deriveToJSON defaultOptions ''CTx
deriveToJSON defaultOptions ''CTExMeta
deriveToJSON defaultOptions ''SoftwareVersion
deriveToJSON defaultOptions ''CUpdateInfo

instance ToJSON ApiVersion where
    toJSON ApiVersion0 = "v0"

instance ToJSON ClientInfo where
    toJSON ClientInfo {..} =
        object
            [ "gitRevision" .= ciGitRevision
            , "softwareVersion" .= pretty ciSoftwareVersion
            , "cabalVersion" .= showVersion ciCabalVersion
            , "apiVersion" .= ciApiVersion
            ]
