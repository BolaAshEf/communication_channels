import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:communication_channels/communication_channels.dart';
import 'dart:isolate';

import 'package:easy_serialization/easy_serialization.dart';


// Define the channels you will work with, and use the type of provider
// you want to send the data with.
// Here we use Sockets.

// * The channel code MUST be unique.
// * All channels MUST use the SAME TYPE OF PROVIDER.
//    BUT they must provide unique parameters to it.

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

final allAvailableChannelFunctions = <ChannelFunctionConfig>[
  PrintIsolateHashCode.config,
  CircleTheShapes.config,
];



/// This is commented in details in the example of `easy_serialization` Package.
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

/// Try to call the function that in it you register [Prop], [ChannelFunction] 
/// and initializing the channel at FIRST in any new isolate(channel)
/// you want to communicate with.
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
  
  final rect = Rectangle(10, 10)
    ..fill = ShapeFillType.outlined
    ..offset = Offset(10, 10);

  final square = Square(75);

  final shapes = <Shape>[rect, square];

  /// Any [ChannelFunction] return and [ChannelResult]
  /// that contains the data of the type of error(if some error occurs).
  final circlesRes = await CircleTheShapes(shapes: shapes).raise();
  print("First shape area ${shapes.first.area()}"); // 100
  print("First circle area ${circlesRes.correctData.first.area()}"); // 100

  await Future.delayed(const Duration(seconds: 2));

  // Here we deAttach the channel when we finish.
  await ThisChannel().deAttach();
}


//*/////////////////////// The channel functions ///////////////////////*//

// You can create them easily with the snippets I provide for you.


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


/// Here we pass the shapes and send them to [mainChannel],
/// then we will return back the [List<Circle>] that have the same area as that shape.
/// 
/// Obviously we can do that in the same isolate, but we do that to show the IDEA
/// of executing code in different channel, sending and recieving to or from any channel. 
class CircleTheShapes extends ChannelFunction<List<Circle>>{
  ///> here we define the arguments of the function.
  final _shapes = Prop<List<Shape>>.list([]);

  ///> add all the arguments here.
  @override
  late final List<Prop> args = [
    _shapes,
  ];

  ///> pass your argument to the function constructor. 
  CircleTheShapes({
    required List<Shape> shapes,
  }) : super.to(
    toChannel: mainChannel,
  ){
    ///> initialize the data.
    _shapes.data = shapes;
  }

  @override
  TypeAsync<List<Circle>> callFunWithArgs() async {
    print("CircleTheShapes in ${Isolate.current.hashCode}");

    /// Here we do the functionality.

    /// Here we use our [_shapes] prop.
    return _shapes.data.map((shape){
      final r = sqrt(shape.area() / 3.14);

      return Circle(r);
    }).toList();
  }


  ///> in case of returning a [List] we must provide an empty instance.
  @override
  List<Circle>? get emptyListFallback => [];

  //*////////////////////////// DO NOT MODIFY THIS SECTION BY HAND //////////////////////////*//

  @override
  ChannelFunctionConfig getConfig() => config;
  static final config = ChannelFunctionConfig<CircleTheShapes>(
    templateFunction: CircleTheShapes._temp,
    fromMarkup: CircleTheShapes.fromJson,
  );
  CircleTheShapes._temp() : super.temp();
  CircleTheShapes.fromJson(Map<String, dynamic> json) : super.fromJson(json);
}











//*/////////////////////// Types that can be sent through channels ///////////////////////*//

// This is commented in details in the example of `easy_serialization` Package.

/// Representative of [Offset] type that comes with Flutter SDK.
class Offset {
  final double dx, dy;
  const Offset(this.dx, this.dy);
}

enum ShapeFillType {
  solid,
  outlined,
}

abstract class Shape with SerializableMixin {
  Offset offset = const Offset(0, 0);
  ShapeFillType fill = ShapeFillType.solid;
  Shape();

  double area();

  @override
  MarkupObj toMarkupObj() => {
        "offset": Prop.valueToMarkup(offset),
        "fill": Prop.valueToMarkup(fill),
      };

  Shape.fromMarkup(MarkupObj markup)
      : offset = Prop.valueFromMarkup(markup["offset"]),
        fill = Prop.valueFromMarkup(markup["fill"]);
}

class Circle extends Shape {
  double radius;
  Circle(this.radius);

  @override
  double area() => 3.14 * radius * radius;

  @override
  MarkupObj toMarkupObj() => {
        ...super.toMarkupObj(),
        "radius": radius,
      };

  Circle.fromMarkup(MarkupObj markup)
      : radius = markup["radius"],
        super.fromMarkup(markup);
}

class Rectangle extends Shape {
  double height, width;
  Rectangle(this.height, this.width);

  @override
  double area() => height * width;

  @override
  MarkupObj toMarkupObj() => {
        ...super.toMarkupObj(),
        "height": height,
        "width": width,
      };

  Rectangle.fromMarkup(MarkupObj markup)
      : height = markup["height"],
        width = markup["width"],
        super.fromMarkup(markup);
}

class Square extends Rectangle {
  Square(double sideLen) : super(sideLen, sideLen);

  Square.fromMarkup(MarkupObj markup) : super.fromMarkup(markup);
}
