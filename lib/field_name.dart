library field_name;

const int PACKET_SIZE = 900;

const int PKT_TYPE = 0;
const int PKT_SRCIP = 1;
const int PKT_SRCPORT = 2;
const int PKT_DSTIP = 3;
const int PKT_DSTPORT = 4;

const double DEFAULT_CWND = 1.0;
const double DEFAULT_THRD = 16.0;

const int AGENT_PKT_LEN = 6;
const int AGENT_PKT_DSTIP = 1;
const int AGENT_PKT_DSTPORT = 2;
const int AGENT_PKT_NUM = 5;

const int SEND_PKT_LEN = 6;
const int SEND_PKT_ACK = 5;

const int RECV_BUFFER_LEN = 32;
const int RECV_PKT_LEN = 7;
const int RECV_PKT_SEQ = 5;
const int RECV_PKT_CONTENT = 6;

const String AGENT_IP = '127.0.0.1';
const int AGENT_PORT = 6000;
const int STABLE_STAGE = 10;
const int LOSS_RATE = 10;