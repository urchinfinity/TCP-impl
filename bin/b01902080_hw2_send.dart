// Copyright (c) 2014, Urchin Wang. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import "args.dart";
import "package:b01902080_hw2/tcp_impl.dart";

Sender sender;

void main(List<String> arguments) {
  
  if (arguments.length != 4) {
    print('Usage: sender.dart [srcPort] [dstIP] [dstPort] [filepath]');
    return;
  }
  
  Args args = new Args.senderParser(arguments);
  
  sender = new Sender(args.srcPort, args.dstIP, args.dstPort, args.filepath)
    ..init().then((_) {
    sender.listen();
    sender.send();
  });
}