import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as Math;
import 'package:path/path.dart' as Path;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:thingsboard_app/constants/app_constants.dart';
import 'package:thingsboard_app/constants/assets_path.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/entity/entities_base.dart';
import 'package:thingsboard_app/core/sem/sem_db.dart';
import 'package:thingsboard_app/utils/services/device_profile_cache.dart';
import 'package:thingsboard_app/utils/services/entity_query_api.dart';
import 'package:thingsboard_app/utils/utils.dart';
import 'package:thingsboard_client/thingsboard_client.dart';

mixin DeviceProfilesBase on EntitiesBase<DeviceProfileInfo, PageLink> {

  final RefreshDeviceCounts refreshDeviceCounts = RefreshDeviceCounts();

  @override
  String get title => 'Devices';

  @override
  String get noItemsFoundText => 'No devices found';

  @override
  Future<PageData<DeviceProfileInfo>> fetchEntities(PageLink pageLink) {
    return DeviceProfileCache.getDeviceProfileInfos(tbClient, pageLink);
  }

  @override
  void onEntityTap(DeviceProfileInfo deviceProfile) {
    navigateTo('/deviceList?deviceType=${deviceProfile.name}');
  }

  @override
  Future<void> onRefresh() {
    if (refreshDeviceCounts.onRefresh != null) {
      return refreshDeviceCounts.onRefresh!();
    } else {
      return Future.value();
    }
  }

  @override
  Widget? buildHeading(BuildContext context) {
    return AllDevicesCard(tbContext, refreshDeviceCounts);
  }

  @override
  Widget buildEntityGridCard(BuildContext context, DeviceProfileInfo deviceProfile) {
    return DeviceProfileCard(tbContext, deviceProfile);
  }

  @override
  double? gridChildAspectRatio() {
    return 156 / 200;
  }

}

class RefreshDeviceCounts {
  Future<void> Function()? onRefresh;
}

class AllDevicesCard extends TbContextWidget {

  final RefreshDeviceCounts refreshDeviceCounts;

  AllDevicesCard(TbContext tbContext, this.refreshDeviceCounts) : super(tbContext);

  @override
  _AllDevicesCardState createState() => _AllDevicesCardState();

}

class _AllDevicesCardState extends TbContextState<AllDevicesCard> {

  final StreamController<int?> _activeDevicesCount = StreamController.broadcast();
  final StreamController<int?> _inactiveDevicesCount = StreamController.broadcast();

  @override
  void initState() {
    super.initState();
    widget.refreshDeviceCounts.onRefresh = _countDevices;
    _countDevices();
  }

  @override
  void didUpdateWidget(AllDevicesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.refreshDeviceCounts.onRefresh = _countDevices;
  }

  @override
  void dispose() {
    _activeDevicesCount.close();
    _inactiveDevicesCount.close();
    widget.refreshDeviceCounts.onRefresh = null;
    super.dispose();
  }

  Future<void> _countDevices() {
    _activeDevicesCount.add(null);
    _inactiveDevicesCount.add(null);
    Future<int> activeDevicesCount = EntityQueryApi.countDevices(tbClient, active: true);
    Future<int> inactiveDevicesCount = EntityQueryApi.countDevices(tbClient, active: false);
    Future<List<int>> countsFuture = Future.wait([activeDevicesCount, inactiveDevicesCount]);
    countsFuture.then((counts) {
      if (this.mounted) {
        _activeDevicesCount.add(counts[0]);
        _inactiveDevicesCount.add(counts[1]);
      }
    });
    return countsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return
      GestureDetector(
          behavior: HitTestBehavior.opaque,
          child:
          Container(
            child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                elevation: 0,
                child: Column(
                  children: [
                    Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 15),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('All devices',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  height: 20 / 14
                              )
                          ),
                          Icon(Icons.arrow_forward, size: 18)
                        ],
                      )
                    ),
                    Divider(height: 1),
                    Padding(padding: EdgeInsets.all(0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Flexible(fit: FlexFit.tight,
                              child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:  BorderRadius.circular(4),
                                      ),
                                      child: StreamBuilder<int?>(
                                        stream: _activeDevicesCount.stream,
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData) {
                                            var deviceCount = snapshot.data!;
                                            return _buildDeviceCount(context, true, deviceCount);
                                          } else {
                                            return Center(child:
                                            Container(height: 20, width: 20,
                                                child: CircularProgressIndicator(
                                                    valueColor: AlwaysStoppedAnimation(Theme.of(tbContext.currentState!.context).colorScheme.primary),
                                                    strokeWidth: 2.5)));
                                          }
                                        },
                                      )
                                  ),
                                  onTap: () {
                                    navigateTo('/deviceList?active=true');
                                  }
                              ),
                            ),
                            // SizedBox(width: 4),
                            Container(width: 1,
                                height: 40,
                                child: VerticalDivider(width:  1)
                            ),
                            Flexible(fit: FlexFit.tight,
                              child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:  BorderRadius.circular(4),
                                      ),
                                      child: StreamBuilder<int?>(
                                        stream: _inactiveDevicesCount.stream,
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData) {
                                            var deviceCount = snapshot.data!;
                                            return _buildDeviceCount(context, false, deviceCount);
                                          } else {
                                            return Center(child:
                                            Container(height: 20, width: 20,
                                                child: CircularProgressIndicator(
                                                    valueColor: AlwaysStoppedAnimation(Theme.of(tbContext.currentState!.context).colorScheme.primary),
                                                    strokeWidth: 2.5)));
                                          }
                                        },
                                      )
                                  ),
                                  onTap: () {
                                    navigateTo('/deviceList?active=false');
                                  }
                              ),
                            )
                          ],
                        )
                    )
                  ],
                )
            ),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha((255 * 0.05).ceil()),
                    blurRadius: 6.0,
                    offset: Offset(0, 4)
                )
              ],
            ),
          ),
          onTap: () {
            navigateTo('/deviceList');
          }
      );
  }

}

