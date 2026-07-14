// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// getifaddrs-based network info for watchOS. SSID/BSSID and gateway are not
// exposed — those rely on CaptiveNetwork / routing-table APIs that watchOS
// does not provide — so this file implements only the addressing getters.

#import "network_info_plus_watchos_ffi.h"

#import <Foundation/Foundation.h>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>

// Which address field to read off each interface.
typedef enum {
    kFieldAddress,
    kFieldNetmask,
    kFieldBroadcast,
} AddrField;

static struct sockaddr* _field(struct ifaddrs* ifa, AddrField field) {
    switch (field) {
        case kFieldAddress:
            return ifa->ifa_addr;
        case kFieldNetmask:
            return ifa->ifa_netmask;
        case kFieldBroadcast:
            return ifa->ifa_dstaddr;  // broadcast addr for AF_INET, IFF_BROADCAST
    }
    return NULL;
}

// Formats a sockaddr of `family` into a heap string, or NULL.
static char* _format(struct sockaddr* sa, int family) {
    if (sa == NULL || sa->sa_family != family) {
        return NULL;
    }
    char buf[INET6_ADDRSTRLEN] = {0};
    if (family == AF_INET) {
        struct sockaddr_in* in = (struct sockaddr_in*)sa;
        if (inet_ntop(AF_INET, &in->sin_addr, buf, sizeof(buf)) == NULL) {
            return NULL;
        }
    } else {
        struct sockaddr_in6* in6 = (struct sockaddr_in6*)sa;
        if (inet_ntop(AF_INET6, &in6->sin6_addr, buf, sizeof(buf)) == NULL) {
            return NULL;
        }
    }
    return strdup(buf);
}

// Walks getifaddrs for the given family/field. Prefers "en0" (the primary
// interface on Apple platforms); otherwise the first non-loopback, up
// interface. Link-local IPv6 (fe80::) is skipped so a routable address wins.
static char* _lookup(int family, AddrField field) {
    struct ifaddrs* ifaddr = NULL;
    if (getifaddrs(&ifaddr) != 0 || ifaddr == NULL) {
        return NULL;
    }

    char* preferred = NULL;   // from en0
    char* fallback = NULL;    // from any other eligible interface

    for (struct ifaddrs* ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != family) {
            continue;
        }
        if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_LOOPBACK)) {
            continue;
        }
        struct sockaddr* sa = _field(ifa, field);
        if (family == AF_INET6 && field == kFieldAddress) {
            struct sockaddr_in6* in6 = (struct sockaddr_in6*)sa;
            if (in6 != NULL && IN6_IS_ADDR_LINKLOCAL(&in6->sin6_addr)) {
                continue;  // prefer a global address
            }
        }
        char* formatted = _format(sa, family);
        if (formatted == NULL) {
            continue;
        }
        if (ifa->ifa_name != NULL && strcmp(ifa->ifa_name, "en0") == 0) {
            free(preferred);
            preferred = formatted;
        } else if (fallback == NULL) {
            fallback = formatted;
        } else {
            free(formatted);
        }
    }

    freeifaddrs(ifaddr);
    if (preferred != NULL) {
        free(fallback);
        return preferred;
    }
    return fallback;
}

char* network_info_plus_watchos_wifi_ip(void) {
    return _lookup(AF_INET, kFieldAddress);
}

char* network_info_plus_watchos_wifi_ipv6(void) {
    return _lookup(AF_INET6, kFieldAddress);
}

char* network_info_plus_watchos_wifi_submask(void) {
    return _lookup(AF_INET, kFieldNetmask);
}

char* network_info_plus_watchos_wifi_broadcast(void) {
    return _lookup(AF_INET, kFieldBroadcast);
}

void network_info_plus_watchos_free(char* ptr) {
    if (ptr != NULL) {
        free(ptr);
    }
}
