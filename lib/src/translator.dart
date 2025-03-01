import 'dart:ui';

import '../interpolator.dart' as interpolator;
import 'options.dart';
import 'plural_resolver.dart';
import 'resource_store.dart';

class Translator {
  Translator(
    this.pluralResolver,
    this.resourceStore, [
    this.contextNamespace,
  ]) : super();

  final PluralResolver pluralResolver;
  final ResourceStore resourceStore;
  final String? contextNamespace;

  String? call(
    String key,
    Locale locale,
    Map<String, dynamic> variables,
    I18NextOptions options,
  ) {
    var namespace = contextNamespace;
    var keyPath = key;
    final nsSeparator = options.namespaceSeparator ?? ':';
    final match = RegExp(nsSeparator).firstMatch(key);
    if (match != null) {
      namespace = key.substring(0, match.start);
      keyPath = key.substring(match.end);
    }
    namespace ??= '';
    return translateKey(locale, namespace, keyPath, variables, options);
  }

  /// Order of key resolution:
  ///
  /// Expects `variables['context']` to be a `String?` and
  /// `variables['count']` to be an `int?`. Otherwise throws cast error.
  ///
  /// - context + pluralization:
  ///   ['key_ctx_plr', 'key_ctx', 'key_plr', 'key']
  /// - context only:
  ///   ['key_ctx', 'key']
  /// - pluralization only:
  ///   ['key_plr', 'key']
  /// - Otherwise:
  ///   ['key']
  String? translateKey(
    Locale locale,
    String namespace,
    String key,
    Map<String, dynamic> variables,
    I18NextOptions options,
  ) {
    final context = _castAs<String>(variables['context']);
    final count = _castAs<int>(variables['count']);
    final needsContext = context != null && context.isNotEmpty;
    final needsPlural = count != null;

    var pluralSuffix = '';
    if (needsPlural) {
      pluralSuffix = pluralResolver.pluralize(locale, count!, options);
    }

    var tempKey = key;
    final keys = <String>[key];
    if (needsContext && needsPlural) {
      keys.add(tempKey + pluralSuffix);
    }
    if (needsContext) {
      keys.add(tempKey += '${options.contextSeparator}$context');
    }
    if (needsPlural) {
      keys.add(tempKey += pluralSuffix);
    }

    final namespaces = <String>[
      namespace,
      if (options.fallbackNamespaces != null) ...options.fallbackNamespaces!,
    ];

    for (final currentNamespace in namespaces) {
      for (final currentKey in keys.reversed) {
        // TODO: translation context object
        try {
          final found = find(
            locale,
            currentNamespace,
            currentKey,
            variables,
            options,
          );
          if (found != null) return found;
        } catch (error) {
          return options.translationFailedHandler?.call(
            locale,
            currentNamespace,
            currentKey,
            variables,
            options,
            error,
          );
        }
      }
    }
    return null;
  }

  /// Attempts to find the value given a [namespace] and [key].
  ///
  /// If one is not found directly, then tries to fallback (if necessary). May
  /// still return null if none is found.
  String? find(
    Locale locale,
    String namespace,
    String key,
    Map<String, dynamic> variables,
    I18NextOptions options,
  ) {
    var result = resourceStore.retrieve(locale, namespace, key, options);
    if (result != null) {
      result = interpolator.interpolate(locale, result, variables, options);
      result = interpolator.nest(
        locale,
        result,
        (currentKey, locale, newVariables, options) {
          // nesting a potentially recursive key
          if (currentKey == key &&
              newVariables['context'] == variables['context']) {
            return null;
          }

          return Translator(pluralResolver, resourceStore, namespace)
              .call(currentKey, locale, newVariables, options);
        },
        variables,
        options,
      );
    }
    return result;
  }
}

/// Dart casting syntax is not nullable safe
/// `map['value'] as int?` will throw if the value is non int value
T? _castAs<T>(dynamic value) {
  return value is T ? value : null;
}
