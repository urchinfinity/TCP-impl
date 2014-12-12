// Copyright (c) 2014, Urchin Wang. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import "args.dart";
import 'package:b01902080_hw2/tcp_impl.dart';

Receiver receiver;
var listener;

void main(List<String> arguments) {
  
  if (arguments.length != 2) {
    print('Usage: receiver.dart [srcPort] [filepath]');
    return;
  }
  
  Args args = new Args.receiverParser(arguments);
  
  receiver = new Receiver(args.srcPort, args.filepath)  
    ..init().then((_) => receiver.listen());
}