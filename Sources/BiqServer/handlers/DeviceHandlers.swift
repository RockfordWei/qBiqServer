//
//  DeviceHandlers.swift
//  BIQServer
//
//  Created by Kyle Jessup on 2017-12-20.
//

import Foundation
import PerfectHTTP
import PerfectCRUD
import SwiftCodables
import SAuthCodables
import PerfectLib

let secondsPerDay = 86400

func shareTokenKey(_ uuid: Foundation.UUID, deviceId: DeviceURN) -> String {
	return "share-token:\(uuid):\(deviceId)"
}

public struct QBiqStat: Codable {
  public let owned: Int
  public let followed: Int
  public let following: Int
}

public struct QBiqSearchResult: Codable {
  public let id: String
  public let name: String
}

public struct QBiqTagSearchResult: Codable {
  public let id: String
  public let name: String
  public let description: String
  public let tags: [String]
}

public struct QBiqProfileRecord: Codable {
  public let id: DeviceURN
  public let description: String
}

public struct QBiqProfileTag: Codable {
  public let id: DeviceURN
  public let tag: String
}

public struct QBiqProfile: Codable {
  public let id: DeviceURN
  public let description: String
  public let tags: [String]
}

public struct QBiqLocationUpdate: Codable {
  public let id: DeviceURN
  public let x: Double
  public let y: Double
}

public enum QBiqError: Error {
  case reason(String)
}

public extension QBiqProfile {

	static func load(id: DeviceURN) throws -> QBiqProfile? {
    let db = try biqDatabaseInfo.deviceDb()
    let records: [QBiqProfileRecord] = try db.table(QBiqProfileRecord.self).where(\QBiqProfileRecord.id == id).select().map { $0 }
    let tags = try db.table(QBiqProfileTag.self).where(\QBiqProfileTag.id == id).select().map { $0.tag }
    if let me = records.first {
      return QBiqProfile.init(id: id, description: me.description, tags: tags)
    } else {
      return QBiqProfile.init(id: id, description: "", tags: tags)
    }
  }

	static func setup() throws {
    let db = try biqDatabaseInfo.deviceDb()
    try db.sql(
      """
CREATE TABLE IF NOT EXISTS QBiqProfileRecord (
  id VARCHAR(36) NOT NULL PRIMARY KEY,
  description VARCHAR(1024) DEFAULT ''
);
""")
    try db.sql(
      """
CREATE TABLE IF NOT EXISTS QBiqProfileTag (
  id VARCHAR(36) NOT NULL,
  tag VARCHAR(64) NOT NULL,
  PRIMARY KEY (id, tag)
);
""")
  }
	func save(uid: Foundation.UUID) throws {
    let db = try biqDatabaseInfo.deviceDb()
    guard let _ = try db.table(BiqDevice.self).where(\BiqDevice.id == self.id && \BiqDevice.ownerId == uid).first() else {
      throw QBiqError.reason("invalid owner id")
    }
    let prof = QBiqProfileRecord.init(id: self.id, description: self.description)
    let tb = db.table(QBiqProfileTag.self)
    let tbprof = db.table(QBiqProfileRecord.self)
    try db.transaction {
			try tbprof.where(\QBiqProfileRecord.id == self.id).delete()
      try tb.where(\QBiqProfileTag.id == self.id).delete()
			try tbprof.insert(prof)
      for t in self.tags {
        let r = QBiqProfileTag.init(id: self.id, tag: t)
        try tb.insert(r)
      }
    }
  }
}

func secsToBeginningOfHour(_ secs: Double) -> Double {
	let then = Date(timeIntervalSince1970: secs)
	let minute = Double(Calendar.current.component(.minute, from: then))
	let trueThenSecs = secs - (minute * 60)
	return trueThenSecs
}

func secsToBeginningOfDay(_ secs: Double) -> Double {
	let then = Date(timeIntervalSince1970: secs)
	let hour = Double(Calendar.current.component(.hour, from: then))
	let trueThenSecs = secs - (hour * 60 * 60)
	return trueThenSecs
}

let defaultReportInterval = Float(3600.0)
let defaultLimits: [DeviceAPI.DeviceLimit] = [
	.init(limitType: .tempHigh, limitValue: 28.0, limitFlag: .none),
	.init(limitType: .tempLow, limitValue: 12.0, limitFlag: .none),
	.init(limitType: .movementLevel, limitValue: 1.0, limitFlag: .none),
	.init(limitType: .batteryLevel, limitValue: 10.0, limitFlag: .none),
	.init(limitType: .interval, limitValue: defaultReportInterval, limitFlag: .none),
]

private func userHasDeviceAccess<C: DatabaseConfigurationProtocol>(db: Database<C>, deviceId: DeviceURN, userId: UserId) throws -> BiqDevice? {
	let table = db.table(BiqDevice.self)
	return try table
		.join(\.accessPermissions, on: \.id, equals: \.deviceId)
		.where(
			\BiqDevice.id == deviceId &&
				(\BiqDevice.ownerId == userId ||
					\BiqDeviceAccessPermission.userId == userId)).first()
}

