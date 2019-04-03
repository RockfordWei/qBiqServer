
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


struct ObsPoller: RedisWorker {
	typealias State = Bool
	
	let workPauseSeconds: TimeInterval = 5.0

	public static var timeouts: [String: time_t] = [:]
	
	func run(workGroup: RedisWorkGroup, state: Bool?) -> Bool? {
		do {
			let client = try workGroup.client()
			repeat {
				()
			} while try readItem(with: client)
		} catch (let err) {
      let emsg = "run(workGroup.client) \(err)"
      guard emsg.contains("282") && emsg.contains("timeout") else {
        CRUDLogging.log(.error, emsg)
        return false
      }
		}
		return true
	}
	private func readItem(with client: RedisClient) throws -> Bool {
		guard let obs = try ProcessingObs(fromList: obsAddMsgKey, toList: obsInProgressMsgKey, client: client) else {
			return false
		}
		return try handleNewObs(obs, client: client)
	}

	enum NoteType {
		case checkIn
		case motion
		case temperature(Double, Bool)
		case humidity(Int)
		case brightness(Int)
	}

	private func isObsMoved(_ obs: ObsDatabase.BiqObservation) -> Bool {
		let counter = obs.accelx & 0xFFFF
		let xy = obs.accely
		let z = obs.accelz & 0xFFFF
		let moved = xy != 0 || z != 0
		CRUDLogging.log(.error, "motional data: \(counter), \(xy), \(z), \(moved), conclusion: \(counter > 0 && moved)")
		return counter > 0 && moved
	}

	private func getThresholds(value: Float) -> (low:Int, high:Int) {
		let v = UInt16(value)
		var low = Int(v & 0x00FF)
		var high = Int((v & 0xFF00) >> 8)
		if low < 0 { low = 0 } else if low > 100 { low = 100 }
		if high < 0 { high = 0 } else if high > 100 { high = 100 }
		if low > high {
			let mid = high
			high = low
			low = mid
		}
		return (low: low, high: high)
	}
	private func isObsOverHumid(_ obs: ObsDatabase.BiqObservation, limits: [BiqDeviceLimit] = []) -> Bool {
		guard let lim = (limits.filter { $0.type == .humidityLevel }.first) else {
			CRUDLogging.log(.error, "no humidity threshold found")
			return false
		}
		let threshold = getThresholds(value: lim.limitValue)
		CRUDLogging.log(.error, "humidity: \(obs.humidity) in range: [\(threshold.low), \(threshold.high)]")
		return obs.humidity < threshold.low || obs.humidity > threshold.high
	}

	private func isObsOverBright(_ obs: ObsDatabase.BiqObservation, limits: [BiqDeviceLimit] = []) -> Bool {
		guard let lim = (limits.filter { $0.type == .lightLevel }.first) else {
			CRUDLogging.log(.error, "no brightness threshold found")
			return false
		}
		let threshold = getThresholds(value: lim.limitValue)
		CRUDLogging.log(.error, "brightness: \(obs.light) in range: [\(threshold.low), \(threshold.high)]")
		return obs.light < threshold.low || obs.light > threshold.high
	}

	private func isObsOverTemperature(_ obs: ObsDatabase.BiqObservation, limits: [BiqDeviceLimit] = []) -> Bool {
		let lim: [(Float, BiqDeviceLimitType)] = limits.map { limitaion -> (Float, BiqDeviceLimitType) in
			return (limitaion.limitValue, BiqDeviceLimitType.init(rawValue: limitaion.limitType))
		}
		CRUDLogging.log(.error, "temperature limits: \(lim.count)")
		guard let low = (lim.filter { $0.1 == .tempLow}).first,
			let high = (lim.filter { $0.1 == .tempHigh}).first else {
				CRUDLogging.log(.error, "no temperature threshold found")
				return false
		}
		let temp = Float(obs.temp)
		CRUDLogging.log(.error, "temperature: \(temp) in range:[\(low.0), \(high.0)]")
		return temp < low.0 || temp > high.0
	}

