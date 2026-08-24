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
      final (cats, items) = await _repo.fetchPage(offset: 0, limit: pageSize);
      state = PaginatedMenuState(
        categories: cats,
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
      // Merge categories distinct by slug, sorted.
      final catMap = <String, MenuCategory>{for (final c in state.categories) c.slug: c};
      for (final c in cats) {
        catMap.putIfAbsent(c.slug, () => c);
      }
      final mergedCats = catMap.values.toList()..sort((a, b) => a.slug.compareTo(b.slug));
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
}

final paginatedMenuProvider =
    StateNotifierProvider<PaginatedMenuNotifier, PaginatedMenuState>((ref) {
  final repo = ref.watch(menuRepositoryProvider);
  return PaginatedMenuNotifier(repo);
});
