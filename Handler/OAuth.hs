{-# LANGUAGE TupleSections, OverloadedStrings #-}
module Handler.OAuth where

import Import
import OAuthToken
import qualified Data.ByteString.Char8 as C
import qualified Data.Text.Encoding as T
import qualified Data.Text as TS

import qualified Network.HTTP.Types as H
import Network.Wai

import Network.Mail.Mime (randomString)
import System.Random (newStdGen)

import Control.Applicative ((<$>), (<*>))

-- OAuth step 1, fetch a request token
postRequestTokenR :: Handler RepPlain
postRequestTokenR = do
  token  <- liftIO $ randomKey 16
  secret <- liftIO $ randomKey 32

  let reqTok = RequestTokenT
                (read ("R-" ++ token) :: RequestToken)
                (TS.pack secret)
                "http://yourdomain.com/callback?params" -- TODO replace with actual param
  _ <- runDB $ insert reqTok

  let result = [ ("oauth_token",              C.pack . show . requestTokenTToken  $ reqTok)
               , ("oauth_token_secret",       T.encodeUtf8  . requestTokenTSecret $ reqTok)
               , ("oauth_callback_confirmed", "true")
               ]
  return $
    RepPlain $ toContent $ H.renderSimpleQuery False result

  where
    randomKey len = do
      stdgen <- newStdGen
      return $ fst $ randomString len stdgen

-- OAuth step 2, get the authorization from the user
data Authorization = Authorization
                      { granted :: Bool}

authorizeForm :: Form Authorization
authorizeForm = renderDivs $ Authorization
  <$> areq checkBoxField "Please access my data" Nothing

getAuthorizeR :: RequestToken -> Handler RepHtml
getAuthorizeR token = do
  (widget, enctype) <- generateFormPost authorizeForm
  defaultLayout [whamlet|
  <h1>Do you want to grant access to your data?
  <form method=post action=@{AuthorizeR token} encrype=#{enctype}>
    ^{widget}
    <input type="submit" value="Do as I say">
|]

postAuthorizeR :: RequestToken -> Handler RepHtml
postAuthorizeR _ = do
  ((result, _), _) <- runFormPost authorizeForm
  let doRedirect = case result of
                  FormSuccess authorization -> granted authorization
                  _                         -> False
  if doRedirect
    then sendWaiResponse $ responseLBS H.status303 [("Location", "http://www.github.com/")] "ask that dude"
    else defaultLayout [whamlet|
<p>Your data stays on our server.
|]

type Verifier = Int

data OAuth = OAuth {
    oauthToken    :: Text,
    oauthVerifier :: Verifier
  }
  deriving Show

-- OAuth step 3, fetch the access token
postAccessTokenR :: Handler RepPlain
postAccessTokenR = do
  oauth <- runInputGet $ OAuth
            <$> ireq textField "oauth_token"
            <*> ireq intField  "oauth_verifier"
  return $ RepPlain $ toContent ("oauth_token=&oauth_token_secret=&ident=" :: ByteString)
