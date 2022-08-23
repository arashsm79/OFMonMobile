import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:thingsboard_app/core/auth/login/login_page.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/sem/sem_page.dart';
import 'package:thingsboard_app/modules/alarm/alarms_page.dart';
import 'package:thingsboard_app/modules/device/devices_main_page.dart';
import 'package:thingsboard_app/modules/home/home_page.dart';
import 'package:thingsboard_app/modules/more/more_page.dart';
import 'package:thingsboard_client/thingsboard_client.dart';

class WrappedTbMainNavigationItem {
  final Widget page;
  final String title;
  final Icon icon;
  final String path;

  WrappedTbMainNavigationItem(
      {required this.page,
      required this.title,
      required this.icon,
      required this.path});

  static List<WrappedTbMainNavigationItem> getItems(TbContext tbContext) {
    List<WrappedTbMainNavigationItem> items = [
      WrappedTbMainNavigationItem(
          page: LoginPage(tbContext),
          title: 'Login',
          icon: Icon(Icons.login),
          path: '/login'),
      WrappedTbMainNavigationItem(
          page: SemPage(tbContext),
          title: 'Collect',
          icon: Icon(Icons.dataset),
          path: '/sem')
    ];
    return items;
  }
}

class WrappedMainPage extends TbPageWidget {
  final String _path;

  WrappedMainPage(TbContext tbContext, {required String path})
      : _path = path,
        super(tbContext);

  @override
  _WrappedMainPageState createState() => _WrappedMainPageState();
}

class _WrappedMainPageState extends TbPageState<WrappedMainPage>
    with TbMainState, TickerProviderStateMixin {
  late ValueNotifier<int> _currentIndexNotifier;
  late final List<WrappedTbMainNavigationItem> _tabItems;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabItems = WrappedTbMainNavigationItem.getItems(tbContext);
    int currentIndex = _indexFromPath(widget._path);
    _tabController = TabController(
        initialIndex: currentIndex, length: _tabItems.length, vsync: this);
    _currentIndexNotifier = ValueNotifier(currentIndex);
    _tabController.animation!.addListener(_onTabAnimation);
  }

  @override
  void dispose() {
    _tabController.animation!.removeListener(_onTabAnimation);
    super.dispose();
  }

  _onTabAnimation() {
    var value = _tabController.animation!.value;
    var targetIndex;
    if (value >= _tabController.previousIndex) {
      targetIndex = value.round();
    } else {
      targetIndex = value.floor();
    }
    _currentIndexNotifier.value = targetIndex;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_tabController.index > 0) {
            _setIndex(0);
            return false;
          }
          return true;
        },
        child: Scaffold(
            body: TabBarView(
              physics: tbContext.homeDashboard != null
                  ? NeverScrollableScrollPhysics()
                  : null,
              controller: _tabController,
              children: _tabItems.map((item) => item.page).toList(),
            ),
            bottomNavigationBar: ValueListenableBuilder<int>(
              valueListenable: _currentIndexNotifier,
              builder: (context, index, child) => BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  currentIndex: index,
                  onTap: (int index) =>
                      _setIndex(index) /*_currentIndex = index*/,
                  items: _tabItems
                      .map((item) => BottomNavigationBarItem(
                          icon: item.icon, label: item.title))
                      .toList()),
            )));
  }

  int _indexFromPath(String path) {
    return _tabItems.indexWhere((item) => item.path == path);
  }

  @override
  bool canNavigate(String path) {
    return _indexFromPath(path) > -1;
  }

  @override
  navigateToPath(String path) {
    int targetIndex = _indexFromPath(path);
    _setIndex(targetIndex);
  }

  @override
  bool isHomePage() {
    return _tabController.index == 0;
  }

  _setIndex(int index) {
    _tabController.index = index;
  }
}
