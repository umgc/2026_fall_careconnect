import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Prevents an inactive tab or covered route from changing the browser title.
class PageTitleScope extends StatelessWidget {
  const PageTitleScope({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_PageTitleVisibility>()
          ?.active ??
      true;

  @override
  Widget build(BuildContext context) => _PageTitleVisibility(
        active: active && isActive(context),
        child: child,
      );
}

class _PageTitleVisibility extends InheritedWidget {
  const _PageTitleVisibility({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_PageTitleVisibility oldWidget) =>
      active != oldWidget.active;
}

/// Sets a descriptive title and restores it when this route becomes current.
class PageTitle extends StatefulWidget {
  const PageTitle({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends State<PageTitle> {
  bool _active = false;
  String? _lastTitle;
  Color? _lastColor;

  @override
  Widget build(BuildContext context) {
    final active = PageTitleScope.isActive(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final color = Theme.of(context).colorScheme.primary;
    if (active &&
        (!_active || _lastTitle != widget.title || _lastColor != color)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_active) return;
        // This is the Flutter platform API used by the Title widget.
        SystemChrome.setApplicationSwitcherDescription(
          ApplicationSwitcherDescription(
            label: '${widget.title} | CareConnect',
            primaryColor: color.toARGB32(),
          ),
        );
      });
    }
    _active = active;
    _lastTitle = widget.title;
    _lastColor = color;
    return PageTitleScope(
      active: active,
      child: widget.child,
    );
  }
}

/// Keeps the page's hard-coded title beside its route definition.
class TitledGoRoute extends GoRoute {
  TitledGoRoute({
    required String title,
    required super.path,
    super.name,
    super.redirect,
    super.routes,
    GoRouterWidgetBuilder? builder,
  }) : super(
          builder: builder,
          pageBuilder: builder == null
              ? null
              : (context, state) => MaterialPage<void>(
                    key: state.pageKey,
                    name: state.name ?? state.path,
                    arguments: <String, String>{
                      ...state.pathParameters,
                      ...state.uri.queryParameters,
                    },
                    restorationId: state.pageKey.value,
                    child: PageTitle(
                      title: title,
                      child: builder(context, state),
                    ),
                  ),
        );
}

/// The same title behavior for pages opened with Navigator.push.
class TitledMaterialPageRoute<T> extends MaterialPageRoute<T> {
  TitledMaterialPageRoute({
    required String title,
    required super.builder,
    super.settings,
    super.fullscreenDialog,
    super.maintainState,
  }) : _title = title;

  final String _title;

  @override
  Widget buildContent(BuildContext context) => PageTitle(
        title: _title,
        child: super.buildContent(context),
      );
}
