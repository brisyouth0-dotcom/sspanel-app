import 'package:flutter_test/flutter_test.dart';
import 'package:xinglian_vpn/config/app_config.dart';
import 'package:xinglian_vpn/utils/open_external_url.dart';

void main() {
  group('normalizeExternalUri', () {
    test('keeps absolute web urls', () {
      expect(
        normalizeExternalUri('https://pay.example.com/order?id=1').toString(),
        'https://pay.example.com/order?id=1',
      );
    });

    test('normalizes protocol-relative urls', () {
      expect(
        normalizeExternalUri('//pay.example.com/order').toString(),
        'https://pay.example.com/order',
      );
    });

    test('normalizes relative panel urls', () {
      expect(
        normalizeExternalUri(
          '/user/payment/purchase/alipay?invoice_id=1',
        ).toString(),
        '${AppConfig.baseUrl}/user/payment/purchase/alipay?invoice_id=1',
      );
    });

    test('normalizes bare domains', () {
      expect(
        normalizeExternalUri('pay.example.com/order').toString(),
        'https://pay.example.com/order',
      );
    });

    test('keeps alipay deep links', () {
      expect(
        normalizeExternalUri(
          'alipays://platformapi/startapp?appId=20000067',
        ).toString(),
        'alipays://platformapi/startapp?appId=20000067',
      );
    });

    test('decodes encoded absolute payment urls', () {
      expect(
        normalizeExternalUri(
          'https%3A%2F%2Fpay.example.com%2Forder%3Fid%3D1',
        ).toString(),
        'https://pay.example.com/order?id=1',
      );
    });
  });
}
