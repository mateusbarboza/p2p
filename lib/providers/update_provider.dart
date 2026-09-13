// update_provider.dart
//
// "Verificar atualizações" em Perfil > Configurações: compara a versão
// instalada (package_info_plus, que embute a versão do pubspec.yaml no
// binário compilado) com a última tag publicada nos Releases do GitHub
// (https://github.com/mateusbarboza/p2p) — repositório PÚBLICO, checado
// sem autenticação via API REST. Se o repositório voltar a ficar privado,
// essa checagem passa a sempre falhar com erro de rede (404), sem quebrar
// o resto do app.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';

const String _kReleasesApiUrl =
    'https://api.github.com/repos/mateusbarboza/p2p/releases/latest';

enum UpdateCheckStatus { idle, checking, upToDate, available, error }

class UpdateCheckState {
  const UpdateCheckState({
    this.status = UpdateCheckStatus.idle,
    this.currentVersion = '',
    this.latestVersion,
    this.releaseUrl,
    this.errorMessage,
  });

  final UpdateCheckStatus status;
  final String currentVersion;
  final String? latestVersion;
  final String? releaseUrl;
  final String? errorMessage;

  UpdateCheckState copyWith({
    UpdateCheckStatus? status,
    String? currentVersion,
    String? latestVersion,
    String? releaseUrl,
    String? errorMessage,
  }) {
    return UpdateCheckState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      releaseUrl: releaseUrl ?? this.releaseUrl,
      errorMessage: errorMessage,
    );
  }
}

/// Compara duas versões "semver-like" (aceita "v" na frente, ex: "v1.2.3").
/// Retorna > 0 se [a] for mais nova que [b].
int compareVersions(String a, String b) {
  List<int> parse(String v) {
    final cleaned = v.trim().replaceFirst(RegExp(r'^v'), '');
    return cleaned
        .split('.')
        .map((part) =>
            int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '0') ?? 0)
        .toList();
  }

  final partsA = parse(a);
  final partsB = parse(b);
  for (var i = 0; i < 3; i++) {
    final valueA = i < partsA.length ? partsA[i] : 0;
    final valueB = i < partsB.length ? partsB[i] : 0;
    if (valueA != valueB) return valueA - valueB;
  }
  return 0;
}

class UpdateNotifier extends Notifier<UpdateCheckState> {
  @override
  UpdateCheckState build() => const UpdateCheckState();

  Future<void> checkNow() async {
    state = state.copyWith(status: UpdateCheckStatus.checking);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_kReleasesApiUrl),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        state = state.copyWith(
          status: UpdateCheckStatus.error,
          currentVersion: currentVersion,
          errorMessage: 'Não foi possível consultar o servidor de '
              'atualizações (HTTP ${response.statusCode}).',
        );
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String? ?? '';
      final htmlUrl = json['html_url'] as String?;
      if (tagName.isEmpty) {
        state = state.copyWith(
          status: UpdateCheckStatus.error,
          currentVersion: currentVersion,
          errorMessage: 'Resposta inesperada do servidor de atualizações.',
        );
        return;
      }

      final isNewer = compareVersions(tagName, currentVersion) > 0;
      state = state.copyWith(
        status:
            isNewer ? UpdateCheckStatus.available : UpdateCheckStatus.upToDate,
        currentVersion: currentVersion,
        latestVersion: tagName,
        releaseUrl: htmlUrl,
      );
    } catch (e) {
      final currentVersion = state.currentVersion.isNotEmpty
          ? state.currentVersion
          : (await PackageInfo.fromPlatform()).version;
      state = state.copyWith(
        status: UpdateCheckStatus.error,
        currentVersion: currentVersion,
        errorMessage: 'Falha ao verificar atualizações: $e',
      );
    }
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateCheckState>(
  UpdateNotifier.new,
);
