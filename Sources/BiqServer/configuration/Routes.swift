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
	
	var recipeRoutes = TRoutes(baseUri: "/recipe", handler: RecipeHandlers.identity)
	do {
		recipeRoutes.add(method: .get, uri: "/get", handler: RecipeHandlers.recipeGet)
		recipeRoutes.add(method: .get, uri: "/del", handler: RecipeHandlers.recipeDel)
		recipeRoutes.add(method: .post, uri: "/set", handler: RecipeHandlers.recipeSet)
		recipeRoutes.add(method: .post, uri: "/tag/add", handler: RecipeHandlers.recipeTagAdd)
		recipeRoutes.add(method: .post, uri: "/tag/del", handler: RecipeHandlers.recipeTagRemove)
		recipeRoutes.add(method: .get,  uri: "/tag/get", handler: RecipeHandlers.recipeTagGet)
		recipeRoutes.add(method: .post, uri: "/media/add", handler: RecipeHandlers.recipeMediaAdd)
		recipeRoutes.add(method: .post, uri: "/media/del", handler: RecipeHandlers.recipeMediaRemove)
		recipeRoutes.add(method: .get,  uri: "/media/get", handler: RecipeHandlers.recipeMediaGet)
		recipeRoutes.add(method: .post, uri: "/threshold/add", handler: RecipeHandlers.recipeThresholdAdd)
		recipeRoutes.add(method: .post, uri: "/threshold/del", handler: RecipeHandlers.recipeThresholdRemove)
		recipeRoutes.add(method: .get,  uri: "/threshold/get", handler: RecipeHandlers.recipeThresholdGet)
		recipeRoutes.add(method: .get, uri: "/search", handler: RecipeHandlers.search)
	}
	v1.add(recipeRoutes)
	
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
		deviceRoutes.add(method: .post, uri: "/profile/update", handler: DeviceHandlers.deviceProfileUpdate)
		deviceRoutes.add(method: .get, uri: "/profile/get", handler: DeviceHandlers.deviceProfileGet)
		deviceRoutes.add(method: .get, uri: "/search", handler: DeviceHandlers.deviceSearch)
		deviceRoutes.add(method: .get, uri: "/stat", handler: DeviceHandlers.deviceStat)
		deviceRoutes.add(method: .get, uri: "/list", handler: DeviceHandlers.deviceList)
		deviceRoutes.add(method: .post, uri: "/register", handler: DeviceHandlers.deviceRegister)
		deviceRoutes.add(method: .post, uri: "/unregister", handler: DeviceHandlers.deviceUnregister)
		deviceRoutes.add(method: .post, uri: "/share", handler: DeviceHandlers.deviceShare)
		deviceRoutes.add(method: .post, uri: "/share/token", handler: DeviceHandlers.deviceGetShareToken)
		deviceRoutes.add(method: .post, uri: "/unshare", handler: DeviceHandlers.deviceUnshare)
		deviceRoutes.add(method: .post, uri: "/update", handler: DeviceHandlers.deviceUpdate)
		deviceRoutes.add(method: .get, uri: "/obs", handler: DeviceHandlers.deviceObs)
		deviceRoutes.add(method: .post, uri: "/obs/delete", handler: DeviceHandlers.deviceDeleteObs)
		deviceRoutes.add(method: .get, uri: "/info", handler: DeviceHandlers.deviceInfo)
		deviceRoutes.add(method: .get, uri: "/limits", handler: DeviceHandlers.deviceGetLimits)
		deviceRoutes.add(method: .post, uri: "/limits", handler: DeviceHandlers.deviceSetLimits)
		deviceRoutes.add(method: .post, uri: "/location", handler: DeviceHandlers.deviceUpdateLocation)
		deviceRoutes.add(method: .post, uri: "/followers", handler: DeviceHandlers.deviceFollowers)
		deviceRoutes.add(method: .get, uri: "/tag", handler: DeviceHandlers.deviceTag)
		deviceRoutes.add(method: .get, uri: "/tag/get", handler: DeviceHandlers.deviceTagGet)
		deviceRoutes.add(method: .post, uri: "/tag/add", handler: DeviceHandlers.deviceTagAdd)
		deviceRoutes.add(method: .post, uri: "/tag/del", handler: DeviceHandlers.deviceTagDel)
		deviceRoutes.add(method: .get, uri: "/type", handler: DeviceHandlers.deviceType)
		deviceRoutes.add(method: .post, uri: "/bookmark", handler: DeviceHandlers.setBookmark)
		deviceRoutes.add(method: .get, uri: "/firmware", handler: DeviceHandlers.firmware)
	}
	v1.add(deviceRoutes)
	
	var chatRoutes = TRoutes(baseUri: "/chat", handler: ChatHandlers.identity)
	do {
		chatRoutes.add(method: .post, uri: "/save", handler: ChatHandlers.save)
		chatRoutes.add(method: .get, uri: "/load", handler: ChatHandlers.load)
	}
	v1.add(chatRoutes)
	
	var fileRoutes = TRoutes(baseUri: "/profile", handler: ProfileHandlers.identity)
	do {
		fileRoutes.add(method: .post, uri: "/upload", handler: ProfileHandlers.uploadImage)
		fileRoutes.add(method: .get, uri: "/download", handler: ProfileHandlers.downloadImage)
		fileRoutes.add(method: .post, uri: "/update", handler: ProfileHandlers.uploadText)
		fileRoutes.add(method: .get, uri: "/get", handler: ProfileHandlers.downloadText)
		fileRoutes.add(method: .get, uri: "/name", handler: ProfileHandlers.userFullName)
		fileRoutes.add(method: .post, uri: "/bill", handler: ProfileHandlers.validate)
	}
	v1.add(fileRoutes)
	
	routes.add(v1)
	return routes
}
