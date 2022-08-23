import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:thingsboard_app/config/routes/router.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/sem/sem_page.dart';
import 'package:thingsboard_app/core/sem/sem_wrapper.dart';


class SemRoutes extends TbRoutes {

  late var semHandler = Handler(handlerFunc: (BuildContext? context, Map<String, dynamic> params) {
    return SemPage(tbContext);
  });
  late var wrappedMainHandler = Handler(handlerFunc: (BuildContext? context, Map<String, dynamic> params) {
    return WrappedMainPage(tbContext, path: "/login");
  });

  SemRoutes(TbContext tbContext) : super(tbContext);

  @override
  void doRegisterRoutes(router) {
    router.define("/sem", handler: semHandler);
    router.define("/wrappedmain", handler: wrappedMainHandler);
  }

}
