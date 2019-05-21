import PerfectNet
import Foundation
#if os(Linux)
import Glibc
#endif
import PerfectCRUD
import PerfectCrypto
import SwiftCodables
import SAuthCodables
import PerfectNotifications
import PerfectThread
import PerfectHTTP

public struct ChatHandlers {
	
	static func identity(session rs: RequestSession) throws -> RequestSession {
		return rs
	}
	
	static func save(session rs: RequestSession) throws -> Void {
		let adb = try biqDatabaseInfo.authDb()
		guard let account = (try adb.table(Account.self).where(\Account.id == rs.session.id).first()) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid login.")
		}
		let uid = rs.session.id.uuidString.lowercased()
		let data = Data.init(bytes: rs.request.postBodyBytes ?? [])
		let record = try JSONDecoder().decode(ChatLogCreation.self, from: data)
		
		let db = try biqDatabaseInfo.deviceDb()
		guard let device = (try db.table(BiqDevice.self).where(\BiqDevice.id == record.topic).first()) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid device.")
		}
		
		let fullName = account.meta?.fullName ?? "anonymous"
		
		try adb.sql("INSERT INTO chatlog(topic, poster, content) VALUES($1, $2, $3)",
					bindings: [
						("$1", .string(record.topic)),
						("$2", .string(uid)),
						("$1", .string(record.content)),
			])
		
		let permission = try db.table(BiqDeviceAccessPermission.self)
			.where(\BiqDeviceAccessPermission.deviceId == device.id).select()
		let owners = try db.table(BiqDevice.self).where(\BiqDevice.id == device.id).select()
		let recipients = try db.transaction { () -> [String] in
			let shared = permission.map { $0.userId.uuidString.lowercased() }
			let owned = owners.map{ $0.ownerId?.uuidString.lowercased() ?? "" }.filter { !$0.isEmpty }
			let combined = Set<String>(shared + owned)
			return [String](combined.filter { $0 != uid } .map { "'\($0)'"})
		}
		guard !recipients.isEmpty else { return }
		
		let constrains = recipients.joined(separator: ",")
		let sql =
		"""
		SELECT mobiledeviceid.aliasid AS email, mobiledeviceid.deviceid AS device
		FROM mobiledeviceid, alias WHERE mobiledeviceid.aliasid = alias.address
		AND alias.account in (\(constrains))
		"""
		print(sql)
		
		let receivers: [Recipient] = try adb.sql(sql, Recipient.self)
		guard !receivers.isEmpty else { return }
		CRUDLogging.log(.info, "----------- FROM \(fullName)")
		CRUDLogging.log(.info, "----------- QBIQ \(device.id)")
		CRUDLogging.log(.info, "----------- CONT \(record.content)")
		
		let mobiles = receivers.map { $0.device }
		
		NotificationPusher(apnsTopic: notificationsTopic).pushAPNS(
			configurationName: notificationsConfigName,
			deviceTokens: mobiles,
			notificationItems: [
				.customPayload("qbiq.name", device.name),
				.customPayload("qbiq.id", device.id),
				.mutableContent,
				.category("qbiq.chat"),
				.threadId(device.id),
				.alertTitle("\(fullName)~ about \(device.name):"),
				.alertBody(record.content)]) { responses in
					for (response, target) in zip(responses, receivers) {
						if case .ok = response.status {
							CRUDLogging.log(.info, "\(target.email): Sent OK")
						} else {
							CRUDLogging.log(.error, "\(target.email): \(response.stringBody) for device \(device)")
							/*
							var badTokens: [String] = []
							if response.stringBody.contains(string: "BadDeviceToken") {
							badTokens.append("'\(target.device)'")
							}
							
							if !badTokens.isEmpty {
							let all = badTokens.joined(separator: ",")
							try? adb.sql("DELETE FROM mobiledeviceid WHERE deviceid IN (\(all))")
							}
							*/
						}
					}
		}
		
		
	}
	
	static func load(session rs: RequestSession) throws -> [ChatLog] {
		let db = try biqDatabaseInfo.deviceDb()
		let shared = try db.table(BiqDeviceAccessPermission.self)
			.where(\BiqDeviceAccessPermission.userId == rs.session.id).select()
			.map { "'\($0.deviceId)'" }
		let owned = try db.table(BiqDevice.self).where(\BiqDevice.ownerId == rs.session.id).select()
			.map { "'\($0.id)'"}
		
		let devices: Set<String> = Set<String>(shared + owned)
		guard !devices.isEmpty else { return [] }
		
		let dev = devices.joined(separator: ",")
		let adb = try biqDatabaseInfo.authDb()
		let last = Int64(rs.request.param(name: "last") ?? "0") ?? 0
		let sql = "SELECT * FROM chatlog WHERE id > \(last) AND topic IN (\(dev)) AND DATE_PART('day', now() - utc) < 31 ORDER BY id, utc LIMIT 100"
		let records: [ChatLog] = try adb.sql(sql, ChatLog.self)
		return records
	}
}
