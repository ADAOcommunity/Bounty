{--
   Copyright 2021 ₳DAO

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
--}

{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE LambdaCase          #-}

module CollectionMaker where

import           Prelude                (String, show, Show)
import           Control.Monad          hiding (fmap)
import           PlutusTx.Maybe
import qualified Data.Map               as Map
import           Data.Text              (Text)
import           Data.Void              (Void)
import           Plutus.Contract        as Contract
import qualified PlutusTx
import           PlutusTx.IsData
import           PlutusTx.Prelude       hiding (Semigroup(..), unless)
import           Ledger                 hiding (singleton)
import           Ledger.Ada             as Ada
import           Ledger.Constraints     as Constraints
import           Ledger.Index           as Index
import qualified Ledger.Typed.Scripts   as Scripts
import qualified Ledger.Contexts                   as Validation
import           Ledger.Value           as Value
import           Playground.Contract    (printJson, printSchemas, ensureKnownCurrencies, stage, ToSchema, NonEmpty(..) )
import           Playground.TH          (mkKnownCurrencies, mkSchemaDefinitions, ensureKnownCurrencies)
import           Playground.Types       (KnownCurrency (..))
import           Prelude                (Semigroup (..))
import           Text.Printf            (printf)
import           GHC.Generics         (Generic)
import           Data.String          (IsString (..))
import           Data.Aeson           (ToJSON, FromJSON)

{-# INLINABLE mkPolicy #-}
mkPolicy :: AssetClass -> BuiltinData -> ScriptContext -> Bool
mkPolicy asset _ ctx =
    mintedAmount < 0 ||
    traceIfFalse "The CollectionMaker is not present." (nftSum > 0)
  where
    txInfo = scriptContextTxInfo ctx
    txInValues = [txOutValue $ txInInfoResolved txIn | txIn <- txInfoInputs $ scriptContextTxInfo ctx]
    txOuts = txInfoOutputs txInfo
    nftValues = [assetClassValueOf val asset | val <- txInValues]
    nftSum = sum nftValues
    mintedAmount = case flattenValue (txInfoMint txInfo) of
          [(cs, collectionTokenName, amt)] | cs == ownCurrencySymbol ctx -> amt
          _                                                              -> 0

policy :: AssetClass -> Scripts.MintingPolicy
policy asset = mkMintingPolicyScript $
    $$(PlutusTx.compile [|| Scripts.wrapMintingPolicy . mkPolicy ||])
    `PlutusTx.applyCode`
    PlutusTx.liftCode asset

curSymbol :: AssetClass -> CurrencySymbol
curSymbol asset = scriptCurrencySymbol $ policy asset