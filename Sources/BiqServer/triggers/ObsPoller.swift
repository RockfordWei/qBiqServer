
import PerfectCRUD
import Dispatch
import Foundation
import PerfectRedis
import PerfectCrypto
import SwiftCodables
import SAuthCodables
import PerfectNotifications
import PerfectThread

let obsAddMsgKey = "obs-add"
let obsInProgressMsgKey = "obs-inprogress"
let noteAddMsgKey = "note-add"
let noteInProgressMsgKey = "note-inprogress"
let notificationPrefix = "note"
let ignorePrefix = "ignore"

public protocol RedisWorker {
	associatedtype State
	var workPauseSeconds: TimeInterval { get }
	func run(workGroup: RedisWorkGroup, state: State?) -> State?
}

public struct RedisWorkGroup {
	let clientId: RedisClientIdentifier
	public init(_ clientId: RedisClientIdentifier) {
		self.clientId = clientId
	}
	public func client() throws -> RedisClient {
		let c = try clientId.client()
		c.netTimeout = 60.0
		return c
	}
	public func add<Worker: RedisWorker>(worker: Worker) {
		scheduleWorker(worker, state: nil, queue: DispatchQueue(label: "RedisWorkGroup.workers"))
	}
	func scheduleWorker<Worker: RedisWorker>(_ worker: Worker, state: Worker.State?, queue: DispatchQueue) {
//		CRUDLogging.log(.info, "Scheduling worker \(type(of: worker))")
		queue.asyncAfter(deadline: .now() + worker.workPauseSeconds) {
			if let newState = worker.run(workGroup: self, state: state) {
				self.scheduleWorker(worker, state: newState, queue: queue)
			} else {
				CRUDLogging.log(.info, "Exising worker \(type(of: worker))")
			}
		}
	}
}

extension RedisHash {
	func value(forKey: String) -> String? {
		guard let fnd = self[forKey] else {
			return nil
		}
		switch fnd {
		case .string(let s):
			return s
		case .binary(let b):
			return String(validatingUTF8: b)
		}
	}
	func value<T: LosslessStringConvertible>(forKey: String, ofType: T.Type) -> T? {
		guard let s = value(forKey: forKey) else {
			return nil
		}
		return T(s)
	}
	func value<T: LosslessStringConvertible>(forKey: String, default def: T) -> T {
		guard let s = value(forKey: forKey) else {
			return def
		}
		return T(s) ?? def
	}
}

extension ObsDatabase.BiqObservation {
	/*
	"bixid":"K0121-1001-8RATEE",
	"firmware":"QESP_D1.0.88",
	"charging":1,
	"light":10,
	"id":0,
	"temp":34.7,
	"obstime":1528746701987.0,
	"humidity":19,
	"accelx":0,
	"accelz":0,
	"accely":0,
	"battery":0.0}
	*/
	init?(_ hash: RedisHash) {
		guard let deviceId = hash.value(forKey: "bixid") else {
			return nil
		}
		self.init(id: 0,
				  deviceId: deviceId,
				  obstime: hash.value(forKey: "obstime", default: 0.0),
				  charging: hash.value(forKey: "charging", default: 0),
				  firmware: hash.value(forKey: "firmware", default: ""),
				  wifiFirmware: hash.value(forKey: "wifiFirmware", default: ""),
				  battery: hash.value(forKey: "battery", default: 0.0),
				  temp: hash.value(forKey: "temp", default: 0.0),
				  light: hash.value(forKey: "light", default: 0),
				  humidity: hash.value(forKey: "humidity", default: 0),
				  accelx: hash.value(forKey: "accelx", default: 0),
				  accely: hash.value(forKey: "accely", default: 0),
				  accelz: hash.value(forKey: "accelz", default: 0))
	}
	
	init?(hashKey: String, client: RedisClient) {
		self.init(client.hash(named: hashKey))
	}
}

extension BiqDeviceLimitType: CustomStringConvertible {
	public var description: String {
		if self == .tempHigh {
			return "High Temperature"
		}
		if self == .tempLow {
			return "Low Temperature"
		}
		if self == .movementLevel {
			return "Movement Level"
		}
		if self == .batteryLevel {
			return "Battery Level"
		}
		return "Invalid"
	}
}

protocol RedisProcessingItem {
	var key: String { get }
	var client: RedisClient { get }
	init?(key: String, client: RedisClient) throws
}

extension RedisProcessingItem {
	init?(fromList: String, toList: String, client: RedisClient) throws {
		let list = client.list(named: fromList)
		guard let item = list.popLast(appendTo: toList, timeout: 45)?.string else {
			return nil
		}
		try self.init(key: item, client: client)
	}
	func delete(removeList: String) throws {
		client.list(named: removeList).remove(matching: key)
		try delete()
	}
	private func delete() throws {
		_ = try client.delete(keys: key)
	}
}

