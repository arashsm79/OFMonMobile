import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'dart:math' as Math;
import 'package:path/path.dart' as Path;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:thingsboard_app/constants/app_constants.dart';
import 'package:thingsboard_app/constants/assets_path.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/entity/entities_base.dart';
import 'package:thingsboard_app/core/sem/sem_db.dart';
import 'package:thingsboard_app/core/sem/sem_page.dart';
import 'package:thingsboard_app/utils/services/device_profile_cache.dart';
import 'package:thingsboard_app/utils/services/entity_query_api.dart';
import 'package:thingsboard_app/utils/utils.dart';
import 'package:thingsboard_client/thingsboard_client.dart';

mixin DevicesBase on EntitiesBase<EntityData, EntityDataQuery> {

  @override
  String get title => 'Devices';

  @override
  String get noItemsFoundText => 'No devices found';

  @override
  Future<PageData<EntityData>> fetchEntities(EntityDataQuery dataQuery) {
    return tbClient.getEntityQueryService().findEntityDataByQuery(dataQuery);
  }

  @override
  void onEntityTap(EntityData device) async {
    var profile = await DeviceProfileCache.getDeviceProfileInfo(tbClient, device.field('type')!, device.entityId.id!);
    if (profile.defaultDashboardId != null) {
      var dashboardId = profile.defaultDashboardId!.id!;
      var state = Utils.createDashboardEntityState(device.entityId, entityName: device.field('name')!, entityLabel: device.field('label')!);
      navigateToDashboard(dashboardId, dashboardTitle: device.field('name'), state: state);
    } else {
      if (tbClient.isTenantAdmin()) {
        showWarnNotification('Mobile dashboard should be configured in device profile!');
      }
    }
  }

  @override
  Widget buildEntityListCard(BuildContext context, EntityData device) {
    return _buildEntityListCard(context, device, false);
  }

  @override
  Widget buildEntityListWidgetCard(BuildContext context, EntityData device) {
    return _buildEntityListCard(context, device, true);
  }

  @override
  Widget buildEntityGridCard(BuildContext context, EntityData device) {
    return Text(device.field('name')!);
  }

  bool displayCardImage(bool listWidgetCard) => listWidgetCard;

  Widget _buildEntityListCard(BuildContext context, EntityData device, bool listWidgetCard) {
    return DeviceCard(tbContext, device: device, listWidgetCard: listWidgetCard, displayImage: displayCardImage(listWidgetCard));
  }
}

class DeviceQueryController extends PageKeyController<EntityDataQuery> {

  DeviceQueryController({int pageSize = 20, String? searchText, String? deviceType, bool? active}):
        super(EntityQueryApi.createDefaultDeviceQuery(pageSize: pageSize, searchText: searchText, deviceType: deviceType, active: active));

  @override
  EntityDataQuery nextPageKey(EntityDataQuery deviceQuery) => deviceQuery.next();

  onSearchText(String searchText) {
    value.pageKey.pageLink.page = 0;
    value.pageKey.pageLink.textSearch = searchText;
    notifyListeners();
  }

}

class DeviceCard extends TbContextWidget {

  final EntityData device;
  final bool listWidgetCard;
  final bool displayImage;

  DeviceCard(TbContext tbContext, {required this.device, this.listWidgetCard = false, this.displayImage = false}) : super(tbContext);

  @override
  _DeviceCardState createState() => _DeviceCardState();

}

class _DeviceCardState extends TbContextState<DeviceCard> {

  final entityDateFormat = DateFormat('yyyy-MM-dd');

  late Future<DeviceProfileInfo> deviceProfileFuture;