class DeviceProfileCard extends TbContextWidget {

  final DeviceProfileInfo deviceProfile;

  DeviceProfileCard(TbContext tbContext, this.deviceProfile) : super(tbContext);

  @override
  _DeviceProfileCardState createState() => _DeviceProfileCardState();

}

class _DeviceProfileCardState extends TbContextState<DeviceProfileCard> {

  late Future<int> activeDevicesCount;
  late Future<int> inactiveDevicesCount;

  @override
  void initState() {
    super.initState();
    _countDevices();
    _checkOTAUpdateUsingProfile();
  }

  @override
  void didUpdateWidget(DeviceProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _countDevices();
  }

  _countDevices() {
    activeDevicesCount = EntityQueryApi.countDevices(tbClient, deviceType: widget.deviceProfile.name, active: true);
    inactiveDevicesCount = EntityQueryApi.countDevices(tbClient, deviceType: widget.deviceProfile.name, active: false);
  }

  _checkOTAUpdateUsingProfile() async {
    var authority = tbContext.tbClient.getAuthUser()!.authority;
    if(authority != Authority.SYS_ADMIN && authority != Authority.TENANT_ADMIN) {
      return;
    }
    log.info("Checking for OTA updates");
    try {
      if (widget.deviceProfile.id.id == null) {
        return;
      }
      var deviceprofile = await tbClient
          .getDeviceProfileService()
          .getDeviceProfile(widget.deviceProfile.id.id!);

      var otaPackageId = deviceprofile?.firmwareId?.id;
      if (otaPackageId == null) {
        log.info("package id null");
        return;
      }

      var otaPackageProfileId = deviceprofile?.id?.id;
      if (otaPackageProfileId == null) {
        log.info("package profile id null");
        return;
      }

      var otaPackage =
          await tbClient.getOtaPackageService().getOtaPackageInfo(otaPackageId);
      if (otaPackage == null) {
        return;
      }

      var versionStr = otaPackage.version;
      var versionComp = versionStr.split(".");
      var version = int.parse(versionComp[2]) +
          int.parse(versionComp[1]) * (Math.pow(10, versionComp[2].length)) +
          int.parse(versionComp[0]) *
              (Math.pow(10, versionComp[2].length + versionComp[1].length));

      log.info("list $versionComp");
      log.info("version $version");
      var db = await SemDb.getDb();
      var otaList = await db
          .rawQuery('SELECT * FROM ota WHERE profile_tb_id = ?', [otaPackageProfileId]);
      log.info("ota list $otaList");

      int id;
      if (otaList.length != 0) {
        if ((otaList[0]['version'] != null) && otaList[0]['version'] as int >= version) {
          log.info("OLD ota");
          showInfoNotification("No OTA package newer than $version for ${deviceprofile?.name}.");
          await Future.delayed(Duration(seconds: 1));
          return;
        }
        id = otaList[0]['id'] as int;
      } else {
        id = await db.insert("ota", {
          "tb_id": otaPackageId,
          "profile_tb_id": otaPackage.deviceProfileId.id
        });
      }


      showInfoNotification("Found new OTA package with version $version for ${deviceprofile?.name}.");
      await Future.delayed(Duration(seconds: 1));
      var otaResponse = await tbClient
          .getOtaPackageService()
          .downloadOtaPackage(otaPackageId);
      var path = (await getApplicationDocumentsDirectory()).path;
      var file =
          File(Path.join(path, 'ota', '${otaPackage.deviceProfileId.id}'));
      if (await file.exists()) {
        log.info("file exists");
        await file.delete();
      }
      var fileStream = (await File(
                  Path.join(path, 'ota', '${otaPackage.deviceProfileId.id}'))
              .create(recursive: true))
          .openWrite();
      await otaResponse?.stream.cast<List<int>>().pipe(fileStream);
      await db.update("ota", {"version": version, "path": file.path}, where: "id = ?", whereArgs: [id]);
      showSuccessNotification(
          "OTA package with version $version saved to local storage for ${deviceprofile?.name}.");
      await Future.delayed(Duration(seconds: 1));
    } catch (e) {
      showErrorNotification("Failed to download OTA package for ${widget.deviceProfile.name}.");
      await Future.delayed(Duration(seconds: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    var entity = widget.deviceProfile;
    var hasImage = entity.image != null;
    Widget image;
    BoxFit imageFit;
    double padding;
    if (hasImage) {
      image = Utils.imageFromBase64(entity.image!);
      imageFit = BoxFit.contain;
      padding = 8;
    } else {
      image = SvgPicture.asset(ThingsboardImage.deviceProfilePlaceholder,
          color: Theme.of(context).primaryColor,
          colorBlendMode: BlendMode.overlay,
          semanticsLabel: 'Device profile');
      imageFit = BoxFit.cover;
      padding = 0;
    }
    return
      ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
              children: [
                Expanded(
                    child: Stack (
                        children: [
                          SizedBox.expand(
                              child: Padding(
                                  padding: EdgeInsets.all(padding),
                                  child: FittedBox(
                                      clipBehavior: Clip.hardEdge,
                                      fit: imageFit,
                                      child: image
                                  )
                              )
                          )
                        ]
                    )
                ),
                Container(
                  height: 44,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                        child: AutoSizeText(entity.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          minFontSize: 12,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              height: 20 / 14
                          ),
                        )
                    )
                  )
                ),
                Divider(height: 1),
                GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: FutureBuilder<int>(
                      future: activeDevicesCount,
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.connectionState == ConnectionState.done) {
                          var deviceCount = snapshot.data!;
                          return _buildDeviceCount(context, true, deviceCount);
                        } else {
                          return Container(height: 40,
                                    child: Center(
                                      child: Container(
                                          height: 20, width: 20,
                                          child:
                                          CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation(Theme.of(tbContext.currentState!.context).colorScheme.primary),
                                              strokeWidth: 2.5))));
                        }
                      },
                    ),
                    onTap: () {
                      navigateTo('/deviceList?active=true&deviceType=${entity.name}');
                    }
                ),
                Divider(height: 1),
                GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: FutureBuilder<int>(
                      future: inactiveDevicesCount,
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.connectionState == ConnectionState.done) {
                          var deviceCount = snapshot.data!;
                          return _buildDeviceCount(context, false, deviceCount);
                        } else {
                          return Container(height: 40,
                              child: Center(
                                  child: Container(
                                      height: 20, width: 20,
                                      child:
                                      CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation(Theme.of(tbContext.currentState!.context).colorScheme.primary),
                                          strokeWidth: 2.5))));
                        }
                      },
                    ),
                    onTap: () {
                      navigateTo('/deviceList?active=false&deviceType=${entity.name}');
                    }
                ),
                Divider(height: 1),
                GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: FutureBuilder<int>(
                      future: inactiveDevicesCount,
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.connectionState == ConnectionState.done) {
                          var deviceCount = snapshot.data!;
                          return Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Stack(
                                      children: [
                                        Icon(Icons.update, size: 16),
                                      ],
                                    ),
                                    SizedBox(width: 8.67),
                                    Text('Check for Update',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            height: 16 / 12)),
                                    SizedBox(width: 8.67),
                                  ],
                                ),
                              ],
                            ),
                          );
                        } else {
                          return Container(height: 40,
                              child: Center(
                                  child: Container(
                                      height: 20, width: 20,
                                      child:
                                      CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation(Theme.of(tbContext.currentState!.context).colorScheme.primary),
                                          strokeWidth: 2.5))));
                        }
                      },
                    ),
                    onTap: () {
                      _checkOTAUpdateUsingProfile();
                    }
                ),
              ]
          )
      );
  }
}

