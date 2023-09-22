part of 'channels_flow.dart';


abstract class ProviderSender with EquatableMixin{
  const ProviderSender();
  Future<bool> send(SentChannelMessageType msg);
}
abstract class ComProvider<S extends ProviderSender> with EquatableMixin{
  abstract final S sender;

  /// The main receiver stream that receives valid channel messages that are sent to us.
  Stream<ChannelMessage>? _receiver;

  /// [_receiver]`s stream subscription.
  StreamSubscription? _receiverSub;

  ChannelType? _forChannel;

  void _setChannel(ChannelType channel) => _forChannel = channel;

  Future<bool> send(ChannelMessage msg) async {
    if(msg.toChannel._provider.runtimeType != runtimeType){return false;}

    return msg.toChannel._provider.sender.send(msg.toJson());
  }

  /// The main flow to decode received messages.
  Future<void> setStreamSup(void Function(ChannelMessage) onMsg) async {
    await close();

    _receiver = await _getValidChannelMessagesStream();
    _receiverSub = _receiver!.listen(onMsg);
  }

  Future<Stream<SentChannelMessageType>> getReceiverBroadcastStream();

  Future<Stream<ChannelMessage>> _getValidChannelMessagesStream() async {
    return (await getReceiverBroadcastStream()).takeWhile((msg){
      late final ChannelType? toChannel;
      toChannel = ChannelMessage._getToChannel(msg);
      if(toChannel != _forChannel){
        return false;
      }

      return true;
    }).map((msg){
      try{
        final channelMessage = _decodeChannelMessageFromJson(json: msg);
        if(channelMessage == null){return null;}
        return channelMessage;
      }catch(ex){
        return null;
        // TODO
        //throw const ChannelError(r"Unable to decode this message, "
        //r"please make sure not to interfere with the decoding process from outside.");
      }
    }).takeWhile((channelMessage) => channelMessage != null,).cast<ChannelMessage>();
  }

  Future<void> close() async {
    await _receiverSub?.cancel();
    await closeStreamObj();

    _receiverSub = null;
    _receiver = null;
  }

  Future<void> closeStreamObj();


  @override
  List<Object?> get props => [sender];
}

class _DummySender extends ProviderSender{
  const _DummySender();

  @override
  Future<bool> send(SentChannelMessageType msg) => Future.value(false);

  @override
  List<Object?> get props => [];
}
class _DummyComProvider extends ComProvider<_DummySender>{
  @override
  final sender = const _DummySender();

  _DummyComProvider();

  @override
  Future<Stream<SentChannelMessageType>> getReceiverBroadcastStream() async => 
    const Stream.empty();

  @override
  Future<void> closeStreamObj() async {}
}

class SocketSender extends ProviderSender{
  static const _timeout = Duration(milliseconds: 500);

  final dynamic host;
  final int port;
  final Encoding encoding;

  const SocketSender(this.host, this.port, [this.encoding = utf8]) : assert(
    (host is String || host is InternetAddress) && port > 0,
  );

  @override
  Future<bool> send(SentChannelMessageType msg) async {
    try{
      final channelSocketTask = await Socket.startConnect(host, port);
      final res = await Future.any([
        Future(() async {
          try{
            return await channelSocketTask.socket;
          }catch(ex){
            return null;
          }
        }),
        Future.delayed(_timeout, () => null,),
      ]);
      if(res == null){
        channelSocketTask.cancel();
        return false;
      }

      final channelSocket = res;
      channelSocket.encoding = encoding;
      channelSocket.write(jsonEncode(msg));
      await channelSocket.close();
      return true;
    }catch(ex){
      return false;
    }
  }

  @override
  List<Object?> get props => [host, port,];
}
class SocketComProvider extends ComProvider<SocketSender>{
  static const bool shared = false;

  dynamic get host => sender.host;
  int get port => sender.port;
  Encoding get encoding => sender.encoding;

  @override
  final SocketSender sender;

  ServerSocket? _server;
  StreamController<SentChannelMessageType>? _controller;

  SocketComProvider({
    required dynamic host,
    required int port,
    Encoding encoding = utf8
  }) : sender = SocketSender(host, port, encoding);

  @override
  Future<Stream<SentChannelMessageType>> getReceiverBroadcastStream() async {
    _server = await ServerSocket.bind(
      host, port,
      shared: shared,
    );

    _controller = StreamController.broadcast();
    _server!.listen((client) {
      client.listen((Uint8List data) async {
        final strMsg = encoding.decode(data);

        try{
          final msgObj = jsonDecode(strMsg);
          if(msgObj is SentChannelMessageType){
            _controller?.add(msgObj);
          }
        }catch(ex){
          // do NOT add it to stream.
        }
      });
    });


    return _controller!.stream;
  }

  @override
  Future<void> closeStreamObj() async {
    await _server?.close();
    await _controller?.close();

    _server = null;
    _controller = null;
  }
}
