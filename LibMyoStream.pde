import processing.serial.*;


class LibMyoStream {
  private Bluetooth bt;

  // 128 bit string that identifies a BLE device as a Myo Armband.  This ID is
  // used during the connection process to validate the identity of the device
  // being connected
  private final byte[] MYO_ID = {
    (byte)0x42, (byte)0x48, (byte)0x12, (byte)0x4A,
    (byte)0x7F, (byte)0x2C, (byte)0x48, (byte)0x47,
    (byte)0xB9, (byte)0xDE, (byte)0x04, (byte)0xA9,
    (byte)0x01, (byte)0x00, (byte)0x06, (byte)0xD5
  };

  // the myo armband does not send a timestamp along with EMG data because of
  // bandwidth constraints. However, we know that the the myo samples at a
  // constant rate of 200 Hz. Therefore, we can estimate the time of the first
  // same, and then calculate each subsequent sample time.
  private long lastSampleTimeMillis;

  // each EMG packet received from the armband stores 2 sets of sensor
  // readings, measured 5 ms apart. This is a place to store the second sample
  // until it is requested.
  private Sample bufferedSample;


  public LibMyoStream(PApplet mainApp) throws MyoNotDetectectedError {
    this(mainApp, null);
  }

  public LibMyoStream(PApplet mainApp, String serialPort) throws MyoNotDetectectedError {
    bt = new Bluetooth(mainApp, serialPort, MYO_ID);
    bt.connect();

    // disable armband locking
    byte[] disableLockCommand = {0x0a, 0x01, 0x02};
    bt.writeAttributeByHandle(new byte[]{0x19, 0x00}, disableLockCommand);

    // disable armband sleeping
    byte[] disableSleepCommand = {0x09, 0x01, 0x01};
    bt.writeAttributeByHandle(new byte[]{0x19, 0x00}, disableSleepCommand);

    // disable armband vibration
    byte[] vibrateNoneCommand = {0x03, 0x01, 0x00};
    bt.writeAttributeByHandle(new byte[]{0x19, 0x00}, vibrateNoneCommand);

    // set armband mode to stream EMG
    byte[] streamEMGCommand = {0x01, 0x03, 0x02, 0x00, 0x00};
    bt.writeAttributeByHandle(new byte[]{0x19, 0x00}, streamEMGCommand);

    // subscribe for notifications from 4 EMG data channels
    bt.writeAttributeByHandle(new byte[]{0x2c, 0x00}, new byte[]{0x01, 0x00});
    lastSampleTimeMillis = System.currentTimeMillis(); // rough approximation

    bt.writeAttributeByHandle(new byte[]{0x2f, 0x00}, new byte[]{0x01, 0x00});
    bt.writeAttributeByHandle(new byte[]{0x32, 0x00}, new byte[]{0x01, 0x00});
    bt.writeAttributeByHandle(new byte[]{0x35, 0x00}, new byte[]{0x01, 0x00});
  }

  public Sample readSample() {
    if (bufferedSample != null) {
      Sample toReturn = bufferedSample;
      bufferedSample = null;
      return toReturn;
    }

    byte[] packet = new byte[0];
    while (!isEMGData(packet)) {
      packet = bt.readPacket();
    }

    return processEMGPacket(packet);
  }

  private boolean isEMGData(byte[] packet) {
    if (packet.length != 25)
      return false;
    else
      return packet[0] == (byte) 0x80 && packet[2] == 0x04 && packet[3] == 0x05;
  }

  private Sample processEMGPacket(byte[] packet) {
    int[] sensorData1 = new int[8];
    int[] sensorData2 = new int[8];

    for (int i=0; i<8; i++) {
      sensorData1[i] = packet[i+9];
      sensorData2[i] = packet[i+17];
    }

    Sample s1 = new Sample(lastSampleTimeMillis+5, sensorData1);
    Sample s2 = new Sample(lastSampleTimeMillis+10, sensorData2);
    lastSampleTimeMillis += 10;

    // return the first sample, buffer the second
    bufferedSample = s2;
    return s1;
  }
}


