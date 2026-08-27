// Paginated menu controller — FEATURES §27 (20 per page via Supabase .range).
// Uses Riverpod StateNotifier for pages (per task spec).
// Backwards compat: menuCatalogProvider remains for callers that need full catalog;
// this controller is the paginated source for MenuScreen infinite scroll.
import 'package:flutter_riverpod/legacy.dart';

import '../../data/models/menu_models.dart';
import '../../data/repos/menu_repository.dart';
import '../../data/repos/supabase_menu_repository.dart';

/// State for the paginated catalog.
class PaginatedMenuState {
  const PaginatedMenuState({
    this.categories = const [],
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<MenuCategory> categories;
  final List<MenuItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  PaginatedMenuState copyWith({
    List<MenuCategory>? categories,
    List<MenuItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
  }) {
    return PaginatedMenuState(
      categories: categories ?? this.categories,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }

  PaginatedMenuState clearError() {
    return PaginatedMenuState(
      categories: categories,
      items: items,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      hasMore: hasMore,
      error: null,
    );
  }
}

/// StateNotifier that paginates via [MenuRepository.fetchPage] 20 per page.
// ignore: prefer_mixin
class PaginatedMenuNotifier extends StateNotifier<PaginatedMenuState> {
  PaginatedMenuNotifier(this._repo)
      : super(const PaginatedMenuState(isLoading: true)) {
    _loadInitial();
  }

  final MenuRepository _repo;
  static const int pageSize = 20;

  Future<void> _loadInitial() async {
    state = state.copyWith(isLoading: true, hasMore: true);
    // Clear error explicitly
    state = PaginatedMenuState(
      categories: state.categories,
      items: state.items,
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      error: null,
    );
    try {
      // Load all 12 categories + first page in parallel — fixes
      // "too lazy" (was 2 sequential round-trips ≈ 400ms extra).
      // Categories are tiny (12 rows) so loading all is cheap; items stay
      // paginated 20 via range. Parallel cuts first paint ~50%.
      final results = await Future.wait([
        _repo.fetchAllCategories(),
        _repo.fetchPage(offset: 0, limit: pageSize),
      ]);
      final allCats = results[0] as List<MenuCategory>;
      final pageResult = results[1] as CatalogSnapshot;
      final (pageCats, items) = pageResult;
      // Merge: allCats is authoritative (sorted by sort), pageCats may have
      // same slugs but ensure no missing due to empty first page.
      final catMap = <String, MenuCategory>{for (final c in allCats) c.slug: c};
      for (final c in pageCats) {
        catMap.putIfAbsent(c.slug, () => c);
      }
      final mergedCats = catMap.values.toList();
      // If allCats already sorted by sort, respect DB order; fallback to insertion order
      // when allCats empty.
      final orderedCats = allCats.isNotEmpty
          ? allCats
          : mergedCats;
      state = PaginatedMenuState(
        categories: orderedCats,
        items: items,
        isLoading: false,
        isLoadingMore: false,
        hasMore: items.length == pageSize,
        error: null,
      );
    } catch (e) {
      state = PaginatedMenuState(
        categories: state.categories,
        items: state.items,
        isLoading: false,
        isLoadingMore: false,
        hasMore: true,
        error: e,
      );
    }
  }

  Future<void> loadNext() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    if (state.error != null) return;
    state = state.copyWith(isLoadingMore: true);
    // Keep error cleared
    state = PaginatedMenuState(
      categories: state.categories,
      items: state.items,
      isLoading: state.isLoading,
      isLoadingMore: true,
      hasMore: state.hasMore,
      error: null,
    );
    try {
      final offset = state.items.length;
      final (cats, newItems) = await _repo.fetchPage(offset: offset, limit: pageSize);
      // Merge categories preserving DB order (allCats order); append new slugs.
      final mergedCats = [...state.categories];
      for (final c in cats) {
        if (!mergedCats.any((e) => e.slug == c.slug)) mergedCats.add(c);
      }
      state = PaginatedMenuState(
        categories: mergedCats,
        items: [...state.items, ...newItems],
        isLoading: false,
        isLoadingMore: false,
        hasMore: newItems.length == pageSize,
        error: null,
      );
    } catch (e) {
      state = PaginatedMenuState(
        categories: state.categories,
        items: state.items,
        isLoading: false,
        isLoadingMore: false,
        hasMore: state.hasMore,
        error: e,
      );
    }
  }

  Future<void> retry() async {
    if (state.items.isEmpty) {
      await _loadInitial();
    } else {
      // Retry next page — clear error then loadNext
      state = PaginatedMenuState(
        categories: state.categories,
        items: state.items,
        isLoading: false,
        isLoadingMore: false,
        hasMore: state.hasMore,
        error: null,
      );
      await loadNext();
    }
  }

  Future<void> refresh() async => _loadInitial();

  /// Server-filtered category ensure — single RTT (PERF-06).
  /// Replaces the old client-side scan that looped loadNext up to 6 times.
  Future<void> ensureCategoryHasItems(String slug) async {
    if (slug.isEmpty) return;
    if (state.items.any((i) => i.categorySlug == slug)) return;
    if (state.isLoading || state.isLoadingMore || state.error != null) return;
    try {
      final (cats, items) = await _repo.fetchPageByCategory(
        categorySlug: slug,
        offset: 0,
        limit: pageSize,
      );
      if (items.isEmpty) return;
      final mergedCats = [...state.categories];
      for (final c in cats) {
        if (!mergedCats.any((e) => e.slug == c.slug)) mergedCats.add(c);
      }
      state = PaginatedMenuState(
        categories: mergedCats,
        items: [...state.items, ...items.where((i) => !state.items.any((e) => e.id == i.id))],
        isLoading: false,
        isLoadingMore: false,
        hasMore: state.hasMore,
        error: null,
      );
    } catch (_) {
      // Fallback: keep old behavior silent on error
    }
  }
}

final paginatedMenuProvider =
    StateNotifierProvider<PaginatedMenuNotifier, PaginatedMenuState>((ref) {
  final repo = ref.watch(menuRepositoryProvider);
  return PaginatedMenuNotifier(repo);
});
