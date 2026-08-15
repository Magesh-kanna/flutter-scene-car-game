// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

// ============================================================================
// GAME ENUMS & CONFIGURATION
// ============================================================================

/// High-level game states
enum GameState { menu, playing, paused, gameOver }

/// 3 Subway Surfers Track Lanes:
/// In 3D space looking towards -Z:
/// +X is Screen Left (+2.2), 0.0 is Center, -X is Screen Right (-2.2).
enum Lane {
  left(2.2),
  center(0.0),
  right(-2.2);

  final double x;
  const Lane(this.x);
}

// ============================================================================
// ENTITY WRAPPERS (Always-in-Scene Slot System for Maximum Performance)
// ============================================================================

/// An obstacle slot in the pre-warmed 3D scene pool.
class ObstacleSlot {
  final Node node;
  final String type;
  vm.Vector3 pos;
  double hitRadius;
  double oncomingSpeed;
  bool active;

  ObstacleSlot({
    required this.node,
    required this.type,
    vm.Vector3? pos,
    this.hitRadius = 1.0,
    this.oncomingSpeed = 0.0,
    this.active = false,
  }) : pos = pos ?? vm.Vector3(0, -200, 0);

  /// Parks this obstacle far underground so it is completely invisible.
  void park() {
    active = false;
    pos = vm.Vector3(0, -200, 0);
    node.localTransform = vm.Matrix4.identity()..setTranslationRaw(0, -200, 0);
  }
}

/// A collectible coin slot in the pre-warmed 3D scene pool.
class CoinSlot {
  final Node node;
  vm.Vector3 pos;
  double spinAngle;
  bool active;

  CoinSlot({
    required this.node,
    vm.Vector3? pos,
    this.spinAngle = 0.0,
    this.active = false,
  }) : pos = pos ?? vm.Vector3(0, -200, 0);

  /// Parks this coin far underground so it is completely invisible.
  void park() {
    active = false;
    pos = vm.Vector3(0, -200, 0);
    node.localTransform = vm.Matrix4.identity()..setTranslationRaw(0, -200, 0);
  }
}

/// A road segment tile.
class RoadSegment {
  final Node node;
  vm.Vector3 pos;
  RoadSegment({required this.node, required this.pos});
}

/// A roadside street lamp.
class StreetLamp {
  final Node node;
  vm.Vector3 pos;
  final double rotY;
  StreetLamp({required this.node, required this.pos, required this.rotY});
}

// ============================================================================
// MAIN APPLICATION ENTRY POINT
// ============================================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  print('[Boot] Starting Turbo Car Runner 3D with Impeller & Flutter Scene...');
  runApp(const CarRunnerApp());
}

class CarRunnerApp extends StatelessWidget {
  const CarRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Turbo Car Runner 3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF04060C),
        primaryColor: Colors.amber,
      ),
      home: const GameScreen(),
    );
  }
}

