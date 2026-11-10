/// Static resource proof, not an Android emulator or physical-device capture.
/// Run from app/: `dart run tool/android_icons_proof.dart <output-directory>`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_launcher_icons/config/config.dart';
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

const res = 'android/app/src/main/res';
const android = 'http://schemas.android.com/apk/res/android';
const densities = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

img.Image png(String path) => img.decodePng(File(path).readAsBytesSync())!;
XmlDocument xml(String path) =>
    XmlDocument.parse(File(path).readAsStringSync());
String? attr(XmlElement node, String name) =>
    node.getAttribute(name, namespaceUri: android);

void branded(img.Image actual, img.Image source, int size, String path) {
  require(
    actual.width == size && actual.height == size,
    '$path: expected ${size}x$size',
  );
  // Independent expected pixels from the accepted source, not a golden copied
  // from generated output. The locked generator uses area-average downsampling.
  final expected = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  final a = actual.getBytes(order: img.ChannelOrder.rgba);
  final b = expected.getBytes(order: img.ChannelOrder.rgba);
  require(a.length == b.length, '$path: pixel count');
  for (var i = 0; i < a.length; i++) {
    require(a[i] == b[i], '$path: not the expected Pickteams pixels (byte $i)');
  }
}

img.Image insetLayer(img.Image source, int percent) {
  final size = source.width;
  final margin = (size * percent / 100).round();
  final layer = img.Image(width: size, height: size, numChannels: 4);
  img.compositeImage(
    layer,
    img.copyResize(
      source,
      width: size - 2 * margin,
      height: size - 2 * margin,
      interpolation: img.Interpolation.average,
    ),
    dstX: margin,
    dstY: margin,
  );
  return layer;
}

void safeMark(img.Image layer, String density) {
  final center = layer.width / 2;
  // Android guarantees a centered 66dp circle on the 108dp layer. Test every
  // nontransparent pixel, including antialiased edges, not only the two people.
  final radius = layer.width * 33 / 108;
  var pixels = 0;
  for (final p in layer) {
    if (p.a == 0) continue;
    pixels++;
    final dx = (p.x + 0.5 - center).abs() + 0.5;
    final dy = (p.y + 0.5 - center).abs() + 0.5;
    require(
      dx * dx + dy * dy <= radius * radius,
      '$density: mark outside Android safe circle at ${p.x},${p.y}',
    );
  }
  require(pixels > 0, '$density: empty foreground');
}

img.Image masked(img.Image layer, int power) {
  final size = layer.width;
  final result = img.Image(width: size, height: size, numChannels: 4);
  // Static resting viewport: 72dp of the 108dp layer. Squircle uses x^4+y^4.
  final radius = size / 3;
  final background = img.Image(width: size, height: size, numChannels: 4);
  img.fill(background, color: img.ColorRgba8(46, 44, 41, 255));
  img.compositeImage(background, layer);
  for (final p in result) {
    final x = (p.x + 0.5 - size / 2) / radius;
    final y = (p.y + 0.5 - size / 2) / radius;
    if (math.pow(x.abs(), power) + math.pow(y.abs(), power) <= 1) {
      final color = background.getPixel(p.x, p.y);
      p.set(color);
    }
  }
  final margin = (size / 6).round();
  return img.copyCrop(
    result,
    x: margin,
    y: margin,
    width: size - 2 * margin,
    height: size - 2 * margin,
  );
}

