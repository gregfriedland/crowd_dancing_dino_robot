# Aggregate accelerometer data over websocket connections
# to mobile devices and translate the accelerometer data
# into servo control commands sent to an Arduino connected
# to the Dino servos.
#
# Servo 0 gets the averages of the x accelerations
# and each connected device is assigned an id corresponding
# to a another servo

express = require('express')
app     = express();
http    = require('http').Server(app)
io      = require('socket.io')(http)
serialport = require("serialport")
async = require("async")
stats = require("stats-lite")
app.use(express.static('public'))

serial = new serialport.SerialPort process.argv[2],
        parser: serialport.parsers.readline "\n"
        baudrate: 115200
serial.isconnected = false
aggInterval = 100
debug = false
loglevel = 1
maxAccel = 3
disableRotation = true

class PhoneData
  @CURR_ID = 1
  constructor: ->
    @id = @constructor.CURR_ID++
    @x = @y = @z = @count = 0
  add:(data) ->
    @x += data.x
    @y += data.y
    @z += data.z
    @count += 1
  agg: ->
    @aggdata = x: @x/@count, y: @y/@count, z: @z/@count, id:@id
    @x = @y = @z = @count = 0
    @aggdata
  send: (ms, callback) ->
    sendCmd @id, @aggdata.x, ms, callback

log = (level, msg) ->
  if loglevel >= level
    console.log msg

constrain = (x, min, max)=>
  if x < min
    min
  else if x > max
    max
  else
    x

map = (x, in_min, in_max, out_min, out_max)=>
  x = (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min
  if (x < out_min)
    out_min
  else if (x > out_max)
    out_max
  else
    x

sendCmd = (servo, val, ms, callback) ->
    if servo == 0
      angle = map val, -maxAccel, maxAccel, 80, 100
      if disableRotation
        angle = 90
    else
      angle = map val, -maxAccel, maxAccel, 45, 135

    cmd = "S" + pad(Math.floor(servo), 2) + pad(Math.floor(angle), 3) + pad(Math.floor(ms), 4)
    if !disableRotation || servo != 0
      log 1, "Servo " + servo + " to " + pad(Math.floor(angle), 3) + " in " + ms + "ms (xacc=" + val.toFixed(1) + ")"
    log 2, "Sending cmd: " + cmd
    if serial.isconnected
      serial.write cmd + "\n", callback

pad = (n, width) => 
  n += ''
  if n.length >= width
    n
  else
    new Array(width - n.length + 1).join('0') + n

@phoneDatas = {}
io.on 'connection', (socket)=>
  @phoneDatas[socket] = new PhoneData()
  log 0, "client " + @phoneDatas[socket].id + " connected"

  socket.on "boogy_data", (data) =>
    log 3, "boogy data: " + JSON.stringify(data)
    @phoneDatas[socket].add(data)

if debug
  debugSocket = 'debug'
  @phoneDatas[debugSocket] = new PhoneData()
  log 0, "(test) client " + @phoneDatas[debugSocket].id + " connected"
  setInterval =>
    @phoneDatas[debugSocket].add({x:1,y:1,z:1})
  ,50

serial.on 'open', () =>
  log 0, 'serial open'

  serial.on 'data', (data) =>
    log 2, "  Received: " + data
    serial.isconnected = true

  serial.on 'error', (err) ->
    log 0, "serial error: " + err

setInterval =>
  pds = (pd for sock,pd of @phoneDatas)
  log 3, "phoneDatas: " + JSON.stringify(pds)

  (pd.agg() for pd in pds)
  pds = (pd for pd in pds when pd.aggdata.x)
  accels = (pd.aggdata for pd in pds)
  if pds.length
    log 3, (pd.aggdata for pd in pds)

    avgx = stats.mean(accel.x for accel in accels)
    avgy = stats.mean(accel.y for accel in accels)
    avgz = stats.mean(accel.z for accel in accels)
    avgs = { x: avgx, y: avgy, z: avgz, id: 0 }
    accels.push(avgs)

    # send all agg data to each client
    log 3, "Sending agg_data: " + JSON.stringify(accels)
    io.emit 'agg_data', accels

    sends = []
    for accel in accels
      do (accel) ->
        sends.push (cb) =>
          log 3, "sending: " + JSON.stringify(accel)
          sendCmd accel.id, accel.x, aggInterval
          cb null, accel.id
    async.series sends, (err, result) ->
      log 3, "series error: " + err
      log 3, "series result: " + result
, aggInterval

portNum = 3344
log 0, "listening on #{portNum}"
http.listen(portNum)
