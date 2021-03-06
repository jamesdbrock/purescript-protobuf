-- | Entry point for the code-generating executable `protoc` plugin. See the
-- | package README for instructions on how to run the code generator.
-- |
-- | The funny thing about writing a `protoc` compiler plugin codec is that it
-- | bootstraps itself. We just have to write enough of the compiler plugin codec
-- | that it can handle the `plugin.proto` and `descriptor.proto` files, and
-- | then we call the compiler plugin on these `.proto` files and the compiler
-- | plugin codec generates the rest of itself.
-- |
-- | Then we can delete the hand-written code and generate code to replace it
-- | with this command.
-- |
-- |     protoc --purescript_out=./src/ProtocPlugin google/protobuf/compiler/plugin.proto
-- |
-- | See
-- | * https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.compiler.plugin.pb
-- | * https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.descriptor.pb
module ProtocPlugin.Main (main) where

import Prelude

import Effect (Effect)
import Data.Maybe (Maybe(..),fromMaybe,maybe)
import Data.Either (Either(..))
import Data.Array (concatMap, mapMaybe)
import Data.Array as Array
import Data.String as String
import Data.String.Pattern as String.Pattern
import Data.String.Regex as String.Regex
import Data.String.Regex.Flags as String.Regex.Flags

import Text.Parsing.Parser (runParserT)
import Data.ArrayBuffer.Builder (execPut)
import Node.Process (stdin, stdout, stderr)
import Node.Stream (read, write, writeString, onReadable)
import Node.Buffer (toArrayBuffer, fromArrayBuffer)
import Node.Encoding (Encoding(..))
import Node.Path (basenameWithoutExt)
import Data.ArrayBuffer.DataView as DV

import Google.Protobuf.Compiler.Plugin
  ( CodeGeneratorRequest(..), parseCodeGeneratorRequest
  , CodeGeneratorResponse(..), putCodeGeneratorResponse
  , CodeGeneratorResponse_File(..)
  )

import Google.Protobuf.Descriptor
  ( FileDescriptorProto(..)
  , DescriptorProto(..)
  , FieldDescriptorProto(..)
  , OneofDescriptorProto(..)
  , EnumDescriptorProto(..)
  , EnumValueDescriptorProto(..)
  , FieldDescriptorProto_Type(..)
  , FieldDescriptorProto_Label(..)
  )


main :: Effect Unit
main = do
  onReadable stdin $ do
    stdinbufMay <- read stdin Nothing
    case stdinbufMay of
      Nothing -> pure unit
      Just stdinbuf -> do
        stdinab <- toArrayBuffer stdinbuf
        let stdinview = DV.whole stdinab
        requestParsed <- runParserT stdinview $ parseCodeGeneratorRequest $ DV.byteLength stdinview
        case requestParsed of
          Left err -> void $ writeString stderr UTF8 (show err) (pure unit)
          Right request -> do
            -- Uncomment this line to write the parsed declarations to stderr.
            -- void $ writeString stderr UTF8 (show request) (pure unit)
            let response = generate request
            responseab <- execPut $ putCodeGeneratorResponse response
            responsebuffer <- fromArrayBuffer responseab
            void $ write stdout responsebuffer (pure unit)


generate :: CodeGeneratorRequest -> CodeGeneratorResponse
generate (CodeGeneratorRequest{file_to_generate,parameter,proto_file,compiler_version}) =
  CodeGeneratorResponse
    { error: Nothing
    , file: map (genFile proto_file) proto_file
    , __unknown_fields : []
    }

 -- | Names of parent messages for a message or enum.
type NameSpace = Array String

-- | A message descriptor, plus the names of all parent messages.
data ScopedMsg = ScopedMsg NameSpace DescriptorProto

-- | An enum descriptor, plus the names of all parent messages.
data ScopedEnum = ScopedEnum NameSpace EnumDescriptorProto

-- | Scoped field name which has the qualified package namespace and the field name.
data ScopedField = ScopedField NameSpace String


