{-# LANGUAGE OverloadedStrings #-}


-- Parsing French TAG generated from an FrenchTAG XMG metagrammar.


module NLP.FrenchTAG.Parse where


import           Control.Applicative ((*>), (<$>), (<*>),
                        optional, (<|>))
import           Control.Monad ((<=<))

import qualified Data.Foldable       as F
import qualified Data.Text           as T
import qualified Data.Text.Lazy      as L
import qualified Data.Text.Lazy.IO   as L
import qualified Data.Tree           as R
import qualified Data.Map.Strict     as M

import qualified Text.HTML.TagSoup   as TagSoup
import           Text.XML.PolySoup   hiding (P, Q)
import qualified Text.XML.PolySoup   as PolySoup


-- import           NLP.FrenchTAG.Tree


-------------------------------------------------
-- Data types
-------------------------------------------------


-- | Parsing predicates.
type P a = PolySoup.P (XmlTree L.Text) a
type Q a = PolySoup.Q (XmlTree L.Text) a


-- | Syntagmatic symbol.
type Sym = L.Text


-- | Attribute.
type Attr = L.Text


-- | Attribute value.
type Val = L.Text


-- | Variable.
type Var = L.Text


-- | Attribute-value matrix.
type AVM = M.Map Attr (Either Val Var)


-- | Non-terminal/node type.
data Type
    = Std 
    | Foot
    | Anchor
    | Lex
    | Other SubType
    deriving (Show, Eq, Ord)


-- | Node subtype (e.g. subst, nadj, whatever they mean...)
type SubType = L.Text


-- | Non-terminal.
data NonTerm = NonTerm
    { typ   :: Type
    , sym   :: Sym
    , top   :: Maybe AVM
    , bot   :: Maybe AVM }
    deriving (Show, Eq, Ord)


-- | FrenchTAG tree.
type Tree = R.Tree NonTerm


-------------------------------------------------
-- Parsing
-------------------------------------------------


-- | Grammar parser (as a parser).
grammarP :: P [Tree]
grammarP = concat <$> every' grammarQ


-- | Grammar parser.
grammarQ :: Q [Tree]
grammarQ = true //> treeQ


-- | Tree parser.
treeQ :: Q Tree
treeQ = named "tree" `joinR` first nodeQ


-- | Node parser.
nodeQ :: Q Tree
nodeQ = (named "node" *> attr "type") `join` ( \typTxt -> R.Node
        <$> first (nonTermQ typTxt)
        <*> every' nodeQ )


-- | Non-terminal parser.
nonTermQ :: L.Text -> Q NonTerm
nonTermQ typ = joinR (named "narg") $
    first $ joinR (named "fs") $ do
        sym <- first symQ
        top <- optional $ first $ avmQ "top"
        bot <- optional $ first $ avmQ "bot"
        return $ NonTerm (parseTyp typ) sym top bot


-- | Syntagmatic value parser.
symQ :: Q Sym
symQ = joinR (named "f" *> hasAttrVal "name" "cat") $
    first $ node (named "sym" *> attr "value")


-- | AVM parser.
avmQ :: L.Text -> Q AVM
avmQ name = joinR (named "f" *> hasAttrVal "name" name) $
    first $ joinR (named "fs") $
        M.fromList <$> every attrValQ


-- | An attribute/value parser.
attrValQ :: Q (Attr, Either Val Var)
attrValQ = join (named "f" *> attr "name") $ \atr -> do
    valVar <- first $ (Left <$> valQ)
                  <|> (Right <$> varQ)
    return (atr, valVar)


-- | Attribute value parser.
valQ :: Q Val
valQ = node $ named "sym" *> attr "value"


-- | Attribute variable parser.
varQ :: Q Var
varQ = node $ named "sym" *> attr "varname"


-- | Type parser.
parseTyp :: L.Text -> Type
parseTyp x = case x of
    "std"       -> Std
    "lex"       -> Lex
    "anchor"    -> Anchor
    "foot"      -> Foot
    _           -> Other x


-- | Parse textual contents of the French TAG XML file.
parseGrammar :: L.Text -> [Tree]
parseGrammar =
    F.concat . evalP grammarP . parseForest . TagSoup.parseTags


-- | Parse the stand-alone French TAG xml file.
readGrammar :: FilePath -> IO [Tree]
readGrammar path = parseGrammar <$> L.readFile path


printGrammar :: FilePath -> IO ()
printGrammar =
  let printTree = putStrLn . R.drawTree . fmap show
  in mapM_ printTree <=< readGrammar
