# Aggregate accelerometer data over websocket connections
# to mobile devices and translate the accelerometer data
# into servo control commands sent to an Arduino connected
# to the Dino servos.
#
# Servo 0 gets the averages of the x accelerations
# and each connected device is assigned an id corresponding
# to a another servo


# todo
# - get working with mobile router (directly connected to arduino)
# - setup bonjour on host
# - map accel data to all dino servos
# - have tiny move in a few ways


express = require('express')
app     = express();
http    = require('http').Server(app)
io      = require('socket.io')(http)
serialport = require("serialport")
async = require("async")
stats = require("stats-lite")
_ = require("underscore")
app.use(express.static('public'))

serial = new serialport.SerialPort process.argv[2],
        parser: serialport.parsers.readline "\n"
        baudrate: 115200
serial.isconnected = false
aggInterval = 100
debug = false
loglevel = 1
maxAccel = 3
largeDinoServos = [0, 1, 2, 3]
smallDinoServos = [4, 5, 6, 7]
disableRotation = true


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

pad = (n, width) => 
  n += ''
  if n.length >= width
    n
  else
    new Array(width - n.length + 1).join('0') + n


class PhoneData
  @CURR_ID = smallDinoServos[0]
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


avgAccelData = (accelData) =>
    log 3, "accelData: " + accelData
    avgx = stats.mean(accel.x for accel in accelData)
    avgy = stats.mean(accel.y for accel in accelData)
    avgz = stats.mean(accel.z for accel in accelData)
    { x: avgx, y: avgy, z: avgz }

setInterval =>
    # agg data from different phones
    pds = (pd for sock,pd of @phoneDatas)
    log 3, "phoneDatas: " + JSON.stringify(pds)

    (pd.agg() for pd in pds)
    pds = (pd for pd in pds when pd.aggdata.x)
    accelData = (pd.aggdata for pd in pds)

    if accelData.length == 0
      return

    avgData = avgAccelData accelData

    # send avg agg data to each client
    log 3, "Sending agg_data: " + JSON.stringify(avgData)
    io.emit 'agg_data', avgData
 
    # add data for tiny's servos
    accelData.push {x:avgData.x, y:avgData.y, z:avgData.z, id:0}
    accelData.push {x:avgData.x, y:avgData.y, z:avgData.z, id:1}
    accelData.push {x:avgData.x, y:avgData.y, z:avgData.z, id:2}
    accelData.push {x:avgData.x, y:avgData.y, z:avgData.z, id:3}

    sends = []
    for accel in accelData
      do (accel) ->
        sends.push (cb) =>
          log 3, "sending: " + JSON.stringify(accel)
          sendCmd accel.id, accel.x, aggInterval
          cb null, accel.id
    async.series sends, (err, result) ->
      if err
        log 3, "series error: " + err
      log 3, "series result: " + result
, aggInterval


require('dns').lookup require('os').hostname(), (err, add, fam) ->
  console.log('ip: '+add)

portNum = 3344
log 0, "listening on #{portNum}"
http.listen(portNum)
