//
//  Config.swift
//  BIQServer
//
//  Created by Kyle Jessup on 2017-12-18.
//

import Foundation
import SwiftCodables
import SAuthCodables
import PerfectCloudFormation
import PerfectPostgreSQL
import PerfectCRUD
import PerfectRedis
import PerfectNotifications
import PerfectLib

let configDir = "./config/"
let templatesDir = "./templates/"
#if os(macOS) || DEBUG
let configFilePath = "\(configDir)config.dev.json"
#else
let configFilePath = "\(configDir)config.prod.json"
#endif

let biqDevicesDatabaseName = "qbiq_devices2"
let biqAuthDatabaseName = "qbiq_user_auth2"

let notificationsConfigName = "qbiq-limits"

#if os(macOS)
let notificationsProduction = false
#else
let notificationsProduction = true
#endif

// !FIX! remove this as a mutable global
var notificationsTopic = "unconfigured"

let deviceShareTokenExpirationDays = 15

struct Config: Codable {
	struct Notifications: Codable {
		let keyName: String
		let keyId: String
		let teamId: String
		let topic: String
		let production: Bool
	}
	let notifications: Notifications?
	
	static func get() throws -> Config {
		let f = File(configFilePath)
		let config = try JSONDecoder().decode(Config.self, from: Data(bytes: Array(f.readString().utf8)))
		return config
	}
}

let biqDatabaseInfo: CloudFormation.RDSInstance = {
	if let pgsql = CloudFormation.listRDSInstances(type: .postgres)
		.sorted(by: { $0.resourceName < $1.resourceName }).first {
		return pgsql
	} else {
		return .init(resourceType: .postgres,
					 resourceId: "",
					 resourceName: "",
           userName: "BIQ_PG_USER".env("postgres"),
           password: "BIQ_PG_PASS".env(""),
           hostName: "BIQ_PG_HOST".env("localhost"),
           hostPort: Int("BIQ_PG_PORT".env("5432")) ?? 5432 )
	}
}()

let biqObsDatabaseInfo: CloudFormation.RDSInstance = {
	return biqDatabaseInfo
}()

let biqRedisInfo: CloudFormation.ElastiCacheInstance = {
	if let redis = CloudFormation.listElastiCacheInstances(type: .redis)
		.sorted(by: { $0.resourceName < $1.resourceName }).first {
		return redis
	}
	return CloudFormation.ElastiCacheInstance(resourceType: .redis,
											  resourceId: "",
											  resourceName: "",
											  hostName: "localhost",
											  hostPort: 6379)
}()

func configureNotifications() throws {
	let config = try Config.get()
	guard let n = config.notifications else {
		return
	}
	notificationsTopic = n.topic
	NotificationPusher.addConfigurationAPNS(
		name: notificationsConfigName,
		production: n.production,
		keyId: n.keyId,
		teamId: n.teamId,
		privateKeyPath: "\(configDir)\(n.keyName)")
}

extension CloudFormation.ElastiCacheInstance {
	var clientId: RedisClientIdentifier {
		return RedisClientIdentifier(withHost: hostName, port: hostPort)
	}
	func client() throws -> RedisClient {
		return try clientId.client()
	}
}

extension CloudFormation.SwiftletInstance {
	var baseURL: String {
		let port = hostPorts.first ?? 80
		if port == 443 {
			return "https://\(hostName)"
		}
		if port == 80 {
			return "http://\(hostName)"
		}
		return "http://\(hostName):\(port)"
	}
}

extension CloudFormation.RDSInstance {
	func deviceDb() throws -> Database<PostgresDatabaseConfiguration> {
		return Database(configuration: try databaseConfiguration())
	}
	func authDb() throws -> Database<PostgresDatabaseConfiguration> {
		return Database(configuration: try databaseConfiguration(database: biqAuthDatabaseName))
	}
	func obsDb() throws -> Database<PostgresDatabaseConfiguration> {
		return Database(configuration: try biqObsDatabaseInfo.databaseConfiguration(database: "biq"))
	}
	
	func databaseConfiguration() throws -> PostgresDatabaseConfiguration {
		return try databaseConfiguration(database: biqDevicesDatabaseName)
	}
	func databaseConfiguration(database: String) throws -> PostgresDatabaseConfiguration {
		return try .init(database: database, host: hostName, port: hostPort, username: userName, password: password)
	}

	func initBiqDatabase() throws {
		do {
			let postgresConfig = try databaseConfiguration(database: "postgres")
			let db = Database(configuration: postgresConfig)
			struct PGDatabase: Codable, TableNameProvider {
				static var tableName = "pg_database"
				let datname: String
			}
			let count = try db.table(PGDatabase.self).where(\PGDatabase.datname == biqDevicesDatabaseName).count()
			if count == 0 {
				try db.sql("CREATE DATABASE \(biqDevicesDatabaseName)")
			}
		}
		let db = try deviceDb()
		try db.create(BiqBookmark.self, policy: [.reconcileTable, .shallow]).index(\BiqBookmark.id)
		try db.create(BiqDevice.self, policy: [.reconcileTable, .shallow])
			.index(\BiqDevice.ownerId)
		try db.create(BiqDeviceGroup.self, policy: [.reconcileTable, .shallow])
			.index(\.ownerId)
		try db.create(BiqDeviceGroupMembership.self, policy: [.reconcileTable, .shallow])
			.index(unique: true, \.groupId, \.deviceId)
		try db.create(BiqDeviceAccessPermission.self, policy: [.reconcileTable, .shallow])
			.index(unique: true, \.userId, \.deviceId)
		let lim = try db.create(BiqDeviceLimit.self, policy: [.reconcileTable, .shallow])
		try lim.index(unique: true, \.userId, \.deviceId, \.limitType)
		try lim.index(\.deviceId)
	}
}

extension ObsDatabase.BiqObservation: TableNameProvider {
	public static var tableName = "obs"
}

extension AliasBrief: TableNameProvider {
	public static var tableName = Alias.CRUDTableName
}





