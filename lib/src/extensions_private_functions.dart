part of 'channels_flow.dart';

Future<void> _notify(ChannelType channel, ChannelEvent event) => _RaiseChannelNotification(
  notification: ChannelNotification(
    about: channel,
    event: event,
  ),
).broadcast();

Future<void> _notifyClosed(ChannelType channel) => _notify(channel, ChannelEvent.closed);
Future<void> _notifyStarted(ChannelType channel) => _notify(channel, ChannelEvent.started);

({Future<bool> res, Future<void> Function() cancel}) _waitFor({
  required ChannelType channelType,
  ChannelEvent event = ChannelEvent.started,
  Duration? timeout,
}) {
  final completer = Completer<void>();
  final sup = ThisChannel()._notificationsStream?.listen((notification) {
    if(notification.about == channelType && notification.event == event){
      if(!completer.isCompleted) {completer.complete();}
    }
  });

  if(sup == null){
    return (res: Future.value(false), cancel: () async {});
  }

  Future<void> cancelMe() async {
    await sup.cancel();
    if(!completer.isCompleted) {completer.complete();}
  }

  final ret = Future.any([
    Future(() async {await completer.future; return true;}),
    if(timeout != null) Future.delayed(timeout, () => false,),
  ]).then((value) async {await cancelMe(); return value;});

  return (res: ret, cancel: cancelMe,);
}

extension RaiseChannelFunctionExtension<Ret extends TypeSync> on ChannelFunction<Ret> {
  /// exec this function with this channel
  ChannelResultGenType<Ret> raise() async {
    return await ThisChannel()._raiseMessage<Ret>(this);
  }

  Stream<ChannelResult<Ret>> broadcastStream() async* {
    for(final channel in ChannelType._activeChannels){
      if(channel == ThisChannel()._myChannelType){continue;}

      _toChannel = channel;

      yield (await raise());
    }
  }

  Future<ChannelResult<Ret>> broadcast() => broadcastStream().last;
}

extension ChannelTypeExtension on ChannelType {
  Future<bool> waitUntilStart([Duration? timeout, bool pingFirst = true]) async {
    if(this == ThisChannel()._myChannelType){return true;}

    final result = _waitFor(
      channelType: this,
      event: ChannelEvent.started,
      timeout: timeout,
    );

    if(pingFirst){
      final channelRes = await _RaisePing.to(this).raise();
      if(channelRes.hasData){
        await result.cancel();
        return true;
      }
    }

    return await result.res;
  }

  Future<bool> ping() async {
    if(this == ThisChannel()._myChannelType){return true;}

    final channelRes = await _RaisePing.to(this).raise();
    return channelRes.hasData;
  }
}

class _RaisePing extends ChannelFunction{
  @override
  late final List<Prop> args = [];

  _RaisePing.to(ChannelType toChannel) : super.to(
    toChannel: toChannel,
  );

  @override
  TypeAsync callFunWithArgs() async => null;

  //*////////////////////////// DO NOT MODIFY THIS SECTION BY HAND //////////////////////////*//

  @override
  ChannelFunctionConfig getConfig() => config;
  static final config = ChannelFunctionConfig<_RaisePing>(
    templateFunction: _RaisePing._temp,
    fromMarkup: _RaisePing.fromJson,
  );
  _RaisePing._temp() : super.temp();
  _RaisePing.fromJson(Map<String, dynamic> json) : super.fromJson(json);
}

const _notificationPropMarkupPropName = "\$_notification";
class _RaiseChannelNotification extends ChannelFunction{
  late final ChannelNotification _notification;

  @override
  late final List<Prop> args = [];

  _RaiseChannelNotification({
    required ChannelNotification notification,
  }) : super.to(
    toChannel: ChannelType._dummyChannel,
  ){
    _notification = notification;
  }

  @override
  TypeAsync callFunWithArgs() async {
    if(_notification.about == ThisChannel()._myChannelType){return null;}

    ThisChannel()._notificationsStreamController?.add(_notification);
    return null;
  }

  //*////////////////////////// DO NOT MODIFY THIS SECTION BY HAND //////////////////////////*//

  @override
  ChannelFunctionConfig getConfig() => config;
  static final config = ChannelFunctionConfig<_RaiseChannelNotification>(
    templateFunction: _RaiseChannelNotification._temp,
    fromMarkup: _RaiseChannelNotification.fromJson,
  );
  _RaiseChannelNotification._temp() : super.temp();
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    _notificationPropMarkupPropName : _notification.toJson(),
  };
  _RaiseChannelNotification.fromJson(Map<String, dynamic> json) : _notification = ChannelNotification.fromJson(json[_notificationPropMarkupPropName]),
        super.fromJson(json);
}
