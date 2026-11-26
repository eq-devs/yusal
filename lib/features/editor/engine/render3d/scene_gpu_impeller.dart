import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:yusal/features/editor/engine/render3d/scene_gpu.dart';
import 'package:yusal/features/editor/engine/render3d/scene_gpu_frame.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart'
    show Vec3;
import 'package:yusal/features/editor/engine/render3d/textures.dart';

const _bundle = 'build/shaderbundles/scene.shaderbundle';

/// The Flutter GPU renderer, or null where Flutter GPU does not run: it
/// needs the Impeller engine, which older Android phones do not use.
Future<SceneGpu?> createSceneGpu() async {
  final gpu.GpuContext context;
  try {
    context = gpu.gpuContext;
  } catch (_) {
    return null;
  }
  final library = await gpu.ShaderLibrary.fromAsset(_bundle);
  final vertex = library?['SceneVertex'];
  final fragment = library?['SceneFragment'];
  if (vertex == null || fragment == null) return null;
  final depthVertex = library?['DepthVertex'];
  final depthFragment = library?['DepthFragment'];
  final renderer = _ImpellerScene(
      context,
      context.createRenderPipeline(vertex, fragment),
      depthVertex == null || depthFragment == null
          ? null
          : context.createRenderPipeline(depthVertex, depthFragment));
  // The textiles, copied to the GPU once: there are few and they are small.
  for (final textile in Textile.values) {
    for (var variant = 0; variant < 3; variant++) {
      final image = textileImage(textile, variant);
      final bytes = await image.toByteData();
      if (bytes == null) continue;
      renderer.textiles[image] = context.createTexture(
          gpu.StorageMode.hostVisible, image.width, image.height,
          enableRenderTargetUsage: false)
        ..overwrite(bytes);
    }
  }
  // A first, tiny frame: a device that cannot draw says so here rather
  // than in front of the user.
  renderer
      .draw(GpuFrame(Float32List(16)..[0] = 1, const [], const [], 0), 4, 4)
      .dispose();
  if (renderer.depthPipeline != null) {
    try {
      await renderer.tryShadows();
    } catch (_) {
      renderer.mapsUp = 0;
    }
  }
  return renderer;
}

class _ImpellerScene extends SceneGpu {
  _ImpellerScene(this.context, this.pipeline, this.depthPipeline)
      : frameInfo = pipeline.vertexShader.getUniformSlot('FrameInfo'),
        textile = pipeline.fragmentShader.getUniformSlot('textile'),
        shadowMap = pipeline.fragmentShader.getUniformSlot('shadow_map'),
        depthMap = pipeline.fragmentShader.getUniformSlot('depth_map'),
        lightInfo = pipeline.fragmentShader.getUniformSlot('LightInfo'),
        depthInfo = depthPipeline?.vertexShader.getUniformSlot('DepthInfo'),
        host = context.createHostBuffer(),
        white = context.createTexture(gpu.StorageMode.hostVisible, 1, 1,
            enableRenderTargetUsage: false) {
    white.overwrite(
        ByteData.sublistView(Uint8List.fromList(const [255, 255, 255, 255])));
    samples = context.doesSupportOffscreenMSAA ? 4 : 1;
  }

  final gpu.GpuContext context;
  final gpu.RenderPipeline pipeline;
  final gpu.UniformSlot frameInfo;
  final gpu.UniformSlot textile;
  final gpu.UniformSlot shadowMap;
  final gpu.UniformSlot depthMap;
  final gpu.UniformSlot lightInfo;

  /// Draws distances: from the sun for shadows, from the eye for corners.
  final gpu.RenderPipeline? depthPipeline;
  final gpu.UniformSlot? depthInfo;

  /// Which way up a picture drawn here reads back in a shader: 1, -1, or
  /// 0 while unknown, and for good where the trial of it failed.
  double mapsUp = 0;

  @override
  bool get shades => mapsUp != 0;

  gpu.Texture? sunMap;
  gpu.Texture? sunDepth;
  String? sunKey;
  Float32List? sunSolids;
  gpu.Texture? eyeMap;
  gpu.Texture? eyeDepth;

  static final _nearest = gpu.SamplerOptions();

