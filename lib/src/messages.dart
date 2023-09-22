part of 'channels_flow.dart';

/// The type of Message
enum ChannelMessageType {
  /// the response of a function
  funRespondMessage(0),

  /// function message
  funMessage(1),

  /// annotate message arrival
  msgArrived(2),

  /// error message
  msgError(3),
  ;

  const ChannelMessageType(this.code);
  final int code;
}

const _propMsgCodeMarkupName = "\$msg#code";
const _propCallerChannelMarkupName = "\$caller#channel";
const _propToChannelMarkupName = "\$to#channel";
const _propMsgTypeMarkupName = "\$msg#type";

/// The base Class for Messages that are sent through Channels
class ChannelMessage {
  /// The message identifier through all channels.
  ///
  /// this can be changed to allow to send the same message multiple times.
  int msgCode = -1;

  final ChannelMessageType msgType;
  final ChannelType callerChannel;
  ChannelType _toChannel;
  ChannelType get toChannel => _toChannel;

  ChannelMessage._({
    required this.msgType,
    required ChannelType toChannel,
  })  : _toChannel = toChannel,
        callerChannel = ThisChannel()
            ._myChannelType; // set the callerChannel field as the type of caller Channel

  ChannelMessage._create({
    required this.msgCode,
    required this.msgType,
    required ChannelType toChannel,
  })  : _toChannel = toChannel,
        callerChannel = ThisChannel()
            ._myChannelType; // set the callerChannel field as the type of caller Channel

  Map<String, dynamic> toJson() => {
        _propMsgCodeMarkupName: msgCode,
        _propCallerChannelMarkupName: callerChannel.code,
        _propToChannelMarkupName: _toChannel.code,
        _propMsgTypeMarkupName: msgType.code,
      };

  static ChannelType? _getToChannel(Map<String, dynamic> json) {
    final toChannelCode = json[_propToChannelMarkupName];
    if (toChannelCode is! int) {
      return null;
    }
    return ChannelType.fromCode(toChannelCode);
  }

  ChannelMessage._fromJson(Map<String, dynamic> json)
      : msgCode = json[_propMsgCodeMarkupName] as int,
        callerChannel =
            ChannelType.fromCode(json[_propCallerChannelMarkupName] as int),
        _toChannel = ChannelType.fromCode(json[_propToChannelMarkupName]),
        msgType = ChannelMessageType.values
            .firstWhere((e) => e.code == json[_propMsgTypeMarkupName] as int);

  void _assignMsgCode(int code) => msgCode = code;
}

/// message indicates that the message has arrived.
class _ChannelMessageArrived extends ChannelMessage {
  _ChannelMessageArrived({
    required super.msgCode,
    required super.toChannel,
  }) : super._create(
          msgType: ChannelMessageType.msgArrived,
        );

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
      };

  _ChannelMessageArrived.fromJson(Map<String, dynamic> json)
      : super._fromJson(json);
}

const _propErrorStringMarkupName = "\$err#string";
const _propStacktraceStringMarkupName = "\$stacktrace#string";

/// message indicates that the message has arrived.
class _ChannelMessageError extends ChannelMessage {
  final String errString;
  final String stacktraceString;

  _ChannelMessageError({
    required super.msgCode,
    required super.toChannel,
    required this.errString,
    required this.stacktraceString,
  }) : super._create(
          msgType: ChannelMessageType.msgError,
        );

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        _propErrorStringMarkupName: errString,
        _propStacktraceStringMarkupName: stacktraceString,
      };

  _ChannelMessageError.fromJson(Map<String, dynamic> json)
      : errString = json[_propErrorStringMarkupName],
        stacktraceString = json[_propStacktraceStringMarkupName],
        super._fromJson(json);
}
