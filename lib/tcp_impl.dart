// Copyright (c) 2014, Urchin Wang. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// The tcp_impl library.
library tcp_impl;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import "data_agent.dart";
import 'field_name.dart';

class TCPSocket {
  ///source IP address
  String srcIP;
  
  ///destination IP address
  String dstIP;
  
  ///source port
  int srcPort;
  
  ///source port
  int dstPort;
  
  /**Sender:   [srcIP, srcPort, dstIP, dstPort, ack#]
   * Receiver: [srcIP, srcPort, dstIP, dstPort, sequence#, data]
   */
  List<String> pktInfo;
  
  ///UDP socket
  RawDatagramSocket sock;
  
  ///incoming datagrams listener
  var listener;
  
  TCPSocket(this.srcPort, [this.dstIP, this.dstPort]);
  
  /// Bind socket on target address and port.
  Future init() {
    Completer cmpl = new Completer();
    
    RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, srcPort)
    .then((RawDatagramSocket socket) {
      sock = socket;
      srcIP = sock.address.address;
      return cmpl.complete();
    });
    
    return cmpl.future;
  }
  
  ///Cancel datagram listener.
  void unlisten() => listener.cancel();
  
  ///Parse information from received datagram.
  List<String> parsePkt(String packet, int parseLen) {
    List<String> info = new List(parseLen);
    int flag = 0, lastPos = 0;
    
    for (int i = 0; i < packet.length && flag < parseLen - 1; i++) {
      //split header by comma
      if (packet[i] == ',') {
        info[flag++] = packet.substring(lastPos, i);
        lastPos = i + 1;
      }
    }
    //get data from the rest of the packet
    info[flag] = packet.substring(lastPos, packet.length - 1);
    
    return info;
  }
  
  ///Send [data] directly.
  int sendRaw(String data, [int targetPort = AGENT_PORT])
    => sock.send(data.codeUnits, InternetAddress.LOOPBACK_IP_V4, targetPort);
  
  ///Receive datagram without parsing information.
  String recvRaw() {
    Datagram d = sock.receive();
    if (d == null) return null;
    return new String.fromCharCodes(d.data).trim();
  }
  
  bool get isSEQ => pktInfo[PKT_TYPE] == 'SEQ';
  bool get isACK => pktInfo[PKT_TYPE] == 'ACK';
  bool get isFIN => pktInfo[PKT_TYPE] == 'FIN';
}


class Sender extends TCPSocket {
  ///packets generator
  Packets _pkts;
  
  ///resent packets
  List<int> _resent;
  
  ///-1 if ack is not received yet, 1 otherwise.
  List<int> _acks;
  
  ///timers for sent packets
  List<Timer> _timers;
  
  ///Counter to calculate the sum of received and timeout packets.
  int _daultQuan;
  
  double _cwnd;
  double _thrd;
  int _curWndSize;
  bool _firstTimeout;
  
  int get _cwndRound => _cwnd.ceil();
  int get _thrdRound => _thrd.ceil();
  bool get _pktsAllDault => _daultQuan == _curWndSize; 
  
  Sender(int srcPort, String dstIP, int dstPort, String filepath) :
    super(srcPort, dstIP, dstPort) {
    //init packets generator from target file path
    _pkts = new Packets.fromFile(filepath);
    _resent = new List();
    _daultQuan = 0;
    _cwnd = DEFAULT_CWND;
    _thrd = DEFAULT_THRD;
  }
  
  Future init() {
    Completer cmpl = new Completer();
    
    //read contents form file
    _pkts.readFile();
    super.init().then((_) => cmpl.complete());
    
    return cmpl.future;
  }
  
  ///Start listening on incoming datagrams.
  void listen() {
    listener = sock.listen((RawSocketEvent e) => _recv());
  }
  