genFile :: Array FileDescriptorProto -> FileDescriptorProto -> CodeGeneratorResponse_File
genFile proto_file (FileDescriptorProto
  { name: fileName
  , package
  , dependency
  , public_dependency
  , message_type
  , enum_type
  , syntax
  }) = CodeGeneratorResponse_File
    { name : Just fileNameOut
    , insertion_point : Nothing
    , content : Just content
    , __unknown_fields : []
    }
 where
  capitalize :: String -> String
  capitalize s = String.toUpper (String.take 1 s) <> String.drop 1 s
  decapitalize :: String -> String
  decapitalize s = String.toLower (String.take 1 s) <> String.drop 1 s

  baseName = case fileName of
    Nothing -> "Generated"
    Just "" -> "Generated"
    Just n -> basenameWithoutExt n ".proto"

  messages :: Array ScopedMsg
  messages = flattenMessages [] message_type

  enums :: Array ScopedEnum
  enums = (ScopedEnum [] <$> enum_type) <> flattenEnums [] message_type

  fileNameOut = baseName <> "." <> (String.joinWith "." ((map capitalize packageName))) <> ".purs"

  packageName = case package of
    Nothing -> []
    Just ps -> String.split (String.Pattern.Pattern ".") ps


  lookupPackageByFilepath :: String -> Maybe (Array String)
  lookupPackageByFilepath fpath =
    case Array.find (\(FileDescriptorProto f) -> maybe false (_ == fpath) f.name) proto_file of
      Just (FileDescriptorProto {package: Just p}) -> Just $ String.split (String.Pattern.Pattern ".") p
      _ -> Nothing

  content = String.joinWith "\n" $
    [ "-- | Generated by __purescript-protobuf__ from file `" <> fromMaybe "<unknown>" fileName <> "`"
    , "module " <> (String.joinWith "." ((map mkModuleName packageName))) <> "." <> mkModuleName baseName
    , "( " <> (String.joinWith "\n, "
         ((map genMessageExport messages) <> (map genEnumExport enums)))
    , """)
where

import Prelude
import Effect.Class (class MonadEffect)
import Control.Monad.Rec.Class (class MonadRec)
import Record.Builder as Record.Builder
import Data.Array as Array
import Data.Bounded as Bounded
import Data.Enum as Enum
import Data.Eq as Eq
import Data.Function as Function
import Data.Float32 as Float32
import Data.Show as Show
import Data.Ord as Ord
import Data.Maybe as Maybe
import Data.Newtype as Newtype
import Data.Generic.Rep as Generic.Rep
import Data.Generic.Rep.Show as Generic.Rep.Show
import Data.Generic.Rep.Bounded as Generic.Rep.Bounded
import Data.Generic.Rep.Enum as Generic.Rep.Enum
import Data.Generic.Rep.Ord as Generic.Rep.Ord
import Data.Semigroup as Semigroup
import Data.Symbol as Symbol
import Record as Record
import Data.Traversable as Traversable
import Data.UInt as UInt
import Data.Unit as Unit
import Prim.Row as Prim.Row
import Data.Long.Internal as Long
import Text.Parsing.Parser as Parser
import Data.ArrayBuffer.Builder as ArrayBuffer.Builder
import Data.ArrayBuffer.Types as ArrayBuffer.Types
import Protobuf.Common as Common
import Protobuf.Decode as Decode
import Protobuf.Encode as Encode
import Protobuf.Runtime as Runtime
"""
    ]
    <>
    (map genImport dependency)
    <>
    ["\n"]
    <>
    (map genMessage messages)
    <>
    (map genEnum enums)
    <>
    ["\n"]


  -- We have to import the modules qualified in the way because
  -- 1. When protoc "fully qualifies" a field type from an imported
  --    desriptor, the qualification consists of only the package name
  -- 2. protoc allows multiple files to have the same package name,
  --    such as descriptor.proto and any.proto (package "google.protobuf")
  --    but Purescript requires each file to have a different module name.
  genImport :: String -> String
  genImport fpath = "import " <> make moduleName <> " as " <> make qualifiedName
   where
    pkg = lookupPackageByFilepath fpath
    moduleName = mkImportName (Just fpath) pkg
    qualifiedName = Array.dropEnd 1 moduleName
    make = String.joinWith "." <<< map capitalize

  mkImportName
    :: Maybe String -- file path
    -> Maybe (Array String) -- package name
    -> Array String
  mkImportName fileString packages = map mkModuleName $ pkg <> file
   where
    file = case fileString of
      Nothing -> []
      Just f -> [basenameWithoutExt f ".proto"]
    pkg = case packages of
      Nothing -> []
      Just ps -> ps


  -- | underscores and primes are not allowed in module names
  -- | https://github.com/purescript/documentation/blob/master/errors/ErrorParsingModule.md
  mkModuleName :: String -> String
  mkModuleName n =  capitalize $ illegalDelete $ underscoreToUpper n
   where
    underscoreToUpper :: String -> String
    underscoreToUpper = case String.Regex.regex "_([a-z])" flag of
      Left _ -> identity
      Right patt -> String.Regex.replace' patt toUpper
    toUpper _ [x] = String.toUpper x
    toUpper x _ = x
    flag = String.Regex.Flags.RegexFlags
      { global: true
      , ignoreCase: false
      , multiline: false
      , sticky: false
      , unicode: true
      }
    illegalDelete :: String -> String
    illegalDelete =
      String.replaceAll (String.Pattern.Pattern "_") (String.Pattern.Replacement "") <<<
      String.replaceAll (String.Pattern.Pattern "'") (String.Pattern.Replacement "1")


  -- | Pull all of the enums out of of the nested messages and bring them
  -- | to the top, with their namespace.
  flattenEnums :: NameSpace -> Array DescriptorProto -> Array ScopedEnum
  flattenEnums namespace msgarray = concatMap go msgarray
   where
    go :: DescriptorProto -> Array ScopedEnum
    go (DescriptorProto {name: Just msgName, nested_type, enum_type: msgEnums}) =
      (ScopedEnum (namespace <> [msgName]) <$> msgEnums)
        <> flattenEnums (namespace <> [msgName]) nested_type
    go _ = [] -- error no name

  genEnumExport :: ScopedEnum -> String
  genEnumExport (ScopedEnum namespace (EnumDescriptorProto {name: Just eName})) =
    (mkTypeName $ namespace <> [eName]) <> "(..)"
  genEnumExport _ = "" -- error, no name

  genEnum :: ScopedEnum -> String
  genEnum (ScopedEnum namespace (EnumDescriptorProto {name: Just eName, value})) =
    let tname = mkTypeName $ namespace <> [eName]
    in
    String.joinWith "\n" $
      [ "\ndata " <> tname
      , "  = " <> String.joinWith "\n  | " (genEnumConstruct <$> value)
      , "derive instance generic" <> tname <> " :: Generic.Rep.Generic " <> tname <> " _"
      , "derive instance eq" <> tname <> " :: Eq.Eq " <> tname
      , "instance show" <> tname <> " :: Show.Show " <> tname <> " where show = Generic.Rep.Show.genericShow"
      , "instance ord" <> tname <> " :: Ord.Ord " <> tname <> " where compare = Generic.Rep.Ord.genericCompare"
      , "instance bounded" <> tname <> " :: Bounded.Bounded " <> tname
      , " where"
      , "  bottom = Generic.Rep.Bounded.genericBottom"
      , "  top = Generic.Rep.Bounded.genericTop"
      , "instance enum" <> tname <> " :: Enum.Enum " <> tname
      , " where"
      , "  succ = Generic.Rep.Enum.genericSucc"
      , "  pred = Generic.Rep.Enum.genericPred"
      , "instance boundedenum" <> tname <> " :: Enum.BoundedEnum " <> tname
      , " where"
      , "  cardinality = Generic.Rep.Enum.genericCardinality"
      ]
      <>
      (map genEnumTo value)
      <>
      [ "  toEnum _ = Maybe.Nothing"]
      <>
      (map genEnumFrom value)
   where
    genEnumConstruct (EnumValueDescriptorProto {name: Just name}) =
      mkEnumName name
    genEnumConstruct _ = "" -- error no name
    genEnumTo (EnumValueDescriptorProto {name: Just name,number: Just number}) =
      "  toEnum " <> show number <> " = Maybe.Just " <> mkEnumName name
    genEnumTo _ = "" -- error no name
    genEnumFrom (EnumValueDescriptorProto {name: Just name,number: Just number}) =
      "  fromEnum " <> mkEnumName name <> " = " <> show number
    genEnumFrom _ = "" -- error no name
    mkEnumName name = mkTypeName $ namespace <> [eName] <> [name]
  genEnum _ = "" -- error no name

  -- | Pull all of the nested messages out of of the messages and bring them
  -- | to the top, with their namespace.
  flattenMessages :: NameSpace -> Array DescriptorProto -> Array ScopedMsg
  flattenMessages namespace msgarray = concatMap go msgarray
   where
    go :: DescriptorProto -> Array ScopedMsg
    go (DescriptorProto r@{name: Just msgName, nested_type}) =
      [ScopedMsg namespace (DescriptorProto r)]
        <> flattenMessages (namespace <> [msgName]) nested_type
    go _ = [] -- error no name


  genMessageExport :: ScopedMsg -> String
  genMessageExport (ScopedMsg namespace (DescriptorProto {name: Just msgName, oneof_decl})) =
    tname <> "(..), " <> tname <> "Row, " <> tname <> "R, parse" <> tname <> ", put" <> tname <> ", default" <> tname <> ", mk" <> tname
      <> String.joinWith "" (map genOneofExport oneof_decl)
   where
    tname = mkTypeName $ namespace <> [msgName]
    genOneofExport (OneofDescriptorProto {name: Just oname}) = ", " <> mkTypeName (namespace <> [msgName,oname]) <> "(..)"
    genOneofExport _ = "" -- error, no oname
  genMessageExport _ = "" -- error, no name



