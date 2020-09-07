module ProtocPlugin.Main where

import Prelude

import Effect (Effect)
import Data.Maybe (Maybe(..))

import Protobuf.Decode as Decode
import Protobuf.Encode as Encode
import Protobuf.Common (WireType)

import Node.Process (stdin, stdout)
import Node.Stream (read, writeString, uncork, onReadable)
import Node.Buffer (toArrayBuffer)
import Node.Encoding (Encoding(..))
import Data.ArrayBuffer.ArrayBuffer as AB

main :: Effect Unit
main = do
  onReadable stdin $ do
    stdinbufMay <- read stdin Nothing
    case stdinbufMay of
      Nothing -> pure unit
      Just stdinbuf -> do
        stdinab <- toArrayBuffer stdinbuf
        void $ writeString stdout UTF8 (show $ AB.byteLength stdinab) (pure unit)

parseCodeGeneratorRequest :: ParserT DataView Effect CodeGeneratorRequest
-- https://pursuit.purescript.org/packages/purescript-record

-- | Data type for a CodeGenerationRequest message.
-- | https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.compiler.plugin.pb
data CodeGeneratorRequest = CodeGeneratorRequest
  { file_to_generate :: Array String -- 1
  , parameter :: Maybe String -- 2
  , proto_file :: Array FileDescriptorProto -- 15
  , compiler_version :: Maybe Version -- 3
  }
derive instance showCodeGeneratorRequest :: Show CodeGeneratorRequest

defaultCodeGeneratorRequest =
  { file_to_generate = []
  , parameter = Nothing
  , proto_file = []
  , compiler_version = Nothing
  }

-- | The version number of protocol compiler.
data Version = Version
  { major :: Maybe Int --1
  , minor :: Maybe Int --2
  , patch :: Maybe Int --3
  , suffix :: Maybe String -- 4
  }
derive instance showVersion :: Show Version

-- | Describes a complete .proto file.
-- | https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.descriptor.pb
-- | The syntax for decoding this is "proto2"?
data FileDescriptorProto = FileDescriptorProto
  { name :: Maybe String -- 1
  , package :: Maybe String -- 2
  , dependency :: Array String -- 3
  , public_dependency :: Array Int -- 10
  , message_type :: Array DescriptorProto -- 4
  , enum_type :: Array EnumDescriptorProto -- 5
  , service :: Array ServiceDescriptorProto -- 6
  , extension :: Array FileDescriptorProto -- 7
  -- TODO , options :: Maybe FileOptions -- 8
  -- TODO , source_code_info :: Maybe SourceCodeInfo -- 9
  , syntax :: Maybe String -- 12
  }

-- | Describes a message type.
data DescriptorProto = DescriptorProto
  { name :: Maybe String -- 1
  , field :: Array FieldDescriptorProto -- 2
  , extension :: Array FieldDescriptorProto -- 6
  , nested_type :: Array DescriptorProto -- 3
  , enum_type :: Array EnumDescriptorProto -- 4
  , extension_range :: Array DescriptorProto_ExtensionRange -- 5
  , oneof_decl :: Array OneofDescriptorProto -- 8
  -- TODO , options :: Maybe MessageOptions -- 7
  -- TODO eh who cares about reserved ranges
  }

data DescriptorProto_ExtensionRange = DescriptorProto_ExtensionRange
  { start :: Maybe Int -- 1
  , end :: Maybe Int -- 2
  -- TODO , options :: Maybe ExtensionRangeOptions
  }

-- TODO
-- data ExtensionRangeOptions = ExtensionRangeOptions
--   { uninterpreted_option :: Array UninterpretedOption
--   -- ,  TODO extensions ::
--   }

data FieldDescriptorProto_Label = OPTIONAL | REQUIRED | REPEATED

-- | Describes a field within a message.
data FieldDescriptorProto = FieldDescriptorProto
  { name :: Maybe String -- 1
  , number :: Maybe Int -- 3
  , label :: Maybe FieldDescriptorProto_Label -- 4
  , type_ :: Maybe WireType -- 5
  , type_name :: Maybe String -- 6
  , extendee :: Maybe String -- 2
  , default_value :: Maybe String -- 7
  , oneof_index :: Maybe Int -- 9
  , json_name :: Maybe String -- 10
  -- TODO , options :: Maybe FieldOptions --8
  }

-- | Describes a oneof.
data OneofDescriptorProto = OneofDescriptorProto
  { name :: Maybe String -- 1
  -- TODO , options :: Maybe OneofOptions -- 2
  }

-- | Describes an enum type.
data EnumDescriptorProto = EnumDescriptorProto
  { name :: Maybe String -- 1
  , value :: Array EnumValueDescriptorProto -- 2
  -- TODO , options :: Maybe EnumOptions -- 3
  -- TODO , reserved_range :: Array EnumReservedRange -- 4
  -- TODO , reserved_name :: Array String -- 5
  }

-- | Describes a value within an enum.
data EnumValueDescriptorProto = EnumValueDescriptorProto
  { name :: Maybe String -- 1
  , number :: Maybe Int -- 2
  -- TODO , options :: Maybe EnumValueOptions -- 3
  }

-- TODO data ServiceDescriptorProto

-- TODO data MethodDescriptorProto