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
app.use(express.static('public'))


serial = new serialport.SerialPort "/dev/tty.usbmodem1421",
        parser: serialport.parsers.readline "\n"
        baudrate: 9600
serial.isconnected = false
aggInterval = 250

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
    @avg = x: @x/@count, y: @y/@count, z: @z/@count
    @x = @y = @z = @count = 0
    @avg
  send: (ms, callback) ->
    sendCmd @id, @avg.x, ms, callback

map = (x, in_min, in_max, out_min, out_max)=>
  x = (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min
  if (x < out_min)
    out_min
  else if (x > out_max)
    out_max
  else
    x

sendCmd = (servo, val, ms, callback) ->
    angle = map val, -5, 5, 45, 135
    cmd = "S" + pad(Math.floor(servo), 2) + pad(Math.floor(angle), 3) + pad(Math.floor(ms), 4)
    console.log("Sending cmd: " + cmd)
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
  console.log "client " + @phoneDatas[socket].id + " connected"

  socket.on "boogy_data", (data) =>
    @phoneDatas[socket].add(data)

serial.on 'open', () =>
  console.log 'serial open'

  serial.on 'data', (data) =>
    console.log "  Received: " + data
    serial.isconnected = true

  serial.on 'error', (err) ->
    console.error "serial error: " + err

setInterval =>
  pds = (pd for sock,pd in @phoneDatas)

  aggs = (pd.agg() for pd in pds)
  aggs = (agg for agg in aggs when agg.x)
  if aggs.length
    allx = (agg.x for agg in aggs).reduce (a,b) -> a+b
    ally = (agg.y for agg in aggs).reduce (a,b) -> a+b
    allz = (agg.z for agg in aggs).reduce (a,b) -> a+b
    all = { x: allx/aggs.length, y: ally/aggs.length, z: allz/aggs.length }
    io.emit 'agg_data', all

    sends = []
    for pd in pds
      sends.push (cb) ->
        pd.send 200
        cb null, pd.id
    if all.x
      sends.unshift (cb) ->
        sendCmd 0, all.x, 100
        cb null, 0
    async.series sends#, (err, result) ->
        #console.log "series error: " + err
        #console.log "series result: " + result
, aggInterval

portNum = 3344
console.log "listening on #{portNum}"
http.listen(portNum)