  @override
  void initState() {
    super.initState();
    _addDeviceNameToDb();
    _checkOTAUpdateUsingToken();
    if (widget.displayImage || !widget.listWidgetCard) {
      deviceProfileFuture = DeviceProfileCache.getDeviceProfileInfo(
          tbClient, widget.device.field('type')!, widget.device.entityId.id!);
    }
  }
  _checkOTAUpdateUsingToken() async {
    var authority = tbContext.tbClient.getAuthUser()!.authority;
    if (authority != Authority.CUSTOMER_USER) {
      return;
    }
    var cred = await tbClient
        .getDeviceService()
        .getDeviceCredentialsByDeviceId(widget.device.entityId.id!);

    var deviceInfo = await tbClient
        .getDeviceService()
        .getDeviceInfo(widget.device.entityId.id!);

    if (deviceInfo == null || cred == null) {
      return;
    }

    log.info("Checking for OTA updates");
    try {
      if (deviceInfo.deviceProfileId?.id == null) {
        return;
      }
      var deviceProfileId = deviceInfo.deviceProfileId?.id;
      var accessToken = cred.credentialsId;


      Map<String, dynamic> sharedKeysWrapped = json.decode((await http
              .get(Uri.parse(
                  "${ThingsboardAppConstants.thingsBoardApiEndpoint}/api/v1/$accessToken/attributes?sharedKeys"))
              .timeout(Duration(seconds: 30)))
          .body);
      Map<String, dynamic> sharedKeys = sharedKeysWrapped['shared'];
      log.info(sharedKeys);

      var fwTitle = sharedKeys['fw_title'] as String?;
      var versionStr = sharedKeys['fw_version'] as String?;
      if(versionStr == null || fwTitle == null){
          return;
      }

      var versionComp = versionStr.split(".");
      var version = int.parse(versionComp[2]) +
          int.parse(versionComp[1]) * (Math.pow(10, versionComp[2].length)) +
          int.parse(versionComp[0]) *
              (Math.pow(10, versionComp[2].length + versionComp[1].length));

      log.info("list $versionComp");
      log.info("version $version");
      var db = await SemDb.getDb();
      var otaList = await db
          .rawQuery('SELECT * FROM ota WHERE profile_tb_id = ?', [deviceProfileId]);
      log.info("ota list $otaList");

      int id;
      if (otaList.length != 0) {
        if ((otaList[0]['version'] != null) && otaList[0]['version'] as int >= version) {
          log.info("OLD ota");
          showInfoNotification("No OTA package newer than $version for ${deviceInfo.name}.");
          await Future.delayed(Duration(seconds: 2));
          return;
        }
        id = otaList[0]['id'] as int;
      } else {
        id = await db.insert("ota", {
          "tb_id": deviceInfo.id?.id,
          "profile_tb_id": deviceProfileId
        });
      }


      showInfoNotification("Found new OTA package with version $version for ${deviceInfo.name}.");
      await Future.delayed(Duration(seconds: 2));
      var otaResponse = (await http
              .get(Uri.parse(
                  '${ThingsboardAppConstants.thingsBoardApiEndpoint}/api/v1/$accessToken/firmware?title=$fwTitle&version=$versionStr'))
              .timeout(Duration(seconds: 120)))
          .bodyBytes;
      var path = (await getApplicationDocumentsDirectory()).path;
      var file =
          File(Path.join(path, 'ota', '$deviceProfileId'));
      if (await file.exists()) {
        log.info("file exists");
        await file.delete();
      }
      var fileStream = (await File(
                  Path.join(path, 'ota', '$deviceProfileId'))
              .create(recursive: true));

      await fileStream.writeAsBytes(otaResponse);
      await db.update("ota", {"version": version, "path": file.path}, where: "id = ?", whereArgs: [id]);
      showSuccessNotification(
          "OTA package with version $version saved to local storage for ${deviceInfo.name}.");
      await Future.delayed(Duration(seconds: 2));
    } catch (e) {
      log.info(e);
      showErrorNotification("Failed to download OTA package for ${deviceInfo.name}.");
      await Future.delayed(Duration(seconds: 2));
    }
  }

  _addDeviceNameToDb() async {
    var cred = await tbClient
        .getDeviceService()
        .getDeviceCredentialsByDeviceId(widget.device.entityId.id!);

    var deviceInfo = await tbClient
        .getDeviceService()
        .getDeviceInfo(widget.device.entityId.id!);

    if (deviceInfo == null || cred == null) {
      return;
    }
    var accessToken = cred.credentialsId;
    var db = await SemDb.getDb();
    await db.update("devices", {'name': deviceInfo.name}, where: 'access_token = ?', whereArgs: [accessToken]);
  }

