module Utilities where

import Config
import Control.Monad (filterM)
import Data.Aeson (Result (Error, Success))
import qualified Data.Aeson as A
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
import Data.Time.Format.ISO8601 (iso8601Show)
import Data.Yaml.Aeson
import Development.Shake (Action)
import qualified Development.Shake as Shake
import Development.Shake.FilePath ((<.>), (</>))
import qualified Development.Shake.FilePath as FP
import Text.Pandoc (Block (Plain), Meta (..), MetaValue (..), Pandoc (..))
import qualified Text.Pandoc as Pandoc
import Types

indexHtmlOutputPath :: FilePath -> FilePath
indexHtmlOutputPath srcPath =
  outputDir </> FP.dropExtension srcPath </> "index.html"

-- were applicative shenanigans necessary? no
-- but using them felt cool
indexHtmlSourcePaths :: FilePath -> [FilePath]
indexHtmlSourcePaths path = [indexHtmlMarkdownSourcePath] <*> [path]

indexHtmlMarkdownSourcePath :: FilePath -> FilePath
indexHtmlMarkdownSourcePath =
  FP.dropDirectory1
    . (<.> "md")
    . FP.dropTrailingPathSeparator
    . FP.dropFileName

markdownToHtml :: (FromJSON a) => FilePath -> Action (a, Text)
markdownToHtml filePath = do
  content <- Shake.readFile' filePath
  Shake.quietly . Shake.traced "Markdown to HTML" $ do
    pandoc@(Pandoc meta _) <-
      runPandoc . Pandoc.readMarkdown readerOptions . T.pack $ content
    -- WARNING markdown needs to have no whitespace before/after dashes
    -- print meta
    meta' <- fromMeta meta
    html <- runPandoc . Pandoc.writeHtml5String writerOptions $ pandoc
    return (meta', html)
  where
    readerOptions =
      Pandoc.def
        { Pandoc.readerStandalone = True,
          Pandoc.readerExtensions = Pandoc.enableExtension Pandoc.Ext_yaml_metadata_block Pandoc.pandocExtensions
        }
    writerOptions =
      Pandoc.def {Pandoc.writerExtensions = Pandoc.pandocExtensions}
    fromMeta (Meta meta) =
      A.fromJSON . A.toJSON <$> traverse metaValueToJSON meta >>= \case
        Success res -> pure res
        Error err -> fail $ "json conversion error:" <> err
    metaValueToJSON = \case
      MetaMap m -> A.toJSON <$> traverse metaValueToJSON m
      MetaList m -> A.toJSONList <$> traverse metaValueToJSON m
      MetaBool m -> pure $ A.toJSON m
      MetaString m -> pure $ A.toJSON $ T.strip m
      MetaInlines m -> metaValueToJSON $ MetaBlocks [Plain m]
      MetaBlocks m ->
        fmap (A.toJSON . T.strip)
          . runPandoc
          . Pandoc.writePlain Pandoc.def
          $ Pandoc mempty m

runPandoc :: Pandoc.PandocIO b -> IO b
runPandoc action =
  Pandoc.runIO (Pandoc.setVerbosity Pandoc.ERROR >> action)
    >>= either (fail . show) return

now :: Action T.Text
now = Shake.liftIO $ fmap (T.pack . iso8601Show) getCurrentTime

markdownToPost :: FilePath -> Action Post
markdownToPost path = do
  content <- Shake.readFile' path
  (Pandoc meta _) <-
    Shake.liftIO . runPandoc . Pandoc.readMarkdown readerOptions . T.pack $ content
  Shake.liftIO $ fromMeta meta
  where
    readerOptions =
      Pandoc.def
        { Pandoc.readerStandalone = True,
          Pandoc.readerExtensions = Pandoc.enableExtension Pandoc.Ext_yaml_metadata_block Pandoc.pandocExtensions
        }
    fromMeta (Meta meta) =
      A.fromJSON . A.toJSON <$> traverse metaValueToJSON meta >>= \case
        Success res -> pure res
        Error err -> fail $ "json conversion error:" <> err
    metaValueToJSON = \case
      MetaMap m -> A.toJSON <$> traverse metaValueToJSON m
      MetaList m -> A.toJSONList <$> traverse metaValueToJSON m
      MetaBool m -> pure $ A.toJSON m
      MetaString m -> pure $ A.toJSON $ T.strip m
      MetaInlines m -> metaValueToJSON $ MetaBlocks [Plain m]
      MetaBlocks m ->
        fmap (A.toJSON . T.strip)
          . runPandoc
          . Pandoc.writePlain Pandoc.def
          $ Pandoc mempty m

yamlToPost :: FilePath -> Action Post
yamlToPost path = do
  post <- decodeFileThrow path
  -- let post' = dateTransform post
  return post

isMarkdownPost :: FilePath -> Bool
isMarkdownPost path = FP.takeExtension path == ".md"

postHandles :: [(FilePath -> Bool, FilePath -> Action Post)]
postHandles = [(isMarkdownPost, markdownToPost)]

isDraft :: FilePath -> Action Bool
isDraft path = do
  let action =
        case find (\(test, _) -> test path) postHandles of
          (Just (_, action')) -> action'
          Nothing -> error "no post handle for this file type"
  post <- action path
  return $ case postDraft post of
    Just ret -> ret
    Nothing -> (error $ "Missing draft attr: " ++ path)

getPublishedPosts :: Action [FilePath]
getPublishedPosts = do
  postPaths <- Shake.getDirectoryFiles "" postGlobs
  filterM (fmap not . isDraft) postPaths

parseDate :: Text -> Maybe Text
parseDate str = do
  date <- parseTimeM False defaultTimeLocale "%Y-%-m-%-d" $ T.unpack str
  -- need to append the time to avoid potential issues
  return $ T.pack $ formatTime @UTCTime defaultTimeLocale "%Y-%m-%dT00:00:00Z" date

urlConvert :: FilePath -> Text
urlConvert = T.pack . FP.dropFileName . flip FP.replaceDirectory1 "https://pagwin.xyz"
