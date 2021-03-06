{-# LANGUAGE Rank2Types   #-}
{-# LANGUAGE TypeFamilies #-}

-- | Instance of SscGStateClass.

module Pos.Ssc.GodTossing.GState
       ( -- * Instances
         -- ** instance SscGStateClass
         getGlobalCerts
       , gtGetGlobalState
       , getStableCerts
       ) where

import           Control.Lens                     ((.=), _Wrapped)
import           Control.Monad.Except             (MonadError (throwError), runExceptT)
import           Control.Monad.Morph              (hoist)
import qualified Crypto.Random                    as Rand
import qualified Data.HashMap.Strict              as HM
import           Formatting                       (build, sformat, (%))
import           System.Wlog                      (WithLogger, logDebug, logInfo)
import           Universum

import           Pos.Binary.GodTossing            ()
import           Pos.Core                         (BlockVersionData, EpochIndex (..),
                                                   HasConfiguration, SlotId (..),
                                                   VssCertificatesMap (..), epochIndexL,
                                                   epochOrSlotG, vcVssKey)
import           Pos.DB                           (MonadDBRead, SomeBatchOp (..))
import           Pos.Lrc.Types                    (RichmenStakes)
import           Pos.Ssc.Class.Storage            (SscGStateClass (..), SscVerifier)
import           Pos.Ssc.Extra                    (MonadSscMem, sscRunGlobalQuery)
import           Pos.Ssc.GodTossing.Configuration (HasGtConfiguration)
import           Pos.Ssc.Core                     (SscPayload (..))
import qualified Pos.Ssc.GodTossing.DB            as DB
import           Pos.Ssc.GodTossing.Functions     (getStableCertsPure)
import           Pos.Ssc.GodTossing.Seed          (calculateSeed)
import           Pos.Ssc.GodTossing.Toss          (MultiRichmenStakes, PureToss,
                                                   applyGenesisBlock,
                                                   rollbackGT, runPureTossWithLogger,
                                                   supplyPureTossEnv,
                                                   verifyAndApplySscPayload)
import           Pos.Ssc.Types                    (SscBlock (..), SscGlobalState (..), sgsCommitments,
                                                   sgsOpenings, sgsShares,
                                                   sgsVssCertificates)
import           Pos.Ssc.VerifyError              (SscVerifyError (..))
import qualified Pos.Ssc.GodTossing.VssCertData   as VCD
import           Pos.Util.Chrono                  (NE, NewestFirst (..), OldestFirst (..))
import           Pos.Util.Util                    (_neHead, _neLast)

----------------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------------

gtGetGlobalState
    :: (MonadSscMem ctx m, MonadIO m)
    => m SscGlobalState
gtGetGlobalState = sscRunGlobalQuery ask

getGlobalCerts
    :: (MonadSscMem ctx m, MonadIO m)
    => SlotId -> m VssCertificatesMap
getGlobalCerts sl =
    sscRunGlobalQuery $
        VCD.certs .
        VCD.setLastKnownSlot sl <$>
        view sgsVssCertificates

-- | Get stable VSS certificates for given epoch.
getStableCerts
    :: (HasGtConfiguration, HasConfiguration, MonadSscMem ctx m, MonadIO m)
    => EpochIndex -> m VssCertificatesMap
getStableCerts epoch =
    getStableCertsPure epoch <$> sscRunGlobalQuery (view sgsVssCertificates)

----------------------------------------------------------------------------
-- Methods from class
----------------------------------------------------------------------------

instance (HasGtConfiguration, HasConfiguration) => SscGStateClass where
    sscLoadGlobalState = loadGlobalState
    sscGlobalStateToBatch = dumpGlobalState
    sscRollbackU = rollbackBlocks
    sscVerifyAndApplyBlocks = verifyAndApply
    sscCalculateSeedQ _epoch richmen =
        calculateSeed
        <$> view sgsCommitments
        <*> (map vcVssKey . getVssCertificatesMap . VCD.certs <$>
             view sgsVssCertificates)
        <*> view sgsOpenings
        <*> view sgsShares
        <*> pure richmen

loadGlobalState :: (HasConfiguration, MonadDBRead m, WithLogger m) => m SscGlobalState
loadGlobalState = do
    logDebug "Loading SSC global state"
    gs <- DB.getSscGlobalState
    gs <$ logInfo (sformat ("Loaded GodTossing state: " %build) gs)

dumpGlobalState :: HasConfiguration => SscGlobalState -> [SomeBatchOp]
dumpGlobalState = one . SomeBatchOp . DB.gtGlobalStateToBatch

-- randomness needed for crypto :(
type GSUpdate a = forall m . (MonadState SscGlobalState m, WithLogger m, Rand.MonadRandom m) => m a

rollbackBlocks :: (HasGtConfiguration, HasConfiguration) => NewestFirst NE SscBlock -> GSUpdate ()
rollbackBlocks blocks = tossToUpdate $ rollbackGT oldestEOS payloads
  where
    oldestEOS = blocks ^. _Wrapped . _neLast . epochOrSlotG
    payloads = over _Wrapped (map snd . rights . map getSscBlock . toList)
                   blocks

verifyAndApply
    :: (HasGtConfiguration, HasConfiguration)
    => RichmenStakes
    -> BlockVersionData
    -> OldestFirst NE SscBlock
    -> SscVerifier ()
verifyAndApply richmenStake bvd blocks =
    verifyAndApplyMultiRichmen False (richmenData, bvd) blocks
  where
    epoch = blocks ^. _Wrapped . _neHead . epochIndexL
    richmenData = HM.fromList [(epoch, richmenStake)]

verifyAndApplyMultiRichmen
    :: (HasGtConfiguration, HasConfiguration)
    => Bool
    -> (MultiRichmenStakes, BlockVersionData)
    -> OldestFirst NE SscBlock
    -> SscVerifier ()
verifyAndApplyMultiRichmen onlyCerts env =
    tossToVerifier . hoist (supplyPureTossEnv env) .
    mapM_ (verifyAndApplyDo . getSscBlock)
  where
    verifyAndApplyDo (Left header) = applyGenesisBlock $ header ^. epochIndexL
    verifyAndApplyDo (Right (header, payload)) =
        verifyAndApplySscPayload (Right header) $
        filterPayload payload
    filterPayload payload
        | onlyCerts = leaveOnlyCerts payload
        | otherwise = payload
    leaveOnlyCerts (CommitmentsPayload _ certs) =
        CommitmentsPayload mempty certs
    leaveOnlyCerts (OpeningsPayload _ certs) = OpeningsPayload mempty certs
    leaveOnlyCerts (SharesPayload _ certs) = SharesPayload mempty certs
    leaveOnlyCerts c@(CertificatesPayload _) = c

tossToUpdate :: PureToss a -> GSUpdate a
tossToUpdate action = do
    oldState <- use identity
    (res, newState) <- runPureTossWithLogger oldState action
    (identity .= newState) $> res

tossToVerifier
    :: ExceptT SscVerifyError PureToss a
    -> SscVerifier a
tossToVerifier action = do
    oldState <- use identity
    (resOrErr, newState) <-
        runPureTossWithLogger oldState $ runExceptT action
    case resOrErr of
        Left e    -> throwError e
        Right res -> (identity .= newState) $> res
