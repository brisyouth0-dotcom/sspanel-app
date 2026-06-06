import 'package:flutter_test/flutter_test.dart';
import 'package:xinglian_vpn/models/models.dart';
import 'package:xinglian_vpn/services/sspanel_parsers.dart';

void main() {
  const sampleServerHtml = '''
<div class="page-title"><span class="home-title">节点列表</span></div>
<div class="card">
  <div class="card-body">
    <div class="card">
      <div class="card-body">
        <span class="status-indicator status-orange status-indicator-animated">
          <span class="status-indicator-circle"></span>
        </span>
        <h2 class="page-title" style="font-size: 16px;">香港-01</h2>
        <span class="badge bg-blue-lt">1 倍</span>
      </div>
    </div>
    <div class="card">
      <div class="card-body">
        <span class="status-indicator status-green status-indicator-animated"></span>
        <h2 class="page-title">香港-02</h2>
      </div>
    </div>
  </div>
</div>
''';

  test('parses UIM server page with orange/green indicators', () {
    final nodes = SspanelParsers.nodesFromServerHtml(sampleServerHtml);
    expect(nodes.length, 2);
    expect(nodes[0].name, '香港-01');
    expect(nodes[0].status, NodeStatus.online);
    expect(nodes[1].name, '香港-02');
  });
}
