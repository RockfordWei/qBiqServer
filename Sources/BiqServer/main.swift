//
//  main.swift
//

import PerfectHTTP
import PerfectHTTPServer
import PerfectCRUD
import PerfectThread
import PerfectCrypto
import PerfectRedis
import Foundation


extension String {
	func env(_ defaultValue: String = "" ) -> String {
		guard let pval = getenv(self) else {
			print("loading env ", self, " = ", defaultValue)
			return defaultValue
		}
		let val = String.init(cString: pval)
		print("loading env ", self, " = ", val)
		return val
	}
}

_ = PerfectCrypto.isInitialized
let biqIAPSecret = "BIQ_IA_PKEY".env()
CRUDLogging.queryLogDestinations = []


#if os(Linux)
let port = 443
let authServerPubKey = try PEMKey(pemPath: "/root/jwtRS256.key.pub")
#else
let port = 8443
let authServerPubKey = try PEMKey(pemPath: "./config/jwtRS256.key.pub")
#endif

do {
	let rds = biqDatabaseInfo
	try rds.initBiqDatabase()
} catch {
	let msg = "Unable to initialize qBiq database. This is fatal error. \(error.localizedDescription)"
	CRUDLogging.log(.error, msg)
	CRUDLogging.flush()
	Threading.sleep(seconds: 1.0)
	fatalError(msg)
}

try configureNotifications()

// let info = biqRedisInfo
let redisAddr = RedisClientIdentifier(withHost: "BIQ_RD_HOST".env("localhost"), port: Int("BIQ_RD_PORT".env("6379")) ?? 6379)
let workGroup = RedisWorkGroup(redisAddr)
workGroup.add(worker: TheWatcher())
workGroup.add(worker: ObsPoller())
workGroup.add(worker: NotePoller())

let routes = mainRoutes()
#if os(Linux)
try HTTPServer.launch(.secureServer(TLSConfiguration(certPath: "/root/combo.crt", keyPath: "/root/server.key"),
									name: "api.ubiqweus.com", port: port, routes: routes))
#else
try HTTPServer.launch(name: "api.ubiqweus.com", port: port, routes: routes)
#endif