struct ProcessingObs: RedisProcessingItem {
	let key: String
	let obs: ObsDatabase.BiqObservation
	let client: RedisClient
	init?(key: String, client: RedisClient) throws {
		guard let o = ObsDatabase.BiqObservation(hashKey: key, client: client) else {
			return nil
		}
		self.key = key
		self.obs = o
		self.client = client
	}
}
extension BiqDeviceLimit {
	func valueFromObs(_ obs: ObsDatabase.BiqObservation) -> Double {
		let t = type
		if t == .tempHigh {
			return obs.temp
		}
		if t == .tempLow {
			return obs.temp
		}
		if t == .movementLevel {
			return Double(obs.accelx + obs.accely + obs.accelz)
		}
		if t == .batteryLevel {
			return obs.battery
		}
		return 0.0
	}
}

struct NotificationTask: RedisProcessingItem {
	let key: String
	let userId: UserId
	let deviceId: DeviceURN
	let limitType: UInt8
	let obsValue: Double
	let batteryLevel: Double
	let charging: Bool
	let client: RedisClient
	
	func formattedObsValue(tempScale: TemperatureScale) -> String {
		let t = BiqDeviceLimitType(rawValue: limitType)
		if t == .tempHigh {
			return tempScale.formatC(obsValue)
		}
		if t == .tempLow {
			return tempScale.formatC(obsValue)
		}
		if t == .movementLevel {
			return "\(obsValue)"
		}
		if t == .batteryLevel {
			return "\(obsValue)%"
		}
		return "\(obsValue)"
	}
	
	// returns nil if task is in ignore list
	// adds task to ignore list
	// adds hash w/key
	// adds key to list
	init?(userId: UserId,
		  timeout: TimeInterval,
		  deviceId: DeviceURN,
		  limitType: UInt8,
		  obsValue: Double,
		  batteryLevel: Double,
		  charging: Bool,
		  client: RedisClient) throws {
		
		self.userId = userId
		self.deviceId = deviceId
		self.limitType = limitType
		self.obsValue = obsValue
		self.batteryLevel = batteryLevel
		self.charging = charging
		self.client = client
		self.key = "\(notificationPrefix):\(UUID().uuidString)"
		guard try taskOK(timeout: timeout) else {
			return nil
		}
		var hash = RedisHash(client, name: key)
		hash["userId"] = .string(userId.uuidString)
		hash["deviceId"] = .string(deviceId)
		hash["limitType"] = .string("\(limitType)")
		hash["obsValue"] = .string("\(obsValue)")
		hash["batteryLevel"] = .string("\(batteryLevel)")
		hash["charging"] = .string("\(charging)")
		client.list(named: noteAddMsgKey).append(key)
	}
	
	// init with existing task
	init?(key: String, client: RedisClient) throws {
		let hash = RedisHash(client, name: key)
		guard hash.exists else {
			return nil
		}
		guard let userIdR = hash["userId"]?.string,
				let deviceId = hash["deviceId"]?.string,
				let limitTypeR = hash["limitType"]?.string,
				let obsValueR = hash["obsValue"]?.string,
				let batteryLevelR = hash["batteryLevel"]?.string,
				let chargingR = hash["charging"]?.string,
			
				let userId = UUID(uuidString: userIdR),
				let limitType = UInt8(limitTypeR),
				let obsValue = Double(obsValueR),
				let batteryLevel = Double(batteryLevelR),
				let charging = Bool(chargingR) else {
			try client.delete(keys: key)
			return nil
		}
		self.key = key
		self.userId = userId
		self.deviceId = deviceId
		self.limitType = limitType
		self.obsValue = obsValue
		self.batteryLevel = batteryLevel
		self.charging = charging
		self.client = client
	}
	
	private var notificationIgnoreKey: String {
		return "\(notificationPrefix):\(ignorePrefix):\(userId):\(deviceId):\(limitType)"
	}
	
	private func taskOK(timeout: TimeInterval) throws -> Bool {
		let key = notificationIgnoreKey
		let response = try client.set(key: key, value: .string(key), expires: timeout, ifNotExists: true)
		if case .bulkString(let i) = response, i == nil {
			return false
		}
		return true
	}
}

struct ObsPoller: RedisWorker {
	typealias State = Bool
	
	let workPauseSeconds: TimeInterval = 5.0
	
