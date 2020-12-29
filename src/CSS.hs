{-# LANGUAGE OverloadedStrings #-}

module CSS where

import Control.Monad (join, void)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import Text.Parsec.Text (Parser)
import qualified Text.Parsec as P
import Data.List (intercalate)
import Text.Parsec ((<|>))
import Text.Render
import Util

data Selector
  = GenericSelector String
  | ClassSelector String (Maybe String)
  deriving (Eq, Show)

instance Render Selector where
  render (GenericSelector selector) = selector
  render (ClassSelector cx (Just mod)) = "." <> cx <> mod
  render (ClassSelector cx Nothing) = "." <> cx

data CssNode
  = RuleGroup (NonEmpty Selector) String
  | MediaQuery String [CssNode]
  | Query String String [CssNode]
  | Comment String
  deriving (Eq, Show)

instance Render CssNode where
  render (RuleGroup selectors body) = selectors' <> " {" <> body <> "}"
    where
      selectors' = intercalate ",\n" $ NE.toList $ fmap render selectors
  render (MediaQuery query nodes) = "@media " <> query <> " {\n" <> nodes' <> "\n}"
    where
      nodes' = intercalate "\n\n" $ map (("  " ++) . render) nodes
  render (Query query name nodes) = "@" <> query <> " " <> name <> " {\n" <> nodes' <> "\n}"
    where
      nodes' = intercalate "\n\n" $ map (("  " ++) . render) nodes
  render (Comment c) = "/*" <> c <> "*/"

newtype AST = AST {unAst :: [CssNode]}
  deriving (Eq, Show)

instance Render AST where
  render (AST nodes) = intercalate "\n\n" (map render nodes) <> "\n"

genericSelector :: Parser Selector
genericSelector = GenericSelector . trimEnd <$> P.many1 (P.noneOf ",{}") <* P.spaces

classSelector :: Parser Selector
classSelector = do
  void $ P.char '.'
  className <- join <$> P.many (P.try escape <|> fmap pure nonEscape)
  mod <- trimEnd <$> P.many (P.noneOf ",{")
  pure $ ClassSelector className $ NE.toList <$> NE.nonEmpty mod
  where
    nonEscape :: Parser Char
    nonEscape = P.noneOf ",:{ "
    escape :: Parser String
    escape = do
      d <- P.char '\\'
      c <- P.noneOf " \n\t"
      pure [d, c]

selector :: Parser Selector
selector = P.try classSelector <|> genericSelector

brackets :: Parser a -> Parser a
brackets = P.between (P.char '{') (P.char '}')

ruleGroup :: Parser CssNode
ruleGroup = do
  selectors <- P.sepBy1 selector (P.char ',' <* P.spaces)
  body <- brackets $ P.many $ P.noneOf "}"
  P.spaces
  -- selectors is guaranteed to have at least one item becase of P.sepBy1
  pure $ RuleGroup (NE.fromList selectors) body

mediaQuery :: Parser CssNode
mediaQuery = do
  void $ P.string "@media" <* P.spaces
  q <- P.many (P.noneOf "{")
  ruleGroups <- brackets $ P.spaces *> P.many (P.try mediaQuery <|> ruleGroup)
  P.spaces
  pure $ MediaQuery (trimEnd q) ruleGroups

query :: Parser CssNode
query = do
  q <- P.char '@' *> P.many (P.noneOf " ") <* P.spaces
  name <- P.many P.alphaNum <* P.spaces
  ruleGroups <- brackets $ P.spaces *> P.many ruleGroup
  P.spaces
  pure $ Query q name ruleGroups

comment :: Parser CssNode
comment = do
  void $ P.string "/*"
  Comment <$> P.manyTill P.anyChar (P.try $ P.string "*/") <* P.spaces

cssFile :: Parser AST
cssFile = AST <$> P.many node <* P.spaces <* P.eof
  where
    node = P.try comment <|> P.try mediaQuery <|> P.try query <|> ruleGroup
