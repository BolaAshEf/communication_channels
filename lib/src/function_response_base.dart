part of 'channels_flow.dart';

final Map<TypeID, ChannelFunctionConfig> _privateChannelFunctions = {
  _RaisePing.config.typeID : _RaisePing.config,
  _RaiseChannelNotification.config.typeID : _RaiseChannelNotification.config,
};

final Map<TypeID, ChannelFunctionConfig> _registeredChannelFunctions = {};


const _channelFunctionTypeIDPropMarkupPropName = "\$type#id";

/// Base class for all channel functions
///
/// The ability of just adding params(primitive types) within the [args]
///  and [to and from json] will be done automatically for these params.
abstract class ChannelFunction<Ret extends TypeSync> extends ChannelMessage{
  ChannelFunction.to({
    required super.toChannel,
  }) : super._(
    msgType: ChannelMessageType.funMessage,
  );

  ChannelFunction.temp() : super._(
    toChannel: ChannelType._dummyChannel,
    msgType: ChannelMessageType.funMessage,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    _channelFunctionTypeIDPropMarkupPropName : getConfig().typeID.toMarkupObj(),
    ..._fieldsToJson(args),
  };

  ChannelFunction.fromJson(Map<String, dynamic> json)
      : super._fromJson(json){
    _fieldsFromJson(args, json);
  }

  TypeAsync<Ret> callFunWithArgs();

  /// here put all props you have defined.
  abstract final List<Prop> args;

  /// pass [EnumSerializationConfig] if the return type contains some unregistered [Enum] type.
  final EnumSerializationConfig? enumConfig = null;

  /// An empty list is required if the return type is a list.
  final Ret? emptyListFallback = null;

  ChannelFunctionConfig getConfig();

  static ChannelFunction _decodeFromJson(Map<String, dynamic> json){
    final funTypeID = TypeID.fromMarkup(json[_channelFunctionTypeIDPropMarkupPropName]);
    final privateFunctionConfig = _privateChannelFunctions[funTypeID];
    if(privateFunctionConfig != null){
      return privateFunctionConfig._fromMarkup(json);
    }

    final functionConfig = _registeredChannelFunctions[funTypeID]!;
    return functionConfig._fromMarkup(json);
  }

  static void register(List<ChannelFunctionConfig> configs, [bool clearFirst = false]){
    if(clearFirst){_registeredChannelFunctions.clear();}

    _registeredChannelFunctions.addAll({
      for(final config in configs) config.typeID : config,
    });
  }
}

/// Base function response.
class _ChannelFunctionRespond<Ret extends TypeSync> extends ChannelMessage{
  late final Prop<Ret> _ret;

  Ret get ret => _ret.data;

  _ChannelFunctionRespond({
    required Ret ret,
    required ChannelFunction callerFunction,
  }) : super._create(
    msgCode: callerFunction.msgCode,
    toChannel: callerFunction.callerChannel,
    msgType: ChannelMessageType.funRespondMessage,
  ){
    _setProp(callerFunction);

    _ret.data = ret;
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    ..._fieldsToJson([_ret]),
  };

  _ChannelFunctionRespond.fromJson(Map<String, dynamic> json, ChannelFunction callerFunction,)
      : super._fromJson(json){
    _setProp(callerFunction);

    _fieldsFromJson([_ret], json);
  }

  void _setProp(ChannelFunction callerFunction) => _ret = Prop<Ret>.all(
    debugName: "_ret",
    enumConfig: callerFunction.enumConfig,
    emptyList: callerFunction.emptyListFallback as Ret?,
  );
}


const _propsGroupMarkupPropName = "\$all#props";

Map<String, List<MarkupObj>> _fieldsToJson(List<Prop> fields) =>
    {_propsGroupMarkupPropName : fields.map((e) => e.toMarkup(),).toList(),};

void _fieldsFromJson(List<Prop> fields, MarkupObj markup){
  final fieldsMarkup = List<MarkupObj>.from(markup[_propsGroupMarkupPropName]);
  for(int i = 0; i < fields.length; i++){
    fields[i].fromMarkup(fieldsMarkup[i],);
  }
}

//*//////////////////////////////////////////// Configration ///////////////////////////////////

class ChannelFunctionConfig<FUN extends ChannelFunction> with TypeHash<FUN>{
  FUN? _template;

  final FUN Function() _templateFunction;
  final FUN Function(MarkupObj markup) _fromMarkup;

  ChannelFunctionConfig({
    required FUN Function() templateFunction,
    required FUN Function(Map<String, dynamic>) fromMarkup,
  }) : _fromMarkup = fromMarkup, _templateFunction = templateFunction{
    ensureCalcTypeID();
  }

  FUN get _singleton => _template ?? (_template = _templateFunction());
}