Widget _buildDeviceCount(BuildContext context, bool active, int count) {
  Color color = active ? Color(0xFF008A00) : Color(0xFFAFAFAF);
  return Padding(
    padding: EdgeInsets.all(12),
    child: Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Stack(
              children: [
                Icon(Icons.devices_other, size: 16, color: color),
                if (!active) CustomPaint(
                  size: Size.square(16),
                  painter: StrikeThroughPainter(color: color, offset: 2),
                )
              ],
            ),
              SizedBox(width: 8.67),
              Text(active ? 'Active' : 'Inactive', style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 16 / 12,
                  color: color
              )),
              SizedBox(width: 8.67),
              Text(count.toString(), style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 16 / 12,
                  color: color
              ))
          ],
        ),
        Icon(Icons.chevron_right, size: 16, color: Color(0xFFACACAC))
      ],
    ),
  );
}

class StrikeThroughPainter extends CustomPainter {

  final Color color;
  final double offset;

  StrikeThroughPainter({required this.color, this.offset = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    paint.strokeWidth = 1.5;
    canvas.drawLine(Offset(offset, offset), Offset(size.width - offset, size.height - offset), paint);
    paint.color = Colors.white;
    canvas.drawLine(Offset(2, 0), Offset(size.width + 2, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant StrikeThroughPainter oldDelegate) {
    return color != oldDelegate.color;
  }

}