void main(List<String> args) {
  require(
    args.length == 1,
    'Usage: dart run tool/android_icons_proof.dart <output-directory>',
  );
  final output = Directory(args.single)..createSync(recursive: true);
  final config = Config.loadConfigFromPath(
    'flutter_launcher_icons_android.yaml',
    '.',
  )!;
  require(
    config.android == true &&
        config.ios == false &&
        config.webConfig?.generate != true &&
        config.windowsConfig?.generate != true &&
        config.macOSConfig?.generate != true,
    'Configuration must generate Android only',
  );
  require(
    config.imagePathAndroid == 'assets/icons/app_icon.png' &&
        config.adaptiveIconForeground == 'assets/icons/app_icon_2.png',
    'Use existing Pickteams assets',
  );
  require(
    config.adaptiveIconBackground == '#2E2C29',
    'Use existing brand background',
  );
  final manifest = xml('android/app/src/main/AndroidManifest.xml');
  require(
    attr(manifest.findAllElements('application').single, 'icon') ==
        '@mipmap/ic_launcher',
    'Application must resolve @mipmap/ic_launcher',
  );
  final adaptive = xml('$res/mipmap-anydpi-v26/ic_launcher.xml');
  require(
    adaptive.rootElement.name.local == 'adaptive-icon',
    'Adaptive resource root',
  );
  require(
    attr(adaptive.findAllElements('background').single, 'drawable') ==
        '@color/ic_launcher_background',
    'Adaptive background reference',
  );
  final foreground = adaptive
      .findAllElements('foreground')
      .single
      .findElements('inset')
      .single;
  require(
    attr(foreground, 'drawable') == '@drawable/ic_launcher_foreground',
    'Adaptive foreground reference',
  );
  require(
    attr(foreground, 'inset') == '${config.adaptiveIconForegroundInset}%',
    'Inset must match generator configuration',
  );
  final color = xml('$res/values/colors.xml')
      .findAllElements('color')
      .singleWhere((e) => e.getAttribute('name') == 'ic_launcher_background');
  require(
    color.innerText.toUpperCase() == '#2E2C29',
    'Background resource must match configuration',
  );

  final source = png('assets/icons/app_icon.png');
  final transparent = png('assets/icons/app_icon_2.png');
  final sheet = img.Image(width: 780, height: 1110);
  img.fill(sheet, color: img.ColorRgb8(235, 235, 235));
  void label(String text, int x, int y) => img.drawString(
    sheet,
    text,
    font: img.arial14,
    x: x,
    y: y,
    color: img.ColorRgb8(20, 20, 20),
  );
  label('STATIC RESOURCE PREVIEW - not a device screenshot', 20, 12);
  label('Density / ordinary', 20, 42);
  label('Adaptive circle', 280, 42);
  label('Adaptive squircle', 540, 42);
  final results = <Map<String, Object>>[];
  var row = 0;
  for (final entry in densities.entries) {
    final density = entry.key;
    final size = entry.value;
    final foregroundSize = size * 108 ~/ 48;
    final ordinaryPath = '$res/mipmap-$density/ic_launcher.png';
    final foregroundPath = '$res/drawable-$density/ic_launcher_foreground.png';
    final ordinary = png(ordinaryPath);
    final generated = png(foregroundPath);
    branded(ordinary, source, size, ordinaryPath);
    branded(generated, transparent, foregroundSize, foregroundPath);
    final layer = insetLayer(generated, config.adaptiveIconForegroundInset);
    safeMark(layer, density);
    final circle = masked(layer, 2);
    final squircle = masked(layer, 4);
    for (final item in {'circle': circle, 'squircle': squircle}.entries) {
      File(
        '${output.path}/$density-${item.key}.png',
      ).writeAsBytesSync(img.encodePng(item.value));
    }
    final y = 80 + row * 200;
    label('$density: $size / $foregroundSize px', 20, y);
    for (final item in [ordinary, circle, squircle].indexed) {
      img.compositeImage(
        sheet,
        img.copyResize(item.$2, width: 156, height: 156),
        dstX: 20 + item.$1 * 260,
        dstY: y + 25,
      );
    }
    results.add({
      'density': density,
      'ordinaryPixels': size,
      'foregroundPixels': foregroundSize,
      'brandingPixelMatch': true,
      'allAlphaInside66dpSafeCircle': true,
    });
    stdout.writeln(
      'PASS $density: ${size}x$size ordinary, ${foregroundSize}x$foregroundSize foreground, exact branding, complete mark in safe circle',
    );
    row++;
  }
  label(
    'Real generated PNGs + XML inset. Static 72dp viewport; not OEM launcher proof.',
    20,
    1085,
  );
  File(
    '${output.path}/launcher-masks.png',
  ).writeAsBytesSync(img.encodePng(sheet));
  File('${output.path}/resources.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'kind': 'static generated-resource proof; not device capture', 'insetPercent': config.adaptiveIconForegroundInset, 'applicationIcon': '@mipmap/ic_launcher', 'densities': results})}\n',
  );
  stdout.writeln(
    'PASS Android-only configuration and manifest/adaptive/color references',
  );
  stdout.writeln('Preview: ${output.path}/launcher-masks.png');
}