// ============================================================================
// MAIN GAME SCREEN (3D Viewport + Responsive Layout + Gestures / Buttons)
// ============================================================================
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  // 3D Scene Graph
  final Scene _scene = Scene();
  Node? _playerCarNode;

  // Pools
  final List<ObstacleSlot> _obstacleSlots = [];
  final List<CoinSlot> _coinSlots = [];
  final List<RoadSegment> _roadSegments = [];
  final List<StreetLamp> _streetLamps = [];

  // Road Dimensions (32 tiles × 4.0 units = 128.0 units span)
  static const int _tileCount = 32;
  static const double _tileLength = 4.0;
  static const double _roadWidth = 8.0; // Wide highway covering 3 lanes + shoulders
  static const double _totalRoadSpan = _tileCount * _tileLength;

  // Gameplay State
  GameState _gameState = GameState.menu;
  bool _isEngineReady = false;
  String _loadingMessage = 'Booting 3D Graphics Engine...';

  // Player movement
  Lane _currentLane = Lane.center;
  double _playerCurrentX = 0.0;
  double _playerTargetX = 0.0;
  double _playerTiltAngle = 0.0;
  double _playerY = 0.0;
  double _verticalVelocity = 0.0;
  bool _isJumping = false;
  static const double _playerZ = -2.0; // Fixed player Z anchor

  // Physics constants
  static const double _gravity = -0.016;
  static const double _jumpForce = 0.30;

  // Speed & Scoring
  double _worldSpeed = 0.40;
  double _distanceTraveled = 0.0;
  int _score = 0;
  int _coinsCollected = 0;
  int _highScore = 0;

  // Continuous Spawner Distance Counters
  double _distanceUntilNextObstacle = 10.0; // Initial gap before 1st obstacle
  double _distanceUntilNextCoin = 5.0;      // Initial gap before 1st coin cluster
  final math.Random _random = math.Random();
  late Ticker _gameLoopTicker;
  late final FocusNode _focusNode;

  // 3D Model Asset Paths
  static const Map<String, String> _obstacleModelPaths = {
    'truck': 'assets/kenney_car-kit/Models/GLB format/truck.glb',
    'police': 'assets/kenney_car-kit/Models/GLB format/police.glb',
    'taxi': 'assets/kenney_car-kit/Models/GLB format/taxi.glb',
    'delivery': 'assets/kenney_car-kit/Models/GLB format/delivery.glb',
    'cone': 'assets/kenney_car-kit/Models/GLB format/cone.glb',
    'box': 'assets/kenney_car-kit/Models/GLB format/box.glb',
  };

  static const Set<String> _trafficVehicleTypes = {'truck', 'police', 'taxi', 'delivery'};

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _gameLoopTicker = createTicker(_onGameTick);
    _initialize3DGame();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _gameLoopTicker.dispose();
    super.dispose();
  }

  // ==========================================================================
  // 3D INITIALIZATION & OBJECT POOL PRE-WARMING
  // ==========================================================================
  Future<void> _initialize3DGame() async {
    try {
      setState(() => _loadingMessage = 'Configuring Impeller GPU Pipeline...');
      await Scene.initializeStaticResources();
      print('[3D Loader] Static GPU pipelines initialized.');

      setState(() => _loadingMessage = 'Loading 3D Cars, Highway & Assets...');

      // 1. Lighting Setup (Bright Sunlight + Studio Map)
      _scene.directionalLight = DirectionalLight(
        direction: vm.Vector3(0.5, -1.0, -0.6).normalized(),
        color: vm.Vector3(1.0, 0.98, 0.92),
        intensity: 1.25,
        castsShadow: true,
      );
      _scene.environment = EnvironmentMap.studio();
      _scene.environmentIntensity = 0.85;

      // 2. Load Player Car (Red Sports Racer)
      _playerCarNode = await Node.fromGlbAsset(
        'assets/kenney_car-kit/Models/GLB format/race.glb',
      );
      _scene.add(_playerCarNode!);
      print('[3D Loader] Player car loaded.');

      // 3. Pre-load Obstacle Slots (3 instances per type = 18 slots total)
      for (final entry in _obstacleModelPaths.entries) {
        for (int i = 0; i < 3; i++) {
          final node = await Node.fromGlbAsset(entry.value);
          node.localTransform = vm.Matrix4.identity()..setTranslationRaw(0, -200, 0);
          _scene.add(node);
          _obstacleSlots.add(ObstacleSlot(node: node, type: entry.key));
        }
      }
      print('[3D Loader] ${_obstacleSlots.length} obstacle slots pre-loaded.');

      // 4. Pre-load Coin Slots (18 coins total = 6 clusters of 3)
      for (int i = 0; i < 18; i++) {
        final node = await Node.fromGlbAsset(
          'assets/kenney_car-kit/Models/GLB format/debris-nut.glb',
        );
        node.localTransform = vm.Matrix4.identity()..setTranslationRaw(0, -200, 0);
        _scene.add(node);
        _coinSlots.add(CoinSlot(node: node));
      }
      print('[3D Loader] ${_coinSlots.length} coin slots pre-loaded.');

      // 5. Build Seamless 3D Continuous Highway
      print('[3D Loader] Building 3D Highway ($_tileCount segments)...');
      for (int i = 0; i < _tileCount; i++) {
        final double zPos = 12.0 - (i * _tileLength);
        final roadNode = await Node.fromGlbAsset(
          'assets/kenney_city-kit-roads/Models/GLB format/road-straight.glb',
        );
        final pos = vm.Vector3(0.0, 0.0, zPos);

        roadNode.localTransform = vm.Matrix4.identity()
          ..setTranslationRaw(pos.x, pos.y, pos.z)
          ..scaleByVector3(vm.Vector3(_roadWidth, 1.0, _tileLength))
          ..rotateY(math.pi * 0.5);

        _scene.add(roadNode);
        _roadSegments.add(RoadSegment(node: roadNode, pos: pos));

        // Place street lamps every 3 tiles along both sides
        if (i % 3 == 0) {
          // Left lamp
          final leftLampNode = await Node.fromGlbAsset(
            'assets/kenney_city-kit-roads/Models/GLB format/light-curved.glb',
          );
          final leftLampPos = vm.Vector3(4.5, 0.0, zPos);
          leftLampNode.localTransform = vm.Matrix4.identity()
            ..setTranslationRaw(leftLampPos.x, leftLampPos.y, leftLampPos.z)
            ..rotateY(-math.pi * 0.5)
            ..scaleByVector3(vm.Vector3(1.8, 1.8, 1.8));
          _scene.add(leftLampNode);
          _streetLamps.add(StreetLamp(node: leftLampNode, pos: leftLampPos, rotY: -math.pi * 0.5));

          // Right lamp
          final rightLampNode = await Node.fromGlbAsset(
            'assets/kenney_city-kit-roads/Models/GLB format/light-curved.glb',
          );
          final rightLampPos = vm.Vector3(-4.5, 0.0, zPos);
          rightLampNode.localTransform = vm.Matrix4.identity()
            ..setTranslationRaw(rightLampPos.x, rightLampPos.y, rightLampPos.z)
            ..rotateY(math.pi * 0.5)
            ..scaleByVector3(vm.Vector3(1.8, 1.8, 1.8));
          _scene.add(rightLampNode);
          _streetLamps.add(StreetLamp(node: rightLampNode, pos: rightLampPos, rotY: math.pi * 0.5));
        }
      }

      _updatePlayerTransform();

      setState(() {
        _isEngineReady = true;
        _gameState = GameState.menu;
      });
      print('[3D Loader] All assets loaded! Ready to race.');
    } catch (e, st) {
      print('[3D Loader Error] $e\n$st');
      setState(() => _loadingMessage = 'Error loading assets: $e');
    }
  }

  // ==========================================================================
  // GAMEPLAY LIFECYCLE
  // ==========================================================================
  void _startGame() {
    print('[Game] === STARTING NEW RACE ===');
    for (final slot in _obstacleSlots) {
      slot.park();
    }
    for (final slot in _coinSlots) {
      slot.park();
    }

    _currentLane = Lane.center;
    _playerTargetX = 0.0;
    _playerCurrentX = 0.0;
    _playerY = 0.0;
    _verticalVelocity = 0.0;
    _isJumping = false;
    _playerTiltAngle = 0.0;

    _worldSpeed = 0.40;
    _distanceTraveled = 0.0;
    _score = 0;
    _coinsCollected = 0;
    _distanceUntilNextObstacle = 12.0; // First obstacle arrives shortly
    _distanceUntilNextCoin = 6.0;

    _updatePlayerTransform();
    setState(() => _gameState = GameState.playing);
    _gameLoopTicker.start();
  }

  void _triggerGameOver(String obstacleType) {
    print('[Crash] Hit $obstacleType at ${_distanceTraveled.toStringAsFixed(0)}m! Final Score: $_score');
    _gameLoopTicker.stop();
    if (_score > _highScore) {
      _highScore = _score;
    }
    setState(() => _gameState = GameState.gameOver);
  }

  void _togglePause() {
    if (_gameState == GameState.playing) {
      _gameLoopTicker.stop();
      setState(() => _gameState = GameState.paused);
    } else if (_gameState == GameState.paused) {
      _gameLoopTicker.start();
      setState(() => _gameState = GameState.playing);
    }
  }

  // ==========================================================================
  // INPUT HANDLING (Lanes, Jump, Quick Drop)
  // ==========================================================================
  void _moveLeft() {
    if (_gameState != GameState.playing) return;
    if (_currentLane == Lane.right) {
      _currentLane = Lane.center;
      _playerTargetX = Lane.center.x;
      _playerTiltAngle = 0.22;
    } else if (_currentLane == Lane.center) {
      _currentLane = Lane.left;
      _playerTargetX = Lane.left.x;
      _playerTiltAngle = 0.32;
    }
  }

  void _moveRight() {
    if (_gameState != GameState.playing) return;
    if (_currentLane == Lane.left) {
      _currentLane = Lane.center;
      _playerTargetX = Lane.center.x;
      _playerTiltAngle = -0.22;
    } else if (_currentLane == Lane.center) {
      _currentLane = Lane.right;
      _playerTargetX = Lane.right.x;
      _playerTiltAngle = -0.32;
    }
  }

  void _jump() {
    if (_gameState != GameState.playing) return;
    if (!_isJumping && _playerY <= 0.02) {
      _isJumping = true;
      _verticalVelocity = _jumpForce;
    }
  }

  void _quickDrop() {
    if (_gameState != GameState.playing || !_isJumping) return;
    _verticalVelocity = -0.30;
  }

  // ==========================================================================
  // 60-FPS GAME LOOP TICK (100% Synchronous, Zero Async Overhead)
  // ==========================================================================
  void _onGameTick(Duration elapsed) {
    if (_gameState != GameState.playing) return;

    // 1. Distance & Score
    _distanceTraveled += _worldSpeed * 0.5;
    _score = _distanceTraveled.toInt() + (_coinsCollected * 25);
    if (_worldSpeed < 0.85) {
      _worldSpeed += 0.00004; // Gradually ramp up speed
    }

    // 2. Smooth Lateral Lane Interpolation (Lerp) & Tilt Return
    _playerCurrentX += (_playerTargetX - _playerCurrentX) * 0.25;
    _playerTiltAngle *= 0.82;

    // 3. Vertical Jump & Gravity Physics
    if (_isJumping || _playerY > 0.0) {
      _playerY += _verticalVelocity;
      _verticalVelocity += _gravity;
      if (_playerY <= 0.0) {
        _playerY = 0.0;
        _verticalVelocity = 0.0;
        _isJumping = false;
      }
    }

    // 4. Update Player 3D Transform
    _updatePlayerTransform();

    // 5. Scroll & Seamlessly Recycle Highway & Lamps
    _updateHighway();

    // 6. Continuous Spawning for Obstacles & Coins
    _spawnTrackEntities();

    // 7. Move Obstacles & Check Fatal Collisions
    _updateObstacles();

    // 8. Move Coins & Check Pickups
    _updateCoins();

    // 9. Rebuild HUD
    if (mounted) setState(() {});
  }

  void _updatePlayerTransform() {
    if (_playerCarNode == null) return;
    _playerCarNode!.localTransform = vm.Matrix4.identity()
      ..setTranslationRaw(_playerCurrentX, _playerY, _playerZ)
      ..rotateY(math.pi) // Face forwards down the road towards -Z
      ..rotateZ(_playerTiltAngle);
  }

  void _updateHighway() {
    // 1. Scroll Road Segments
    for (final segment in _roadSegments) {
      segment.pos.z += _worldSpeed;
      if (segment.pos.z > 16.0) {
        segment.pos.z -= _totalRoadSpan;
      }
      segment.node.localTransform = vm.Matrix4.identity()
        ..setTranslationRaw(segment.pos.x, segment.pos.y, segment.pos.z)
        ..scaleByVector3(vm.Vector3(_roadWidth, 1.0, _tileLength))
        ..rotateY(math.pi * 0.5);
    }

    // 2. Scroll Street Lamps
    for (final lamp in _streetLamps) {
      lamp.pos.z += _worldSpeed;
      if (lamp.pos.z > 16.0) {
        lamp.pos.z -= _totalRoadSpan;
      }
      lamp.node.localTransform = vm.Matrix4.identity()
        ..setTranslationRaw(lamp.pos.x, lamp.pos.y, lamp.pos.z)
        ..rotateY(lamp.rotY)
        ..scaleByVector3(vm.Vector3(1.8, 1.8, 1.8));
    }
  }

  // ==========================================================================
  // CONTINUOUS SPAWNING SYSTEM (Distance-Interval Driven)
  // ==========================================================================
  void _spawnTrackEntities() {
    // 1. Obstacle Spawning Interval
    _distanceUntilNextObstacle -= _worldSpeed;
    if (_distanceUntilNextObstacle <= 0.0) {
      final lanes = Lane.values;
      final chosenLane = lanes[_random.nextInt(lanes.length)];
      final types = _obstacleModelPaths.keys.toList();
      final chosenType = types[_random.nextInt(types.length)];
      final bool isVehicle = _trafficVehicleTypes.contains(chosenType);

      // Find an inactive slot of this type
      final slot = _obstacleSlots.where((s) => !s.active && s.type == chosenType).firstOrNull;
      if (slot != null) {
        slot.active = true;
        const double spawnDepthZ = -70.0; // Spawn far on the horizon
        slot.pos = vm.Vector3(chosenLane.x, 0.0, spawnDepthZ);
        slot.hitRadius = isVehicle ? 1.3 : 0.7;
        slot.oncomingSpeed = isVehicle ? 0.15 : 0.0; // Oncoming traffic drives towards player

        final scale = isVehicle ? 1.0 : 1.4;
        final rotY = isVehicle ? 0.0 : math.pi;

        slot.node.localTransform = vm.Matrix4.identity()
          ..setTranslationRaw(slot.pos.x, slot.pos.y, slot.pos.z)
          ..rotateY(rotY)
          ..scaleByVector3(vm.Vector3(scale, scale, scale));

        print('[Spawner] Spawned $chosenType in ${chosenLane.name.toUpperCase()} lane at Z = $spawnDepthZ');
      }

      // Reset distance to next obstacle (18m to 32m interval for constant action!)
      _distanceUntilNextObstacle = 18.0 + _random.nextDouble() * 14.0;
    }

    // 2. Coin Cluster Spawning Interval (3 coins in a line)
    _distanceUntilNextCoin -= _worldSpeed;
    if (_distanceUntilNextCoin <= 0.0) {
      final lanes = Lane.values;
      final coinLane = lanes[_random.nextInt(lanes.length)];
      const double coinSpawnZ = -60.0;

      for (int i = 0; i < 3; i++) {
        final slot = _coinSlots.where((s) => !s.active).firstOrNull;
        if (slot == null) break;

        slot.active = true;
        slot.spinAngle = 0.0;
        slot.pos = vm.Vector3(coinLane.x, 0.7, coinSpawnZ - (i * 3.2));

        slot.node.localTransform = vm.Matrix4.identity()
          ..setTranslationRaw(slot.pos.x, slot.pos.y, slot.pos.z)
          ..scaleByVector3(vm.Vector3(2.2, 2.2, 2.2));
      }

      print('[Spawner] Spawned coin cluster in ${coinLane.name.toUpperCase()} lane at Z = $coinSpawnZ');
      _distanceUntilNextCoin = 22.0 + _random.nextDouble() * 16.0;
    }
  }

  // ==========================================================================
  // ENTITY UPDATES & COLLISION DETECTION
  // ==========================================================================
  void _updateObstacles() {
    for (final slot in _obstacleSlots) {
      if (!slot.active) continue;

      // Move toward player (positive Z)
      slot.pos.z += (_worldSpeed + slot.oncomingSpeed);

      final bool isVehicle = _trafficVehicleTypes.contains(slot.type);
      final double scale = isVehicle ? 1.0 : 1.4;
      final double rotY = isVehicle ? 0.0 : math.pi;

      slot.node.localTransform = vm.Matrix4.identity()
        ..setTranslationRaw(slot.pos.x, slot.pos.y, slot.pos.z)
        ..rotateY(rotY)
        ..scaleByVector3(vm.Vector3(scale, scale, scale));

      // Check collision with player
      final double deltaX = (slot.pos.x - _playerCurrentX).abs();
      final double deltaZ = (slot.pos.z - _playerZ).abs();

      const double playerLength = 1.8;
      const double playerWidth = 0.9;

      if (deltaZ < playerLength && deltaX < (playerWidth + slot.hitRadius * 0.45)) {
        final bool isLowObstacle = (slot.type == 'cone' || slot.type == 'box');
        if (isLowObstacle && _playerY > 0.85) {
          // Successfully jumped over low obstacle!
        } else {
          _triggerGameOver(slot.type);
          return;
        }
      }

      // Passed behind camera -> Park
      if (slot.pos.z > 14.0) {
        slot.park();
      }
    }
  }

  void _updateCoins() {
    for (final slot in _coinSlots) {
      if (!slot.active) continue;

      slot.pos.z += _worldSpeed;
      slot.spinAngle += 0.08;

      slot.node.localTransform = vm.Matrix4.identity()
        ..setTranslationRaw(slot.pos.x, slot.pos.y, slot.pos.z)
        ..rotateY(slot.spinAngle)
        ..scaleByVector3(vm.Vector3(2.2, 2.2, 2.2));

      // Check pickup collision
      final double deltaX = (slot.pos.x - _playerCurrentX).abs();
      final double deltaZ = (slot.pos.z - _playerZ).abs();
      final double deltaY = (_playerY - slot.pos.y).abs();

      if (deltaZ < 1.3 && deltaX < 1.0 && deltaY < 1.3) {
        _coinsCollected++;
        _score += 50;
        print('[Pickup] Gold collected! Coins: $_coinsCollected, Score: $_score');
        slot.park();
        continue;
      }

      if (slot.pos.z > 12.0) {
        slot.park();
      }
    }
  }

  // ==========================================================================
  // RESPONSIVE WIDGET BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    if (!_isEngineReady) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: Colors.amber,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  _loadingMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final double screenHeight = constraints.maxHeight;
        final bool isPortrait = screenHeight > screenWidth;
        final double aspect = screenWidth / (screenHeight > 0 ? screenHeight : 1.0);
        final bool isNarrow = screenWidth < 420;
        final bool isShortHeight = screenHeight < 520;
        final bool isDesktopLayout = screenWidth >= 600 && !isShortHeight;

        // Dynamic 3D Camera Perspective positioned so the player car is completely visible
        final double camZ = isPortrait
            ? (5.2 + (0.75 - aspect.clamp(0.35, 0.75)) * 2.4)
            : 4.8;
        final double camY = isPortrait ? 3.6 : 3.0;
        final double camTargetY = isPortrait ? 0.8 : 0.5;

        return Scaffold(
          body: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (e) {
              if (e is! KeyDownEvent) return;
              final k = e.logicalKey;
              if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
                _moveLeft();
              } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
                _moveRight();
              } else if (k == LogicalKeyboardKey.arrowUp ||
                  k == LogicalKeyboardKey.space ||
                  k == LogicalKeyboardKey.keyW) {
                _jump();
              } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
                _quickDrop();
              } else if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP) {
                _togglePause();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _focusNode.requestFocus(),
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -120) _moveLeft();
                if (v > 120) _moveRight();
              },
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -120) _jump();
                if (v > 120) _quickDrop();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Sky Background Image from assets
                  Positioned.fill(
                    child: Image.asset(
                      'assets/sky.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),

                  // 3D Scene Viewport with dynamic aspect-ratio camera
                  SceneView(
                    _scene,
                    camera: PerspectiveCamera(
                      position: vm.Vector3(_playerCurrentX * 0.18, camY, camZ),
                      target: vm.Vector3(_playerCurrentX * 0.18, camTargetY, -22.0),
                    ),
                  ),

                  // Responsive In-Game HUD
                  if (_gameState == GameState.playing || _gameState == GameState.paused)
                    _buildResponsiveHUD(screenWidth, isNarrow, isShortHeight),

                  // Responsive On-Screen Controls during gameplay
                  if (_gameState == GameState.playing)
                    isDesktopLayout
                        ? _buildDesktopControlButtons()
                        : _buildMobileControlButtons(isNarrow, isShortHeight),

                  // Start Menu Overlay
                  if (_gameState == GameState.menu)
                    _buildMenuOverlay(screenWidth, screenHeight, isNarrow, isShortHeight, isPortrait),

                  // Game Paused Overlay
                  if (_gameState == GameState.paused)
                    _buildPausedOverlay(screenWidth, screenHeight, isNarrow, isShortHeight),

                  // Game Over Overlay
                  if (_gameState == GameState.gameOver)
                    _buildGameOverOverlay(screenWidth, screenHeight, isNarrow, isShortHeight),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // RESPONSIVE 2D UI OVERLAYS & CONTROLS
  // ==========================================================================

  Widget _buildResponsiveHUD(double screenWidth, bool isNarrow, bool isShortHeight) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 10 : 18,
            vertical: isShortHeight ? 4 : 8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Score & Distance Stats Pill
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isNarrow ? 10 : 16,
                      vertical: isNarrow ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speed, color: Colors.amber, size: 18),
                        const SizedBox(width: 5),
                        Text(
                          '${_distanceTraveled.toInt()}m',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isNarrow ? 13 : 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: isNarrow ? 8 : 14),
                        const Icon(Icons.monetization_on, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '$_coinsCollected',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: isNarrow ? 13 : 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: isNarrow ? 8 : 14),
                        const Icon(Icons.stars, color: Colors.orangeAccent, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '$_score',
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: isNarrow ? 13 : 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_highScore > 0 && screenWidth > 500) ...[
                          const SizedBox(width: 14),
                          const Icon(Icons.emoji_events, color: Colors.yellowAccent, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            'BEST: $_highScore',
                            style: const TextStyle(
                              color: Colors.yellowAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Pause / Play Button
              IconButton(
                icon: Icon(
                  _gameState == GameState.paused ? Icons.play_arrow : Icons.pause,
                  color: Colors.white,
                  size: isNarrow ? 22 : 26,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.75),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: EdgeInsets.all(isNarrow ? 8 : 10),
                ),
                onPressed: _togglePause,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ergonomic mobile touch controls (Left/Right & Jump/Drop buttons)
  Widget _buildMobileControlButtons(bool isNarrow, bool isShortHeight) {
    final double buttonSize = isShortHeight ? 44 : (isNarrow ? 52 : 58);
    final double iconSize = isShortHeight ? 22 : (isNarrow ? 26 : 30);

    return Positioned(
      bottom: isShortHeight ? 10 : 18,
      left: 12,
      right: 12,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Directional Controls (Left & Right)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTouchButton(
                    icon: Icons.arrow_back,
                    size: buttonSize,
                    iconSize: iconSize,
                    color: Colors.white.withValues(alpha: 0.85),
                    bgColor: Colors.white.withValues(alpha: 0.18),
                    onPressed: _moveLeft,
                  ),
                  const SizedBox(width: 6),
                  _buildTouchButton(
                    icon: Icons.arrow_forward,
                    size: buttonSize,
                    iconSize: iconSize,
                    color: Colors.white.withValues(alpha: 0.85),
                    bgColor: Colors.white.withValues(alpha: 0.18),
                    onPressed: _moveRight,
                  ),
                ],
              ),
            ),

            // Action Controls (Jump & Drop)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTouchButton(
                    icon: Icons.arrow_downward,
                    size: buttonSize,
                    iconSize: iconSize,
                    color: Colors.white70,
                    bgColor: Colors.white.withValues(alpha: 0.18),
                    onPressed: _quickDrop,
                  ),
                  const SizedBox(width: 6),
                  _buildTouchButton(
                    icon: Icons.arrow_upward,
                    size: buttonSize,
                    iconSize: iconSize,
                    color: Colors.black,
                    bgColor: Colors.amber,
                    onPressed: _jump,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTouchButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required Color color,
    required Color bgColor,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      ),
    );
  }

  /// Desktop / Tablet On-Screen Control Buttons with Keyboard Shortcut Indicators
  Widget _buildDesktopControlButtons() {
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _moveLeft,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text(
                      'LEFT [A]',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _jump,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      elevation: 6,
                    ),
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    label: const Text(
                      'JUMP [SPACE]',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _quickDrop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text(
                      'DROP [S]',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _moveRight,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text(
                      'RIGHT [D]',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuOverlay(
    double screenWidth,
    double screenHeight,
    bool isNarrow,
    bool isShortHeight,
    bool isPortrait,
  ) {
    final double titleFontSize = isShortHeight ? 24 : (isNarrow ? 26 : 34);
    final double iconSize = isShortHeight ? 48 : (isNarrow ? 64 : 84);

    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 16 : 24,
              vertical: isShortHeight ? 12 : 20,
            ),
            child: isShortHeight && !isPortrait
                // Compact 2-column layout for short landscape mode
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left Column: Branding & Play Button
                      Flexible(
                        flex: 5,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.directions_car_filled, color: Colors.amber, size: iconSize),
                            const SizedBox(height: 6),
                            Text(
                              'TURBO CAR RUNNER',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            if (_highScore > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'BEST SCORE: $_highScore',
                                style: const TextStyle(
                                  color: Colors.yellowAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _startGame,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              icon: const Icon(Icons.play_arrow, size: 24),
                              label: const Text(
                                'START RACE',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),

                      // Right Column: How to play
                      Flexible(
                        flex: 6,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '🎮 CONTROLS & HOW TO PLAY',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text('• Tap / A-D / Swipe: Switch Lanes',
                                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                              SizedBox(height: 4),
                              Text('• Jump / Space / Swipe Up: Jump over Obstacles',
                                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                              SizedBox(height: 4),
                              Text('• Drop / S / Swipe Down: Quick Ground Drop',
                                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                              SizedBox(height: 6),
                              Text('⚡ Dodge oncoming traffic & collect gold nuts!',
                                  style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                // Standard Portrait / Full Screen Layout
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_car_filled,
                        color: Colors.amber,
                        size: iconSize,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'TURBO CAR RUNNER',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '3D Highway Runner • Impeller & Flutter Scene',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: isNarrow ? 12 : 14,
                        ),
                      ),
                      if (_highScore > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            '🏆 BEST SCORE: $_highScore',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(isNarrow ? 14 : 20),
                        constraints: const BoxConstraints(maxWidth: 460),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              '🎮 HOW TO PLAY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text('◀ ▶  Swipe / Tap Buttons or A / D keys to switch lanes',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 6),
                            const Text('▲  Swipe Up / Tap Jump / SPACE to Jump',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 6),
                            const Text('▼  Swipe Down / Tap Drop / S to Quick Drop',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 10),
                            const Text(
                              '⚡ Dodge oncoming traffic & collect gold nuts!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.amberAccent, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _startGame,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(
                            horizontal: isNarrow ? 36 : 48,
                            vertical: isNarrow ? 14 : 18,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 10,
                        ),
                        icon: const Icon(Icons.play_arrow, size: 28),
                        label: Text(
                          'START RACE',
                          style: TextStyle(
                            fontSize: isNarrow ? 18 : 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPausedOverlay(
    double screenWidth,
    double screenHeight,
    bool isNarrow,
    bool isShortHeight,
  ) {
    return Container(
      color: Colors.black.withValues(alpha: 0.80),
      child: Center(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.pause_circle_filled,
                  color: Colors.amber,
                  size: isShortHeight ? 48 : (isNarrow ? 64 : 80),
                ),
                const SizedBox(height: 10),
                Text(
                  'PAUSED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isShortHeight ? 26 : (isNarrow ? 30 : 38),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Distance: ${_distanceTraveled.toInt()}m   •   Score: $_score',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _togglePause,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 24 : 32,
                          vertical: isNarrow ? 12 : 16,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('RESUME', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 14),
                    OutlinedButton.icon(
                      onPressed: _startGame,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 20 : 28,
                          vertical: isNarrow ? 12 : 16,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      icon: const Icon(Icons.replay),
                      label: const Text('RESTART'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay(
    double screenWidth,
    double screenHeight,
    bool isNarrow,
    bool isShortHeight,
  ) {
    final bool isNewRecord = _score >= _highScore && _score > 0;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 16 : 24,
              vertical: isShortHeight ? 12 : 20,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.car_crash,
                  color: Colors.redAccent,
                  size: isShortHeight ? 48 : (isNarrow ? 64 : 84),
                ),
                const SizedBox(height: 8),
                Text(
                  'CRASHED!',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: isShortHeight ? 26 : (isNarrow ? 30 : 38),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(isNarrow ? 16 : 24),
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isNewRecord ? Colors.amberAccent : Colors.white24,
                      width: isNewRecord ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (isNewRecord) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events, color: Colors.yellowAccent, size: 16),
                              SizedBox(width: 5),
                              Text(
                                'NEW HIGH SCORE!',
                                style: TextStyle(
                                  color: Colors.yellowAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        'DISTANCE: ${_distanceTraveled.toInt()} m',
                        style: TextStyle(color: Colors.white70, fontSize: isNarrow ? 14 : 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'GOLD NUTS: $_coinsCollected',
                        style: TextStyle(color: Colors.amberAccent, fontSize: isNarrow ? 14 : 16),
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 6),
                      Text(
                        'SCORE: $_score',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: isNarrow ? 24 : 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'BEST: $_highScore',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(
                      horizontal: isNarrow ? 36 : 48,
                      vertical: isNarrow ? 14 : 18,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 10,
                  ),
                  icon: const Icon(Icons.replay, size: 26),
                  label: Text(
                    'RACE AGAIN',
                    style: TextStyle(
                      fontSize: isNarrow ? 17 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCENEVIEW CUSTOM WIDGET FOR FLUTTER SCENE 0.16.0
// ============================================================================
class SceneView extends StatelessWidget {
  final Scene scene;
  final Camera camera;

  const SceneView(this.scene, {super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScenePainter(scene: scene, camera: camera),
      size: Size.infinite,
    );
  }
}

class _ScenePainter extends CustomPainter {
  final Scene scene;
  final Camera camera;

  _ScenePainter({required this.scene, required this.camera});

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Rect.fromLTWH(0, 0, size.width, size.height));
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true;
}
