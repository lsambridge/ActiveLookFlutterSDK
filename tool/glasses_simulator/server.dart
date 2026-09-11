// ignore_for_file: avoid_print
import 'dart:io';

/// Standalone dev-tool server for the ActiveLook glasses simulator.
///
/// Serves `viewer.html` over HTTP and relays messages both ways between the
/// app's `FakeActivelookSdk` WebSocket (`lib/src/activelook_sdk_fake.dart`)
/// and any connected browser tab(s) showing that page:
/// - app -> viewers: every JSON draw command, rendered on the viewer's
///   Canvas.
/// - viewer -> app: currently just the "Double tap" button's
///   `{"event": "sensorTap"}` message, which `FakeActivelookSdk.connect`
///   turns back into a `sensorTapNotifications` event app-side - simulating
///   the glasses' capacitive touch button without hardware.
///
/// This process does no interpretation of message contents itself - it's
/// just static hosting + a two-way relay; the browser does the actual
/// Canvas rendering and the app does the actual state changes.
///
/// Usage: `dart run tool/glasses_simulator/server.dart`
/// Then open http://localhost:8787 in a browser, and run the app with the
/// fake-glasses flag on (see docs/glasses-simulator.md).
Future<void> main(List<String> args) async {
  const port = 8787;
  final viewerHtml = File('${Directory.current.path}/tool/glasses_simulator/viewer.html');
  if (!viewerHtml.existsSync()) {
    stderr.writeln(
      'viewer.html not found at ${viewerHtml.path} - run this from the ActiveLookSdk package root.',
    );
    exit(1);
  }

  final viewers = <WebSocket>[];
  WebSocket? app;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Glasses simulator listening on http://localhost:$port');
  print('Open that URL in a browser, then launch the app with the fake-glasses flag on.');

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      final isBrowserViewer = request.uri.queryParameters['role'] == 'viewer';
      if (isBrowserViewer) {
        viewers.add(socket);
        print('Viewer connected (${viewers.length} total)');
        socket.listen(
          (message) {
            // Only the app has a real socket to forward to - if it isn't
            // connected yet, a tap here has nothing to reach, so just drop
            // it rather than queueing/erroring. Also drop (rather than
            // crash the relay) if the app's socket looks alive here but has
            // actually gone stale.
            try {
              app?.add(message);
            } catch (_) {}
          },
          onDone: () {
            viewers.remove(socket);
            print('Viewer disconnected (${viewers.length} total)');
          },
        );
      } else {
        print('App connected');
        app = socket;
        socket.listen(
          (message) {
            // A viewer whose page was reloaded/closed can still linger here
            // briefly before its onDone fires and removes it - writing to
            // that dead socket throws (WebSocketChannelException/
            // StateError), which previously propagated out of this
            // listener uncaught and could take the whole relay process
            // down mid-message, breaking the app's socket along with it.
            for (final viewer in viewers.toList()) {
              try {
                viewer.add(message);
              } catch (_) {
                viewers.remove(viewer);
              }
            }
          },
          onDone: () {
            print('App disconnected');
            if (identical(app, socket)) app = null;
          },
        );
      }
      continue;
    }

    if (request.uri.path == '/' || request.uri.path == '/viewer.html') {
      request.response.headers.contentType = ContentType.html;
      await request.response.addStream(viewerHtml.openRead());
      await request.response.close();
      continue;
    }

    // Serves this tool's own copies of Engyne's stat-row icons
    // (tool/glasses_simulator/icons/*.png, copied from
    // Engyne/assets/icons/glasses/*.png) so the viewer can draw the real
    // icons instead of a placeholder box for layoutDisplay's rows. Path
    // segments are restricted to a plain filename (no `/` or `..`) before
    // touching the filesystem, since this is served directly from a request
    // path.
    if (request.uri.path.startsWith('/icons/')) {
      final name = request.uri.path.substring('/icons/'.length);
      final isPlainFilename = !name.contains('/') && !name.contains('..') && name.isNotEmpty;
      final iconFile = isPlainFilename
          ? File('${Directory.current.path}/tool/glasses_simulator/icons/$name')
          : null;
      if (iconFile != null && iconFile.existsSync()) {
        request.response.headers.contentType = ContentType('image', 'png');
        await request.response.addStream(iconFile.openRead());
        await request.response.close();
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }
}