  @override
  void didUpdateWidget(DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.displayImage || !widget.listWidgetCard) {
      var oldDevice = oldWidget.device;
      var device = widget.device;
      if (oldDevice.field('type')! != device.field('type')!) {
        deviceProfileFuture = DeviceProfileCache.getDeviceProfileInfo(
            tbClient, widget.device.field('type')!, widget.device.entityId.id!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.listWidgetCard) {
      return buildListWidgetCard(context);
    } else {
      return buildCard(context);
    }
  }

  _copyDeviceToken() async {
    var cred = await tbClient
        .getDeviceService()
        .getDeviceCredentialsByDeviceId(widget.device.entityId.id!);

    var deviceInfo = await tbClient
        .getDeviceService()
        .getDeviceInfo(widget.device.entityId.id!);

    if (deviceInfo == null || cred == null) {
      return;
    }

    if (cred.credentialsType == DeviceCredentialsType.ACCESS_TOKEN) {
      Clipboard.setData(ClipboardData(text: cred.credentialsId + deviceInfo.deviceProfileId!.id!));
      showSuccessNotification("Copied Token: ${cred.credentialsId + deviceInfo.deviceProfileId!.id!}");
    }
  }

  Widget buildCard(BuildContext context) {
    return Stack(
        children: [
          Positioned.fill(
              child: Container(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                        color: widget.device.attribute('active') == 'true' ? Color(0xFF008A00) : Color(0xFFAFAFAF),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4))
                    ),
                  )
              )
          ),
          FutureBuilder<DeviceProfileInfo>(
            future: deviceProfileFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.connectionState == ConnectionState.done) {
                var profile = snapshot.data!;
                bool hasDashboard = profile.defaultDashboardId != null;
                Widget image;
                BoxFit imageFit;
                if (profile.image != null) {
                  image = Utils.imageFromBase64(profile.image!);
                  imageFit = BoxFit.contain;
                } else {
                  image = SvgPicture.asset(ThingsboardImage.deviceProfilePlaceholder,
                      color: Theme.of(context).primaryColor,
                      colorBlendMode: BlendMode.overlay,
                      semanticsLabel: 'Device');
                  imageFit = BoxFit.cover;
                }
                return Row(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 20),
                      Flexible(
                          fit: FlexFit.tight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (widget.displayImage) Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.all(Radius.circular(4))
                                    ),
                                    child: ClipRRect(
                                        borderRadius: BorderRadius.all(Radius.circular(4)),
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                                child: FittedBox(
                                                  fit: imageFit,
                                                  child: image,
                                                )
                                            )
                                          ],
                                        )
                                    )
                                  ),
                                  SizedBox(width: 12),
                                  Flexible(
                                      fit: FlexFit.tight,
                                      child: Column(
                                          children: [
                                            Row(
                                                mainAxisSize: MainAxisSize.max,
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Flexible(
                                                      fit: FlexFit.tight,
                                                      child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment.centerLeft,
                                                          child: Text('${widget.device.field('name')!}',
                                                              style: TextStyle(
                                                                  color: Color(0xFF282828),
                                                                  fontSize: 14,
                                                                  fontWeight: FontWeight.w500,
                                                                  height: 20 / 14
                                                              ))
                                                      )
                                                  ),
                                                  SizedBox(width: 12),
                                                  Text(entityDateFormat.format(DateTime.fromMillisecondsSinceEpoch(widget.device.createdTime!)),
                                                      style: TextStyle(
                                                          color: Color(0xFFAFAFAF),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.normal,
                                                          height: 16 / 12
                                                      ))
                                                ]
                                            ),
                                            SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('${widget.device.field('type')!}',
                                                    style: TextStyle(
                                                        color: Color(0xFFAFAFAF),
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.normal,
                                                        height: 16 / 12
                                                    )),
                                                Text(widget.device.attribute('active') == 'true' ? 'Active' : 'Inactive',
                                                    style: TextStyle(
                                                      color: widget.device.attribute('active') == 'true' ? Color(0xFF008A00) : Color(0xFFAFAFAF),
                                                      fontSize: 12,
                                                      height: 16 / 12,
                                                      fontWeight: FontWeight.normal,
                                                    ))
                                              ],
                                            )
                                          ]
                                      )
                                  ),
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    onSelected: (String command) {
                                      switch (command) {
                                        case "token":
                                          _copyDeviceToken();
                                          break;
                                        default:
                                          break;
                                      }
                                    },
                                    itemBuilder: (BuildContext context) {
                                      return [
                                        PopupMenuItem(
                                            value: 'token',
                                            child: Text('Copy Token'))
                                      ];
                                    },
                                  ),
                                  SizedBox(width: 16),
                                  if (hasDashboard) Icon(Icons.chevron_right, color: Color(0xFFACACAC)),
                                  if (hasDashboard) SizedBox(width: 16),
                                ]
                              ),
                              SizedBox(height: 12)
                            ],
                          )
                      )
                    ]
                );
              } else {
                return Container(
                  height: 64,
                  child: Center(
                      child: RefreshProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Theme.of(tbContext.currentState!.context).colorScheme.primary)
                      )
                  )
                );
              }
            }
          )
        ]
    );
  }

  Widget buildListWidgetCard(BuildContext context) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.displayImage) Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              // color: Color(0xFFEEEEEE),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(4))
            ),
            child: FutureBuilder<DeviceProfileInfo>(
              future: deviceProfileFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.connectionState == ConnectionState.done) {
                  var profile = snapshot.data!;
                  Widget image;
                  BoxFit imageFit;
                  if (profile.image != null) {
                    image = Utils.imageFromBase64(profile.image!);
                    imageFit = BoxFit.contain;
                  } else {
                    image = SvgPicture.asset(ThingsboardImage.deviceProfilePlaceholder,
                        color: Theme.of(context).primaryColor,
                        colorBlendMode: BlendMode.overlay,
                        semanticsLabel: 'Device');
                    imageFit = BoxFit.cover;
                  }
                  return ClipRRect(
                      borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
                      child: Stack(
                        children: [
                          Positioned.fill(
                              child: FittedBox(
                                fit: imageFit,
                                child: image,
                              )
                          )
                        ],
                      )
                  );
                } else {
                  return Center(child: RefreshProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Theme.of(tbContext.currentState!.context).colorScheme.primary)
                  ));
                }
              },
            ),
          ),
          Flexible(
              fit: FlexFit.loose,
              child:
              Container(
                  padding: EdgeInsets.symmetric(vertical: 9, horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            FittedBox(
                                fit: BoxFit.fitWidth,
                                alignment: Alignment.centerLeft,
                                child: Text('${widget.device.field('name')!}',
                                    style: TextStyle(
                                        color: Color(0xFF282828),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 20 / 14
                                    ))
                            )
                          ]
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${widget.device.field('type')!}',
                              style: TextStyle(
                                  color: Color(0xFFAFAFAF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  height: 16 / 12
                              )),
                        ]
                      )
                    ],
                  )
              )
          )
        ]
    );
  }

}
