# Riverpod for state management

We adopted `flutter_riverpod` (+ riverpod_generator) over provider/Bloc. Decided while zero feature code existed, primarily because the planned Supabase migration (ADR-0001) will stream orders/loyalty across devices via realtime channels, which map directly onto `StreamProvider`/`FutureProvider`. Compile-safe DI and testability were secondary factors. Consequence: all feature slices express state as Riverpod notifiers/providers; no inherited-widget DI.