struct DeviceHandlers {
	static func identity(session rs: RequestSession) throws -> RequestSession {
		return rs
	}

	static func deviceType(session rs: RequestSession) throws -> ProfileAPIResponse {
		var p = ProfileAPIResponse()
		guard let bixid = rs.request.param(name: "id"),
			let move = rs.request.param(name: "move"),
			let movementEnabled = Int(move) else {
				p.content = "Invalid Parameters"
				return p
		}
		let db = try biqDatabaseInfo.deviceDb()
		guard let _ = try db.table(BiqDevice.self).where(\BiqDevice.id == bixid && \BiqDevice.ownerId == rs.session.id).first() else {
			p.content = "Unregistered device or unauthorized operation"
			return p
		}
		let flag = movementEnabled > 0 ? 2 : 4
		try db.sql("UPDATE BiqDevice SET flags = \(flag) WHERE id = '\(bixid)'")
		p.content = "\(flag)"
		return p
	}
	
  static func deviceTag(session rs: RequestSession) throws -> [QBiqTagSearchResult] {
    guard let tag = rs.request.param(name: "with"), !tag.isEmpty else {
      throw QBiqError.reason("empty")
    }
    let sql =
"""
SELECT * FROM (SELECT BiqDevice.id AS id, BiqDevice.name AS name,
  QBiqProfileRecord.description AS description
FROM BiqDevice
LEFT JOIN QBiqProfileRecord ON BiqDevice.id = QBiqProfileRecord.id) AS BiqDeviceProfile
WHERE id IN (SELECT id FROM QBiqProfileTag WHERE tag LIKE '%\(tag)%');
"""
    struct QBiqSimpleProfile: Codable {
      public let id: String
      public let name: String
      public let description: String
    }
    let db = try biqDatabaseInfo.deviceDb()
    let simple: [QBiqSimpleProfile] = try db.sql(sql, QBiqSimpleProfile.self)
    return try simple.map { prof -> QBiqTagSearchResult in
      let tags = try db.table(QBiqProfileTag.self).where(\QBiqProfileTag.id == prof.id).select().map { $0.tag }
      return QBiqTagSearchResult.init(id: prof.id, name: prof.name, description: prof.description, tags: tags)
    }
  }

  static func deviceFollowers(session rs: RequestSession) throws -> [String] {
    let db = try biqDatabaseInfo.deviceDb()
    if let deviceId = rs.request.postBodyString {
      let guests = try db.table(BiqDeviceAccessPermission.self).where(\BiqDeviceAccessPermission.deviceId == deviceId).select()
      return guests.map { $0.userId.uuidString.lowercased() }
    } else {
      let oid = rs.session.id.uuidString.lowercased()
      return try db.sql("SELECT DISTINCT userid FROM biqdeviceaccesspermission WHERE deviceid IN (SELECT id FROM biqdevice WHERE ownerid = $1)",
                        bindings: [("$1", .string(oid))], String.self)
    }
  }

  static func deviceUpdateLocation(session rs: RequestSession) throws -> ProfileAPIResponse {
    guard let postbody = rs.request.postBodyBytes else {
      throw QBiqError.reason("empty")
    }
    let postdata = Data.init(bytes: postbody)
    let profile = try JSONDecoder.init().decode(QBiqLocationUpdate.self, from: postdata)
    let db = try biqDatabaseInfo.deviceDb()

    try db.sql("UPDATE biqdevice SET longitude = $1, latitude = $2 WHERE id = $3 AND ownerid = $4", bindings: [
      ("$1", .decimal(profile.x)), ("$2", .decimal(profile.y)),
      ("$3", .string(profile.id)), ("$4", .string(rs.session.id.uuidString.lowercased()))
      ])
    return ProfileAPIResponse.init(content: "updated")
  }
  
  static func deviceProfileUpdate(session rs: RequestSession) throws -> ProfileAPIResponse {
    guard let postbody = rs.request.postBodyBytes else {
      throw QBiqError.reason("empty")
    }
    let postdata = Data.init(bytes: postbody)
    let profile = try JSONDecoder.init().decode(QBiqProfile.self, from: postdata)
    try profile.save(uid: rs.session.id)
    return ProfileAPIResponse.init(content: "updated")
  }

  static func deviceProfileGet(session rs: RequestSession) throws -> QBiqProfile {
    guard let uid = rs.request.param(name: "uid"), !uid.isEmpty else {
      throw QBiqError.reason("empty")
    }
    guard let prof = try QBiqProfile.load(id: uid) else {
      throw QBiqError.reason("invalid")
    }
    return prof
  }

  static func deviceSearch(session rs: RequestSession) throws -> [QBiqSearchResult] {
    guard let uid = rs.request.param(name: "uid"), !uid.isEmpty else {
      return []
    }
    let db = try biqDatabaseInfo.deviceDb()
    let sql = "SELECT * FROM biqdevice WHERE id LIKE '%\(uid)' OR name LIKE '%\(uid)%' LIMIT 5"
    let devTable = try db.sql(sql, BiqDevice.self)
    return devTable.map { QBiqSearchResult.init(id: $0.id, name: $0.name) }
  }

