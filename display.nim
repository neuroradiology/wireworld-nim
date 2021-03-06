import sdl2
import wireworld
import times

const
  TileSize = 10
  MinTicksPerSecond = 1
  MaxTicksPerSecond = 60
  WindowSize = WorldSize * TileSize
  BottomBarHeight = 1
  black: Color = (0'u8, 0'u8, 0'u8, 255'u8)
  green: Color = (0'u8, 255'u8, 0'u8, 255'u8)
  red: Color = (255'u8, 0'u8, 0'u8, 255'u8)

var TicksPerSecond = 10

proc clampSpeedChange(speed, delta: int): int =
  if speed + delta < 1:
    result = MinTicksPerSecond
  elif speed + delta > MaxTicksPerSecond:
    result = MaxTicksPerSecond
  else:
    result = speed + delta

type SDLException = object of Exception

type
  Input {.pure.} = enum
    none, reset, exit,
    groundmode, wiremode, headmode, tailmode,
    place,
    pauseplay,
    speedup, speeddown

  DrawMode = enum
    GroundMode,
    WireMode,
    HeadMode,
    TailMode

  Game = ref object
    inputs: array[Input, bool]
    mx, my: int
    tx, ty: int
    renderer: RendererPtr
    world: World
    drawmode: DrawMode
    paused: bool
    dirty: seq[bool]

proc newGame(renderer: RendererPtr): Game =
  new result

  result.world = newWorld()

  newSeq(result.dirty, WorldSize * WorldSize)
  for x in 0..<WorldSize:
    for y in 0..<WorldSize:
      result.dirty.get(x, y) = true

  result.drawmode = WireMode

  result.paused = false

  result.renderer = renderer

proc color(tile: State): Color =
  case tile:
    of ground:
      (r: 28'u8, g: 20'u8, b: 14'u8, a: 255'u8)
    of wire:
      (r: 234'u8, g: 225'u8, b: 93'u8, a: 255'u8)
    of head:
      (r: 43'u8, g: 145'u8, b: 255'u8, a: 255'u8)
    of tail:
      (r: 255'u8, g: 57'u8, b: 43'u8, a: 255'u8)

proc screenToWorld(x, y: int): tuple[x, y: int] = (x div TileSize, y div TileSize)

proc keyToInput(key: Scancode): Input =
  case key:
    of SDL_SCANCODE_Q: Input.exit
    of SDL_SCANCODE_A: Input.groundmode
    of SDL_SCANCODE_S: Input.wiremode
    of SDL_SCANCODE_D: Input.headmode
    of SDL_SCANCODE_F: Input.tailmode
    of SDL_SCANCODE_R: Input.reset
    of SDL_SCANCODE_P: Input.pauseplay
    of SDL_SCANCODE_UP: Input.speedup
    of SDL_SCANCODE_DOWN: Input.speeddown
    else: Input.none

proc handleInput(game: Game) =
  var event = defaultEvent
  while pollEvent(event):
    case event.kind:
      of QuitEvent:
        game.inputs[Input.exit] = true
      of KeyDown:
        game.inputs[event.key.keysym.scancode.keyToInput] = true
      of KeyUp:
        game.inputs[event.key.keysym.scancode.keyToInput] = false
      of MouseMotion:
        game.mx = event.motion.x
        game.my = event.motion.y

        let tile = screenToWorld(game.mx, game.my)
        game.tx = tile.x
        game.ty = tile.y

      of MouseButtonDown:
        if event.button.button == BUTTON_LMASK:
          game.inputs[Input.place] = true
      of MouseButtonUp:
        if event.button.button == BUTTON_LMASK:
          game.inputs[Input.place] = false
      else:
        discard

