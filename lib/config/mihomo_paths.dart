import 'package:path_provider/path_provider.dart';

/// Mihomo 工作目录与配置文件路径
class MihomoPaths {
  static Future<String> workDir() async {
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/mihomo';
    return path;
  }

  static Future<String> configFile() async {
    final dir = await workDir();
    return '$dir/config.yaml';
  }
}
