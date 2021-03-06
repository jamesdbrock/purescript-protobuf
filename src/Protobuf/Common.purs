-- | Do not import this module.
-- | See package README for explanation.
module Protobuf.Common
( FieldNumber
, WireType(..)
, Bytes(..)
)
where

import Prelude

import Data.ArrayBuffer.ArrayBuffer as AB
import Data.ArrayBuffer.Typed as TA
import Data.ArrayBuffer.Types (ArrayBuffer, Uint8Array)
import Data.Enum (class Enum, fromEnum, class BoundedEnum, Cardinality(..))
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype)
import Data.UInt (UInt)
import Effect (Effect)
import Effect.Unsafe (unsafePerformEffect)

type FieldNumber = UInt

-- | https://developers.google.com/protocol-buffers/docs/encoding#structure
data WireType
  = VarInt
  | Bits64
  | LenDel
  | Bits32

derive instance eqWireType :: Eq WireType
derive instance genericWireType :: Generic WireType _

instance ordWireType :: Ord WireType
 where
  compare l r = compare (fromEnum l) (fromEnum r)

instance boundedWireType :: Bounded WireType
 where
  top = Bits32
  bottom = VarInt

instance enumWireType :: Enum WireType
 where
  succ VarInt = Just Bits64
  succ Bits64 = Just LenDel
  succ LenDel = Just Bits32
  succ Bits32 = Nothing
  pred VarInt = Nothing
  pred Bits64 = Just VarInt
  pred LenDel = Just Bits64
  pred Bits32 = Just LenDel

instance boundedEnumWireType :: BoundedEnum WireType
 where
  cardinality = Cardinality 4
  toEnum 0 = Just VarInt
  toEnum 1 = Just Bits64
  toEnum 2 = Just LenDel
  toEnum 5 = Just Bits32
  toEnum _ = Nothing
  fromEnum VarInt = 0
  fromEnum Bits64 = 1
  fromEnum LenDel = 2
  fromEnum Bits32 = 5

instance showWireType :: Show WireType where show = genericShow

-- | Representation of a __bytes__
-- | [Scalar Value Type](https://developers.google.com/protocol-buffers/docs/proto3#scalar)
-- | field.
newtype Bytes = Bytes ArrayBuffer

instance showBytes :: Show Bytes
 where
  show (Bytes ab) = "<Bytes length " <> show (AB.byteLength ab) <> ">"

instance eqBytes :: Eq Bytes
 where
  eq (Bytes l) (Bytes r) = unsafePerformEffect $ do
    l' <- TA.whole l :: Effect Uint8Array
    r' <- TA.whole r :: Effect Uint8Array
    TA.eq l' r'

derive instance newtypeBytes :: Newtype Bytes _