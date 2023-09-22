part of 'channels_flow.dart';

class ChannelError<OBJ extends Object> implements Exception {
  final OBJ errorObj;
  const ChannelError(this.errorObj);

  @override
  String toString() => errorObj.toString();
}

class ChannelWrongResult extends ChannelError<ChannelResultType>{
  const ChannelWrongResult(super.errorObj);
}

class ChannelExceptionResult extends ChannelError<ResultErrorType>{
  const ChannelExceptionResult(super.errorObj);
}