	private func getNoteType(_ obs: ObsDatabase.BiqObservation) throws -> NoteType? {
		let db = try biqDatabaseInfo.deviceDb()
		guard let device = try db.table(BiqDevice.self).where(\BiqDevice.id == obs.deviceId).first(),
		let owner = device.ownerId else { return nil }
		let limits:[BiqDeviceLimit] = try db.table(BiqDeviceLimit.self)
			.where(\BiqDeviceLimit.deviceId == obs.deviceId && \BiqDeviceLimit.userId == owner)
			.select().map { $0 }
		CRUDLogging.log(.error, "note type inspecting: \(limits.count) threshold found for owner \(owner.uuidString)")
		if isObsMoved(obs) { return .motion }
		if isObsOverBright(obs, limits: limits) { return .brightness(obs.light) }
		if isObsOverHumid(obs, limits: limits) { return .humidity(obs.humidity) }
		if isObsOverTemperature(obs, limits: limits) {
			let lim: [(Float, BiqDeviceLimitType)] = limits.map { limitaion -> (Float, BiqDeviceLimitType) in
				return (limitaion.limitValue, BiqDeviceLimitType.init(rawValue: limitaion.limitType))
			}
			let scale = lim.filter { $0.1 == .tempScale }.first
			let farhrenheit: Bool
			if let farh = scale, farh.0 > 0 {
				farhrenheit = true
			} else {
				farhrenheit = false
			}
			return .temperature(obs.temp, farhrenheit)
		}
		return .checkIn
	}

