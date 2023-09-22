import 'dart:async';
import 'dart:isolate';
import 'package:easy_serialization/easy_serialization.dart';
import 'package:equatable/equatable.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

part 'messages.dart';
part 'function_response_base.dart';
part 'result_handling.dart';
part 'channel_exceptions.dart';
part 'extensions_private_functions.dart';
part 'communication_provider.dart';


// TODO : add support to passing the receive port directly and us it.
// TODO : add support to disable the serializable configurations and send objects directly(in case of same code isolate).

typedef ChannelResultGenType<T extends Object?> = Future<ChannelResult<T>>;
typedef TypeAsync<T extends Object?> = Future<T>;
typedef TypeSync = Object?;

typedef SentChannelMessageType = Map<String, dynamic>;
typedef ResultErrorType = ({String err, String stacktrace,});



class ChannelType with EquatableMixin{
  static final _dummyChannel = ChannelType._(
    debugName: "DUMMY",
    code: -404,
  );

  final String? debugName;
  final int code;
  ComProvider _provider = _DummyComProvider();


  ChannelType({
    required this.code,
    required ComProvider provider,
    this.debugName,
  }): assert(code > -1){
    _setProvider(provider);
  }

  ChannelType._({
    required this.code,
    this.debugName,
  });

  void _setProvider(ComProvider provider) =>
      _provider = provider.._setChannel(this);


  static final _activeChannels = <ChannelType>[];

  static ChannelType fromCode(int code){
    if(code == _dummyChannel.code){ return _dummyChannel; }

    for(final activeChannel in _activeChannels){
      if(activeChannel.code == code){return activeChannel;}
    }

    throw const ChannelError("Same channels definitions MUST be provided to all channels!");
  }

  @override
  String toString() => debugName ?? super.toString();

  @override
  List<Object?> get props => [code];
}

class ChannelsDefinitions with EquatableMixin{
  static const _dummy = ChannelsDefinitions._empty();

  final List<ChannelType> _channelsDefinitions;
  ChannelsDefinitions(List<ChannelType> channels) :
        assert(channels.length > 1),
        assert(_assertion(channels)),
        _channelsDefinitions = [...channels];

  const ChannelsDefinitions._empty() : _channelsDefinitions = const [];

  static bool _assertion(List<ChannelType> channels){
    final providerType = channels.first._provider.runtimeType;
    for(final channel in channels){
      if(channel._provider.runtimeType != providerType){
        throw const ChannelError("Please provide the same provider runtime type across all channels.");
      }
    }

    final providers = {for(final channel in channels) channel._provider};
    if(providers.length != channels.length){
      throw const ChannelError("Do NOT pass the same provider to multiple channels.");
    }

    final channelsSet = {...channels};
    if(channelsSet.length != channels.length){
      throw const ChannelError("A Channel Code must be unique.");
    }

    return true;
  }

  @override
  List<Object?> get props => [..._channelsDefinitions];
}


//*////////////////////////////////// Channel Handler ///////////////////////////////////////
enum ChannelEvent{
  started,
  closed,
  ;
}


const _propAboutChannelCodeMarkupName = "\$about#channel#code";
const _propChannelEventIMarkupName = "\$event#i";

class ChannelNotification{
  final ChannelType about;
  final ChannelEvent event;
  const ChannelNotification({
    required this.about,
    required this.event,
  });

  Map<String, dynamic> toJson() => {
    _propAboutChannelCodeMarkupName : about.code,
    _propChannelEventIMarkupName : event.index,
  };

  ChannelNotification.fromJson(MarkupObj markup):
        about = ChannelType.fromCode(markup[_propAboutChannelCodeMarkupName]),
        event = ChannelEvent.values[markup[_propChannelEventIMarkupName] as int];
}

/// Store a completer to wait for channel functions responses, also
/// when the response is sent back again to us with the same code
/// we can then identify its return type using its caster.
class _ResponsesFuture<Ret extends TypeSync> with TypeProvider<Ret>{
  final Completer<Ret> completer;

  final Completer<void> arrived;

