-- | Primitive `Long`-based parsers for decoding Google Protocol Buffers.
-- |
-- | Do not import this module.
-- | See package README for explanation.
module Protobuf.Decode64
( zigzag64
, varint64
) where

import Prelude
import Effect.Class (class MonadEffect)
import Text.Parsing.Parser (ParserT, fail)
import Text.Parsing.Parser.DataView as Parse
import Data.Long.Internal
  ( Long
  , Unsigned
  , Signed
  , signedToUnsigned
  , unsignedToSigned
  , signedLongFromInt
  , unsafeFromInt
  , and
  , or
  , xor
  , complement
  , shl
  , zshr
  )
import Data.UInt (UInt)
import Data.UInt as UInt
import Data.ArrayBuffer.Types (DataView)

-- | Bitwise AND.
infixl 10 and as .&.

-- | Bitwise OR.
infixl 10 or as .|.

-- | Bitwise XOR.
infixl 10 xor as .^.

fromInt :: UInt -> Long Unsigned
fromInt = signedToUnsigned <<< signedLongFromInt <<< UInt.toInt

-- | https://stackoverflow.com/questions/2210923/zig-zag-decoding
zigzag64 :: Long Unsigned -> Long Signed
zigzag64 n = let n' = unsignedToSigned n in (n' `zshr` u1) .^. (lnegate (n' .&. u1))
 where
   lnegate x = complement x + u1
   u1    = unsafeFromInt 1

-- | https://developers.google.com/protocol-buffers/docs/encoding#varints
varint64 :: forall m. MonadEffect m => ParserT DataView m (Long Unsigned)
varint64 = do
  n_0 <- fromInt <$> Parse.anyUint8
  if n_0 < u0x80
    then pure n_0
    else do
      let acc_0 = n_0 `and` u0x7F
      n_1 <- fromInt <$> Parse.anyUint8
      if n_1 < u0x80
        then pure $ acc_0 .|. (n_1 `shl` u7)
        else do
          let acc_1 = ((n_1 .&. u0x7F) `shl` u7) .|. acc_0
          n_2 <- fromInt <$> Parse.anyUint8
          if n_2 < u0x80
            then pure $ acc_1 .|. (n_2 `shl` u14)
            else do
              let acc_2 = ((n_2 .&. u0x7F) `shl` u14) .|. acc_1
              n_3 <- fromInt <$> Parse.anyUint8
              if n_3 < u0x80
                then pure $ acc_2 .|. (n_3 `shl` u21)
                else do
                  let acc_3 = ((n_3 .&. u0x7F) `shl` u21) .|. acc_2
                  n_4 <- fromInt <$> Parse.anyUint8
                  if n_4 < u0x80
                    then pure $ acc_3 .|. (n_4 `shl` u28)
                    else do
                      let acc_4 = ((n_4 .&. u0x7F) `shl` u28) .|. acc_3
                      n_5 <- fromInt <$> Parse.anyUint8
                      if n_5 < u0x80
                        then pure $ acc_4 .|. (n_5 `shl` u35)
                        else do
                          let acc_5 = ((n_5 .&. u0x7F) `shl` u35) .|. acc_4
                          n_6 <- fromInt <$> Parse.anyUint8
                          if n_6 < u0x80
                            then pure $ acc_5 .|. (n_6 `shl` u42)
                            else do
                              let acc_6 = ((n_6 .&. u0x7F) `shl` u42) .|. acc_5
                              n_7 <- fromInt <$> Parse.anyUint8
                              if n_7 < u0x80
                                then pure $ acc_6 .|. (n_7 `shl` u49)
                                else do
                                  let acc_7 = ((n_7 .&. u0x7F) `shl` u49) .|. acc_6
                                  n_8 <- fromInt <$> Parse.anyUint8
                                  if n_8 < u0x80
                                    then pure $ acc_7 .|. (n_8 `shl` u56)
                                    else do
                                      let acc_8 = ((n_8 .&. u0x7F) `shl` u56) .|. acc_7
                                      n_9 <- fromInt <$> Parse.anyUint8
                                      if n_9 < u0x02
                                        then pure $ acc_8 .|. (n_9 `shl` u63)
                                        else fail "varint64 overflow. Possibly there is an encoding error in the input stream."
 where
  u7    = unsafeFromInt 7
  u14   = unsafeFromInt 14
  u21   = unsafeFromInt 21
  u28   = unsafeFromInt 28
  u35   = unsafeFromInt 35
  u42   = unsafeFromInt 42
  u49   = unsafeFromInt 49
  u56   = unsafeFromInt 56
  u63   = unsafeFromInt 63
  u0x02 = unsafeFromInt 2
  u0x7F = unsafeFromInt 0x7F
  u0x80 = unsafeFromInt 0x80
