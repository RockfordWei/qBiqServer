//
//  Routes.swift
//

import Foundation
import PerfectHTTP
import PerfectHTTPServer
import PerfectCRUD

let apiVersion1 = "v1"
let apiVersion = apiVersion1

func mainRoutes() -> Routes {
	var routes = Routes()
	routes.add(TRoute(method: .get, uri: "/healthcheck", handler: Handlers.healthCheck))
	
	var v1 = TRoutes(baseUri: "/\(apiVersion)", handler: Handlers.authCheck)
	
	var groupRoutes = TRoutes(baseUri: "/group", handler: GroupHandlers.identity)
	do {
		groupRoutes.add(method: .get, uri: "/list", handler: GroupHandlers.groupList)
		groupRoutes.add(method: .post, uri: "/create", handler: GroupHandlers.groupCreate)
		groupRoutes.add(method: .post, uri: "/update", handler: GroupHandlers.groupUpdate)
		groupRoutes.add(method: .post, uri: "/delete", handler: GroupHandlers.groupDelete)
		groupRoutes.add(method: .post, uri: "/device/add", handler: GroupHandlers.groupDeviceAdd)
		groupRoutes.add(method: .post, uri: "/device/remove", handler: GroupHandlers.groupDeviceRemove)
		groupRoutes.add(method: .get, uri: "/device/list", handler: GroupHandlers.groupDeviceList)
	}
	v1.add(groupRoutes)
	
	var deviceRoutes = TRoutes(baseUri: "/device", handler: DeviceHandlers.identity)
	do {
		deviceRoutes.add(method: .get, uri: "/list", handler: DeviceHandlers.deviceList)
		deviceRoutes.add(method: .post, uri: "/register", handler: DeviceHandlers.deviceRegister)
		deviceRoutes.add(method: .post, uri: "/unregister", handler: DeviceHandlers.deviceUnregister)
		deviceRoutes.add(method: .post, uri: "/share", handler: DeviceHandlers.deviceShare)
		deviceRoutes.add(method: .post, uri: "/share/token", handler: DeviceHandlers.deviceGetShareToken)
		deviceRoutes.add(method: .post, uri: "/unshare", handler: DeviceHandlers.deviceUnshare)
		deviceRoutes.add(method: .post, uri: "/update", handler: DeviceHandlers.deviceUpdate)
		deviceRoutes.add(method: .get, uri: "/obs", handler: DeviceHandlers.deviceObs)
    deviceRoutes.add(method: .get, uri: "/sum", handler: DeviceHandlers.deviceSum)
		deviceRoutes.add(method: .post, uri: "/obs/delete", handler: DeviceHandlers.deviceDeleteObs)
		deviceRoutes.add(method: .get, uri: "/info", handler: DeviceHandlers.deviceInfo)
		deviceRoutes.add(method: .get, uri: "/limits", handler: DeviceHandlers.deviceGetLimits)
		deviceRoutes.add(method: .post, uri: "/limits", handler: DeviceHandlers.deviceSetLimits)
	}
	v1.add(deviceRoutes)
	
	routes.add(v1)
	return routes
}
