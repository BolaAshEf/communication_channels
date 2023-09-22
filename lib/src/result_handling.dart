part of 'channels_flow.dart';

final neverFuture = Future.any([]);

/// possible results when calling a message.
enum ChannelResultType {
  done,
  exception,
  channelNotRegistered,
  channelRegisteredButNoResponse,
  connectionLost,

  /// means the message takes long time.
  longResponseTime,
  ;
}

/// the result object the will be returned of message.
class ChannelResult<T extends Object?> {
  static const _emptyError = (
    err: "",
    stacktrace: "",
  );
  static const _noResponseTimeoutDuration = Duration(
    seconds: 2,
  );

  /// Currently we do NOT support waiting time, because if the callback then returns.
  /// its consequences must be {ROLLED UP}!
  static Future<void> _getLongResponseFuture() => neverFuture;

  final ResultErrorType? error;
  final ChannelType responseFromChannel;
  final ChannelResultType type;
  final T? _data;

  const ChannelResult._done(this.responseFromChannel, T this._data)
      : type = ChannelResultType.done,
        error = null;
  ChannelResult._exception(this.responseFromChannel,
      [ResultErrorType this.error = _emptyError])
      : _data = null,
        type = ChannelResultType.exception;
  const ChannelResult._connectionLost(this.responseFromChannel)
      : _data = null,
        type = ChannelResultType.connectionLost,
        error = null;
  const ChannelResult._longResponseTime(this.responseFromChannel)
      : _data = null,
        type = ChannelResultType.longResponseTime,
        error = null;
  const ChannelResult._channelNotRegistered(this.responseFromChannel)
      : _data = null,
        type = ChannelResultType.channelNotRegistered,
        error = null;
  const ChannelResult._channelRegisteredButNoResponse(this.responseFromChannel)
      : _data = null,
        error = null,
        type = ChannelResultType.channelRegisteredButNoResponse;

  /// whether [type] = [ChannelResultType.done] or not.
  bool get hasData => type == ChannelResultType.done;

  /// In case of [type] = [ChannelResultType.done], we return the date.
  T get correctData {
    switch (type) {
      case ChannelResultType.done:
        // do nothing and pass the value.
        break;
      case ChannelResultType.exception:
        throw ChannelExceptionResult(error!);
      case ChannelResultType.channelNotRegistered:
      case ChannelResultType.channelRegisteredButNoResponse:
      case ChannelResultType.connectionLost:
      case ChannelResultType.longResponseTime:
        throw ChannelWrongResult(type);
    }

    return _data as T;
  }
}