  final Completer<ResultErrorType> error;

  final ChannelMessage callerMsg;
  _ResponsesFuture({
    required this.completer,
    required this.callerMsg,
  }) : arrived = Completer(), error = Completer();
}

/// The base interface for channels communication flow.
abstract class _BaseAppChannels{
  bool _initialized = false;
  bool get isInitialized => _initialized;

  int _lastSentMsgCode = -1;

  final _responsesMap = <int, _ResponsesFuture>{};

  StreamController<ChannelNotification>? _notificationsStreamController;
  Stream<ChannelNotification>? get _notificationsStream => _notificationsStreamController?.stream;


  ChannelType _myChannelType = ChannelType._dummyChannel;
  ChannelType? get channelType => _initialized ? _myChannelType : null;

  _BaseAppChannels._();

  Future<void> init({
    required ChannelsDefinitions definitions,
    required ChannelType channelType,
    // bool overridable = true, // TODO
  });

  /// Raise any Channel Message from any channel.
  ChannelResultGenType<Ret> _raiseMessage<Ret extends TypeSync>(ChannelMessage channelMessage);

  /// Get new message identifier to send the message through channels
  int _generateNewMsgCode() => ++_lastSentMsgCode;

  Future<void> deAttach();

  /// Start doing message in its dest Channel
  Future<bool> doChannelMessage(ChannelMessage channelMessage);

  /// Do message in the same channel if its dest channel is the executed-from-channel.
  TypeAsync<Ret> doChannelMessageHere<Ret extends TypeSync>(ChannelMessage channelMessage);
}

