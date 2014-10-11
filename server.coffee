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
        baudrate: 9600
serial.isconnected = false
aggInterval = 100


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
    #console.log "boogy data: " + JSON.stringify(data)
    @phoneDatas[socket].add(data)

serial.on 'open', () =>
  console.log 'serial open'

  serial.on 'data', (data) =>
    console.log "  Received: " + data
    serial.isconnected = true

  serial.on 'error', (err) ->
    console.error "serial error: " + err

setInterval =>
  pds = (pd for sock,pd of @phoneDatas)
  #console.log "phoneDatas: " + JSON.stringify(pds)

  (pd.agg() for pd in pds)
  pds = (pd for pd in pds when pd.aggdata.x)
  accels = (pd.aggdata for p in pds)
  if pds.length
    avgx = stats.mean(accel.x for accel in accels)
    avgy = stats.mean(accel.y for accel in accels)
    avgz = stats.mean(accel.z for accel in accels)
    avgs = { x: avgx, y: avgy, z: avgz, id: 0 }
    accels.push(avgs)

    # send all agg data to each client
    console.log "Sending agg_data: " + JSON.stringify(accels)
    io.emit 'agg_data', accels

    sends = []
    for accel in accels
      do (accel) ->
        sends.push (cb) =>
          #console.log "sending: " + JSON.stringify(accel)
          sendCmd accel.id, accel.x, 200
          cb null, accel.id
    async.series sends#, (err, result) ->
        #console.log "series error: " + err
        #console.log "series result: " + result
, aggInterval

portNum = 3344
console.log "listening on #{portNum}"
http.listen(portNum)
