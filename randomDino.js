// randomly move the dinos

var SerialPort = require("serialport").SerialPort;

var delay = 1000;
var numServos = 10;
var device = process.argv[2];
var serialPort = new SerialPort(device, {
	baudrate: 115200
    });

function pad(n, width, z) {
    z = z || '0';
    n = n + '';
    return n.length >= width ? n : new Array(width - n.length + 1).join(z) + n;
}

function sendCmd(servo, angle, time) {
    var cmd = "S" + pad(servo, 2) + pad(angle, 3) + pad(time, 4) + "\n";

    console.log("Sending cmd: " + cmd);

    serialPort.write(cmd, function(err, results) {
	    //console.log('err ' + err);
	    //console.log('results ' + results);
	});
}

var servoNum = 0;
var left = true;
function sendCmds() {
    var angle;
    if (left) angle = 45;
    else angle = 135;

    sendCmd(servoNum, angle, delay);
    servoNum++;
    if (servoNum == numServos) {
	servoNum = 0;
	left = !left;
    }
}

serialPort.on("open", function () {
	console.log('serial open');

	setInterval(sendCmds, 200);
    });
