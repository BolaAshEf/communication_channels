<a href="https://www.buymeacoffee.com/bola" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="41" width="174"></a>

## Description

This package helps you request executing code in different isolate(ex: service, overlay, etc..) with the ability to register data types that you will work with, then send and receive easily.
These different isolates we call `Channels`.

* A channel is basically a new isolate the you want to be able to send and receive data from and to it form any other channel.

* All channels have what I call `communication provider`, it is the way that a channel should communicate with.
There is a `SocketComProvider` provider that works by making a server and communicate through it. There is other types of providers, for example if you use `Flutter` , then it is preferable to use `IsolateComProvider`. here it is

```dart
abstract class _ChannelNameServer {
  const _ChannelNameServer._();
  static SendPort? lookupPortByName(String portName) => 
    IsolateNameServer.lookupPortByName(portName);
  static bool registerPortWithName(SendPort port, String portName) => 
    IsolateNameServer.registerPortWithName(port, portName);
  static bool removePortNameMapping(String portName) => 
    IsolateNameServer.removePortNameMapping(portName);
}
class IsolateSender extends ProviderSender{
  final String portName;
  const IsolateSender(this.portName) : assert(portName != "");

  @override
  Future<bool> send(SentChannelMessageType msg) async {
    final sendPort = _ChannelNameServer.lookupPortByName(portName);
    if(sendPort == null){return false;}
    sendPort.send(msg);
    return true;
  }

  @override
  List<Object?> get props => [portName];
}
class IsolateComProvider extends ComProvider<IsolateSender>{
  String get portName => sender.portName;

  @override
  final IsolateSender sender;

  ReceivePort? _recPort;

  IsolateComProvider({
    required String portName,
  }) : sender = IsolateSender(portName);

  @override
  Future<Stream<SentChannelMessageType>> getReceiverBroadcastStream() async {
    _recPort = ReceivePort();
    _ChannelNameServer.registerPortWithName(_recPort!.sendPort, portName);
    return _recPort!.asBroadcastStream()
        .takeWhile((msg) => msg is SentChannelMessageType,).cast<SentChannelMessageType>();
  }

  @override
  Future<void> closeStreamObj() async {
    _ChannelNameServer.removePortNameMapping(portName);
    _recPort?.close();

    _recPort = null;
  }
}
```


## Usage

* First, you start by defining all the types that you might send or receive.
For more details about this step you can see the example of `easy_serialization` package.

```dart
final customSerializableObjects = <SerializationConfig>[
  SerializationConfig<Offset>(
    toMarkupObj: (obj) => {
      "dx": obj.dx,
      "dy": obj.dy,
    },
    fromMarkupObj: (markup) => Offset(
      markup["dx"],
      markup["dy"],
    ),
  ),

  ShapeFillType.values.config,

  SerializationConfig.abstract<Shape>(),
  SerializationConfig.serializable<Circle>(Circle.fromMarkup),
  SerializationConfig.serializable<Rectangle>(Rectangle.fromMarkup),
  SerializationConfig.serializable<Square>(Square.fromMarkup),
];
```


* Secondly, you must define the channels that you will work with.

```dart
final mainChannel = ChannelType(
  code: 0, debugName: "MAIN",
  provider: SocketComProvider(host: InternetAddress.tryParse("127.0.0.1"), port: 5000,),
);

final isolateChannel = ChannelType(
  code: 1, debugName: "ISOLATE",
  provider: SocketComProvider(host: InternetAddress.tryParse("127.0.0.1"), port: 5001,),
);

/// Pass all channels you have defined here.
final channelsDefinitions = ChannelsDefinitions([mainChannel, isolateChannel]);
```

* Then you create the `Channel Functions` that you will work with.
A ChannelFunction is basically a regular function(with arguments and return type you define) that you want to be able to call it from any `channel` and execute it in any other `channel`.
But its arguments and return types should be registered. Here is a channel function:

```dart
// here we add the function configration.
final allAvailableChannelFunctions = <ChannelFunctionConfig>[
  PrintIsolateHashCode.config,
];

/// This function shows you that [callFunWithArgs] is executed in [isolateChannel].
/// 
/// It also returns the [hashCode] of [isolateChannel].
class PrintIsolateHashCode extends ChannelFunction<int>{
  @override
  late final List<Prop> args = [];

  PrintIsolateHashCode() : super.to(
    toChannel: isolateChannel,
  );

  @override
  TypeAsync<int> callFunWithArgs() async => Isolate.current.hashCode;

  //*////////////////////////// DO NOT MODIFY THIS SECTION BY HAND //////////////////////////*//

  @override
  ChannelFunctionConfig getConfig() => config;
  static final config = ChannelFunctionConfig<PrintIsolateHashCode>(
    templateFunction: PrintIsolateHashCode._temp,
    fromMarkup: PrintIsolateHashCode.fromJson,
  );
  PrintIsolateHashCode._temp() : super.temp();
  PrintIsolateHashCode.fromJson(Map<String, dynamic> json) : super.fromJson(json);
}
```

* Note: Creating new `Channel Function` might seem complicated, but I provide you with snippets(in `/example/snippets`) you can configure in `VS Code` or `Android Studio`, these will help you create them faster.



* Finnaly, we register our `Channel Functions` and `Props`, then we can start using our `Channel Functions` execute them and check and use their results:

```dart
Future<void> initChannelCommunications(ChannelType channel) async {
  /// Configure registered-types that can be sent throw a channel.
  /// This is commented in details in the example of `easy_serialization` Package.
  Prop.registerSerializationConfigs(customSerializableObjects);

  // Configure channel functions in use.
  ChannelFunction.register(allAvailableChannelFunctions);

  // Register this channel and initialize it.
  await ThisChannel().init(
    channelType: channel,
    definitions: channelsDefinitions,
  );
}


void main() async {
  print("Main hashcode ${Isolate.current.hashCode}");

  // call at FIRST.
  await initChannelCommunications(mainChannel);

  await Isolate.spawn(isolateMain, "");

  // This waits until the isolate channel is created.
  await isolateChannel.waitUntilStart();

  /// Any [ChannelFunction] return and [ChannelResult]
  /// that contains the data of the type of error(if some error occurs).
  final isolateHashCodeRes = await PrintIsolateHashCode().raise();
  print("The isolate hashcode is ${isolateHashCodeRes.correctData}");

  await Future.delayed(const Duration(seconds: 2));

  // Here we deAttach the channel when we finish.
  await ThisChannel().deAttach();
}

void isolateMain(String str) async {
  print("isolate hashcode ${Isolate.current.hashCode}");

  // call at FIRST.
  await initChannelCommunications(isolateChannel);

  await Future.delayed(const Duration(seconds: 2));

  // Here we deAttach the channel when we finish.
  await ThisChannel().deAttach();
}
```


## Utils

* There are some utility functions that you can use.


* 1- you can `broadcast` a channel function to all channels.

```dart
await PrintIsolateHashCode().broadcast();
```


## Additional information

* For a more detailed example you can see `/example/main.dart`.