mixin _ChannelsHandlerMixin on _BaseAppChannels{
  ChannelsDefinitions _definitions = ChannelsDefinitions._dummy;

  void Function()? _closingDummyCallback;

  void _setupDefinitions(ChannelsDefinitions definitions){
    _definitions = definitions;
    ChannelType._activeChannels.clear();
    ChannelType._activeChannels.addAll(_definitions._channelsDefinitions);
  }

  ComProvider get _comProvider => _myChannelType._provider;

  @override
  Future<void> init({
    required ChannelsDefinitions definitions,
    required ChannelType channelType,
  }) async {
    if(_initialized) {return;}

    assert(definitions._channelsDefinitions.contains(channelType));

    _setupDefinitions(definitions);

    // TODO : check if already assigned or not (if yes then decide to override it or not).

    // config
    _myChannelType = channelType;

    try{
      await channelType._provider.setStreamSup(doChannelMessage);
    }catch(ex){
      await channelType._provider.close();
      _myChannelType = ChannelType._dummyChannel;
      _definitions = ChannelsDefinitions._dummy;
      ChannelType._activeChannels.clear();

      throw const ChannelError("Cannot use this provider with its current parameters.");
    }

    // notify closed.
    _closingDummyCallback = await _setupDummyChannelToNotifyClosed();

    _notificationsStreamController = StreamController.broadcast();

    _initialized = true;

    await _notifyStarted(channelType);
  }

  //******************************** RECEIVE ***************************//

  @override
  Future<bool> doChannelMessage(ChannelMessage channelMessage) async {
    switch(channelMessage.msgType){
        /// handled in SRC Channel.
      case ChannelMessageType.msgArrived:
        final storedResHandler = _responsesMap[channelMessage.msgCode];
        storedResHandler?.arrived.complete();
        return true;
      case ChannelMessageType.msgError:
        final channelMessageError = channelMessage as _ChannelMessageError;
        final storedResHandler = _responsesMap[channelMessage.msgCode];
        storedResHandler?.error.complete((
          err: channelMessageError.errString,
            stacktrace: channelMessageError.stacktraceString,
        ));
        return true;
      case ChannelMessageType.funRespondMessage:
        final storedResHandler = _responsesMap[channelMessage.msgCode];
        storedResHandler?.provType(<OUT>(){
          final castedStoredResHandler = storedResHandler as _ResponsesFuture<OUT>;

          // notify that the response has came(for checking channel response).
          final channelFunctionRespond = channelMessage as _ChannelFunctionRespond<OUT>;
          castedStoredResHandler.completer.complete(channelFunctionRespond.ret);
        });
        return true;

        /// handled in DEST Channel.
      case ChannelMessageType.funMessage:
        final channelFunction = channelMessage as ChannelFunction;

        // the logic of sending the response of this function back to the caller channel.
        // send arrival notification.
        final arrival= _ChannelMessageArrived(
          msgCode: channelFunction.msgCode,
          toChannel: channelFunction.callerChannel,
        );
        final sent = _comProvider.send(arrival);

        // exec the actual functionality or spot exception
        try{
          final res = await channelFunction.callFunWithArgs();
          if(!(await sent)){return true;}

          // to json does NOT need static typing
          final respond = _ChannelFunctionRespond(
            ret: res,
            callerFunction: channelFunction,
          );
          await _comProvider.send(respond);
          return true;
        }catch(err, st){
          if(!(await sent)){return true;}

          final error = _ChannelMessageError(
            msgCode: channelFunction.msgCode,
            toChannel: channelFunction.callerChannel,
            errString: err.toString(),
            stacktraceString: st.toString(),
          );
          await _comProvider.send(error);
          return false;
        }
    }
  }
  //***********************************************************//

  //******************************** SEND ***************************//
  @override
  TypeAsync<Ret> doChannelMessageHere<Ret extends TypeSync>(ChannelMessage channelMessage) async {
    switch(channelMessage.msgType){
      case ChannelMessageType.msgError:
      case ChannelMessageType.msgArrived:
      case ChannelMessageType.funRespondMessage:
        throw const ChannelError("This message is a private API please do NOT use from outside.");
      case ChannelMessageType.funMessage:
        final channelFunction = channelMessage as ChannelFunction<Ret>;
        return channelFunction.callFunWithArgs();
    }
  }

  /// checks [ChannelResultType.exception] and [ChannelResultType.longResponseTime].
  ChannelResultGenType<Ret> _handleHereLongResponseTimeAndExceptions<Ret extends TypeSync>(ChannelMessage channelMessage) async {
    final toChannel = channelMessage._toChannel;
    final callback = doChannelMessageHere<Ret>(channelMessage);
    return await Future.any([
      Future(() async => ChannelResult<Ret>._done(toChannel, await callback),),
      Future(() async {
        await ChannelResult._getLongResponseFuture();
        return ChannelResult<Ret>._longResponseTime(toChannel);
      }),
    ]);
  }

  @override
  ChannelResultGenType<Ret> _raiseMessage<Ret extends TypeSync>(ChannelMessage channelMessage) async {
    final toChannel = channelMessage._toChannel;

    // get new message identifier and set it on channelMessage
    final msgCode = _generateNewMsgCode();
    channelMessage._assignMsgCode(msgCode);
    if(channelMessage._toChannel == _myChannelType){
      // exec here already in dest channel
      return await _handleHereLongResponseTimeAndExceptions<Ret>(channelMessage);
    }

    if(!_initialized){
      throw const ChannelError("Initialize the channel first.");
    }

    // Store a completer to wait for channel functions responses
    //  also when the response is sent back again to us with the same message code
    //  we can then identify its return type using its caster
    final response = _ResponsesFuture(
      completer: Completer<Ret?>(),
      callerMsg: channelMessage,
    );
    _responsesMap.putIfAbsent(msgCode, () => response,);

    // send the message through toChannel port.
    //  if failed then the channel is NOT registered.
    final sent = await _comProvider.send(channelMessage);
    if(!sent){
      _responsesMap.remove(msgCode);
      return ChannelResult._channelNotRegistered(toChannel);
    }

    // handling arrived or no response timeout
    final isArrived = await Future.any([
      Future(() async {await response.arrived.future; return true;}),
      Future.delayed(ChannelResult._noResponseTimeoutDuration, () => false,),
    ]);
    if(!isArrived){return ChannelResult<Ret>._channelRegisteredButNoResponse(toChannel);}

    // handle msg completed, error or long response time.
    final connectionLostResult = _waitFor(
      channelType: channelMessage._toChannel,
      event: ChannelEvent.closed,
    );
    final ret = await Future.any([
      Future(() async => ChannelResult<Ret>._done(toChannel, (await response.completer.future) as Ret)),
      Future(() async {
        final error = await response.error.future;
        return ChannelResult<Ret>._exception(toChannel, error);
      }),
      Future(() async {
        await ChannelResult._getLongResponseFuture();
        return ChannelResult<Ret>._longResponseTime(toChannel);
      }),
      Future(() async {
        await connectionLostResult.res;
        return ChannelResult<Ret>._connectionLost(toChannel);
      }),
    ]);
    await connectionLostResult.cancel();

    _responsesMap.remove(msgCode);
    return ret;
  }
  //***********************************************************//

  @override
  Future<void> deAttach() async {
    if(_initialized){
      _closingDummyCallback?.call();
      await _notifyClosed(_myChannelType);
      await _comProvider.close();

      _initialized = false;
      _lastSentMsgCode = -1;
      _responsesMap.clear();
      
      await _notificationsStreamController?.close();
      _notificationsStreamController = null;
    }
  }
}

