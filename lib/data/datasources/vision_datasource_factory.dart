import 'vision_datasource.dart';
import 'vision_datasource_stub.dart'
    if (dart.library.io) 'vision_datasource_mobile.dart'
    if (dart.library.html) 'vision_datasource_web.dart';

VisionDataSource getVisionDataSource() => createVisionDataSource();