  static func deviceStat(session rs: RequestSession) throws -> QBiqStat {
    guard let id = rs.request.param(name: "uid"),
      let uid = UUID.init(uuidString: id)  else {
      return QBiqStat.init(owned: -1, followed: -1, following: -1)
    }
    let db = try biqDatabaseInfo.deviceDb()
    let owned = try db.table(BiqDevice.self).where(\BiqDevice.ownerId == uid).select().map { $0.id }
    let followed: [String]
    if owned.isEmpty {
      followed = []
    } else {
      followed = try db.table(BiqDeviceAccessPermission.self).where(\BiqDeviceAccessPermission.deviceId ~ owned).select().map { $0.userId.uuidString.lowercased() }
    }
    let uniqFollowed = Set<String>(followed)
    let following = try db.table(BiqDeviceAccessPermission.self).where(\BiqDeviceAccessPermission.userId == uid).count()
    return QBiqStat.init(owned: owned.count, followed: uniqFollowed.count, following: following)
  }

	private static func getLimits<C: DatabaseConfigurationProtocol>(
								  db: Database<C>,
								  deviceId: DeviceURN,
								  ownerId: UserId,
								  userId: UserId) throws -> [DeviceAPI.DeviceLimit] {
		let sql =
			"""
			SELECT * FROM \(BiqDeviceLimit.CRUDTableName)
			WHERE deviceid = $1
				AND (userid = $2 OR (userid = $3 AND 0 != (limitflag & \(BiqDeviceLimitFlag.ownerShared.rawValue))))
			"""
		let userLimits = try db.sql(sql,
									bindings: [("$1", .string(deviceId)), ("$2", .uuid(userId)), ("$3", .uuid(ownerId))],
									BiqDeviceLimit.self)
		return userLimits.compactMap {
			return DeviceAPI.DeviceLimit(limitType: $0.type,
										 limitValue: $0.limitValue,
										 limitValueString: $0.limitValueString,
										 limitFlag: $0.flag)
		}
	}
	
	private static func setStandardLimits<C: DatabaseConfigurationProtocol>(
												db: Database<C>,
												deviceId: DeviceURN,
												userId: UserId) {
		let limitsTable = db.table(BiqDeviceLimit.self)
		let models = defaultLimits.map {
			BiqDeviceLimit(userId: userId,
						   deviceId: deviceId,
						   limitType: $0.limitType,
						   limitValue: $0.limitValue ?? 0.0,
						   limitValueString: $0.limitValueString,
						   limitFlag: .none)
		}
		_ = try? limitsTable.insert(models)
		_ = try? biqDatabaseInfo.obsDb().table(BiqDevicePushLimit.self).insert(BiqDevicePushLimit(deviceId: deviceId, limitType: .interval, limitValue: defaultReportInterval, limitValueString: nil))
	}
	
	static func deviceList(session rs: RequestSession) throws -> [DeviceAPI.ListDevicesResponseItem] {
		let (_, session) = rs
		let userId = session.id
		let db1 = Database(configuration: try biqDatabaseInfo.databaseConfiguration())
		let table = db1.table(BiqDevice.self)
		let list = try table
			.join(\.accessPermissions, on: \.id, equals: \.deviceId)
			.where(
				\BiqDevice.ownerId == userId ||
					\BiqDeviceAccessPermission.userId == userId).select()
		let devices = list.map { $0 }
		do {
			let db = Database(configuration: try biqObsDatabaseInfo.databaseConfiguration(database: "biq"))
			let shareTable = db1.table(BiqDeviceAccessPermission.self)
			let table = db.table(ObsDatabase.BiqObservation.self)
							.order(descending: \.obstime)
							.limit(1)
			let obs = try devices.map {
				return try table
					.where(\ObsDatabase.BiqObservation.deviceId == $0.id)
					.first()
			}
			var shares = try devices.map {
				try shareTable.where(\BiqDeviceAccessPermission.deviceId == $0.id).count()
			}.makeIterator()
			var limits = try devices.map {
				device -> [DeviceAPI.DeviceLimit] in
				guard let ownerId = device.ownerId else {
					return []
				}
				return try getLimits(db: db1, deviceId: device.id, ownerId: ownerId, userId: userId)
			}.makeIterator()
			
			let ret = zip(devices, obs).map {
				DeviceAPI.ListDevicesResponseItem(device: $0.0, shareCount: shares.next() ?? 0, lastObservation: $0.1, limits: limits.next() ?? [])
			}
			return ret
		}
	}
	
