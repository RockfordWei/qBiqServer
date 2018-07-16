//
//  GroupHandlers.swift
//  BIQServer
//
//  Created by Kyle Jessup on 2017-12-19.
//

import Foundation
import PerfectHTTP
import PerfectCRUD
import SwiftCodables
import SAuthCodables

struct GroupHandlers {
	static func identity(session rs: RequestSession) throws -> RequestSession {
		return rs
	}
	
	static func groupList(session rs: RequestSession) throws -> [BiqDeviceGroup] {
		let (_, session) = rs
		let db = Database(configuration: try biqDatabaseInfo.databaseConfiguration())
		let table = db.table(BiqDeviceGroup.self)
		let list = try table
			.join(\.devices,
				  with: BiqDeviceGroupMembership.self,
				  on: \.id,
				  equals: \.groupId,
				  and: \.id,
				  is: \.deviceId)
			.where(\BiqDeviceGroup.ownerId == session.id)
		let i = try list.select()
		return i.map { $0 }
	}
	
	static func groupCreate(session rs: RequestSession) throws -> BiqDeviceGroup {
		let (request, session) = rs
		let createRequest: GroupAPI.CreateRequest = try request.decode()
		let db = try biqDatabaseInfo.deviceDb()
		let newId = UUID()
		let newOne = BiqDeviceGroup(id: newId, ownerId: session.id, name: createRequest.name)
		let table = db.table(BiqDeviceGroup.self)
		try table.insert(newOne)
		return newOne
	}
	
	static func groupUpdate(session rs: RequestSession) throws -> EmptyReply {
		let (request, session) = rs
		let updateRequest: GroupAPI.UpdateRequest = try request.decode()
		guard let newName = updateRequest.name else {
			return EmptyReply()
		}
		let db = try biqDatabaseInfo.deviceDb()
		let updateObj = BiqDeviceGroup(id: updateRequest.groupId, ownerId: UUID(), name: newName)
		try db.table(BiqDeviceGroup.self)
			.where(\BiqDeviceGroup.id == updateRequest.groupId &&
				\BiqDeviceGroup.ownerId == session.id)
			.update(updateObj, setKeys: \.name)
		return EmptyReply()
	}
	
	static func groupDelete(session rs: RequestSession) throws -> EmptyReply {
		let (request, session) = rs
		let deleteRequest: GroupAPI.DeleteRequest = try request.decode()
		let db = try biqDatabaseInfo.deviceDb()
		return try db.transaction {
			guard let group = try db.table(BiqDeviceGroup.self)
				.where(\BiqDeviceGroup.id == deleteRequest.groupId &&
					\BiqDeviceGroup.ownerId == session.id).first() else {
						return EmptyReply()
			}
			try db.table(BiqDeviceGroupMembership.self)
				.where(\BiqDeviceGroupMembership.groupId == group.id)
				.delete()
			try db.table(BiqDeviceGroup.self)
				.where(\BiqDeviceGroup.id == group.id)
				.delete()
			return EmptyReply()
		}
	}
}

extension GroupHandlers {
	static func groupDeviceAdd(session rs: RequestSession) throws -> EmptyReply {
		let (request, session) = rs
		let addRequest: GroupAPI.AddDeviceRequest = try request.decode()
		let db = try biqDatabaseInfo.deviceDb()
		let deviceTable = db.table(BiqDevice.self)
		let groupDeviceTable = db.table(BiqDeviceGroupMembership.self)
		return try db.transaction {
			guard let device = try deviceTable.where(\BiqDevice.id == addRequest.deviceId).first() else {
				throw HTTPResponseError(status: .badRequest, description: "Device does not exist.")
			}
			guard let group = try db.table(BiqDeviceGroup.self)
				.where(\BiqDeviceGroup.id == addRequest.groupId &&
					\BiqDeviceGroup.ownerId == session.id).first() else {
				throw HTTPResponseError(status: .badRequest, description: "Group does not exist.")
			}
			// is this user the owner?
			// this is where we would check ownership vs. follow-invite
			if device.ownerId != session.id {
				let shareTable = db.table(BiqDeviceAccessPermission.self)
				guard try shareTable.where(
					\BiqDeviceAccessPermission.deviceId == device.id &&
						\BiqDeviceAccessPermission.userId == session.id).count() != 0 else {
							throw HTTPResponseError(status: .badRequest, description: "User is not device owner and device has not been shared.")
				}
			}
			guard try groupDeviceTable
				.where(
					\BiqDeviceGroupMembership.groupId == group.id &&
						\BiqDeviceGroupMembership.deviceId == device.id).count() == 0 else {
							return EmptyReply()
			}
			let newOne = BiqDeviceGroupMembership(groupId: group.id, deviceId: device.id)
			try groupDeviceTable.insert(newOne)
			return EmptyReply()
		}
	}
	
	static func groupDeviceRemove(session rs: RequestSession) throws -> EmptyReply {
		let (request, session) = rs
		let addRequest: GroupAPI.AddDeviceRequest = try request.decode()
		let db = try biqDatabaseInfo.deviceDb()
		let deviceTable = db.table(BiqDevice.self)
		let groupDeviceTable = db.table(BiqDeviceGroupMembership.self)
		return try db.transaction {
			guard let device = try deviceTable
				.where(\BiqDevice.id == addRequest.deviceId)
				.first() else {
					throw HTTPResponseError(status: .badRequest, description: "Device does not exist.")
			}
			guard let group = try db.table(BiqDeviceGroup.self)
				.where(\BiqDeviceGroup.id == addRequest.groupId &&
					\BiqDeviceGroup.ownerId == session.id)
				.first() else {
					throw HTTPResponseError(status: .badRequest, description: "Group does not exist.")
			}
			try groupDeviceTable
				.where(\BiqDeviceGroupMembership.groupId == group.id &&
					\BiqDeviceGroupMembership.deviceId == device.id)
				.delete()
			return EmptyReply()
		}
	}
	
	static func groupDeviceList(session rs: RequestSession) throws -> [BiqDevice] {
		let (request, session) = rs
		let listRequest: GroupAPI.ListDevicesRequest = try request.decode()
		let db = try biqDatabaseInfo.deviceDb()
		let deviceGroupTable = db.table(BiqDeviceGroup.self)
		let devicesTable = db.table(BiqDevice.self)
		return try db.transaction {
			guard let group = try deviceGroupTable
				.where(\BiqDeviceGroup.id == listRequest.groupId &&
					\BiqDeviceGroup.ownerId == session.id)
				.first() else {
					throw HTTPResponseError(status: .badRequest, description: "Group does not exist.")
			}
			return try devicesTable
				.join(\.groupMemberships, on: \.id, equals: \.deviceId)
				.where(\BiqDeviceGroupMembership.groupId == group.id)
				.select().map{ BiqDevice(id: $0.id, name: $0.name) }
		}
	}
}
