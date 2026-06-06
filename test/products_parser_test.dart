import 'package:flutter_test/flutter_test.dart';
import 'package:xinglian_vpn/models/models.dart';
import 'package:xinglian_vpn/services/sspanel_parsers.dart';

void main() {
  const sampleTabp = '''
<div id="tabp" class="tab-pane active show">
  <div id="product-2-name" class="text-uppercase">2</div>
  <div id="product-2-price" class="display-6">
    <p class="fw-bold">22.00</p>
  </div>
  <div class="list-group-item">
    <div class="text-reset d-block">Lv. 1</div>
  </div>
  <div class="list-group-item">
    <div class="text-reset d-block">30 天</div>
  </div>
  <div class="list-group-item">
    <div class="text-reset d-block">30 GB</div>
  </div>
  <a href="/user/order/create?product_id=2">订阅</a>
</div>
<div id="bandwidth" class="tab-pane"></div>
''';

  test('parses standard UIM product markup', () {
    final plans = SspanelParsers.productsFromHtml(sampleTabp);
    expect(plans.length, 1);
    expect(plans.first.id, '2');
    expect(plans.first.name, '2');
    expect(plans.first.price, 22.0);
    expect(plans.first.kind, ProductKind.periodic);
    expect(plans.first.features, isNotEmpty);
  });

  test('parses order/create links when ids differ', () {
    const html = '''
<a href="/user/order/create?product_id=9">购买</a>
<div id="product-9-name">Plus</div>
<div id="product-9-price"><span>¥ 9.90 /月</span></div>
''';
    final plans = SspanelParsers.productsFromHtml(html);
    expect(plans.length, 1);
    expect(plans.first.id, '9');
    expect(plans.first.name, 'Plus');
    expect(plans.first.price, closeTo(9.9, 0.01));
  });
}