  /**Send a window-sized number of packets.
   * Set timer for each packet.
   */
  void send() {
    _renderAckList(_cwndRound);
    _resetTimers();
    _daultQuan = 0;
    _pkts.start = _pkts.seq;
    _curWndSize = _cwndRound;
    
    //send each packet
    for (int i = 0; i < _cwndRound; i++) {
      //all packets are sent
      if (_pkts.reachEnd) {
        _curWndSize = i;
        return;
      }
      
      int curSeq = _pkts.seq;
      StringBuffer sb = new StringBuffer();
      
      //write header and content into packet
      sb.write('SEQ');
      sb.write(',');
      sb.write(dstIP);
      sb.write(',');
      sb.write(dstPort);
      sb.write(',');
      sb.write(srcIP);
      sb.write(',');
      sb.write(srcPort);
      sb.write(',');
      sb.write(curSeq);
      sb.write(',');
      sb.write(_pkts.next);
      sb.write(',');
      
      if (_resent.contains(curSeq)) {
        print('resnd data #${curSeq + 1}, winSize = $_curWndSize');
        _resent.remove(curSeq);
      } else
        print('send  data #${curSeq + 1}, winSize = $_curWndSize');
      
      //send packet to agent
      sendRaw(sb.toString());
      //set timer for the packet
      _timers.add(new Timer(new Duration(milliseconds: 3000), ()
          => _handleTimeout(curSeq)));
    }
    _firstTimeout = true;
  }

  ///Generate ack list with size equals to current window size.
  void _renderAckList(int length) {
    _acks = [];
    for (int i = 0; i < length; i++)
      _acks.add(-1);
  }
  

  ///Generate timer list with size equals to current window size.
  void _resetTimers() {
    _timers = [];
  }
  
  /**Change congestion window size and threshold.
   * Set next packet to send to timeout packet if it has smaller sequence#.
   */
  void _handleTimeout(int ack) {
    if (_firstTimeout) {
      for (int i = ack; i < _pkts.start + _curWndSize; i++)
        _resent.add(i);
      _thrd = _cwnd / 2;
      _cwnd = DEFAULT_CWND;
      _pkts.setStart(ack);
      _firstTimeout = false;
      print('time  out,    threshold = $_thrdRound');
    }
    _daultQuan++;
    if (_pktsAllDault)
      send();
  }
  
  ///Handle received datagrams.
  void _recv() {
    while (true) {
      //receive a dataagram, null if the queue is empty
      String packet = recvRaw();
      if (packet == null) break;

      pktInfo = parsePkt(packet, SEND_PKT_LEN);
     
      if (isACK) {
        int ackRecv = int.parse(pktInfo[SEND_PKT_ACK]);
        print('recv  ack  #${ackRecv + 1}');
        if (_isExpectedAck(ackRecv)) {
          //align received ack to the position in current window size
          int alignAck = ackRecv - _pkts.start;
          //ack already received, can keep track of triple duplicate ack case
          if (_acks[alignAck] == 1);
         //expected packet, save to buffer and send ack back
          else if (_acks[alignAck] == -1) {
            _timers[alignAck].cancel();
            _acks[alignAck] = 1;
            _increaseCwnd();
            _daultQuan++;
          }
        }
      } else if (isFIN) {
        print('recv fin');
        _timers[0].cancel();
        unlisten();
        return;
      }
    }
    //packets in current window are acked or timeout 
    if (_pktsAllDault) {
      if (_pkts.reachEnd)
        _closeConnection();
      else
        send();
    }
  }
  
  ///received ack is the ack for packet in current window
  bool _isExpectedAck(int ack) => ack >= _pkts.start && ack < _pkts.start + _curWndSize;
  
  ///increase the size of the congestion window
  void _increaseCwnd() {
    if (_slowStart)
      _cwnd++;
    else
      _cwnd += 1/_cwnd;
  }
  
  bool get _slowStart => _cwndRound < _thrdRound;
  
