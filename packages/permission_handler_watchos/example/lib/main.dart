// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// A watch demo of permission_handler: every permission watchOS has, with its
// status. Tapping one asks for it.
//
// permission_handler's own example is a phone app built on
// baseflow_plugin_template, whose url_launcher links do not run on the watch.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// The permissions watchOS has, in the order the list shows them.
const List<Permission> watchPermissions = <Permission>[
  Permission.notification,
  Permission.locationWhenInUse,
  Permission.locationAlways,
  Permission.sensors,
  Permission.microphone,
  Permission.contacts,
  Permission.calendarFullAccess,
  Permission.calendarWriteOnly,
  Permission.reminders,
  Permission.bluetooth,
];

void main() => runApp(const PermissionsApp());

/// The demo app.
class PermissionsApp extends StatelessWidget {
  /// Creates the app.
  const PermissionsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: ListView(
            padding: MediaQuery.paddingOf(context) +
                const EdgeInsets.symmetric(horizontal: 8),
            children: <Widget>[
              for (final Permission permission in watchPermissions)
                PermissionTile(permission: permission),
            ],
          ),
        ),
      );
}

/// One permission: its name and status; a tap asks for it.
class PermissionTile extends StatefulWidget {
  /// Creates the tile for [permission].
  const PermissionTile({super.key, required this.permission});

  /// The permission it shows.
  final Permission permission;

  @override
  State<PermissionTile> createState() => _PermissionTileState();
}

class _PermissionTileState extends State<PermissionTile> {
  String _status = '…';

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final PermissionStatus status = await widget.permission.status;
    if (mounted) {
      setState(() => _status = status.name);
    }
  }

  Future<void> _ask() async {
    String status;
    try {
      status = (await widget.permission.request()).name;
    } on PlatformException catch (error) {
      status = error.code;
    }
    if (mounted) {
      setState(() => _status = status);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(widget.permission.toString().split('.').last),
        subtitle: Text(_status),
        onTap: _ask,
      );
}
