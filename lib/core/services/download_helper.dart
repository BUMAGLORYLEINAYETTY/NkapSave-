// Cross-platform file download.
//
// On web, this triggers the browser "Save as…" via a Blob + anchor click.
// On native platforms it throws — wire `path_provider` + `share_plus`
// when adding mobile support.
export 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';