  ///Send close connection command to receiver.
  void _closeConnection() {
    _resetTimers();
    StringBuffer sb = new StringBuffer();
    
    sb.write('FIN');
    sb.write(',');
    sb.write(dstIP);
    sb.write(',');
    sb.write(dstPort);
    sb.write(',');
    sb.write(srcIP);
    sb.write(',');
    sb.write(srcPort);
    sb.write(',,,');
    
    print('send fin');
    sendRaw(sb.toString());
    _timers.add(new Timer(new Duration(milliseconds: 4900), () {
      _closeConnection();
    }));
  }
}

class Receiver extends TCPSocket {
  ///file object to store received contents
  myFile _file;
  
  ///buffer to store target received contents
  List<String> _buffer;
  
  ///counter for current buffer quantity
  int _bufferQuan;
  
  ///-1 if data is not received yet, 1 otherwise.
  List<int> _seqs;
  
  ///the first data that should be stored in buffer
  int _seqStart;
  
  ///True if ack destination is set, false otherwise.
  bool _dstIsSet;
  
  bool get _bufferIsFull => _bufferQuan == RECV_BUFFER_LEN;
  
  Receiver(int srcPort, String filepath) :
    super(srcPort) {
    _file = new myFile(filepath);
    _buffer = new List(RECV_BUFFER_LEN);
    _seqs = new List(RECV_BUFFER_LEN);
    _seqStart = 0;
    _bufferQuan = 0;
    _dstIsSet = false;
    
    _resetSeqs();
  }
  
  ///Reset all sequence status to -1.
  void _resetSeqs() {
    for(int i = 0; i < RECV_BUFFER_LEN; i++)
      _seqs[i] = -1;
  }
  
  ///Start listening on incoming datagrams.
  void listen() {
    listener = sock.listen((RawSocketEvent e) => _recv());
  }
  
  ///Handle received datagrams.
  void _recv() {
    while (true) {
      //receive a dataagram, null if the queue is empty
      String packet = recvRaw();
      if (packet == null) break;
 
      //parse sneder's IP, port, sequence#, contents from received packet
      pktInfo = parsePkt(packet, RECV_PKT_LEN);
      _setDst();
      
      if (isSEQ) {
        int seqRecv = int.parse(pktInfo[RECV_PKT_SEQ]);

        if (_isPreRoundSeq(seqRecv)) {
            print('ignore data #${seqRecv + 1}');
            _sendAck(seqRecv);
        } else if (_isNextRoundSeq(seqRecv)) {
          print('drop   data #${seqRecv + 1}');
          //drop overflow packet and flush buffer to file if buffer is full
          if (_bufferIsFull) {
            print('flush');
            _file.write(_buffer);
            _bufferQuan = 0;
            _seqStart += RECV_BUFFER_LEN;
            _resetSeqs();
          }
        } else {
          //align received data to the position stored in buffer
          int alignSeq = seqRecv % RECV_BUFFER_LEN;
          //packet already received, send ack back only
          if (_seqs[alignSeq] == 1) {
            print('ignore data #${seqRecv + 1}');
            _sendAck(seqRecv);
          }
          //packet first received, save to buffer and send ack back
          else {
            print('recv   data #${seqRecv + 1}');
            _seqs[alignSeq] = 1;
            _buffer[alignSeq] = pktInfo[RECV_PKT_CONTENT];
            _bufferQuan++;
            _sendAck(seqRecv);
          }
        }
      } else if (isFIN) {
        print('recv   fin');
        _file.write(_buffer, _bufferQuan);
        _sendFIN();
        unlisten();
        return;
      }
    }
  }
  
  ///Set ack destination from packet information [srcIP] and [srcPort].
  void _setDst() {
    if (!_dstIsSet) {
      dstIP = pktInfo[PKT_DSTIP];
      dstPort = int.parse(pktInfo[PKT_DSTPORT]);
      _dstIsSet = true;
    }
  }
  
  bool _isPreRoundSeq(int seq) => seq < _seqStart;
  bool _isNextRoundSeq(int seq) => seq >= _seqStart + RECV_BUFFER_LEN;
  
