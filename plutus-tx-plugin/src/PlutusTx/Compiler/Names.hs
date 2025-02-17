-- editorconfig-checker-disable-file
{-# LANGUAGE ConstraintKinds  #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs            #-}

-- | Functions for compiling GHC names into Plutus Core names.
module PlutusTx.Compiler.Names where


import PlutusTx.Compiler.Kind
import {-# SOURCE #-} PlutusTx.Compiler.Type
import PlutusTx.Compiler.Types
import PlutusTx.PLCTypes

import GHC.Plugins qualified as GHC

import PlutusCore qualified as PLC
import PlutusCore.MkPlc qualified as PLC
import PlutusCore.Quote

import PlutusIR.Compiler.Names

import Data.Char
import Data.Functor
import Data.List
import Data.List.NonEmpty qualified as NE
import Data.Map qualified as Map
import Data.Text qualified as T

lookupName :: Scope uni -> GHC.Name -> Maybe (PLCVar uni)
lookupName (Scope ns _) n = Map.lookup n ns

{- |
Reverses the OccName tidying that GHC does, see 'tidyOccEnv'
and accompanying Notes.

This is bad, because it makes it much harder to read since the
disambiguating numbers are gone. However, these appear to be
non-deterministic (possibly depending on the order in which
modules are processed?), so we can't rely on them.

Essentially, we just strip off trailing digits.
This might remove "real" digits added by the user, but
there's not much we can do about that.

Note that this only affects the *textual* name, not the underlying
unique, so it has no effect on the behaviour of the program, merely
on how it is printed.
-}
getUntidiedOccString :: GHC.Name -> String
getUntidiedOccString n = dropWhileEnd isDigit (GHC.getOccString n)

compileNameFresh :: MonadQuote m => GHC.Name -> m PLC.Name
compileNameFresh n = safeFreshName $ T.pack $ getUntidiedOccString n

compileVarFresh :: CompilingDefault uni fun m ann => Ann -> GHC.Var -> m (PLCVar uni)
compileVarFresh ann v = do
    t' <- compileTypeNorm $ GHC.varType v
    n' <- compileNameFresh $ GHC.getName v
    pure $ PLC.VarDecl ann n' t'

lookupTyName :: Scope uni -> GHC.Name -> Maybe PLCTyVar
lookupTyName (Scope _ tyns) n = Map.lookup n tyns

compileTyNameFresh :: MonadQuote m => GHC.Name -> m PLC.TyName
compileTyNameFresh n = safeFreshTyName $ T.pack $ getUntidiedOccString n

compileTyVarFresh :: Compiling uni fun m ann => GHC.TyVar -> m PLCTyVar
compileTyVarFresh v = do
    k' <- compileKind $ GHC.tyVarKind v
    t' <- compileTyNameFresh $ GHC.getName v
    pure $ PLC.TyVarDecl annMayInline t' (k' $> annMayInline)

compileTcTyVarFresh :: Compiling uni fun m ann => GHC.TyCon -> m PLCTyVar
compileTcTyVarFresh tc = do
    k' <- compileKind $ GHC.tyConKind tc
    t' <- compileTyNameFresh $ GHC.getName tc
    pure $ PLC.TyVarDecl annMayInline t' (k' $> annMayInline)

pushName :: GHC.Name -> PLCVar uni-> ScopeStack uni -> ScopeStack uni
pushName ghcName n stack = let Scope ns tyns = NE.head stack in Scope (Map.insert ghcName n ns) tyns NE.<| stack

pushNames :: [(GHC.Name, PLCVar uni)] -> ScopeStack uni -> ScopeStack uni
pushNames mappings stack = foldl' (\acc (n, v) -> pushName n v acc) stack mappings

pushTyName :: GHC.Name -> PLCTyVar -> ScopeStack uni -> ScopeStack uni
pushTyName ghcName n stack = let Scope ns tyns = NE.head stack in Scope ns (Map.insert ghcName n tyns) NE.<| stack

pushTyNames :: [(GHC.Name, PLCTyVar)] -> ScopeStack uni -> ScopeStack uni
pushTyNames mappings stack = foldl' (\acc (n, v) -> pushTyName n v acc) stack mappings
