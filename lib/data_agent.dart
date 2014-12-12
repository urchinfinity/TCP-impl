library data_agent;

import 'dart:io';
import "field_name.dart";

class Packets {
  ///current packet ready to send
  int start;
  
  ///size for each packet
  int _size;
  
  ///number of packets to send
  int _num;
  
  ///sequence# of the current packet
  int _seq;
  
  ///filepath
  String _path;
  
  ///file content
  String _content;
  
  Packets.fromFile(this._path) :
    _size = PACKET_SIZE, _seq = 0;
  
  void readFile() {
    _content = new File(_path).readAsStringSync();
    _num = (_content.length / _size).ceil();
  }

  ///Set current packet to [start]
  void setStart(int start) {
    if (start < _seq)
      _seq = start;
  }
  
  ///True if current packet reaches the end of the file, false otherwise.
  bool get reachEnd => _seq == _num;
  
  int get seq => _seq;
  
  ///Return corresponding packet to send to receiver
  String get next => _seq == (_num - 1) 
      ? _content.substring(_seq++ * _size)
      : _content.substring(_seq++ * _size, _seq * _size);
}

class myFile {
  ///Wrapped Stream helper to write to the file.
  IOSink _sink;
  
  myFile(String path) {
    _sink = new File(path).openWrite();
  }
  
  ///Write [contents] to target file.
  void write(List<String> contents, [int len = RECV_BUFFER_LEN]) {
    for (int i = 0; i < len; i++)
      _sink.write(contents[i]);
  }
  
  ///Close file.
  void close() {
    _sink.close();
  }
}