proc processKeys(game: var Game) =
  if game.inputs[Input.pauseplay]:
    game.paused = not game.paused
    return
  elif game.inputs[Input.speedup]:
    TicksPerSecond = TicksPerSecond.clampSpeedChange(1)
    return
  elif game.inputs[Input.speeddown]:
    TicksPerSecond = TicksPerSecond.clampSpeedChange(-1)
    return
  elif game.inputs[Input.groundmode]:
    game.drawmode = GroundMode
    return
  elif game.inputs[Input.wiremode]:
    game.drawmode = WireMode
    return
  elif game.inputs[Input.headmode]:
    game.drawmode = HeadMode
    return
  elif game.inputs[Input.tailmode]:
    game.drawmode = TailMode
    return
  elif game.inputs[Input.reset]:
    game = newGame(game.renderer)
    return

proc drawState(game: Game): State =
  case game.drawmode:
    of GroundMode: ground
    of WireMode: wire
    of HeadMode: head
    of TailMode: tail

proc processClicks(game: var Game) =
  if game.inputs[Input.place]:
    game.world.get(game.tx, game.ty) = game.drawState

template sdlFailIf(cond: typed, reason: string) =
  if cond:
    raise SDLException.newException(reason & ", SDLError: " & $getError())

proc renderTile(game: Game, x, y: int) =
  let
    tileState = game.world.get(x, y)
    tileColor = tileState.color
  var tileRect: Rect = (x: cint(x * TileSize), y: cint(y * TileSize), w: cint(TileSize), h: cint(TileSize))

  # Draw the tile background
  game.renderer.setDrawColor(tileColor)
  game.renderer.fillRect(tileRect)
  # Draw the outline
  game.renderer.setDrawColor(black)
  game.renderer.drawRect(tileRect)

proc renderDrawMode(game: Game) =
  let
    x = 0
    y = WorldSize
    width = WorldSize div 2

  var barRect: Rect = (x: cint(x * TileSize),
                       y: cint(y * TileSize),
                       w: cint(width * TileSize),
                       h: cint(BottomBarHeight * TileSize))

  game.renderer.setDrawColor(game.drawState.color)
  game.renderer.fillRect(barRect)


proc renderPauseState(game: Game) =
  let
    x = WorldSize div 2
    y = WorldSize
    width = WorldSize div 2
    color = case game.paused:
              of true: red
              of false: green
  var barRect: Rect = (x: cint(x * TileSize),
                       y: cint(y * TileSize),
                       w: cint(width * TileSize),
                       h: cint(BottomBarHeight * TileSize))

  game.renderer.setDrawColor(color)
  game.renderer.fillRect(barRect)

proc renderBottomBar(game: Game) =
  game.renderDrawMode
  game.renderPauseState

proc renderWorld(game: Game) =
  for x in 0..<WorldSize:
    for y in 0..<WorldSize:
      game.renderTile(x, y)

proc render(game: Game) =
  game.renderer.clear
  game.renderWorld
  game.renderBottomBar
  game.renderer.present

proc processWorld(game: Game) = game.world.process

proc main =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed."

  # Gets called at the end of the proc even if an exception has been thrown
  defer: sdl2.quit()

  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALTITY", "2")):
    "Linear texture filtering could not be enabled."

  let window = createWindow(title = "Wireworld",
                            x = SDL_WINDOWPOS_CENTERED,
                            y = SDL_WINDOWPOS_CENTERED,
                            w = WindowSize, h = WindowSize + BottomBarHeight * TileSize,
                                flags = SDL_WINDOW_SHOWN)

  sdlFailIf window.isNil: "Window could not be created."
  defer: window.destroy()

  let renderer = window.createRenderer(index = -1,
                                       flags = Renderer_Accelerated or Renderer_PresentVsync)

  sdlFailIf renderer.isNil: "Renderer could not be created."

  # Setting the default color
  renderer.setDrawColor(ground.color)

  var
    startTime = epochTime()
    lastTick = 0
    game = newGame(renderer)

  # Game Loop
  while not game.inputs[Input.exit]:
    game.render()
    game.handleInput()
    game.processKeys()
    game.processClicks()
    let newTick = int((epochTime() - startTime) * float(TicksPerSecond))
    if not game.paused:
      for tick in lastTick+1 .. newTick:
        game.processWorld()
    lastTick = newTick

if isMainModule:
  main()