  /// A square receiver with a caster over its upper half, lit from the
  /// eye: the half that comes out dark says which way up a map reads, and
  /// neither dark says shadows do not work here.
  Future<void> tryShadows() async {
    final m = Float32List(16)
      ..[0] = 1
      ..[5] = 1
      ..[10] = -0.25
      ..[14] = 0.5
      ..[15] = 1;
    final v = Float32List(gpuVertexFloats * 6);
    final solids = <double>[];
    var at = 0;
    for (final (x, y) in const [
      (-1, -1),
      (1, -1),
      (1, 1),
      (-1, -1),
      (1, 1),
      (-1, 1)
    ]) {
      v[at] = x.toDouble();
      v[at + 1] = y.toDouble();
      v[at + 3] = v[at + 4] = v[at + 5] = v[at + 6] = 1;
      v[at + 7] = v[at + 8] = 0.5;
      v[at + 11] = 1;
      v[at + 12] = 0.9;
      v[at + 13] = x.toDouble();
      v[at + 14] = y.toDouble();
      at += gpuVertexFloats;
      solids.addAll([x.toDouble(), y.toDouble(), 0]);
    }
    for (final (x, y) in const [
      (-1, 0),
      (1, 0),
      (1, 1),
      (-1, 0),
      (1, 1),
      (-1, 1)
    ]) {
      solids.addAll([x.toDouble(), y.toDouble(), 1]);
    }
    final row = Float32List.fromList(const [0, 0, -0.25, 0.5]);
    mapsUp = 1;
    final image = draw(
        GpuFrame(
            m,
            [GpuBatch(v, 6)],
            const [],
            1,
            const [],
            null,
            GpuEffects(
                Float32List.fromList(solids),
                12,
                m,
                'trial',
                1,
                0,
                0.01,
                m,
                row,
                1,
                const Vec3(0, 0, -1),
                const Vec3(1, 0, 0),
                const Vec3(0, 1, 0),
                1,
                1),
            const Vec3(0, 0, 4)),
        16,
        16);
    final bytes = await image.toByteData();
    sunKey = null;
    if (bytes == null) {
      mapsUp = 0;
      return;
    }
    int red(int x, int y) => bytes.getUint8((y * 16 + x) * 4);
    final top = red(8, 3);
    final bottom = red(8, 12);
    mapsUp = top + 60 < bottom ? 1 : (bottom + 60 < top ? -1 : 0);
  }

  gpu.Texture _map(int width, int height) =>
      context.createTexture(gpu.StorageMode.hostVisible, width, height);

  gpu.Texture _mapDepth(int width, int height) =>
      context.createTexture(gpu.StorageMode.deviceTransient, width, height,
          format: context.defaultDepthStencilFormat,
          enableShaderReadUsage: false);

