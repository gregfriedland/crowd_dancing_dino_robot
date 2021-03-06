
#include <Servo.h>

// CONFIGURE
#define D0_ROTATION_PIN   2 // S00
#define D0_FRONT_LEG_PIN  3 // S01
#define D0_BACK_LEG_PIN   4 // S02
#define D0_HEAD_PIN       8 // S03
#define D1_PIN            5 // S04
#define D2_PIN            6 // S05
#define D3_PIN            9 // S06
#define D4_PIN            10 // S07

#define LED1_RED_PIN      7  // L00
// END CONFIGURE

#define NUM_LEDS          1
#define NUM_SERVOS        8
int servoPins[] = { D0_ROTATION_PIN,     // S00
                    D0_FRONT_LEG_PIN,    // S01
                    D0_BACK_LEG_PIN,     // S02
                    D0_HEAD_PIN,         // S03
                    D1_PIN,              // S04
                    D2_PIN,              // S05
                    D3_PIN,              // S06
                    D4_PIN,              // S07
                  };
                  
int ledPins[] = { LED1_RED_PIN,          // L00
                };

//#define p(x) Serial.print(x)
#define p(x) 

#define UPDATE_TIME      100

Servo servos[NUM_SERVOS];
float currAngles[NUM_SERVOS];
float toAngles[NUM_SERVOS];
unsigned long toTimes[NUM_SERVOS];
unsigned long lastUpdateTime = 0;


void setup()
{
  Serial.begin(115200);
  Serial.println("Starting");
  
  for (int i = 0; i < NUM_SERVOS; i++) {
    servos[i].attach(servoPins[i]);
    currAngles[i] = 90;
    toAngles[i] = 0;
    toTimes[i] = 0;
  }
  for (int i = 0; i < NUM_LEDS; i++) {
    pinMode(ledPins[i], OUTPUT);
    analogWrite(ledPins[i], 0);
  }
  Serial.println("Setup");  
}

String inBuffer = "";         // a string to hold incoming data
boolean cmdComplete = false;  // whether the string is complete

void serialEvent() {
  while (Serial.available()) {
    char inChar = (char)Serial.read();
    inBuffer += inChar;
    if (inChar == '\n') {
      cmdComplete = true;
      break;
      //p(inBuffer); p("\n");
    }
  }
}

void loop()
{
  // parse command if finished
  if (cmdComplete) {
    cmdComplete = false;
    String cmd = inBuffer;
    inBuffer = "";
    
    // e.g. S011200450 or L0099
    if (cmd.length() == 11 && cmd[0] == 'S') {
      int servoNum = cmd.substring(1,3).toInt();
      int toAngle  = cmd.substring(3,6).toInt();
      int time     = cmd.substring(6,10).toInt();

      if (servoNum >= NUM_SERVOS) {
        p("Invalid servo: "); p(servoNum); Serial.println();
        return;
      }
      
      toAngles[servoNum] = toAngle;
      toTimes[servoNum] = time + millis();
      p("Servo "); p(servoNum); p(" to "); p(toAngle); p(" in "); p(time); p("ms\n");
    } else if (cmd.length() == 6 && cmd[0] == 'L') {
      int ledNum = cmd.substring(1,3).toInt();
      int brightness  = cmd.substring(3,5).toInt();   
      
      if (ledNum >= NUM_LEDS) {
        p("Invalid led: "); p(ledNum); Serial.println();
        return;
      }      
      brightness = 255 - brightness*255/100;
      analogWrite(ledPins[ledNum], brightness);
      p("Writing "); p(brightness); p(" for led "); p(ledNum); p("\n");
    } else { //if (cmd.length() > 0) {
      p("Invalid (");p(cmd.length());p("): '"); p(cmd); p("'\n");
    }
  } 
  
  if (millis() - lastUpdateTime > UPDATE_TIME) {
    lastUpdateTime = millis();
    
    for (int i = 0; i < NUM_SERVOS; i++) {
      if (millis() >= toTimes[i])
        continue;
      
      int periodsLeft = ceil(float(toTimes[i] - millis()) / UPDATE_TIME);
      float angle = (toAngles[i] - currAngles[i]) / periodsLeft + currAngles[i];
      //p("Servo="); p(i); p(" from angle="); p(currAngles[i]); p(" periodsLeft="); p(periodsLeft); p(" to angle="); p(angle); Serial.println();
      servos[i].write(int(angle));
      currAngles[i] = angle;
      if (periodsLeft == 1) {
        p("Servo "); p(i); p(" done\n"); 
      }
    }
  }
}
     