	static func deviceRegister(session rs: RequestSession) throws -> BiqDevice {
		let (request, session) = rs
		let registerRequest: DeviceAPI.RegisterRequest = try request.decode()
		let deviceId = registerRequest.deviceId
		// validate the urn to ensure it is
		// valid for an unowned-biq
		let db = try biqDatabaseInfo.deviceDb()
		let newOne = try db.transaction {
			() -> BiqDevice in
			let table = db.table(BiqDevice.self)
			guard let device = try table.where(\BiqDevice.id == deviceId).first() else {
				throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
			}
			let newOne: BiqDevice
			let flags = BiqDeviceFlag(rawValue: device.flags ?? 0)
			if let currentOwner = device.ownerId {
				if currentOwner == session.id { // already owner
					newOne = device
				} else { // valid biq, but already owned by someone else
					newOne = BiqDevice(id: deviceId, name: "", flags: flags)
				}
			} else {
				newOne = BiqDevice(id: device.id,
								   name: device.name,
								   ownerId: session.id,
								   flags: flags)
				try table.where(\BiqDevice.id == deviceId).update(newOne, setKeys: \.ownerId)
			}
			return newOne
		}
		setStandardLimits(db: db, deviceId: deviceId, userId: session.id)
		return newOne
	}
	
	static func deviceUnregister(session rs: RequestSession) throws -> EmptyReply {
		let (request, session) = rs
		let registerRequest: DeviceAPI.RegisterRequest = try request.decode()
		let deviceId = registerRequest.deviceId
		let db = try biqDatabaseInfo.deviceDb()
		try db.transaction {
			let deviceOk = try db.table(BiqDevice.self)
				.where(\BiqDevice.id == deviceId && \BiqDevice.ownerId == session.id)
				.count()
			guard deviceOk == 1 else {
				throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
			}
			// clear out owner's info
			// this is sql because of the bit flip op
			try db.sql(
				"""
				update \(BiqDevice.CRUDTableName)
				set ownerid=NULL, latitude=NULL, longitude=NULL, flags=(flags & ~1)
				where id=$1 and ownerid=$2
				""", bindings: [("$1", .string(deviceId)), ("$2", .uuid(session.id))])
			// remove all limits
			try db.table(BiqDeviceLimit.self)
				.where(\BiqDeviceLimit.deviceId == deviceId)
				.delete()
			// remove from all groups
			try db.table(BiqDeviceGroupMembership.self)
				.where(\BiqDeviceGroupMembership.deviceId == deviceId)
				.delete()
			// remove all shares
			try db.table(BiqDeviceAccessPermission.self)
				.where(\BiqDeviceAccessPermission.deviceId == deviceId)
				.delete()
		}
		return EmptyReply()
	}
	
	static func deviceShare(session rs: RequestSession) throws -> BiqDevice {
		let (request, session) = rs
		let shareRequest: DeviceAPI.ShareRequest = try request.decode()
		let deviceId = shareRequest.deviceId
		// if there is a share token, validate that here outside of the xaction
		let validatedShare: Bool
		if let shareToken = shareRequest.token {
			let key = shareTokenKey(shareToken, deviceId: deviceId)
			let client = try biqRedisInfo.client()
			let response = try client.delete(keys: key)
			guard case .integer(let i) = response, i == 1 else {
				throw HTTPResponseError(status: .badRequest, description: "Invalid share token.")
			}
			validatedShare = true
		} else {
			validatedShare = false
		}
		let db = try biqDatabaseInfo.deviceDb()
		return try db.transaction {
			let deviceTable = db.table(BiqDevice.self)
			guard let device = try deviceTable.where(\BiqDevice.id == deviceId && \BiqDevice.ownerId != nil).first() else {
				throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
			}
			if device.ownerId == session.id {
				return device
			}
			guard !device.deviceFlags.contains(.locked) || validatedShare else {
				throw HTTPResponseError(status: .forbidden, description: "Device locked.")
			}
			let shareTable = db.table(BiqDeviceAccessPermission.self)
			guard try shareTable.where(\BiqDeviceAccessPermission.userId == session.id && \BiqDeviceAccessPermission.deviceId == device.id).count() == 0 else {
				return device
			}
			let perm = BiqDeviceAccessPermission(userId: session.id, deviceId: device.id)
			try shareTable.insert(perm)
			return device
		}
	}
	
	static func deviceUnshare(session rs: RequestSession) throws -> EmptyReply {
		let (request, session) = rs
		let shareRequest: DeviceAPI.ShareRequest = try request.decode()
		let deviceId = shareRequest.deviceId
		let db = try biqDatabaseInfo.deviceDb()
		try db.transaction {
			let accessTableMatch = db.table(BiqDeviceAccessPermission.self)
				.where(\BiqDeviceAccessPermission.userId == session.id && \BiqDeviceAccessPermission.deviceId == deviceId)
			guard try accessTableMatch.count() != 0 else {
				throw HTTPResponseError(status: .badRequest, description: "Not a shared device.")
			}
			try accessTableMatch.delete()
			try db.table(BiqDeviceLimit.self)
				.where(\BiqDeviceLimit.userId == session.id && \BiqDeviceLimit.deviceId == deviceId)
				.delete()
			try db.sql(
				"""
				delete from \(BiqDeviceGroupMembership.CRUDTableName)
				where deviceid = $1 and groupid in (select id from \(BiqDeviceGroup.CRUDTableName) where ownerid = $2)
				""", bindings: [("$1", .string(deviceId)), ("$2", .uuid(session.id))])
		}
		return EmptyReply()
	}
	
