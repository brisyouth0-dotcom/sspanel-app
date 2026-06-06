import 'package:flutter_test/flutter_test.dart';
import 'package:xinglian_vpn/services/sspanel_parsers.dart';

void main() {
  test('parses announcement table rows', () {
    const html = '''
<table>
  <thead><tr><th>公告ID</th><th>发布日期</th><th>公告内容</th></tr></thead>
  <tbody>
    <tr><td>1</td><td>2025-01-01</td><td>系统维护通知</td></tr>
    <tr><td>2</td><td>2025-02-01</td><td>春节活动上线</td></tr>
  </tbody>
</table>
''';
    final list = SspanelParsers.announcementsFromHtml(html);
    expect(list.length, 2);
    expect(list.first.content, '系统维护通知');
    expect(list.last.id, '2');
  });
}
