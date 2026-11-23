import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:yusal/features/editor/engine/render3d/scene_gpu.dart';
import 'package:yusal/features/editor/engine/render3d/scene_gpu_frame.dart';
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
  final renderer =
      _ImpellerScene(context, context.createRenderPipeline(vertex, fragment));
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
  return renderer;
}

class _ImpellerScene extends SceneGpu {
  _ImpellerScene(this.context, this.pipeline)
      : frameInfo = pipeline.vertexShader.getUniformSlot('FrameInfo'),
        textile = pipeline.fragmentShader.getUniformSlot('textile'),
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
      host.reset();
      final camera = host.emplace(ByteData.sublistView(frame.mvp));
      void batches(List<GpuBatch> list) {
        for (final b in list) {
          if (b.count == 0) continue;
          pass
            ..clearBindings()
            ..bindVertexBuffer(host.emplace(ByteData.sublistView(b.vertices)))
            ..bindUniform(frameInfo, camera)
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