class Sample {
  public long timestamp;
  public int[] sensorData;

  public Sample(long timestamp, int[] sensorData) {
    this.timestamp = timestamp;
    this.sensorData = sensorData;
  }
}


private class Bluetooth {
  final int BAUD_RATE = 256000;

  // When attempting to auto-detect the myo dongle, a request for discovery
  // messages is sent across each serial port prompting the armband to
  // broadcast its identity. A port will be ruled-out after this duration of
  // time.
  final int DISCOVERY_TIMEOUT_MILLIS = 2000;

  // During auto-detection, we cannot be sure that the port we are
  // communicating across is connected to an armband, meaning that we may never
  // receive a response. Give up trying to receive a packet after this
  // duration of time.
  final int PACKET_TIMEOUT_MILLIS = 50;

  Serial serialConnection;
  byte bluetoothConnectionID = -1;
  byte[] deviceID;
  PApplet mainApp;


  public Bluetooth(PApplet mainApp, String serialPort, byte[] deviceID) {
    if (serialPort != null)
      this.serialConnection = new Serial(mainApp, serialPort, BAUD_RATE);

    this.mainApp = mainApp;
    this.deviceID = deviceID;
  }

  public void connect() throws MyoNotDetectectedError {
    if (serialConnection == null)
      establishSerialConnection();

    // clean up any residue from previous runs
    disconnect();

    // enable discovery (Myo armband will begin broadcasting it's identity)
    byte[] discoverMessage = {0x00, 0x01, 0x06, 0x02, 0x01};
    write(discoverMessage);

    // wait for discovery response until timeout
    byte[] response = {};
    int startTime = millis();
    while (!endsWith(response, deviceID)) {
      if (millis() > startTime+DISCOVERY_TIMEOUT_MILLIS)
        throw(new MyoNotDetectectedError());
      response = readPacket();
    }

    // disable discovery (to prevent more broadcasted messages)
    byte[] endScanCommand = {0x00, 0x00, 0x06, 0x04};
    write(endScanCommand);

    // parse myo serial number (from bytes 2-7 of payload, i.e., bytes 6-11 of response)
    byte[] serialNumber = new byte[6];
    for (int i=0; i<=5; i++)
      serialNumber[i] = response[i+6];

    // request connection
    byte[] connectionMessage = {
      0x00, 0x0f, 0x06, 0x03,
      serialNumber[0], serialNumber[1], serialNumber[2], serialNumber[3], serialNumber[4], serialNumber[5],
      0x00, 0x06, 0x00, 0x06, 0x00, 0x40, 0x00, 0x00, 0x00
    };
    write(connectionMessage);

    // wait for connection response, and parse connection ID for future messages
    while (true) {
      response = readPacket();
      if (response[2] == 6 && response[3] == 3) {
        bluetoothConnectionID = response[response.length-1];
        break;
      }
    }
  }

  public void disconnect() {
    assert(serialConnection != null);

    // disable any active discovery broadcasting
    byte[] endScanCommand = {0x00, 0x00, 0x06, 0x04};
    write(endScanCommand);

    if (bluetoothConnectionID > -1) {
      byte[] disconnectMessage = {0x00, 0x01, 0x03, 0x00, bluetoothConnectionID};
      write(disconnectMessage);
    } else {
      // if no active connection, just brute force it to clean up any rogue connections
      byte[] disconnectMessage0 = {0x00, 0x01, 0x03, 0x00, 0x00};
      byte[] disconnectMessage1 = {0x00, 0x01, 0x03, 0x00, 0x01};
      byte[] disconnectMessage2 = {0x00, 0x01, 0x03, 0x00, 0x02};
      write(disconnectMessage0);
      write(disconnectMessage1);
      write(disconnectMessage2);
    }

    bluetoothConnectionID = -1;
  }

