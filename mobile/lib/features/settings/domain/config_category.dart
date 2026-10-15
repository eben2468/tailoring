/// A configurable category (material or tool categories): from the configuration bundle, or from the
/// settings endpoints with [itemCount].
class ConfigCategory {
  const ConfigCategory({required this.id, required this.name, required this.isActive, this.itemCount});

  factory ConfigCategory.fromJson(Map<String, dynamic> json) => ConfigCategory(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        isActive: json['is_active'] == true,
        itemCount: (json['item_count'] as num?)?.toInt(),
      );

  final int id;
  final String name;
  final bool isActive;
  final int? itemCount;
}

/// Category settings calls (online only; the configuration is downloaded again afterwards).
abstract interface class CategorySettings {
  Future<List<ConfigCategory>> categories();

  Future<void> createCategory(String name);

  Future<void> updateCategory(int id, {String? name, bool? isActive});
}
