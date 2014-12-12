// Copyright (c) 2014, Urchin Wang. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import "args.dart";
import "package:b01902080_hw2/tcp_impl.dart";

Agent agent;

void main(List<String> arguments) {
  
  if (arguments.length != 2) {
    print('Usage: receiver.dart [stable stage] [loss rate (%)]');
    return;
  }
  
  Args args = new Args.agentParser(arguments);
  
  agent = new Agent(args.stable, args.lossRate)
    ..init().then((_) => agent.listen());
}