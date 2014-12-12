///arguments parser
class Args {
  String dstIP;
  int srcPort;
  int dstPort;
  String filepath;
  int stable;
  int lossRate;
  
  Args.senderParser(List<String> args) {
    srcPort = int.parse(args[0]);
    dstIP = args[1];
    dstPort = int.parse(args[2]);
    filepath = args[3];
  }
  
  Args.receiverParser(List<String> args) {
    srcPort = int.parse(args[0]);
    filepath = args[1];
  }
  
  Args.agentParser(List<String> args) {
    stable = int.parse(args[0]);
    lossRate = int.parse(args[1]);
  }
}