	private func sendBiqNotification(userDevices: [String],
																biqName: String, deviceId: String, biqColour: String,
																batteryLevel: Double, charging: Bool, isOwner: Bool,
																formattedValue: String, alertMessage: String) {
		NotificationPusher(apnsTopic: notificationsTopic).pushAPNS(
			configurationName: notificationsConfigName,
			deviceTokens: userDevices,
			notificationItems: [
				.customPayload("qbiq.name", biqName),
				.customPayload("qbiq.id",deviceId),
				.customPayload("qbiq.colour", biqColour),
				.customPayload("qbiq.battery", batteryLevel),
				.customPayload("qbiq.charging", charging),
				.customPayload("qbiq.shared", !isOwner),
				.customPayload("qbiq.value", formattedValue),
				.mutableContent,
				.category("qbiq.alert"),
				.threadId(deviceId),
				.alertTitle(biqName),
				.alertBody(alertMessage)]) {
					responses in
					guard responses.count == userDevices.count else {
						return CRUDLogging.log(.error, "sendBiqNotification: mismatching responses vs userDevices count.")
					}
					for (response, device) in zip(responses, userDevices) {
						if case .ok = response.status {
							CRUDLogging.log(.info, "sendBiqNotification: success for device \(device)")
						} else {
							CRUDLogging.log(.error, "sendBiqNotification: \(response.stringBody) failed for device \(device)")
						}
					}
		}
	}
	private func handleNewObs(_ obj: ProcessingObs, client: RedisClient) throws -> Bool {
		// ignore unregistered device
		CRUDLogging.log(.error, "handling incoming obj: \(obj.obs.deviceId)")

		guard let noteType = try getNoteType(obj.obs) else {
			CRUDLogging.log(.error, "note type is invalid")
			return false
		}

		let db = try biqDatabaseInfo.deviceDb()
		let deviceId = obj.obs.deviceId
		guard let device = try db.table(BiqDevice.self).where(\BiqDevice.id == deviceId).first() else { return false }
		CRUDLogging.log(.error, "checking device \(deviceId)")
		let biqName: String
		if device.name.count > 0 {
			biqName = device.name
		} else {
			let last = deviceId.endIndex
			let begin = deviceId.index(last, offsetBy: -6)
			biqName = String(deviceId[begin..<last])
		}

		CRUDLogging.log(.error, "device name = \(biqName)")
		let alert: String
		switch noteType {
		case .temperature(let temp, let farhrenheit):
			let tempScale = farhrenheit ? TemperatureScale.fahrenheit : TemperatureScale.celsius
			let tempString = tempScale.formatC(temp)
			alert = "\(biqName): temperature is reaching \(tempString)"
		case .humidity(let humidity):
			alert = "\(biqName): humidity is reaching \(humidity)%"
		case .brightness(let lightLevel):
			alert = "\(biqName): light level is reaching \(lightLevel)%"
		case .motion:
			alert = "\(biqName): device has been moved over \(obj.obs.accelx & 0xFFFF) times"
		default:
			// ignore check-in
			CRUDLogging.log(.error, "ignore regular check-in")
			return false
		}

		let adb = try biqDatabaseInfo.authDb()
		try adb.sql("INSERT INTO chatlog(topic, poster, content) VALUES($1, $1, $2)",
								bindings:  [("$1", .string(deviceId)), ("$2", .string(alert))])

		let triggers: [BiqDeviceLimit] = try db.table(BiqDeviceLimit.self)
			.where(\BiqDeviceLimit.deviceId == deviceId &&
				\BiqDeviceLimit.limitType == BiqDeviceLimitType.notifications.rawValue &&
				\BiqDeviceLimit.limitValue != 0).select().map { $0 }
		CRUDLogging.log(.error, "\(triggers.count) triggers found")
		let limitsTable = db.table(BiqDeviceLimit.self)
		for limit in triggers {
			let aliasTable = adb.table(AliasBrief.self)
			let mobileTable = adb.table(MobileDeviceId.self)
			let userIds = try aliasTable.where(\AliasBrief.account == limit.userId).select().map { $0.address }
			if userIds.isEmpty { continue }
			CRUDLogging.log(.error, "\(userIds.count) users found")
			let userDevices = try mobileTable.where(\MobileDeviceId.aliasId ~ userIds).select().map { $0.deviceId }
			let timeoutKey = "\(limit.userId)/\(deviceId)"
			let now = time(nil)
			let seconds = time_t(limit.limitValue)

			if let timeout = ObsPoller.timeouts[timeoutKey] {
				if now > (timeout + seconds) {
					ObsPoller.timeouts[timeoutKey] = now
					CRUDLogging.log(.error, "timeout expired. sending notification now")
				} else {
					// skip this notification
					CRUDLogging.log(.error, "sendBiqNotification: skip \(timeoutKey)")
					continue;
				}
			} else {
				CRUDLogging.log(.error, "No timeout found. sending notification now")
				ObsPoller.timeouts[timeoutKey] = now
			}
			do {
				let biqColour: String
				if let colour = try limitsTable
					.where(\BiqDeviceLimit.deviceId == deviceId &&
						\BiqDeviceLimit.userId == limit.userId &&
						\BiqDeviceLimit.limitType == BiqDeviceLimitType.colour.rawValue).first()?.limitValueString {
					biqColour = colour
				} else {
					biqColour = "4c96fc"
				}

				let isOwner = device.ownerId == limit.userId
				self.sendBiqNotification(userDevices: userDevices, biqName: biqName, deviceId: deviceId, biqColour: biqColour,
																 batteryLevel: obj.obs.battery, charging: obj.obs.charging != 0, isOwner: isOwner,
																 formattedValue: "\(obj.obs.humidity)%", alertMessage: alert)
			}
		}
		CRUDLogging.log(.error, "notification cleaning up")
		try obj.delete(removeList: obsInProgressMsgKey)
		return true
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
		} catch (let err) {
      let emsg = "Error while watching: \(err)"
      if emsg.contains("282") && emsg.contains("timeout") {
      } else {
        CRUDLogging.log(.error, emsg)
      }
		}
		return state ?? []
	}
}
