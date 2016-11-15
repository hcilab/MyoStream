MyoEMG myoEmg;

void setup() {
  try {
    myoEmg = new MyoEMG(this);
  } catch (MyoNotDetectectedError e) {
    println("[Error] Myo armband not detected, exiting.");
    System.exit(1);
  }

  while (true)
    prettyPrint(myoEmg.readSample());
}


void draw() {
  // do nothing
}


private void prettyPrint(Sample sample) {
  int[] data = sample.sensorData;

  print(sample.timestamp + ": [");
  for (int i=0; i<data.length; i++) {
    if (i < data.length -1)
      print(data[i] + " ");
    else
      print(data[i]);
  }
  println("]");
}