class ThisChannel extends _BaseAppChannels with _ChannelsHandlerMixin{
  static final ThisChannel _instance = ThisChannel._();
  ThisChannel._() : super._();
  factory ThisChannel() => _instance;
}



ChannelMessage? _decodeChannelMessageFromJson({
  required Map<String, dynamic> json,
}) {
  final channelMessage = ChannelMessage._fromJson(json);

  switch(channelMessage.msgType){
    case ChannelMessageType.funMessage:
      return ChannelFunction._decodeFromJson(json);
    case ChannelMessageType.funRespondMessage:
      final responseHandler = ThisChannel()._responsesMap[channelMessage.msgCode];
      if(responseHandler != null){
        // if it have an assigned caster exec it
        late final _ChannelFunctionRespond channelFunctionRespond;
        final channelFunction = responseHandler.callerMsg as ChannelFunction;
        responseHandler.provType(<OUT>(){
          channelFunctionRespond = _ChannelFunctionRespond<OUT>.fromJson(
            json,
            channelFunction,
          );
        });

        return channelFunctionRespond;
      }

      // if it have NO assigned caster discard it and return null
      // because [funRespondMessage] must have caster.

      return null;
    case ChannelMessageType.msgArrived:
      return _ChannelMessageArrived.fromJson(json);
    case ChannelMessageType.msgError:
      return _ChannelMessageError.fromJson(json);
  }
}


/// returns a callback that is used to dispose the isolate.
Future<void Function()> _setupDummyChannelToNotifyClosed() async {
  final aboutChannel = ThisChannel()._myChannelType;
  final senders = <ProviderSender, SentChannelMessageType>{};
  for(final channel in ChannelType._activeChannels){
    if(channel != ThisChannel()._myChannelType){
      final msg = _RaiseChannelNotification(
        notification: ChannelNotification(
          about: aboutChannel,
          event: ChannelEvent.closed,
        ),
      ).._toChannel = channel;

      senders.addAll({channel._provider.sender : msg.toJson(),});
    }
  }

  final waitRec = ReceivePort();

  final dummyIsolate = await Isolate.spawn((obj) async {
    final waitSendPort = obj.$1;
    final senders = obj.$2;

    final myRec = ReceivePort();
    waitSendPort.send(myRec.sendPort);
    await myRec.first;

    for(final sender in senders.keys){
      final msg = senders[sender]!;
      await sender.send(msg);
    }

    Isolate.current.kill();
  }, (waitRec.sendPort, senders));

  final dummyIsolateSendPort = (await waitRec.first) as SendPort;
  final callerIsolate = Isolate.current;
  callerIsolate.addOnExitListener(dummyIsolateSendPort, response: 0);

  void deAttachDummy(){
    callerIsolate.removeOnExitListener(dummyIsolateSendPort);
    dummyIsolate.kill();
  }

  return deAttachDummy;
}