	static func deviceGetShareToken(session rs: RequestSession) throws -> DeviceAPI.ShareTokenResponse {
		let (request, session) = rs
		let shareTokenRequest: DeviceAPI.ShareTokenRequest = try request.decode()
		let deviceId = shareTokenRequest.deviceId
		
		// must be owner
		let db = try biqDatabaseInfo.deviceDb()
		guard try db.table(BiqDevice.self).where(\BiqDevice.id == deviceId && \BiqDevice.ownerId == session.id).count() == 1 else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
		}
    guard let device = try db.table(BiqDevice.self).where(\BiqDevice.id == deviceId).first(), !device.deviceFlags.contains(.locked) else {
      throw HTTPResponseError(status: .forbidden, description: "Device is locked.")
    }

		let shareToken = Foundation.UUID()
		let key = shareTokenKey(shareToken, deviceId: deviceId)
		let client = try biqRedisInfo.client()
		let response = try client.set(key: key, value: .string("1"), expires: Double(deviceShareTokenExpirationDays * secondsPerDay), ifNotExists: true)
		guard response.isSimpleOK else {
			throw HTTPResponseError(status: .internalServerError, description: "Unable to create device share token.")
		}
		return .init(token: shareToken)
	}
	
	static func deviceInfo(session rs: RequestSession) throws -> BiqDevice {
		let (request, _) = rs
		let shareRequest: DeviceAPI.GenericDeviceRequest = try request.decode()
		let deviceId = shareRequest.deviceId
		let db = try biqDatabaseInfo.deviceDb()
		let deviceTable = db.table(BiqDevice.self)
		guard let device = try deviceTable.where(\BiqDevice.id == deviceId).first() else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
		}
		return device
	}
	
	static func deviceGetLimits(session rs: RequestSession) throws -> DeviceAPI.DeviceLimitsResponse {
		let (request, session) = rs
		let limitsRequest: DeviceAPI.LimitsRequest = try request.decode()
		let deviceId = limitsRequest.deviceId
		let db = try biqDatabaseInfo.deviceDb()
		guard let device = try db.table(BiqDevice.self).where(\BiqDevice.id == deviceId).first() else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
		}
		guard let ownerId = device.ownerId else {
			throw HTTPResponseError(status: .badRequest, description: "device has not been assigned to anyone")
		}
		var limits: [DeviceAPI.DeviceLimit] = []
		if device.deviceFlags.contains(.locked) {
			throw HTTPResponseError(status: .badRequest, description: "User is not device owner and device has been locked.")
		} else {
			if session.id == ownerId {
				limits = try getLimits(db: db, deviceId: deviceId, ownerId: ownerId, userId: session.id)
			} else {
				limits = try getLimits(db: db, deviceId: deviceId, ownerId: ownerId, userId: ownerId)
				limits = limits.filter { $0.limitType != .notifications }

				let sql =
				"""
				SELECT * FROM \(BiqDeviceLimit.CRUDTableName)
				WHERE deviceid = $1 AND userid = $2
				AND limittype = \(BiqDeviceLimitType.notifications.rawValue)
				"""
				let notes = try db.sql(sql,
																		bindings: [("$1", .string(deviceId)), ("$2", .uuid(session.id))],
																		BiqDeviceLimit.self).compactMap {
					return DeviceAPI.DeviceLimit(limitType: $0.type,
																			 limitValue: $0.limitValue,
																			 limitValueString: $0.limitValueString,
																			 limitFlag: $0.flag)
				}
				limits += notes
			}
		}
		let response = DeviceAPI.DeviceLimitsResponse(deviceId: deviceId,
													  limits: limits)
		return response
	}
	
	static func deviceSetLimits(session rs: RequestSession) throws -> DeviceAPI.DeviceLimitsResponse {
		let (request, session) = rs
		let updateRequest: DeviceAPI.UpdateLimitsRequest = try request.decode()
		let deviceId = updateRequest.deviceId
		let db = try biqDatabaseInfo.deviceDb()
		guard let device = try userHasDeviceAccess(db: db, deviceId: deviceId, userId: session.id), let ownerId = device.ownerId else {
			throw HTTPResponseError(status: .badRequest, description: "User is not device owner and device has not been shared.")
		}
		let isOwner = ownerId == session.id
		var pushLimits: [BiqDevicePushLimit] = []
		let limitsTable = db.table(BiqDeviceLimit.self)
		
		let matchDevice: CRUDBooleanExpression =
			\BiqDeviceLimit.userId == session.id &&
			\BiqDeviceLimit.deviceId == deviceId
		
		// temps must go as pairs
		let highLimit = BiqDeviceLimitType.tempHigh
		let lowLimit = BiqDeviceLimitType.tempLow
		var useHigh: Float?
		var useLow: Float?
		do {
			let tempHighs = updateRequest.limits.filter { $0.limitType == .tempHigh }
			let tempLows = updateRequest.limits.filter { $0.limitType == .tempLow }
			if tempHighs.isEmpty && !tempLows.isEmpty {
				if let existingHigh = try limitsTable.where(
					matchDevice &&
						\BiqDeviceLimit.limitType == highLimit.rawValue).first()?.limitValue {
					useHigh = existingHigh
				}
			} else if tempLows.isEmpty && !tempHighs.isEmpty {
				if let existingLow = try limitsTable.where(
					matchDevice &&
						\BiqDeviceLimit.limitType == lowLimit.rawValue).first()?.limitValue {
					useLow = existingLow
				}
			}
		}
		
		try db.transaction {
			for limit in updateRequest.limits {
				let matchWhere = limitsTable.where(
						matchDevice &&
						\BiqDeviceLimit.limitType == limit.limitType.rawValue)
				let value = limit.limitValue
				let valueString = limit.limitValueString
				if nil != value || nil != valueString {
					// update or insert (should be an upsert)
					let model = BiqDeviceLimit(userId: session.id,
											   deviceId: deviceId,
											   limitType: limit.limitType,
											   limitValue: value ?? 0.0,
											   limitValueString: valueString,
											   limitFlag: limit.limitFlag ?? .none)
					try matchWhere.delete()
					try limitsTable.insert(model)
					
					// optionally add response value
					guard isOwner else {
						continue // do not propagate to non-owner biqs
					}
					switch limit.limitType.rawValue {
						// temps must go as pairs
					case BiqDeviceLimitType.tempHigh.rawValue:
						let model = BiqDevicePushLimit(deviceId: deviceId, limitType: limit.limitType, limitValue: limit.limitValue ?? 0.0, limitValueString: nil)
						pushLimits.append(model)
						if let useLow = useLow {
							let model = BiqDevicePushLimit(deviceId: deviceId, limitType: lowLimit, limitValue: useLow, limitValueString: nil)
							pushLimits.append(model)
						}
					// temps must go as pairs
					case BiqDeviceLimitType.tempLow.rawValue:
						let model = BiqDevicePushLimit(deviceId: deviceId, limitType: limit.limitType, limitValue: limit.limitValue ?? 0.0, limitValueString: nil)
						pushLimits.append(model)
						if let useHigh = useHigh {
							let model = BiqDevicePushLimit(deviceId: deviceId, limitType: highLimit, limitValue: useHigh, limitValueString: nil)
							pushLimits.append(model)
						}
					case BiqDeviceLimitType.movementLevel.rawValue:
            let model = BiqDevicePushLimit(deviceId: deviceId, limitType: limit.limitType, limitValue: 0, limitValueString: limit.limitValueString)
						pushLimits.append(model)
					case BiqDeviceLimitType.batteryLevel.rawValue:
						()
					case BiqDeviceLimitType.notifications.rawValue:
						()
					case BiqDeviceLimitType.tempScale.rawValue:
						()
					case BiqDeviceLimitType.colour.rawValue:
						pushLimits.append(BiqDevicePushLimit(deviceId: deviceId,
															 limitType: limit.limitType,
															 limitValue: 0,
															 limitValueString: limit.limitValueString))
					case BiqDeviceLimitType.interval.rawValue:
						pushLimits.append(BiqDevicePushLimit(deviceId: deviceId,
															 limitType: limit.limitType,
															 limitValue: limit.limitValue ?? 300,
															 limitValueString: limit.limitValueString))
					case BiqDeviceLimitType.reportFormat.rawValue:
            let v = limit.limitValue ?? 0
            pushLimits.append(BiqDevicePushLimit(deviceId: deviceId,
                               limitType: limit.limitType,
                               limitValue: v > 1 ? 2.0 : 0.0,
                               limitValueString: ""))
					case BiqDeviceLimitType.reportBufferCapacity.rawValue:
            var v = UInt8(limit.limitValue ?? 2)
            if v < 1 || v > 50 {
              v = 50
            }
            pushLimits.append(BiqDevicePushLimit(deviceId: deviceId,
                               limitType: limit.limitType,
                               limitValue: Float(v),
                               limitValueString: ""))
					case BiqDeviceLimitType.lightLevel.rawValue, BiqDeviceLimitType.humidityLevel.rawValue:
						// 0x6400 = upper(100) << 8 + lower(0)
						let v = limit.limitValue ?? Float(0x6400)
						pushLimits.append(BiqDevicePushLimit(deviceId: deviceId, limitType: limit.limitType, limitValue: v, limitValueString: nil))
					default:
						()
					}
				} else {
					// delete
					try matchWhere.delete()
				}
			}
		}
		let limits = try getLimits(db: db, deviceId: deviceId, ownerId: ownerId, userId: session.id)
		let response = DeviceAPI.DeviceLimitsResponse(deviceId: deviceId,
													  limits: limits.compactMap {
														return DeviceAPI.DeviceLimit(limitType: $0.limitType,
																					 limitValue: $0.limitValue,
																					 limitValueString: $0.limitValueString,
																					 limitFlag: $0.limitFlag)
		})
		if !pushLimits.isEmpty {
			let db = try biqDatabaseInfo.obsDb()
			let table = db.table(BiqDevicePushLimit.self)
			try db.transaction {
				for limit in pushLimits {
					try table.where(\BiqDevicePushLimit.deviceId == deviceId && \BiqDevicePushLimit.limitType == limit.limitType).delete()
					try table.insert(limit)
				}
			}
		}
		return response
	}
	
	static func deviceUpdate(session rs: RequestSession) throws -> EmptyReply {
		let (request, session) = rs
		let updateRequest: DeviceAPI.UpdateRequest = try request.decode()
		let db = try biqDatabaseInfo.deviceDb()
		let deviceTable = db.table(BiqDevice.self)
		return try db.transaction {
			guard let currentDevice = try deviceTable.where(\BiqDevice.id == updateRequest.deviceId).first() else {
				throw HTTPResponseError(status: .badRequest, description: "Invalid device.")
			}
			guard session.id == currentDevice.ownerId else {
				throw HTTPResponseError(status: .unauthorized, description: "Not owner.")
			}
			var deviceFlags = currentDevice.deviceFlags
			let deviceName = updateRequest.name ?? currentDevice.name
			if let updateFlags = updateRequest.deviceFlags {
				if updateFlags.contains(.locked) {
					deviceFlags.insert(.locked)
				} else {
					deviceFlags.remove(.locked)
				}
				//...
			}
			let updateObj = BiqDevice(id: currentDevice.id, name: deviceName, ownerId: UUID(), flags: deviceFlags)
			try db.table(BiqDevice.self)
				.where(\BiqDevice.id == updateObj.id &&
					\BiqDevice.ownerId == session.id)
				.update(updateObj, setKeys: \.name, \.flags)
			return EmptyReply()
		}
	}
	
	static func deviceDeleteObs(session rs: RequestSession) throws -> EmptyReply {
		typealias BiqObservation = ObsDatabase.BiqObservation
		let (request, session) = rs
		let registerRequest: DeviceAPI.GenericDeviceRequest = try request.decode()
		let deviceId = registerRequest.deviceId
		let deviceTable = try biqDatabaseInfo.deviceDb().table(BiqDevice.self)
		guard try deviceTable.where(\BiqDevice.id == deviceId && \BiqDevice.ownerId == session.id).count() == 1 else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
		}		
		let db = try biqDatabaseInfo.obsDb()
		let table = db.table(BiqObservation.self)
		try table.where(\BiqObservation.deviceId == deviceId).delete()		
		return EmptyReply()
	}

  static func smooth(_ obs: [ObsDatabase.BiqObservation]) -> [ObsDatabase.BiqObservation]
  {
    guard obs.count > 2 else { return obs }
    var vobs = obs
    var i = 1
    while i < obs.count - 1 {
      let left = obs[i - 1]
      let mid = obs[i]
      let right = obs[i + 1]
      let avg = abs(left.temp - right.temp)
      let small = min(left.temp, right.temp)
      let big = mid .temp - small
      guard big > 0 else {
        i += 1
        continue
      }
      let rate = big / avg
      if rate > 2 {
        let j = obs[i]
        vobs[i] = ObsDatabase.BiqObservation.init(id: j.id, deviceId: j.deviceId, obstime: j.obstime, charging: j.charging, firmware: j.firmware, wifiFirmware: j.wifiFirmware ?? "", battery: j.battery, temp: small, light: j.light, humidity: j.humidity, accelx: j.accelx, accely: j.accely, accelz: j.accelz)
        i += 2
      } else {
        i += 1
      }
    }
    return vobs
  }

	static func obsSummary(earliest: Double, bixid: DeviceURN, unitScale: Int) throws -> [ObsDatabase.BiqObservation] {
		struct SummaryMutableRecord {
			public var charging: Int = 1
			public var battery: Double = 0
			public var light: Double = 0
			public var movement: Double = 0
			public var temperature: Double = 0
			public var humidity: Double = 0
		}
		struct SummaryTemperature: Codable {
			public let stamp: Int
			public let temperature: Double
		}
		struct SummaryMotion: Codable {
			public let stamp: Int
			public let movement: Double
		}
		struct SummaryMajor: Codable {
			public let stamp: Int
			public let battery: Double
			public let light: Double
			public let humidity: Double
		}
		let db = try biqDatabaseInfo.obsDb()
		var sql = """
		select stamp, avg(temp) as temperature from
		(select temp, ((obstime - \(earliest) ) / 3600000 / \(unitScale))::Int as stamp
		from obs
		where obstime >= \(earliest) and bixid = '\(bixid)' and charging = 0)
		AS rawdata group by stamp
		"""
		let temperatures = try db.sql(sql, bindings: [], SummaryTemperature.self)

		sql = """
		select stamp, avg(accelx) as movement from
		(select accelx, accely, accelz,
		((obstime - \(earliest) ) / 3600000 / \(unitScale))::Int as stamp
		from obs
		where obstime >= \(earliest) and bixid = '\(bixid)' and (accely <> 0 or (accelz & 65535) <> 0))
		AS rawdata group by stamp
		"""

		let motion = try db.sql(sql, bindings: [], SummaryMotion.self)
		sql = """
		select stamp, avg(battery) as battery, avg(light) as light, avg(humidity) as humidity from
		(select battery, light, humidity,
		((obstime - \(earliest) ) / 3600000 / \(unitScale))::Int as stamp
		from obs
		where obstime >= \(earliest) and bixid = '\(bixid)')
		AS rawdata group by stamp
		"""
		let major = try db.sql(sql, bindings:[], SummaryMajor.self)
		var records: [Int: SummaryMutableRecord] = [:]
		major.forEach { records[$0.stamp] = SummaryMutableRecord.init(charging: 1, battery: $0.battery, light: $0.light, movement: 0, temperature: 0, humidity: $0.humidity) }
		motion.forEach { move in
			if var h = records[move.stamp] {
				h.movement = move.movement
				records[move.stamp] = h
			}
		}
		temperatures.forEach { temp in
			if var h = records[temp.stamp] {
				h.temperature = temp.temperature
				h.charging = 0
				records[temp.stamp] = h
			}
		}
		let obsRecords: [ObsDatabase.BiqObservation] = records.keys.compactMap {
			stamp -> ObsDatabase.BiqObservation? in
			guard let rec = records[stamp] else { return nil }
			let timestamp = Double(stamp) * 3600000.0 * Double(unitScale) + earliest
			return ObsDatabase.BiqObservation.init(id: 0, deviceId: bixid, obstime: timestamp, charging: rec.charging, firmware: "", wifiFirmware: "", battery: rec.battery, temp: rec.temperature, light: Int(rec.light), humidity: Int(rec.humidity), accelx: Int(rec.movement), accely: 0, accelz: 0)
		}
		return obsRecords.sorted { a, b in
			return a.obsTimeSeconds < b.obsTimeSeconds
		}
	}

	static func deviceObs(session rs: RequestSession) throws -> [ObsDatabase.BiqObservation] {
		typealias BiqObservation = ObsDatabase.BiqObservation
		let (request, session) = rs
		let obsRequest: DeviceAPI.ObsRequest = try request.decode()
		let deviceId = obsRequest.deviceId
		guard let interval = DeviceAPI.ObsRequest.Interval(rawValue: obsRequest.interval) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid interval.")
		}
    let dbDev = try biqDatabaseInfo.deviceDb()
    let deviceTable = dbDev.table(BiqDevice.self)

    guard let currentDevice = try deviceTable.where(\BiqDevice.id == deviceId).first() else {
      throw HTTPResponseError(status: .badRequest, description: "Invalid device.")
    }
    if currentDevice.ownerId != session.id, let flags = currentDevice.flags {
      if flags & BiqDeviceFlag.locked.rawValue != 0 {
        throw HTTPResponseError(status: .forbidden, description: "Device has been locked by owner.")
      }
    }
		do { // screen for access
			let userId = session.id
			let db = Database(configuration: try biqDatabaseInfo.databaseConfiguration())
			let table = db.table(BiqDevice.self)
			let count = try table
				.join(\.accessPermissions, on: \.id, equals: \.deviceId)
				.where(
					\BiqDevice.id == deviceId &&
						(\BiqDevice.ownerId == userId ||
							\BiqDeviceAccessPermission.userId == userId)).count()
			guard count != 0 else {
				throw HTTPResponseError(status: .badRequest, description: "User is not device owner and device has not been shared.")
			}
		}

		
		let db = try biqDatabaseInfo.obsDb()
		let table = db.table(BiqObservation.self)
		let now = Date().timeIntervalSince1970
		let oneHour = 60.0 * 60.0
		switch interval {
		case .all: // 0
			return try table
				.order(by: \.obstime)
					.where(\BiqObservation.deviceId == deviceId).select().map{$0}
		case .live: // 1 - last 8 hours
			// move time back to beginning of hour, 8 hours ago
			let earliest = secsToBeginningOfHour(now - (oneHour * 8))
			let obs = try table
				.order(by: \.obstime)
				.where(
					\BiqObservation.deviceId == deviceId &&
						\BiqObservation.obstime >= (earliest * 1000)).select().map{$0}
			return smooth(obs)
		case .day: // 2
			let earliest = secsToBeginningOfDay(now - (oneHour * 24))
			return try obsSummary(earliest: earliest * 1000, bixid: deviceId, unitScale: 1)
		case .month: // 3
			let earliest = secsToBeginningOfDay(now - (oneHour * 24 * 31))
			return try obsSummary(earliest: earliest * 1000, bixid: deviceId, unitScale: 24)
		case .year: // 4
			let earliest = secsToBeginningOfDay(now - (oneHour * 24 * 365))
			return try obsSummary(earliest: earliest * 1000, bixid: deviceId, unitScale: 720)
		}
	}
}