-- | We need to wrap our structural record types in a nominal
-- | data type so that we can nest records, otherwise we get
-- | https://github.com/purescript/documentation/blob/master/errors/CycleInTypeSynonym.md
-- | And so that we can assign instances.
  genMessage :: ScopedMsg -> String
  genMessage (ScopedMsg nameSpace (DescriptorProto {name: Just msgName, field, oneof_decl})) =
    let tname = mkTypeName $ nameSpace <> [msgName]
    in
    String.joinWith "\n" $
      [ "\ntype " <> tname <> "Row ="
      , "  ( " <> String.joinWith "\n  , "
            (  (mapMaybe (genFieldRecord nameSpace) field)
            <> (map (genFieldRecordOneof (nameSpace <> [msgName])) oneof_decl)
            <> ["__unknown_fields :: Array Runtime.UnknownField"]
            )
      , "  )"
      , "type " <> tname <> "R = Record " <> tname <> "Row"
      , "newtype " <> tname <> " = " <> tname <> " " <> tname <> "R"
      , "derive instance generic" <> tname <> " :: Generic.Rep.Generic " <> tname <> " _"
      , "derive instance newtype" <> tname <> " :: Newtype.Newtype " <> tname <> " _"
      , "derive instance eq" <> tname <> " :: Eq.Eq " <> tname
      -- https://github.com/purescript/purescript/issues/2975#issuecomment-313650710
      , "instance show" <> tname <> " :: Show.Show " <> tname <> " where show x = Generic.Rep.Show.genericShow x"
      , ""
      , "put" <> tname <> " :: forall m. MonadEffect m => " <> tname <> " -> ArrayBuffer.Builder.PutM m Unit.Unit"
      , "put" <> tname <> " (" <> tname <> " r) = do"
      , String.joinWith "\n" $ Array.catMaybes
          $  (map (genFieldPut nameSpace) field)
          <> (Array.mapWithIndex (genOneofPut (nameSpace <> [msgName]) field) oneof_decl)
      , "  Traversable.traverse_ Runtime.putFieldUnknown r.__unknown_fields"
      , ""
      , "parse" <> tname <> " :: forall m. MonadEffect m => MonadRec m => Int -> Parser.ParserT ArrayBuffer.Types.DataView m " <> tname
      , "parse" <> tname <> " length = Runtime.label \"" <> msgName <> " / \" $"
      , "  Runtime.parseMessage " <> tname <> " default" <> tname <> " parseField length"
      , " where"
      , "  parseField"
      , "    :: Runtime.FieldNumberInt"
      , "    -> Common.WireType"
      , "    -> Parser.ParserT ArrayBuffer.Types.DataView m (Record.Builder.Builder " <> tname <> "R " <> tname <> "R)"
      , String.joinWith "\n" (map (genFieldParser (nameSpace <> [msgName]) oneof_decl) field)
      , "  parseField fieldNumber wireType = Runtime.parseFieldUnknown fieldNumber wireType"
      , ""
      , "default" <> tname <> " :: " <> tname <> "R"
      , "default" <> tname <> " ="
      , "  { " <> String.joinWith "\n  , "
              (  (mapMaybe genFieldDefault field)
              <> (map genFieldDefaultOneof oneof_decl)
              <> ["__unknown_fields: []"]
              )
      , "  }"
      , ""
      , "mk" <> tname <> " :: forall r1 r3. Prim.Row.Union r1 " <> tname <> "Row r3 => Prim.Row.Nub r3 " <> tname <> "Row => Record r1 -> " <> tname
      , "mk" <> tname <> " r = " <> tname <> " $ Record.merge r default" <> tname
      , String.joinWith "\n" (Array.mapWithIndex (genTypeOneof (nameSpace <> [msgName]) field) oneof_decl)
      ]
  genMessage _ = "" -- error not enough information

  genTypeOneof
    :: NameSpace
    -> Array FieldDescriptorProto
    -> Int
    -> OneofDescriptorProto
    -> String
  genTypeOneof nameSpace field indexOneof (OneofDescriptorProto {name: Just oname}) = String.joinWith "\n"
    [ "data " <> cname
    , "  = " <> (String.joinWith "\n  | " (mapMaybe go field))
    , "derive instance generic" <> cname <> " :: Generic.Rep.Generic " <> cname <> " _"
    , "derive instance eq" <> cname <> " :: Eq.Eq " <> cname
    , "instance show" <> cname <> " :: Show.Show " <> cname <> " where show = Generic.Rep.Show.genericShow"
    ]
   where
    cname = String.joinWith "_" $ map capitalize $ nameSpace <> [oname]
    go :: FieldDescriptorProto -> Maybe String
    go f@(FieldDescriptorProto
                      {name: Just fname
                      , oneof_index: Just index
                      , type: Just ftype
                      , type_name
                      }) =
      if index == indexOneof
        then Just $ (String.joinWith "_" $ map capitalize [cname,fname]) <> " " <> genFieldType ftype type_name
        else Nothing
     where
      genFieldType :: FieldDescriptorProto_Type -> Maybe String -> String
      genFieldType FieldDescriptorProto_Type_TYPE_DOUBLE _ = "Number"
      genFieldType FieldDescriptorProto_Type_TYPE_FLOAT _ = "Float32.Float32"
      genFieldType FieldDescriptorProto_Type_TYPE_INT64 _ = "(Long.Long Long.Signed)"
      genFieldType FieldDescriptorProto_Type_TYPE_UINT64 _ = "(Long.Long Long.Unsigned)"
      genFieldType FieldDescriptorProto_Type_TYPE_INT32 _ = "Int"
      genFieldType FieldDescriptorProto_Type_TYPE_FIXED64 _ = "(Long.Long Long.Unsigned)"
      genFieldType FieldDescriptorProto_Type_TYPE_FIXED32 _ = "UInt.UInt"
      genFieldType FieldDescriptorProto_Type_TYPE_BOOL _ = "Boolean"
      genFieldType FieldDescriptorProto_Type_TYPE_STRING _ = "String"
      genFieldType FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) = mkFieldType "" tname
      genFieldType FieldDescriptorProto_Type_TYPE_BYTES _ = "Common.Bytes"
      genFieldType FieldDescriptorProto_Type_TYPE_UINT32 _ = "UInt.UInt"
      genFieldType FieldDescriptorProto_Type_TYPE_ENUM (Just tname) = mkFieldType "" tname
      genFieldType FieldDescriptorProto_Type_TYPE_SFIXED32 _ = "Int"
      genFieldType FieldDescriptorProto_Type_TYPE_SFIXED64 _ = "(Long.Long Long.Signed)"
      genFieldType FieldDescriptorProto_Type_TYPE_SINT32 _ = "Int"
      genFieldType FieldDescriptorProto_Type_TYPE_SINT64 _ = "(Long.Long Long.Signed)"
      genFieldType FieldDescriptorProto_Type_TYPE_GROUP _ = "" -- error ignore
      genFieldType _ _ = "" -- error, not enough information
    go _ = Nothing
  genTypeOneof _ _ _ _ = "" -- error no name


  genOneofPut :: NameSpace -> Array FieldDescriptorProto -> Int -> OneofDescriptorProto -> Maybe String
  genOneofPut nameSpace field oindex (OneofDescriptorProto {name: Just oname}) =
    Just $ String.joinWith "\n" $
      [ "  case r." <> decapitalize oname <> " of"
      , "    Maybe.Nothing -> pure unit"
      ]
      <> map genOneofFieldPut myfields
   where
    myfields = Array.filter ismine field
    ismine f@(FieldDescriptorProto {oneof_index: Just i}) = i == oindex
    ismine _ = false
    genOneofFieldPut (FieldDescriptorProto
      { name: Just name'
      , number: Just fnumber
      , type: Just ftype
      , type_name
      }) = go ftype type_name
     where
      fname = decapitalize name'
      go FieldDescriptorProto_Type_TYPE_DOUBLE _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.double"
      go FieldDescriptorProto_Type_TYPE_FLOAT _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.float"
      go FieldDescriptorProto_Type_TYPE_INT64 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.int64"
      go FieldDescriptorProto_Type_TYPE_UINT64 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.uint64"
      go FieldDescriptorProto_Type_TYPE_INT32 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.int32"
      go FieldDescriptorProto_Type_TYPE_FIXED64 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.fixed64"
      go FieldDescriptorProto_Type_TYPE_FIXED32 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.fixed32"
      go FieldDescriptorProto_Type_TYPE_BOOL _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.bool"
      go FieldDescriptorProto_Type_TYPE_STRING _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.string"
      go FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) $ Runtime.putLenDel " <> mkFieldType "put" tname
      go FieldDescriptorProto_Type_TYPE_BYTES _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.bytes"
      go FieldDescriptorProto_Type_TYPE_UINT32 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.uint32"
      go FieldDescriptorProto_Type_TYPE_ENUM _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Runtime.putEnum"
      go FieldDescriptorProto_Type_TYPE_SFIXED32 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.sfixed32"
      go FieldDescriptorProto_Type_TYPE_SFIXED64 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.sfixed64"
      go FieldDescriptorProto_Type_TYPE_SINT32 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.sint32"
      go FieldDescriptorProto_Type_TYPE_SINT64 _ =
        "    Maybe.Just (" <> mkTypeName (nameSpace <> [oname,name'])<> " x) -> Runtime.putOptional " <> show fnumber <> " (Maybe.Just x) Encode.sint64"
      go _ _ = "" -- error maybe its a TYPE_GROUP?
    genOneofFieldPut _ = "" -- error not enough information
  genOneofPut _ _ _ _ = Nothing -- error no name



  genFieldPut :: NameSpace -> FieldDescriptorProto -> Maybe String
  genFieldPut nameSpace (FieldDescriptorProto
    { name: Just name'
    , number: Just fnumber
    , label: Just flabel
    , type: Just ftype
    , type_name
    , oneof_index: Nothing -- must not be a member of a oneof, that case handled seperately
    }) = Just $ go flabel ftype type_name
   where
    fname = decapitalize name'
    -- For repeated fields of primitive numeric types, always put the packed
    -- encoding.
    -- https://developers.google.com/protocol-buffers/docs/encoding?hl=en#packed
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_DOUBLE _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.double'"
    go _ FieldDescriptorProto_Type_TYPE_DOUBLE _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.double"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FLOAT _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.float'"
    go _ FieldDescriptorProto_Type_TYPE_FLOAT _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.float"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_INT64 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.int64'"
    go _ FieldDescriptorProto_Type_TYPE_INT64 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.int64"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_UINT64 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.uint64'"
    go _ FieldDescriptorProto_Type_TYPE_UINT64 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.uint64"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_INT32 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.int32'"
    go _ FieldDescriptorProto_Type_TYPE_INT32 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.int32"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FIXED64 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.fixed64'"
    go _ FieldDescriptorProto_Type_TYPE_FIXED64 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.fixed64"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FIXED32 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.fixed32'"
    go _ FieldDescriptorProto_Type_TYPE_FIXED32 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.fixed32"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_BOOL _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.bool'"
    go _ FieldDescriptorProto_Type_TYPE_BOOL _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.bool"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_STRING _ =
      "  Runtime.putRepeated " <> show fnumber <> " r." <> fname <> " Encode.string"
    go _ FieldDescriptorProto_Type_TYPE_STRING _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.string"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) =
      "  Runtime.putRepeated " <> show fnumber <> " r." <> fname <> " $ Runtime.putLenDel " <> mkFieldType "put" tname
    go _ FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " $ Runtime.putLenDel " <> mkFieldType "put" tname
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_BYTES _ =
      "  Runtime.putRepeated " <> show fnumber <> " r." <> fname <> " $ Encode.bytes"
    go _ FieldDescriptorProto_Type_TYPE_BYTES _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.bytes"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_UINT32 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.uint32'"
    go _ FieldDescriptorProto_Type_TYPE_UINT32 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.uint32"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_ENUM _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Runtime.putEnum'"
    go _ FieldDescriptorProto_Type_TYPE_ENUM _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Runtime.putEnum"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SFIXED32 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.sfixed32'"
    go _ FieldDescriptorProto_Type_TYPE_SFIXED32 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.sfixed32"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SFIXED64 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.sfixed64'"
    go _ FieldDescriptorProto_Type_TYPE_SFIXED64 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.sfixed64"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SINT32 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.sint32'"
    go _ FieldDescriptorProto_Type_TYPE_SINT32 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.sint32"
    go FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SINT64 _ =
      "  Runtime.putPacked " <> show fnumber <> " r." <> fname <> " Encode.sint64'"
    go _ FieldDescriptorProto_Type_TYPE_SINT64 _ =
      "  Runtime.putOptional " <> show fnumber <> " r." <> fname <> " Encode.sint64"
    go _ _ _ = "" -- error, maybe its a TYPE_GROUP
  genFieldPut _ _ = Nothing -- it's a oneof, or error not enough information

  genFieldParser :: NameSpace -> Array OneofDescriptorProto -> FieldDescriptorProto -> String
  genFieldParser nameSpace oneof_decl (FieldDescriptorProto
    { name: Just name'
    , number: Just fnumber
    , label: Just flabel
    , type: Just ftype
    , type_name
    , oneof_index
    }) = go (lookupOneof oneof_index) flabel ftype type_name
   where
    lookupOneof :: Maybe Int -> Maybe String
    lookupOneof Nothing = Nothing
    lookupOneof (Just i) =
      case Array.index oneof_decl i of
        Just (OneofDescriptorProto {name}) -> name
        _-> Nothing

    fname = decapitalize name'
    mkConstructor oname = mkTypeName (nameSpace <> [oname,name'])

    -- For repeated fields of primitive numeric types, also parse the packed
    -- encoding.
    -- https://developers.google.com/protocol-buffers/docs/encoding?hl=en#packed
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_DOUBLE _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.double"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.double"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FLOAT _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.float"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.float"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_INT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.int64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.int64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_UINT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.uint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.uint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_INT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.int32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.int32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FIXED64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.fixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.fixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FIXED32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.fixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.fixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_BOOL _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.bool"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.bool"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_STRING _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.string"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel " <> mkFieldType "parse" tname
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_BYTES _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.bytes"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_UINT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.uint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.uint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_ENUM _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseEnum"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Runtime.parseEnum"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SFIXED32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sfixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.sfixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SFIXED64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sfixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.sfixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SINT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.sint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]
    go _ FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SINT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Array.snoc x"
      , "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel $ Runtime.manyLength Decode.sint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.flip Semigroup.append x"
      ]

    go (Just oname) _ FieldDescriptorProto_Type_TYPE_DOUBLE _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.double"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_FLOAT _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.float"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_INT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.int64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_UINT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.uint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _  FieldDescriptorProto_Type_TYPE_INT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.int32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_FIXED64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.fixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_FIXED32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.fixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_BOOL _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.bool"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_STRING _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.string"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel " <> mkFieldType "parse" tname
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_BYTES _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.bytes"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_UINT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.uint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_ENUM _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseEnum"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_SFIXED32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sfixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_SFIXED64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sfixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_SINT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]
    go (Just oname) _ FieldDescriptorProto_Type_TYPE_SINT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> decapitalize oname <> "\") $ Function.const $ Maybe.Just (" <> mkConstructor oname <> " x)"
      ]

    go _ _ FieldDescriptorProto_Type_TYPE_DOUBLE _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.double"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_FLOAT _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.float"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_INT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.int64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_UINT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.uint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _  FieldDescriptorProto_Type_TYPE_INT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.int32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_FIXED64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.fixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_FIXED32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.fixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_BOOL _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.bool"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_STRING _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.string"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseLenDel " <> mkFieldType "parse" tname
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_BYTES _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.LenDel = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.bytes"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_UINT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.uint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_ENUM _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Runtime.parseEnum"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_SFIXED32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits32 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sfixed32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_SFIXED64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.Bits64 = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sfixed64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_SINT32 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sint32"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ FieldDescriptorProto_Type_TYPE_SINT64 _ = String.joinWith "\n"
      [ "  parseField " <> show fnumber <> " Common.VarInt = Runtime.label \"" <> name' <> " / \" $ do"
      , "    x <- Decode.sint64"
      , "    pure $ Record.Builder.modify (Symbol.SProxy :: Symbol.SProxy \"" <> fname <> "\") $ Function.const $ Maybe.Just x"
      ]
    go _ _ _ _ = "" -- error, maybe its a TYPE_GROUP
  genFieldParser _ _ _ = "" -- error, not enough information

  -- | For embedded message fields, the parser merges multiple instances of the same field,
  -- | https://developers.google.com/protocol-buffers/docs/encoding?hl=en#optional
  genFieldRecord :: NameSpace -> FieldDescriptorProto -> Maybe String
  genFieldRecord nameSpace (FieldDescriptorProto
    { name: Just name'
    , number: Just fnumber
    , label: Just flabel
    , type: Just ftype
    , type_name
    , oneof_index
    }) = (\x -> fname <> " :: " <> x) <$> ptype oneof_index flabel ftype type_name
   where
    fname = decapitalize name'
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_DOUBLE _ = Just "Array Number"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FLOAT _ = Just "Array Float32.Float32"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_INT64 _ = Just "Array (Long.Long Long.Signed)"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_UINT64 _ = Just "Array (Long.Long Long.Unsigned)"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_INT32 _ = Just "Array Int"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FIXED64 _ = Just "Array (Long.Long Long.Unsigned)"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_FIXED32 _ = Just "Array UInt.UInt"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_BOOL _ = Just "Array Boolean"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_STRING _ = Just "Array String"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) = Just $ "Array " <> mkFieldType "" tname
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_BYTES _ = Just "Array Common.Bytes"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_UINT32 _ = Just "Array UInt.UInt"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_ENUM (Just tname) = Just $"Array " <> mkFieldType "" tname
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SFIXED32 _ = Just "Array Int"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SFIXED64 _ = Just "Array (Long.Long Long.Signed)"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SINT32 _ = Just "Array Int"
    ptype Nothing FieldDescriptorProto_Label_LABEL_REPEATED FieldDescriptorProto_Type_TYPE_SINT64 _ = Just "Array (Long.Long Long.Signed)"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_DOUBLE _ = Just "Maybe.Maybe Number"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_FLOAT _ = Just "Maybe.Maybe Float32.Float32"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_INT64 _ = Just "Maybe.Maybe (Long.Long Long.Signed)"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_UINT64 _ = Just "Maybe.Maybe (Long.Long Long.Unsigned)"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_INT32 _ = Just "Maybe.Maybe Int"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_FIXED64 _ = Just "Maybe.Maybe (Long.Long Long.Unsigned)"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_FIXED32 _ = Just "Maybe.Maybe UInt.UInt"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_BOOL _ = Just "Maybe.Maybe Boolean"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_STRING _ = Just "Maybe.Maybe String"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_MESSAGE (Just tname) = Just $ "Maybe.Maybe " <> mkFieldType "" tname
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_BYTES _ = Just "Maybe.Maybe Common.Bytes"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_UINT32 _ = Just "Maybe.Maybe UInt.UInt"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_ENUM (Just tname) = Just $ "Maybe.Maybe " <> mkFieldType "" tname
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_SFIXED32 _ = Just "Maybe.Maybe Int"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_SFIXED64 _ = Just "Maybe.Maybe (Long.Long Long.Signed)"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_SINT32 _ = Just "Maybe.Maybe Int"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_SINT64 _ = Just "Maybe.Maybe (Long.Long Long.Signed)"
    ptype Nothing _ FieldDescriptorProto_Type_TYPE_GROUP _ = Nothing -- ignore
    ptype _ _ _ _ = Nothing -- its a Oneof
  genFieldRecord _ _ = Nothing -- error, not enough information


  -- https://developers.google.com/protocol-buffers/docs/proto3#oneof_features
  -- “A oneof cannot be repeated.”
  genFieldRecordOneof :: NameSpace -> OneofDescriptorProto -> String
  genFieldRecordOneof nameSpace (OneofDescriptorProto {name: Just fname}) =
    decapitalize fname <> " :: Maybe.Maybe " <> (String.joinWith "_" $ map capitalize $ nameSpace <> [fname])
  genFieldRecordOneof _ _ = "" -- error no name

  genFieldDefault :: FieldDescriptorProto -> Maybe String
  genFieldDefault (FieldDescriptorProto
    { name: Just name'
    , label: Just flabel
    , oneof_index
    }) = (\x -> fname <> ": " <> x) <$> dtype oneof_index flabel
   where
    fname = decapitalize name'
    dtype Nothing FieldDescriptorProto_Label_LABEL_REPEATED = Just "[]"
    dtype Nothing _              = Just "Maybe.Nothing"
    dtype _ _ = Nothing -- it's a Oneof
  genFieldDefault _ = Nothing -- error, not enough information

  -- https://developers.google.com/protocol-buffers/docs/proto3#oneof_features
  -- “A oneof cannot be repeated.”
  genFieldDefaultOneof :: OneofDescriptorProto -> String
  genFieldDefaultOneof (OneofDescriptorProto {name: Just fname}) =
    decapitalize fname <> ": Maybe.Nothing"
  genFieldDefaultOneof _ = "" -- error no name


  mkFieldType
    :: String -- prefix for the name, i.e. "put" "parse"
    -> String -- package-qualified period-separated field name
    -> String
  mkFieldType prefix s =
    let (ScopedField names name) = parseFieldName s
    in
    if names `beginsWith` packageName && (isLocalMessageName name || isLocalEnumName name)
      then
        -- it's a name in this package
        prefix <> (mkTypeName $ Array.drop (Array.length packageName) names <> [name])
      else
        -- it's a name in the top-level of an imported package
        String.joinWith "." $ (map mkModuleName $ names) <> [prefix <> capitalize name]
   where
    isLocalMessageName :: String -> Boolean
    isLocalMessageName fname = maybe false (const true) $
      flip Array.find messages $ \(ScopedMsg _ (DescriptorProto {name})) ->
        maybe false (fname == _) name
    isLocalEnumName :: String -> Boolean
    isLocalEnumName ename = maybe false (const true) $
      flip Array.find enums $ \(ScopedEnum _(EnumDescriptorProto {name})) ->
        maybe false (ename == _) name
    parseFieldName :: String -> ScopedField
    parseFieldName fname =
      if String.take 1 fname == "."
        then
          -- fully qualified
          let names = Array.dropWhile (_ == "") $ String.split (String.Pattern.Pattern ".") fname
          in
          ScopedField (Array.dropEnd 1 names) (fromMaybe "" $ Array.last names)
        else
          ScopedField [] fname -- this case should never occur, protoc always qualifies the names for us
    beginsWith :: Array String -> Array String -> Boolean
    beginsWith xs x = x == Array.take (Array.length x) xs

  mkTypeName :: Array String -> String
  mkTypeName ns = String.joinWith "_" $ map capitalize ns

