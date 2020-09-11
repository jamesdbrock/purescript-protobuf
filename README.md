# WIP purescript-protobuf

Purescript library and code generator for Google Protocol Buffers.

Only
[Protocol Buffers Version 3](https://developers.google.com/protocol-buffers/docs/reference/proto3-spec)
is supported.

This library operates on
[`ArrayBuffer`](https://pursuit.purescript.org/packages/purescript-arraybuffer-types/docs/Data.ArrayBuffer.Types#t:ArrayBuffer), so it will run both
[in Node](https://pursuit.purescript.org/packages/purescript-node-buffer/docs/Node.Buffer.Class)
and in browser environments.

## Using the library

None of the modules in this package should be imported directly in your program.
Rather, you'll import the message modules from the generated `.purs` files,
as well as modules for reading and writing `ArrayBuffer`s.

Each `.proto` message will export four names in the generated `.purs` modules.

1. A message record type, for example
   * `type MyMessageR = { field :: Maybe Int }`.
2. A message data type, for example
   * `newtype MyMessage = MyMessage MyMessageR`.
3. A message encoder which works with 
   [__purescript-arraybuffer-builder__](http://pursuit.purescript.org/packages/purescript-arraybuffer-builder/),
   for example
   * `putMyMessage :: forall m. MonadEffect m => MyMessage -> PutM m Unit`
4. A message decoder which works with
   [__purescript-parsing-dataview__](http://pursuit.purescript.org/packages/purescript-parsing-dataview/),
   for example
   * `parseMyMessage :: forall m. MonadEffect m => ParserT DataView m MyMessage`

Then, in your program, your imports will look something like this.


```purescript
import GeneratedMessages (MyMessage, putMyMessage, parseMyMessage)
import Text.Parsing.Parser (runParserT)
import Data.ArrayBuffer.Builder (execPut)
```

The generated code modules will transitively import other modules from this
package by importing `Protobuf.Runtime`.

The generated code depends on 
[__purescript-longs__](https://pursuit.purescript.org/packages/purescript-longs)
and the Javascript package
[__long__](https://www.npmjs.com/package/long).

## Code Generation

The `shell.nix` environment provides

* The Purescript toolchain
* The [`protoc`](https://github.com/protocolbuffers/protobuf/blob/master/src/README.md) compiler
* The `protoc-gen-purescript` executable plugin for `protoc` on the `PATH` so that
  [`protoc` can find it](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.compiler.plugin).

```
$ nix-shell

Purescript Protobuf development environment.
To build purescript-protobuf, run:

    npm install
    spago build

To test purescript-protobuf, run:

    spago test

To generate Purescript .purs files from .proto files, run:

    protoc --purescript_out=./test test/test.proto

[nix-shell]$
```

## Interpreting invalid encoding parse errors

When the decode parser encounters an invalid encoding in the protobuf input
stream then it will fail to parse.

When
[`Text.Parsing.Parser.ParserT`](https://pursuit.purescript.org/packages/purescript-parsing/docs/Text.Parsing.Parser#t:ParserT)
fails it will return a `ParseError String (Position {line::Int,column::Int})`.
The byte offset at which the invalid encoding occured is given by the
formula `column - 1`.

## Features

We only support __proto3__ so that means we don't support
[extensions](https://developers.google.com/protocol-buffers/docs/proto?hl=en#extensions).

The generated optional record fields will use `Nothing` instead of the 
[default values](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#default).

We support
[enumerations](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#enum).

We do not preserve
[unknown fields](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#unknowns).

We do not support the
[Any message type](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#any).

We do not support
[`oneof`](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#oneof).
The fields in a `oneof` will all be added to the message record product type.

We do not support
[maps](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#maps).

We support
[packages](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#packages).

We do not support
[services](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#services).

We do not support any
[options](https://developers.google.com/protocol-buffers/docs/proto3?hl=en#options).

## Contributing

Pull requests are welcome.