  ///Send corresponding ack to sender.
  void _sendAck(int ackNum) {
    StringBuffer sb = new StringBuffer();
    
    sb.write('ACK');
    sb.write(',');
    sb.write(dstIP);
    sb.write(',');
    sb.write(dstPort);
    sb.write(',');
    sb.write(srcIP);
    sb.write(',');
    sb.write(srcPort);
    sb.write(',');
    sb.write(ackNum);
    sb.write(',');
    
    print('send   ack  #${ackNum + 1}');
    sendRaw(sb.toString());
  }
  
  ///Send close connection command to sender.
  void _sendFIN() {
    StringBuffer sb = new StringBuffer();
    
    sb.write('FIN');
    sb.write(',');
    sb.write(dstIP);
    sb.write(',');
    sb.write(dstPort);
    sb.write(',');
    sb.write(srcIP);
    sb.write(',');
    sb.write(srcPort);
    sb.write(',,');

    print('send   fin');
    
    sendRaw(sb.toString());
  }
}

class Agent extends TCPSocket {
  ///number of stage not to drop packets at start 
  int stable;
  
  ///ideal loss rate
  int lossRate;
  
  ///Base number to generate loss rate
  int _randomBase;
  
  ///Received packet
  String _packet;
  
  ///Controller to decide dropping or forwarding the packet received.
  Random _controller;
  
  ///Total amount of received packets
  int _pktRecved;
  
  ///Total amount of dropped packets
  int _pktDropped;
  
  Agent([this.stable = STABLE_STAGE, this.lossRate = LOSS_RATE]) : super(AGENT_PORT) {
    _randomBase = 100 ~/ lossRate;
    _controller = new Random();
    _pktRecved = 0;
    _pktDropped = 0;
  }

  ///Start listening on incoming datagrams.
  void listen() {
    listener = sock.listen((RawSocketEvent e) => _recv());
  }
  
  ///Handle received datagrams.
  void _recv() {
    while (true) {
      //receive a dataagram, null if the queue is empty
      _packet = recvRaw();
      if (_packet == null) break;

      pktInfo = _parseDst(_packet);
      
      if (isACK) {
        print('get  ack  #${int.parse(pktInfo[AGENT_PKT_NUM]) + 1}');
        _forward();
        print('fwd  ack  #${int.parse(pktInfo[AGENT_PKT_NUM]) + 1}');
      } else if (isFIN) {
        print('get  fin');
        _forward();
        print('fwd  fin');
      } else {
        _pktRecved++;
        print('get  data #${int.parse(pktInfo[AGENT_PKT_NUM]) + 1}');
        if (_dropPkt) {
          _drop();
          print('drop data #${int.parse(pktInfo[AGENT_PKT_NUM]) + 1}, loss rate = $_lossRate');
        }
        else {
          _forward();
          print('fwd  data #${int.parse(pktInfo[AGENT_PKT_NUM]) + 1}, loss rate = $_lossRate');
        }
      }
    }
  }

  ///Drop the packet.
  void _drop() {
    _pktDropped++;
  }
  
  ///Foreard the packet.
  void _forward() {
    //set destination from packet info
    int port = int.parse(pktInfo[AGENT_PKT_DSTPORT]);
    sendRaw(_packet, port);
  }

  ///Parse target IP, port, sequence# from received packet
  List<String> _parseDst(String packet) {
    List<String> info = new List(AGENT_PKT_LEN);
    int flag = 0, lastPos = 0;
    
    for (int i = 0; i < packet.length && flag < AGENT_PKT_LEN; i++) {
      if (packet[i] == ',') {
        info[flag++] = packet.substring(lastPos, i);
        lastPos = i + 1;
      }
    }
    
    return info;  
  }
  
  ///Randomizer to decide whether to drop the packet.
  bool get _dropPkt => _pktRecved < stable ? false 
      : _controller.nextInt(_randomBase) == 0;
  
  double get _lossRate => _pktDropped / _pktRecved;
}