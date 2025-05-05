import 'package:flutter/material.dart';
import 'package:flutter_in_app_pip/pip_params.dart';
import 'dart:ui' show lerpDouble;
import 'package:shared_preferences/shared_preferences.dart';

class MovableOverlay extends StatefulWidget {
  final PiPParams pipParams;
  final bool avoidKeyboard;
  final Widget? topWidget;
  final Widget? bottomWidget;
  final void Function()? onTapTopWidget;

  const MovableOverlay({
    Key? key,
    this.avoidKeyboard = true,
    this.topWidget,
    this.bottomWidget,
    this.onTapTopWidget,
    this.pipParams = const PiPParams(),
  }) : super(key: key);

  @override
  MovableOverlayState createState() => MovableOverlayState();
}

class MovableOverlayState extends State<MovableOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _toggleFloatingAnimationController;
  late final AnimationController _dragAnimationController;

  /// Offset padrão inicial (10% da largura a partir da direita, 20% da altura acima do bottom)
  late Offset _defaultOffset;

  /// Offset salvo da última posição do PiP
  Offset? _positionOffset;

  /// Offset temporário durante o drag
  Offset _dragOffset = Offset.zero;

  bool _isDragging = false;
  bool _isFloating = false;
  Widget? _bottomWidgetGhost;
  Widget? bottomChild;

  double _scaleFactor = 1.0;
  double _baseScaleFactor = 1.0;

  final defaultAnimationDuration = const Duration(milliseconds: 0);

  // *** variáveis para armazenar último tamanho
  late Size _lastFullSize;
  late Size _lastPipSize;

  @override
  void initState() {
    super.initState();

    _toggleFloatingAnimationController = AnimationController(
      duration: defaultAnimationDuration,
      vsync: this,
    )..value = 1.0;

    _dragAnimationController = AnimationController(
      duration: defaultAnimationDuration,
      vsync: this,
    );

    bottomChild = widget.bottomWidget;
    _loadSavedPosition();
  }

  Future<void> _loadSavedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble('pip_position_x');
    final dy = prefs.getDouble('pip_position_y');
    if (dx != null && dy != null) {
      setState(() {
        _positionOffset = Offset(dx, dy);
      });
    }
  }

  Future<void> _savePosition() async {
    if (_positionOffset == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pip_position_x', _positionOffset!.dx);
    await prefs.setDouble('pip_position_y', _positionOffset!.dy);
  }

  @override
  void didUpdateWidget(covariant MovableOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isFloating) {
      _scaleFactor = 1;
      if (widget.topWidget == null || bottomChild == null) {
        _isFloating = false;
        _bottomWidgetGhost = oldWidget.bottomWidget;
        _toggleFloatingAnimationController.reverse().whenComplete(() {
          if (mounted) setState(() => _bottomWidgetGhost = null);
        });
      }
    } else {
      if (widget.topWidget != null && bottomChild != null) {
        _isFloating = true;
        _toggleFloatingAnimationController.forward();
      }
    }
  }

  bool _isAnimating() =>
      _toggleFloatingAnimationController.isAnimating ||
      _dragAnimationController.isAnimating;

  void _onPanStart(ScaleStartDetails details) {
    if (_isAnimating()) return;
    setState(() {
      _dragOffset = _positionOffset ?? _defaultOffset;
      _isDragging = true;
    });
  }

  void _onPanUpdate(ScaleUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      // traduz
      var newOffset = _dragOffset.translate(
        details.focalPointDelta.dx,
        details.focalPointDelta.dy,
      );
      // *** clamp usando os tamanhos armazenados
      final maxDx = _lastFullSize.width - _lastPipSize.width;
      final maxDy = _lastFullSize.height - _lastPipSize.height;
      newOffset = Offset(
        newOffset.dx.clamp(0.0, maxDx),
        newOffset.dy.clamp(0.0, maxDy),
      );
      _dragOffset = newOffset;
    });
  }

  void _onPanEnd(ScaleEndDetails details) {
    if (!_isDragging) return;
    // já está confinado, mas reforça o clamp
    setState(() {
      final maxDx = _lastFullSize.width - _lastPipSize.width;
      final maxDy = _lastFullSize.height - _lastPipSize.height;
      final clamped = Offset(
        _dragOffset.dx.clamp(0.0, maxDx),
        _dragOffset.dy.clamp(0.0, maxDy),
      );
      _positionOffset = clamped;
      _isDragging = false;
    });
    _savePosition();
    _dragAnimationController.forward().whenComplete(() {
      _dragAnimationController.value = 0;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (widget.pipParams.movable) _onPanStart(details);
    if (widget.pipParams.resizable) _baseScaleFactor = _scaleFactor;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (widget.pipParams.movable) _onPanUpdate(details);
    if (!widget.pipParams.resizable || details.scale == 1.0) return;
    final newW =
        details.scale * _baseScaleFactor * widget.pipParams.pipWindowWidth;
    final newH =
        details.scale * _baseScaleFactor * widget.pipParams.pipWindowHeight;
    if (newW < widget.pipParams.minSize.width ||
        newW > widget.pipParams.maxSize.width ||
        newH < widget.pipParams.minSize.height ||
        newH > widget.pipParams.maxSize.height) {
      return;
    }
    setState(() {
      _scaleFactor = _baseScaleFactor * details.scale;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (widget.pipParams.movable) _onPanEnd(details);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    var windowPadding = mq.padding;
    if (widget.avoidKeyboard) windowPadding += mq.viewInsets;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomWidget = bottomChild ?? _bottomWidgetGhost;
        final fullSize = Size(constraints.maxWidth, constraints.maxHeight);
        final pipSize = Size(
          widget.topWidget != null
              ? widget.pipParams.pipWindowWidth * _scaleFactor
              : 0,
          widget.topWidget != null
              ? widget.pipParams.pipWindowHeight * _scaleFactor
              : 0,
        );

        // *** armazena para uso no clamp
        _lastFullSize = fullSize;
        _lastPipSize = pipSize;

        // Offset padrão
        _defaultOffset = Offset(
          fullSize.width * 0.9 - pipSize.width,
          fullSize.height * 0.8 - pipSize.height,
        );

        return Stack(
          children: [
            if (bottomWidget != null) Center(child: bottomWidget),
            if (widget.topWidget != null)
              AnimatedBuilder(
                animation: Listenable.merge([
                  _toggleFloatingAnimationController,
                  _dragAnimationController,
                ]),
                builder: (context, child) {
                  final tToggle = CurvedAnimation(
                    parent: _toggleFloatingAnimationController,
                    curve: Curves.easeInOutQuad,
                  ).value;

                  // rawOffset antes de clamp
                  final rawOffset =
                      _isDragging ? _dragOffset : (_positionOffset ?? _defaultOffset);

                  // *** clamp visual também (segurança)
                  final maxDx = fullSize.width - pipSize.width;
                  final maxDy = fullSize.height - pipSize.height;
                  final offset = Offset(
                    rawOffset.dx.clamp(0.0, maxDx),
                    rawOffset.dy.clamp(0.0, maxDy),
                  );

                  final w = lerpDouble(
                    fullSize.width,
                    pipSize.width,
                    tToggle,
                  )!;
                  final h = lerpDouble(
                    fullSize.height,
                    pipSize.height,
                    tToggle,
                  )!;

                  return Positioned(
                    left: offset.dx,
                    top: offset.dy,
                    child: GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      onTap: widget.onTapTopWidget,
                      child: SizedBox(width: w, height: h, child: child),
                    ),
                  );
                },
                child: widget.topWidget,
              ),
          ],
        );
      },
    );
  }
}
