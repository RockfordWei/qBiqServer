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

func avg(_ i: Int, count: Int) -> Int {
	guard count != 0 else {
		return 0
	}
	return i / count
}

func avg(_ i: Double, count: Int) -> Double {
	guard count != 0 else {
		return 0
	}
	return i / Double(count)
}

let secondsPerDay = 86400

func shareTokenKey(_ uuid: Foundation.UUID, deviceId: DeviceURN) -> String {
	return "share-token:\(uuid):\(deviceId)"
}

//func totalAccel(x: Int, y: Int, z: Int) -> Double {
//	let xd = Double(x) / 10.0
//	let yd = Double(y) / 10.0
//	let zd = Double(z) / 10.0
//	return sqrt(xd*xd + yd*yd + zd*zd)
//}
//sqrt( x^2+y^2+z^2)

public struct QBiqStat: Codable {
  public let owned: Int
  public let followed: Int
  public let following: Int
}

public struct QBiqSearchResult: Codable {
  public let id: String
  public let name: String
}

public struct QBiqProfile: Codable {
  public let id: DeviceURN
  public let description: String
  public let tags: [String]
}

public enum QBiqError: Error {
  case reason(String)
}
// returns and obs containing the average for the given intervals
struct AveragedObsGenerator: IteratorProtocol {
	typealias Element = ObsDatabase.BiqObservation
	var currentDate: Double
	let dateInterval: Double
	var orderedObs: IndexingIterator<[ObsDatabase.BiqObservation]>
	var currOb: ObsDatabase.BiqObservation? = nil
	init(startDate: Double,
		 dateInterval interval: Double,
		 orderedObs obs: [ObsDatabase.BiqObservation]) {
		currentDate = startDate
		dateInterval = interval
		orderedObs = obs.makeIterator()
		currOb = orderedObs.next()
		while nil != currOb && currOb!.obsTimeSeconds < currentDate {
			currOb = orderedObs.next()
		}
	}
	mutating func next() -> ObsDatabase.BiqObservation? {
		guard currOb != nil else {
			return nil
		}
		let deviceId = currOb!.deviceId
		let firmware = currOb!.firmware
		let wifiFirmware = currOb!.wifiFirmware ?? ""
		var theseObs: [ObsDatabase.BiqObservation] = []
		while currOb!.obsTimeSeconds < currentDate + dateInterval {
			theseObs.append(currOb!)
			currOb = orderedObs.next()
			if nil == currOb {
				break
			}
		}
		defer {
			currentDate += dateInterval
		}
		
		let totalCount = theseObs.count
		var temp = 0.0
		var battery = 0.0
		var light = 0,
			humidity = 0,
			x = 0, y = 0, z = 0
		var charging = 0
		for ob in theseObs {
			temp += ob.temp
			battery += ob.battery
			light += ob.light
			humidity += ob.humidity
			if ob.accelx != 0 {
				x += 1
			}
			if ob.accely != 0 {
				y += 1
			}
			if ob.accelz != 0 {
				z += 1
			}
			charging = ob.charging
		}
		return ObsDatabase.BiqObservation(id: 0,
										  deviceId: deviceId,
										  obstime: currentDate * 1000, /*GRUMBLE*/
										  charging: charging,
										  firmware: firmware,
										  wifiFirmware: wifiFirmware,
										  battery: avg(battery, count: totalCount),
										  temp: avg(temp, count: totalCount),
										  light: avg(light, count: totalCount),
										  humidity: avg(humidity, count: totalCount),
										  accelx: x,
										  accely: y,
										  accelz: z)
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

// this is in place for demo purposes
// if the user has no biqs then share these with them
let fakeShareIds = ["UBIQTF1111", "UBIQTF2222", "UBIQTF3333", "UBIQTF4444"]
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

  static func jsonPath(id: DeviceURN) -> String {
    return "biqs/\(id).json"
  }

  static func deviceProfileUpdate(session rs: RequestSession) throws -> ProfileAPIResponse {
    guard let postbody = rs.request.postBodyBytes else {
      throw QBiqError.reason("empty")
    }
    let postdata = Data.init(bytes: postbody)
    let profile = try JSONDecoder.init().decode(QBiqProfile.self, from: postdata)
    let db = try biqDatabaseInfo.deviceDb()
    let obj = try db.table(BiqDevice.self).where(\BiqDevice.id == profile.id).count()
    guard obj > 0 else {
      throw QBiqError.reason("invalid")
    }
    let path = jsonPath(id: profile.id)
    let file = File(path)
    try file.open(.truncate)
    try file.write(bytes: postbody)
    file.close()
    return ProfileAPIResponse.init(content: "updated")
  }

  static func deviceProfileGet(session rs: RequestSession) throws -> QBiqProfile {
    guard let uid = rs.request.param(name: "uid"), !uid.isEmpty else {
      throw QBiqError.reason("empty")
    }
    let path = jsonPath(id: uid)
    let file = File(path)
    try file.open(.read)
    defer { file.close() }
    let content = try file.readSomeBytes(count: file.size)
    let data = Data.init(bytes: content)
    return try JSONDecoder.init().decode(QBiqProfile.self, from: data)
  }

  static func deviceSearch(session rs: RequestSession) throws -> [QBiqSearchResult] {
    guard let uid = rs.request.param(name: "uid"), !uid.isEmpty else {
      return []
    }
    let wild = Character.init("%")
    var pattern = "%"
    for c in uid {
      pattern.append(c)
      pattern.append(wild)
    }
    let db = try biqDatabaseInfo.deviceDb()
    let sql = "SELECT * FROM biqdevice WHERE id LIKE '\(pattern)' OR name LIKE '\(pattern)' LIMIT 5"
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
			// this is in place for demo purposes
			if ret.count == 0 {
				try db1.transaction {
					for id in fakeShareIds {
						let share = BiqDeviceAccessPermission(userId: userId, deviceId: id)
						try shareTable.insert(share)
					}
				}
				return try deviceList(session: rs)
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
		guard let device = try userHasDeviceAccess(db: db, deviceId: deviceId, userId: session.id) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid device id.")
		}
		guard let ownerId = device.ownerId else {
			throw HTTPResponseError(status: .badRequest, description: "User is not device owner and device has not been shared.")
		}
		let limits = try getLimits(db: db, deviceId: deviceId, ownerId: ownerId, userId: session.id)
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
            let motionLevels = [80, 40, 20, 10, 5]
            let level = Int(limit.limitValue ?? 0)
            let model = BiqDevicePushLimit(deviceId: deviceId, limitType: limit.limitType, limitValue: Float(motionLevels[level]), limitValueString: nil)
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
					case BiqDeviceLimitType.lightLevel.rawValue:
						()
					case BiqDeviceLimitType.humidityLevel.rawValue:
						()
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
			let obs = try table
				.order(by: \.obstime)
				.where(
					\BiqObservation.deviceId == deviceId &&
						\BiqObservation.obstime >= (earliest * 1000)).select().map{$0}
			var averageObs: [ObsDatabase.BiqObservation] = []
			var gen = AveragedObsGenerator(startDate: earliest,
										   dateInterval: oneHour,
										   orderedObs: obs)
			while let ob = gen.next() {
				averageObs.append(ob)
			}
			return averageObs
		case .month: // 3
			let earliest = secsToBeginningOfDay(now - (oneHour * 24 * 31))
			let obs = try table
				.order(by: \.obstime)
				.where(
					\BiqObservation.deviceId == deviceId &&
						\BiqObservation.obstime >= (earliest * 1000)).select().map{$0}
			var averageObs: [ObsDatabase.BiqObservation] = []
			var gen = AveragedObsGenerator(startDate: earliest,
										   dateInterval: oneHour * 24,
										   orderedObs: obs)
			while let ob = gen.next() {
				averageObs.append(ob)
			}
			return averageObs
		case .year: // 4
			let earliest = secsToBeginningOfDay(now - (oneHour * 24 * 365))
			let obs = try table
				.order(by: \.obstime)
				.where(
					\BiqObservation.deviceId == deviceId &&
						\BiqObservation.obstime >= (earliest * 1000)).select().map{$0}
			var averageObs: [ObsDatabase.BiqObservation] = []
			var gen = AveragedObsGenerator(startDate: earliest,
										   dateInterval: oneHour * 24 * 30,
										   orderedObs: obs)
			while let ob = gen.next() {
				averageObs.append(ob)
			}
			return averageObs
		}
	}