	func run(workGroup: RedisWorkGroup, state: Bool?) -> Bool? {
		do {
			let client = try workGroup.client()
			repeat {
				()
			} while try readItem(with: client)
		} catch {
			CRUDLogging.log(.error, "\(error)")
		}
		return true
	}
	private func readItem(with client: RedisClient) throws -> Bool {
		guard let obs = try ProcessingObs(fromList: obsAddMsgKey, toList: obsInProgressMsgKey, client: client) else {
			return false
		}
		return try handleNewObs(obs, client: client)
	}
	private func handleNewObs(_ obj: ProcessingObs, client: RedisClient) throws -> Bool {
		let db = try biqDatabaseInfo.deviceDb()
		let deviceId = obj.obs.deviceId
		let triggers: [BiqDeviceLimit] = try db.sql(
			"""
			select * from biqdevicelimit
			where deviceid = $1
				and userid in (select userid from biqdevicelimit where deviceid = $1 and limittype = \(BiqDeviceLimitType.notifications.rawValue) and limitvalue != 0)
				and (
					(limittype = \(BiqDeviceLimitType.tempHigh.rawValue) and limitvalue <= $2)
					or (limittype = \(BiqDeviceLimitType.tempLow.rawValue) and limitvalue >= $2) )
			""",
			bindings: [("$1", .string(deviceId)), ("$2", .decimal(obj.obs.temp))],
			BiqDeviceLimit.self)
		for limit in triggers {
			guard let notesLimit = try db.table(BiqDeviceLimit.self)
				.where(\BiqDeviceLimit.userId == limit.userId
					&& \BiqDeviceLimit.deviceId == deviceId
					&& \BiqDeviceLimit.limitType == BiqDeviceLimitType.notifications.rawValue).first()?.limitValue else {
						continue
			}
			if let _ = try NotificationTask(userId: limit.userId,
											timeout: TimeInterval(notesLimit),
											deviceId: obj.obs.deviceId,
											limitType: limit.limitType,
											obsValue: limit.valueFromObs(obj.obs),
											batteryLevel: obj.obs.battery,
											charging: obj.obs.charging != 0,
											client: client) {
				CRUDLogging.log(.info, "Ready for user/device: \(limit.userId):\(obj.obs.deviceId):\(limit.limitType)")
			} else {
				CRUDLogging.log(.info, "User/device in ignore list: \(limit.userId):\(obj.obs.deviceId):\(limit.limitType)")
			}
		}
		try obj.delete(removeList: obsInProgressMsgKey)
		return true
	}
}

struct NotePoller: RedisWorker {
	typealias State = Bool
	
	let workPauseSeconds: TimeInterval = 5.0
	func run(workGroup: RedisWorkGroup, state: Bool?) -> Bool? {
		do {
			let client = try workGroup.client()
			repeat {
				()
			} while try readItem(with: client)
		} catch {
			CRUDLogging.log(.error, "\(error)")
		}
		return true
	}
	private func readItem(with client: RedisClient) throws -> Bool {
		guard let note = try NotificationTask(fromList: noteAddMsgKey, toList: noteInProgressMsgKey, client: client) else {
			return false
		}
		try handleNewObs(note, client: client)
		return true
	}
	private func handleNewObs(_ obj: NotificationTask, client: RedisClient) throws {
		let limitType = BiqDeviceLimitType(rawValue: obj.limitType)
		let isOwner: Bool
		let biqName: String
		let biqColour: String
		let biqId = obj.deviceId
		let tempScale: TemperatureScale
		do {
			let db = try biqDatabaseInfo.deviceDb()
			if let device = try db.table(BiqDevice.self).where(\BiqDevice.id == obj.deviceId).first() {
				biqName = device.name
				isOwner = device.ownerId == obj.userId
			} else {
				biqName = obj.deviceId
				isOwner = true
			}
			let limitsTable = db.table(BiqDeviceLimit.self)
			if let colour = try limitsTable
				.where(\BiqDeviceLimit.deviceId == obj.deviceId &&
					\BiqDeviceLimit.userId == obj.userId &&
					\BiqDeviceLimit.limitType == BiqDeviceLimitType.colour.rawValue).first()?.limitValueString {
				biqColour = colour
			} else {
				biqColour = "4c96fc"
			}
			if let value = try limitsTable
				.where(\BiqDeviceLimit.deviceId == obj.deviceId &&
					\BiqDeviceLimit.userId == obj.userId &&
					\BiqDeviceLimit.limitType == BiqDeviceLimitType.tempScale.rawValue).first()?.limitValue, let scale = TemperatureScale(rawValue: Int(value)) {
				tempScale = scale
			} else {
				tempScale = .celsius
			}
		}
		let db = try biqDatabaseInfo.authDb()
		let aliasTable = db.table(AliasBrief.self)
		let mobileTable = db.table(MobileDeviceId.self)
		let userIds = try aliasTable.where(\AliasBrief.account == obj.userId).select().map { $0.address }
		if !userIds.isEmpty {
			let userDevices = try mobileTable.where(\MobileDeviceId.aliasId ~ userIds).select().map { $0.deviceId }
			let formattedValue = obj.formattedObsValue(tempScale: tempScale)
			
			CRUDLogging.log(.info, "Notification for \(obj.userId) \(obj.deviceId) \(obj.limitType) \(userDevices.joined(separator: " "))")
			let promise: Promise<Bool> = Promise {
				p in
				NotificationPusher(apnsTopic: notificationsTopic).pushAPNS(
					configurationName: notificationsConfigName,
					deviceTokens: userDevices,
					notificationItems: [
						.customPayload("qbiq.name", biqName),
						.customPayload("qbiq.id", biqId),
						.customPayload("qbiq.colour", biqColour),
						.customPayload("qbiq.battery", obj.batteryLevel),
						.customPayload("qbiq.charging", obj.charging),
						.customPayload("qbiq.shared", !isOwner),
						.customPayload("qbiq.value", formattedValue),
						.mutableContent,
						.category("qbiq.alert"),
						.threadId(biqId),
						.alertTitle("\(limitType.description) Alert"),
						.alertBody("Alert triggered for \(biqName) with \(limitType.description) at \(formattedValue)")]) {
							responses in
							try? obj.delete(removeList: noteInProgressMsgKey)
							p.set(true)
							guard responses.count == userDevices.count else {
								return CRUDLogging.log(.error, "Mismatching responses vs userDevices count.")
							}
							for (response, device) in zip(responses, userDevices) {
								if case .ok = response.status {
									CRUDLogging.log(.info, "Success sending notification for device \(device)")
								} else {
									CRUDLogging.log(.error, "Error sending notification \(response.stringBody) for device \(device)")
								}
							}
				}
			}
			guard let b = try? promise.wait(), b == true else {
				try? obj.delete(removeList: noteInProgressMsgKey)
				return CRUDLogging.log(.error, "Failed promise while waiting for notifications.")
			}
		} else {
			try? obj.delete(removeList: noteInProgressMsgKey)
		}
	}
}