  public void writeAttributeByHandle(byte[] handle, byte[] message) {
    assert(serialConnection != null);

    int packetLength = 8+message.length;
    byte[] packet = new byte[packetLength];

    packet[0] = 0x00;
    packet[1] = (byte) (packetLength-4);
    packet[2] = 0x04;
    packet[3] = 0x06;
    packet[4] = bluetoothConnectionID;
    packet[5] = handle[0];
    packet[6] = handle[1];
    packet[7] = (byte) message.length;
    for (int i=0; i<message.length; i++)
      packet[8+i] = message[i];

    write(packet);
  }

  // Attempt to read a bluetooth packet from the armband, hanging indefinitely
  // until a packet is received.
  //
  public byte[] readPacket() {
    return readPacketOrTimeout(0);
  }

  // Attempt to read a bluetooth packet sent from the armband. Give up and
  // return null after a timeout period. Note that after returning from a
  // timeout, the serial stream is at an indeterminate location, and subsequent
  // reads will not behave as expected.
  //
  private byte[] readPacketOrTimeout(int timeoutMillis) {
    assert(serialConnection != null);

    byte messageType = 0;
    byte payloadSize = 0;

    int bytesRead = 0;
    int startTime = millis();
    while (bytesRead < 2) {
      if (timeoutMillis != 0 && millis() > startTime+timeoutMillis)
        return null;

      if (serialConnection.available() > 0) {
        if (bytesRead == 0) {
          messageType = (byte) serialConnection.read();
          bytesRead++;
        } else if (bytesRead == 1) {
          payloadSize = (byte) serialConnection.read();
          bytesRead++;
        }
      } else {
        // avoid burning processor
        delay(1);
      }
    }

    byte[] packet = new byte[4+Byte.toUnsignedInt(payloadSize)];
    packet[0] = messageType;
    packet[1] = payloadSize;
    while (bytesRead < packet.length) {
      if (timeoutMillis != 0 && millis() > startTime+timeoutMillis)
        return null;

      if (serialConnection.available() > 0)
        packet[bytesRead++] = (byte) serialConnection.read();
    }

    return packet;
  }

  private void establishSerialConnection() throws MyoNotDetectectedError {
    for (String port : Serial.list()) {
      try {
        serialConnection = new Serial(mainApp, port, BAUD_RATE);
      } catch (RuntimeException e) {
        // if we experience any errors connecting to the serial port, it
        // probably isn't the right one.
        continue;
      }

      // request discovery notifications, if this is the correct port, the armband should reply.
      byte[] discoverMessage = {0x00, 0x01, 0x06, 0x02, 0x01};
      write(discoverMessage);

      // wait for discovery response until timeout
      long startTime = millis();
      while (millis() < startTime+DISCOVERY_TIMEOUT_MILLIS) {
        byte[] response = readPacketOrTimeout(PACKET_TIMEOUT_MILLIS);
        if (response != null && endsWith(response, deviceID)) {
          // found it, disable discovery notifications and return
          byte[] endScanCommand = {0x00, 0x00, 0x06, 0x04};
          write(endScanCommand);
          return;
        }
      }
    }

    // couldn't find a connected armband, abort
    throw(new MyoNotDetectectedError());
  }

  private void write(byte[] message) {
    // When consecutive messages are written to quickly together, they seem to
    // be dropped/ignored by the Myo armband. Does this have something to do
    // with the "connection interval" in BLE?
    delay(200);
    serialConnection.write(message);
  }

  private boolean endsWith(byte[] message, byte[] suffix) {
    if (suffix.length > message.length)
      return false;

    for (int i=0; i<suffix.length; i++) {
      int messageIndex = (message.length-suffix.length) + i;
      if (suffix[i] != message[messageIndex])
        return false;
    }
    return true;
  }
}

class MyoNotDetectectedError extends Exception {}
