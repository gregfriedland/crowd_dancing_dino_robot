accelInterval = 50

class accel
  start:=>
    console.log("starting accel sensing")

    window.addEventListener 'devicemotion', (data)=>
      @processEvent(data)
    , false

  processEvent:(data)=>
    alpha = data.alpha
    beta  = data.beta
    gamma = data.gamma
    data =  {x: data.acceleration.x, y: data.acceleration.y,  z: data.acceleration.z}

    for f in @callbacks
      f(data)

  onMove:(func)=>
    @callbacks ||= []
    @callbacks.push func

class reporter
  start:=>
    @socket = io()
    @ad_callbacks = []
    @socket.on "agg_data",(ad) =>
      #console.log "agg_data ", ad
      for callback in @ad_callbacks
        callback(ad)

  report_data:(data)=>
    @socket.emit("boogy_data",data )

  add_agg_callback:(cb)=>
    @ad_callbacks.push cb

class barXYZViz
  constructor:(id, parent)->
    @id = id

    html =  "<div id=bars#{@id}><h2>id: #{@id}</h2>"
    html += "<div class='slide_cont' id='xViz'><div class='slider'></div></div>"
    html += "<div class='slide_cont' id='yViz'><div class='slider'></div></div>"
    html += "<div class='slide_cont' id='zViz'><div class='slider'></div></div>"
    html += "</div>"
    $(parent).append(html)

  update:(data)=>
    data = {x:data.x+50, y:data.y+50, z:data.z+50}
    #console.log $("#bars#{@id} #xViz .slider")
    #console.log "To " + JSON.stringify(data)
    $("#bars#{@id} #xViz .slider").css("left", "#{data.x}%")
    $("#bars#{@id} #yViz .slider").css("left", "#{data.y}%")
    $("#bars#{@id} #zViz .slider").css("left", "#{data.z}%")


a = new accel()
r = new reporter()
r.start()
a.start()

r.add_agg_callback (datas) =>
  for data in datas
    if !@vizs[data.id]
      @vizs[data.id] = new barXYZViz(data.id, "#othersdata")
    @vizs[data.id].update(data)

$(document).ready =>
  @vizs = {}
  @vizs[-1] = new barXYZViz(-1, "#selfdata")
  @vizs[0]  = new barXYZViz(0, "#aggdata")
  @lastUpdateTime = 0
  console.log "ready"

  a.onMove (data) =>
    currTime = new Date().getTime()
    if currTime > @lastUpdateTime + accelInterval
      @vizs[-1].update(data)
      r.report_data data
      @lastUpdateTime = currTime