struct TheWatcher: RedisWorker {
	typealias State = [Suspect]
	struct WatchList {
		let name: String
		let returnList: String
		let prefix: String
	}
	struct Suspect {
		let list: String
		let returnList: String
		let value: String
		let age: TimeInterval
		var id: String { return "\(list):\(value)" }
	}
	let workPauseSeconds: TimeInterval = 20.0
	let inProgressMaxAge: TimeInterval = 1 * 60
	let watchLists: [WatchList] = [
		.init(name: obsInProgressMsgKey, returnList: obsAddMsgKey, prefix: "obs"),
		.init(name: noteInProgressMsgKey, returnList: noteAddMsgKey, prefix: "note")]
	func run(workGroup: RedisWorkGroup, state: [Suspect]?) -> [Suspect]? {
		do {
			let client = try workGroup.client()
			let suspects = state ?? []
			let now = Date().timeIntervalSinceReferenceDate
			var suspectKeys = Dictionary(suspects.map { ($0.id, $0) }, uniquingKeysWith: { _, b in return b })
			if !suspects.isEmpty {
				let gotcha = suspects.filter { now > $0.age + inProgressMaxAge }
				for got in gotcha {
					suspectKeys.removeValue(forKey: got.id)
					if 1 == client.list(named: got.list).remove(matching: got.value, count: 1) {
						CRUDLogging.log(.info, "Moving to return list \(got.returnList) from \(got.list) value \(got.value)")
						client.list(named: got.returnList).prepend(got.value)
					}
				}
			}
			var newSuspectKeys = Set<String>()
			// if a watch list item is in suspects list, leave it alone
			let newSuspects: [Suspect] = watchLists.flatMap {
				watchList -> [Suspect] in
				let listValues = client.list(named: watchList.name).values.compactMap { $0.string }
				if !listValues.isEmpty {
					CRUDLogging.log(.info, "Items in list \(watchList.name) \(listValues.count)")
				}
				return listValues.compactMap {
					newSuspectKeys.insert("\(watchList.name):\($0)")
					guard nil == suspectKeys["\(watchList.name):\($0)"] else {
						return nil
					}
					return Suspect(list: watchList.name,
								   returnList: watchList.returnList,
								   value: $0, age: now)
				}
			}
			let adjustedSuspects = suspects.filter { newSuspectKeys.contains("\($0.list):\($0.value)") }
			let returnSuspects = adjustedSuspects + newSuspects
			if !returnSuspects.isEmpty {
				CRUDLogging.log(.info, "Items in suspect list \(returnSuspects.count)")
			}
			return returnSuspects
		} catch {
			CRUDLogging.log(.error, "Error while watching: \(error)")
		}
		return state ?? []
	}
}
