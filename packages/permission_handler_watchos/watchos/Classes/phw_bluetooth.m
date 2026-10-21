// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Bluetooth, through a CBCentralManager the strategy keeps: creating it is
// what asks the wearer, and its first state update is the answer, as in the
// iOS implementation. CoreBluetooth is loaded at runtime and only messaged.

#import "phw_internal.h"

#import <CoreBluetooth/CoreBluetooth.h>

static PHWStatus _bluetoothStatus(NSInteger authorization) {
    switch (authorization) {
        case CBManagerAuthorizationNotDetermined:
            return PHWStatusDenied;
        case CBManagerAuthorizationRestricted:
            return PHWStatusRestricted;
        case CBManagerAuthorizationDenied:
            return PHWStatusPermanentlyDenied;
        case CBManagerAuthorizationAllowedAlways:
            return PHWStatusGranted;
    }
    return PHWStatusDenied;
}

@interface PHWBluetoothStrategy () <CBCentralManagerDelegate>
@end

@implementation PHWBluetoothStrategy {
    CBCentralManager* _manager;
    NSMutableArray<PHWStatusHandler>* _requests;
    NSMutableArray<PHWServiceHandler>* _services;
}

- (Class)managerClass {
    return phw_class(@"CoreBluetooth", @"CBCentralManager");
}

- (PHWStatus)statusOf:(Class)managerClass {
    return _bluetoothStatus(phw_class_integer(managerClass, @selector(authorization)));
}

- (void)startManager:(Class)managerClass {
    if (_manager != nil) {
        return;
    }
    _requests = [NSMutableArray array];
    _services = [NSMutableArray array];
    // The option's key by its value: its constant would link CoreBluetooth.
    _manager = [[managerClass alloc] initWithDelegate:self
                                                queue:dispatch_get_main_queue()
                                              options:@{@"kCBInitOptionShowPowerAlert" : @NO}];
}

- (void)checkPermission:(PHWPermission)permission done:(PHWStatusHandler)done {
    Class managerClass = [self managerClass];
    done(managerClass == nil ? PHWStatusDenied : [self statusOf:managerClass]);
}

- (void)checkService:(PHWPermission)permission
                done:(PHWServiceHandler)done
              failed:(PHWErrorHandler)failed {
    Class managerClass = [self managerClass];
    if (managerClass == nil) {
        done(PHWServiceDisabled);
        return;
    }
    if (!phw_has_key(@"NSBluetoothAlwaysUsageDescription")) {
        phw_missing_key(@"NSBluetoothAlwaysUsageDescription", failed);
        return;
    }
    if (_manager != nil && _manager.state != CBManagerStateUnknown) {
        done(_manager.state == CBManagerStatePoweredOn ? PHWServiceEnabled
                                                       : PHWServiceDisabled);
        return;
    }
    [self startManager:managerClass];
    [_services addObject:done];
}

- (void)requestPermission:(PHWPermission)permission
                     done:(PHWStatusHandler)done
                   failed:(PHWErrorHandler)failed {
    Class managerClass = [self managerClass];
    if (managerClass == nil) {
        done(PHWStatusPermanentlyDenied);
        return;
    }
    PHWStatus status = [self statusOf:managerClass];
    if (status != PHWStatusDenied) {
        done(status);
        return;
    }
    if (!phw_has_key(@"NSBluetoothAlwaysUsageDescription")) {
        phw_missing_key(@"NSBluetoothAlwaysUsageDescription", failed);
        return;
    }
    if (_manager != nil && _manager.state != CBManagerStateUnknown) {
        // A manager already running has asked before: nothing will update.
        done(status);
        return;
    }
    [self startManager:managerClass];
    [_requests addObject:done];
}

- (void)centralManagerDidUpdateState:(CBCentralManager*)central {
    PHWStatus status = [self statusOf:[self managerClass]];
    NSArray<PHWStatusHandler>* requests = [_requests copy];
    [_requests removeAllObjects];
    for (PHWStatusHandler done in requests) {
        done(status);
    }
    PHWService service =
        central.state == CBManagerStatePoweredOn ? PHWServiceEnabled : PHWServiceDisabled;
    NSArray<PHWServiceHandler>* services = [_services copy];
    [_services removeAllObjects];
    for (PHWServiceHandler done in services) {
        done(service);
    }
}

@end