  /// The solids' distances, drawn with [matrix] onto [colour].
  ///
  /// In commands of its own: a second pass in the frame's commands brings
  /// the engine down.
  void _distances(gpu.Texture colour, gpu.Texture depth, GpuEffects e,
      Float32List matrix, Float32List row) {
    final commands = context.createCommandBuffer();
    final pass = commands.createRenderPass(gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: colour, clearValue: vm.Vector4.all(1)),
        depthStencilAttachment:
            gpu.DepthStencilAttachment(texture: depth, depthClearValue: 1)));
    final info = Float32List(20)
      ..setAll(0, matrix)
      ..setAll(16, row);
    pass
      ..bindPipeline(depthPipeline!)
      ..setDepthCompareOperation(gpu.CompareFunction.lessEqual)
      ..setDepthWriteEnable(true)
      ..setColorBlendEnable(false)
      ..bindVertexBuffer(host.emplace(ByteData.sublistView(e.solids)))
      ..bindUniform(depthInfo!, host.emplace(ByteData.sublistView(info)))
      ..draw(e.count);
    commands.submit();
  }

  final gpu.HostBuffer host;
  final gpu.Texture white;
  late int samples;

  gpu.GpuImageSurface? surface;
  gpu.Texture? depth;
  gpu.Texture? multisample;

  /// The textiles on the GPU, by the image they were copied from.
  final textiles = Expando<gpu.Texture>('textile');

  /// A textile that was not copied is drawn as its plain tint.
  gpu.Texture textureOf(ui.Image? image) =>
      image == null ? white : textiles[image] ?? white;

  void resize(int width, int height) {
    final s = surface;
    if (s != null && s.width == width && s.height == height) return;
    surface = context.createImageSurface(width, height,
        format: gpu.PixelFormat.r8g8b8a8UNormInt);
    depth = context.createTexture(
        gpu.StorageMode.deviceTransient, width, height,
        format: context.defaultDepthStencilFormat,
        sampleCount: samples,
        enableShaderReadUsage: false);
    multisample = samples == 1
        ? null
        : context.createTexture(gpu.StorageMode.deviceTransient, width, height,
            sampleCount: samples, enableShaderReadUsage: false);
  }

  @override
  ui.Image draw(GpuFrame frame, int width, int height) {
    resize(width, height);
    final target = surface!.acquireNextFrame();
    final msaa = multisample;
    try {
      final commands = context.createCommandBuffer();
      host.reset();
      final e = mapsUp == 0 || depthPipeline == null ? null : frame.effects;
      final light = Float32List(40);
      if (e != null) {
        if (e.sun > 0 &&
            (sunKey != e.lightKey || !identical(sunSolids, e.solids))) {
          sunMap ??= _map(gpuShadowMapSize, gpuShadowMapSize);
          sunDepth ??= _mapDepth(gpuShadowMapSize, gpuShadowMapSize);
          _distances(
              sunMap!,
              sunDepth!,
              e,
              e.light,
              Float32List.fromList(
                  [e.light[2], e.light[6], e.light[10], e.light[14]]));
          sunKey = e.lightKey;
          sunSolids = e.solids;
        }
        if (e.corners > 0) {
          // Half the size is plenty for what is a soft darkening.
          final w = (width / 2).ceil();
          final h = (height / 2).ceil();
          if (eyeMap?.width != w || eyeMap?.height != h) {
            eyeMap = _map(w, h);
            eyeDepth = _mapDepth(w, h);
          }
          _distances(eyeMap!, eyeDepth!, e, e.camera, e.cameraRow);
        }
        final eye = frame.eye!;
        light
          ..setAll(0, e.light)
          ..setAll(16, [eye.x, eye.y, eye.z, e.far])
          ..setAll(20, [e.forward.x, e.forward.y, e.forward.z, e.corners])
          ..setAll(24, [e.right.x, e.right.y, e.right.z, e.sx])
          ..setAll(28, [e.up.x, e.up.y, e.up.z, e.sy])
          ..setAll(32, [e.sun, 1 / gpuShadowMapSize, mapsUp, e.bias])
          ..setAll(36, [gpuCornerReach, 0, 0, 0]);
      }
      final lightView = host.emplace(ByteData.sublistView(light));
      final sun = e != null && e.sun > 0 ? sunMap! : white;
      final corners = e != null && e.corners > 0 ? eyeMap! : white;
      final pass = commands.createRenderPass(gpu.RenderTarget.singleColor(
          msaa == null
              ? gpu.ColorAttachment(
                  texture: target.colorTexture, clearValue: vm.Vector4.zero())
              : gpu.ColorAttachment(
                  texture: msaa,
                  resolveTexture: target.colorTexture,
                  storeAction: gpu.StoreAction.multisampleResolve,
                  clearValue: vm.Vector4.zero()),
          depthStencilAttachment:
              gpu.DepthStencilAttachment(texture: depth!, depthClearValue: 1)));
      final camera = host.emplace(ByteData.sublistView(frame.mvp));
      void batches(List<GpuBatch> list) {
        for (final b in list) {
          if (b.count == 0) continue;
          pass
            ..clearBindings()
            ..bindVertexBuffer(host.emplace(ByteData.sublistView(b.vertices)))
            ..bindUniform(frameInfo, camera)
            ..bindUniform(lightInfo, lightView)
            ..bindTexture(shadowMap, sun, sampler: _nearest)
            ..bindTexture(depthMap, corners, sampler: _nearest)
            ..bindTexture(textile, textureOf(b.image),
                sampler: gpu.SamplerOptions(
                    minFilter: gpu.MinMagFilter.linear,
                    magFilter: gpu.MinMagFilter.linear,
                    widthAddressMode: b.tiled
                        ? gpu.SamplerAddressMode.repeat
                        : gpu.SamplerAddressMode.clampToEdge,
                    heightAddressMode: b.tiled
                        ? gpu.SamplerAddressMode.repeat
                        : gpu.SamplerAddressMode.clampToEdge))
            ..draw(b.count);
        }
      }

      pass
        ..bindPipeline(pipeline)
        ..setDepthCompareOperation(gpu.CompareFunction.lessEqual)
        ..setDepthWriteEnable(true)
        ..setColorBlendEnable(false);
      batches(frame.opaque);
      // Glass and the like: over what is behind, hidden by what is in
      // front, and not hiding each other.
      pass
        ..setDepthWriteEnable(false)
        ..setColorBlendEnable(true)
        // Colours arrive with alpha multiplied in, which is what the
        // default equation blends: source + destination × (1 − alpha).
        ..setColorBlendEquation(gpu.ColorBlendEquation());
      // The edges lie on the faces they outline: drawn after every solid
      // face, so each is hidden only by what is truly in front of it.
      final edges = frame.edges;
      if (edges != null) batches([edges]);
      batches(frame.translucent);
      target.present(commands);
      commands.submit();
    } catch (_) {
      target.discard();
      rethrow;
    }
    return surface!.currentImage!;
  }
}