  struct MovementSummary : Codable {
    public var unitid = 0
    public var moves = 0
  }

  static func deviceSum(session rs: RequestSession) throws -> [MovementSummary] {
    typealias BiqObservation = ObsDatabase.BiqObservation
    let (request, session) = rs
    let obsRequest: DeviceAPI.ObsRequest = try request.decode()
    let deviceId = obsRequest.deviceId
    guard let interval = DeviceAPI.ObsRequest.Interval(rawValue: obsRequest.interval) else {
      throw HTTPResponseError(status: .badRequest, description: "Invalid interval.")
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
    let sql: String
    switch interval {
    case .day: // 2
      sql =
"""
      select extract(epoch from (clock_timestamp() + hourid * interval '1 hour'))::int as unitid, moves from (
      select hourid, sum(movement) as moves from (
      select extract(hour from tm - clock_timestamp()) as hourid, movement from (
      select to_timestamp(obstime/1000) as tm,
      case (accelx * accelx + accely * accely + accelz * accelz) when 0  then 0  else 1 end as movement
      from obs where bixid = '\(deviceId)' and to_timestamp(obstime/1000) > (clock_timestamp() - interval '24 hours')
      order by obstime desc)
      as fullday)
      as summary group by hourid order by hourid desc)
      as polished;
"""
    case .month: // 3
      sql =
"""
      select extract(epoch from (clock_timestamp() + dayid * interval '1 day'))::int as unitid, moves from (
      select dayid, sum(movement) as moves from (
      select extract(day from tm - clock_timestamp()) as dayid, movement from (
      select to_timestamp(obstime/1000) as tm,
      case (accelx * accelx + accely * accely + accelz * accelz) when 0  then 0  else 1 end as movement
      from obs where bixid = '\(deviceId)' and to_timestamp(obstime/1000) > (clock_timestamp() - interval '30 days')
      order by obstime desc)
      as fullmonth)
      as summary group by dayid order by dayid desc)
      as polished;
"""
    case .year: // 4
      sql =
"""
      select extract(epoch from (clock_timestamp() + monthid * interval '1 month'))::int as unitid, moves from (
      select monthid, sum(movement) as moves from (
      select extract(month from tm - clock_timestamp()) as monthid, movement from (
      select to_timestamp(obstime/1000) as tm,
      case (accelx * accelx + accely * accely + accelz * accelz) when 0  then 0  else 1 end as movement
      from obs where bixid = '\(deviceId)' and to_timestamp(obstime/1000) > (clock_timestamp() - interval '365 days')
      order by obstime desc)
      as fullyear)
      as summary group by monthid order by monthid desc)
      as polished;
"""
    default:
      throw HTTPResponseError(status: .badRequest, description: "Invalid interval")
    }

    let db = try biqDatabaseInfo.obsDb()
    return try db.sql(sql, MovementSummary.self)
  }
}





