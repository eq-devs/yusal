import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/service/api/api_client.dart';

/// Regions the price lists are kept for; the first is the whole country.
/// The back end knows the same keys.
const priceRegions = [
  'kz',
  'almaty',
  'astana',
  'shymkent',
  'karaganda',
  'aktobe',
  'pavlodar',
  'kyzylorda',
  'oral',
  'atyrau',
  'kostanay',
  'oskemen',
  'taraz',
];

/// A price of the user's own to share with others building nearby.
typedef PriceReport = ({String key, bool labour, int price});

/// The price list of each region, kept by the back end from official
/// statistics, the team's entries and what users report.
abstract interface class PriceRepository {
  /// The list of [region]; the last one read when the network is away,
  /// null when there is none.
  Future<PriceBook?> book(String region, Currency currency);

  /// Sends the user's own prices for [region]. Needs a signed-in account.
  Future<void> report(
      String region, Currency currency, List<PriceReport> prices);
}

PriceBook priceBookFromJson(Map<String, dynamic> j) {
  Map<String, PriceQuote> quotes(Object? v) => {
        if (v is Map)
          for (final e in v.entries)
            if (e.value is Map && (e.value as Map)['price'] is num)
              '${e.key}': PriceQuote(((e.value as Map)['price'] as num).round(),
                  source: '${(e.value as Map)['source'] ?? ''}',
                  date: '${(e.value as Map)['date'] ?? ''}')
      };
  return PriceBook(
      region: '${j['region'] ?? ''}',
      currency: Currency.values.firstWhere((c) => c.name == j['currency'],
          orElse: () => Currency.kzt),
      prices: quotes(j['prices']),
      labour: quotes(j['labour']));
}

final class HttpPriceRepository implements PriceRepository {
  HttpPriceRepository(this.api);
  final ApiClient api;

  String _slot(String region, Currency currency) =>
      'price_book_${currency.name}_$region';

  @override
  Future<PriceBook?> book(String region, Currency currency) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final data = await api.request('GET', '/client/prices',
          query: {'region': region, 'currency': currency.name}, auth: false);
      if (data is Map<String, dynamic>) {
        await prefs.setString(_slot(region, currency), jsonEncode(data));
        return priceBookFromJson(data);
      }
    } catch (_) {
      // Offline, or a back end without price lists: use the last one read.
    }
    final kept = prefs.getString(_slot(region, currency));
    if (kept == null) return null;
    try {
      return priceBookFromJson(jsonDecode(kept) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> report(
          String region, Currency currency, List<PriceReport> prices) =>
      api.request('POST', '/client/prices/report', body: {
        'region': region,
        'currency': currency.name,
        'items': [
          for (final p in prices)
            {
              'key': p.key,
              'kind': p.labour ? 'labour' : 'price',
              'price': p.price
            }
        ]
      });
}

final priceRepositoryProvider =
    Provider<PriceRepository>((ref) => HttpPriceRepository(ApiClient.app));
